const std = @import("std");
const resp = @import("response.zig");
const utils = @import("../utils/utils.zig");
const dict = @import("../dict/dict.zig");
const google_api = @import("google_api.zig");
const config = @import("../config.zig");

const require = @import("protest").require;

pub const Handler = union(enum) {
    disconnect_handler: DisconnectHandler,
    candidate_handler: CandidateHandler,
    raw_string_handler: RawStringHandler(128),
    completion_handler: CompletionHandler,
    custom_protocol_handler: CustomProtocolHandler,
    exit_handler: ExitHandler,

    pub fn handle(self: Handler, alloc: std.mem.Allocator, buffer: *std.ArrayList(u8), line: []const u8) anyerror!void {
        switch (self) {
            inline else => |case| {
                try case.handle(alloc, buffer, line);
            },
        }
    }
};

pub const ExitHandler = struct {
    fn handle(_: ExitHandler, _: std.mem.Allocator, _: *std.ArrayList(u8), _: []const u8) !void {
        if (@import("builtin").mode == .Debug) {
            return error.Exit;
        } else unreachable;
    }
};

test "ExitHandler" {
    var arr = std.ArrayList(u8).init(std.testing.allocator);
    defer arr.deinit();

    var h = ExitHandler{};
    const err = h.handle(std.testing.allocator, &arr, "");

    try require.equalError(error.Exit, err);
}

pub const DisconnectHandler = struct {
    fn handle(_: DisconnectHandler, _: std.mem.Allocator, _: *std.ArrayList(u8), _: []const u8) !void {
        return error.Disconnect;
    }
};

test "DisconnectHandler" {
    var arr = std.ArrayList(u8).init(std.testing.allocator);
    defer arr.deinit();

    var h = DisconnectHandler{};
    const err = h.handle(std.testing.allocator, &arr, "");

    try require.equalError(error.Disconnect, err);
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

    fn handle(self: CandidateHandler, alloc: std.mem.Allocator, buffer: *std.ArrayList(u8), line: []const u8) !void {
        const cdd = self.dict_mgr.findCandidate(alloc, line);
        if (cdd.len > 0) {
            return try resp.generateResponse(buffer, line, cdd);
        }
        if (!self.use_google) {
            return try resp.generateResponse(buffer, line, "");
        }

        utils.log.debug("Fallback to google", .{});

        const fallback = google_api.transliterateRequest(alloc, line) catch |err| {
            utils.log.err("Failed to make request due to {}", .{err});
            return try resp.generateResponse(buffer, line, "");
        };
        defer alloc.free(fallback);

        return try resp.generateResponse(buffer, line, fallback);
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

    var arr = std.ArrayList(u8).init(alloc);
    defer arr.deinit();

    var h = CandidateHandler.init(&mgr, true);

    try h.handle(alloc, &arr, "1024");
    try require.equal("1/キロ/", arr.items);

    arr.clearAndFree();
    try h.handle(alloc, &arr, "smile");
    try require.equal("4smile ", arr.items);

    arr.clearAndFree();
    try h.handle(alloc, &arr, "=1+1");
    try require.equal("1/2/2=1+1/＝１＋１/", arr.items);

    h.use_google = false;
    arr.clearAndFree();
    try h.handle(alloc, &arr, "=1+1");
    try require.equal("4=1+1 ", arr.items);
}

pub const CompletionHandler = struct {
    dict_mgr: *dict.Manager,

    pub fn init(dict_mgr: *dict.Manager) @This() {
        return .{
            .dict_mgr = dict_mgr,
        };
    }

    fn handle(self: CompletionHandler, alloc: std.mem.Allocator, buffer: *std.ArrayList(u8), line: []const u8) !void {
        const cdd = try self.dict_mgr.findCompletion(alloc, line);
        defer alloc.free(cdd);

        try resp.generateResponse(buffer, line, cdd);
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

    var arr = std.ArrayList(u8).init(alloc);
    defer arr.deinit();

    var h = CompletionHandler.init(&mgr);

    try h.handle(alloc, &arr, "1");
    try require.equal("1/1024/1seg/", arr.items);

    arr.clearAndFree();
    try h.handle(alloc, &arr, "smile");
    try require.equal("4smile ", arr.items);
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

        fn handle(self: RawStringHandler(size), _: std.mem.Allocator, buffer: *std.ArrayList(u8), _: []const u8) !void {
            try buffer.appendSlice(self.str[0..self.len]);
        }
    };
}

test "RawStringHandler" {
    var arr = std.ArrayList(u8).init(std.testing.allocator);
    defer arr.deinit();

    var h = RawStringHandler(512).init("a string");

    try h.handle(std.testing.allocator, &arr, "");
    try require.equal("a string", arr.items);
}

pub const CustomProtocolHandler = struct {
    dict_mgr: *dict.Manager,

    pub fn init(dict_mgr: *dict.Manager) CustomProtocolHandler {
        return .{
            .dict_mgr = dict_mgr,
        };
    }

    fn handle(self: CustomProtocolHandler, alloc: std.mem.Allocator, _: *std.ArrayList(u8), req: []const u8) !void {
        if (std.mem.eql(u8, req, "reload")) {
            utils.log.info("Reload", .{});

            self.reload(alloc) catch |err| {
                utils.log.err("Failed to reload dictionaries due to {}", .{err});
            };
            return;
        }

        utils.log.err("Not implemented command {s}", .{req});
    }

    fn reload(self: CustomProtocolHandler, alloc: std.mem.Allocator) !void {
        const cfg = try config.loadConfig(alloc);
        defer {
            cfg.deinit(alloc);
            alloc.destroy(cfg);
        }

        try self.dict_mgr.reloadLocations(cfg.dictionaries, cfg.dictionary_directory);
    }
};
