const std = @import("std");
const resp = @import("response.zig");
const log = @import("zutils").log;
const dict = @import("../dict/dict.zig");
const google_api = @import("google_api.zig");
const config = @import("../config.zig");

pub const Handler = union(enum) {
    disconnect_handler: DisconnectHandler,
    candidate_handler: CandidateHandler,
    raw_string_handler: RawStringHandler(128),
    completion_handler: CompletionHandler,
    custom_protocol_handler: CustomProtocolHandler,
    exit_handler: ExitHandler,

    pub fn handle(self: Handler, alloc: std.mem.Allocator, writer: *std.Io.Writer, line: []const u8) anyerror!void {
        switch (self) {
            inline else => |case| {
                try case.handle(alloc, writer, line);
            },
        }
    }
};

pub const ExitHandler = struct {
    fn handle(_: ExitHandler, _: std.mem.Allocator, _: *std.Io.Writer, _: []const u8) !void {
        if (@import("builtin").mode == .Debug) {
            return error.Exit;
        } else unreachable;
    }
};

test "ExitHandler" {
    var allocating = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer allocating.deinit();

    var h = ExitHandler{};
    const err = h.handle(std.testing.allocator, &allocating.writer, "");

    try std.testing.expectError(error.Exit, err);
}

pub const DisconnectHandler = struct {
    fn handle(_: DisconnectHandler, _: std.mem.Allocator, _: *std.Io.Writer, _: []const u8) !void {
        return error.Disconnect;
    }
};

test "DisconnectHandler" {
    var allocating = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer allocating.deinit();

    var h = DisconnectHandler{};
    const err = h.handle(std.testing.allocator, &allocating.writer, "");

    try std.testing.expectError(error.Disconnect, err);
}

pub const CandidateHandler = struct {
    dict_mgr: *dict.Manager,
    use_google: bool,

    pub fn init(dict_mgr: *dict.Manager, use_google: bool) @This() {
        return .{
            .dict_mgr = dict_mgr,
            .use_google = use_google,
        };
    }

    fn handle(self: CandidateHandler, alloc: std.mem.Allocator, writer: *std.Io.Writer, line: []const u8) !void {
        const cdd = self.dict_mgr.findCandidate(alloc, line);
        if (cdd.len > 0) {
            return try resp.generateResponse(writer, line, cdd);
        }
        if (!self.use_google) {
            return try resp.generateResponse(writer, line, "");
        }

        log.debug("Fallback to google", .{});

        const fallback = google_api.transliterateRequest(alloc, line) catch |err| {
            log.err("Failed to make request due to {}", .{err});
            return try resp.generateResponse(writer, line, "");
        };
        defer alloc.free(fallback);

        return try resp.generateResponse(writer, line, fallback);
    }
};

test "CandidateHandler" {
    const alloc = std.testing.allocator;

    var mgr = try dict.Manager.init(alloc);
    defer mgr.deinit();

    const locations: []const dict.Location = &.{
        .{ .url = "testdata/jisyo.utf8", .files = &.{} },
    };
    try mgr.reloadLocations(locations, ".");

    var allocating = std.Io.Writer.Allocating.init(alloc);
    defer allocating.deinit();

    var h = CandidateHandler.init(&mgr, true);

    try h.handle(alloc, &allocating.writer, "1024");
    try std.testing.expectEqualStrings("1/キロ/", allocating.written());

    allocating.clearRetainingCapacity();
    try h.handle(alloc, &allocating.writer, "smile");
    try std.testing.expectEqualStrings("4smile ", allocating.written());

    allocating.clearRetainingCapacity();
    try h.handle(alloc, &allocating.writer, "=1+1");
    try std.testing.expectEqualStrings("1/2/2=1+1/＝１＋１/", allocating.written());

    allocating.clearRetainingCapacity();
    h.use_google = false;
    try h.handle(alloc, &allocating.writer, "=1+1");
    try std.testing.expectEqualStrings("4=1+1 ", allocating.written());
}

pub const CompletionHandler = struct {
    dict_mgr: *dict.Manager,

    pub fn init(dict_mgr: *dict.Manager) @This() {
        return .{
            .dict_mgr = dict_mgr,
        };
    }

    fn handle(self: CompletionHandler, alloc: std.mem.Allocator, writer: *std.Io.Writer, line: []const u8) !void {
        const cdd = try self.dict_mgr.findCompletion(alloc, line, 100);
        defer alloc.free(cdd);

        try resp.generateResponse(writer, line, cdd);
    }
};

test "CompletionHandler" {
    const alloc = std.testing.allocator;

    var mgr = try dict.Manager.init(alloc);
    defer mgr.deinit();

    const locations: []const dict.Location = &.{
        .{ .url = "testdata/jisyo.utf8", .files = &.{} },
    };
    try mgr.reloadLocations(locations, ".");

    var allocating = std.Io.Writer.Allocating.init(alloc);
    defer allocating.deinit();

    var h = CompletionHandler.init(&mgr);

    try h.handle(alloc, &allocating.writer, "1");
    try std.testing.expectEqualStrings("1/1024/1seg/", allocating.written());

    allocating.clearRetainingCapacity();
    try h.handle(alloc, &allocating.writer, "smile");
    try std.testing.expectEqualStrings("4smile ", allocating.written());
}

pub fn RawStringHandler(size: usize) type {
    return struct {
        str: [size]u8,
        len: usize,

        pub fn init(str: []const u8) @This() {
            var self: @This() = .{
                .str = [_]u8{0} ** size,
                .len = str.len,
            };
            std.mem.copyBackwards(u8, &self.str, str);
            return self;
        }

        fn handle(self: RawStringHandler(size), _: std.mem.Allocator, writer: *std.Io.Writer, _: []const u8) !void {
            _ = try writer.write(self.str[0..self.len]);
        }
    };
}

test "RawStringHandler" {
    var allocating = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer allocating.deinit();

    var h = RawStringHandler(512).init("a string");

    try h.handle(std.testing.allocator, &allocating.writer, "");
    try std.testing.expectEqualStrings("a string", allocating.written());
}

pub const CustomProtocolHandler = struct {
    dict_mgr: *dict.Manager,

    pub fn init(dict_mgr: *dict.Manager) CustomProtocolHandler {
        return .{
            .dict_mgr = dict_mgr,
        };
    }

    fn handle(self: CustomProtocolHandler, alloc: std.mem.Allocator, _: *std.Io.Writer, req: []const u8) !void {
        if (std.mem.eql(u8, req, "reload")) {
            log.info("Reload", .{});

            self.reload(alloc) catch |err| {
                log.err("Failed to reload dictionaries due to {}", .{err});
            };
            return;
        }

        log.err("Not implemented command {s}", .{req});
    }

    fn reload(self: CustomProtocolHandler, alloc: std.mem.Allocator) !void {
        const cfg = try config.loadConfig(alloc);
        defer cfg.deinit(alloc);

        try self.dict_mgr.reloadLocations(cfg.dictionaries, cfg.dictionary_directory);
    }
};
