const std = @import("std");
const mem = std.mem;
const resp = @import("response.zig");
const log = @import("../log.zig");
const DictManager = @import("../skk/dict.zig").DictManager;
const google_api = @import("google_api.zig");
const config = @import("../config.zig");

const require = @import("protest").require;

pub const Handler = union(enum) {
    disconnect_handler: *DisconnectHandler,
    candidate_handler: *CandidateHandler,
    raw_string_handler: *RawStringHandler,
    completion_handler: *CompletionHandler,
    custom_protocol_handler: *CustomProtocolHandler,

    pub fn handle(self: Handler, buffer: *std.ArrayList(u8), line: []const u8) anyerror!void {
        switch (self) {
            inline else => |case| {
                try case.handle(buffer, line);
            },
        }
    }
};

pub const DisconnectHandler = struct {
    fn handle(_: DisconnectHandler, _: *std.ArrayList(u8), _: []const u8) !void {
        return error.Disconnect;
    }
};

test "DisconnectHandler" {
    var arr = std.ArrayList(u8).init(std.testing.allocator);
    defer arr.deinit();

    var h = DisconnectHandler{};
    const err = h.handle(&arr, "");

    try require.equalError(error.Disconnect, err);
}

pub const CandidateHandler = struct {
    allocator: mem.Allocator,
    dict_mgr: *DictManager,
    use_google: bool,

    pub fn init(allocator: mem.Allocator, dict_mgr: *DictManager, use_google: bool) @This() {
        return .{
            .allocator = allocator,
            .dict_mgr = dict_mgr,
            .use_google = use_google,
        };
    }

    fn handle(self: CandidateHandler, buffer: *std.ArrayList(u8), line: []const u8) !void {
        const cdd = self.dict_mgr.findCandidate(line);
        if (cdd.len > 0) {
            return try resp.generateResponse(buffer, line, cdd);
        }
        if (!self.use_google) {
            return try resp.generateResponse(buffer, line, "");
        }

        log.debug("Fallback to google", .{});
        const fallback = google_api.transliterateRequest(self.allocator, line) catch |err| {
            log.err("Failed to make request due to {}", .{err});
            return try resp.generateResponse(buffer, line, "");
        };
        defer self.allocator.free(fallback);
        return try resp.generateResponse(buffer, line, fallback);
    }
};

test "CandidateHandler" {
    const alloc = std.testing.allocator;

    var mgr = try DictManager.init(alloc);
    defer mgr.deinit();

    try mgr.loadUrls(&[_][]const u8{
        "testdata/jisyo.utf8",
    }, "");

    var arr = std.ArrayList(u8).init(alloc);
    defer arr.deinit();

    var h = CandidateHandler.init(alloc, &mgr, true);

    try h.handle(&arr, "1024");
    try require.equal("1/キロ/", arr.items);

    arr.clearAndFree();
    try h.handle(&arr, "smile");
    try require.equal("4smile ", arr.items);

    arr.clearAndFree();
    try h.handle(&arr, "=1+1");
    try require.equal("1/2/2=1+1/＝１＋１/", arr.items);

    h.use_google = false;
    arr.clearAndFree();
    try h.handle(&arr, "=1+1");
    try require.equal("4=1+1 ", arr.items);
}

pub const CompletionHandler = struct {
    allocator: mem.Allocator,
    dict_mgr: *DictManager,

    pub fn init(alloc: mem.Allocator, dict_mgr: *DictManager) @This() {
        return .{
            .allocator = alloc,
            .dict_mgr = dict_mgr,
        };
    }

    fn handle(self: CompletionHandler, buffer: *std.ArrayList(u8), line: []const u8) !void {
        const cdd = try self.dict_mgr.findCompletion(self.allocator, line);
        defer self.allocator.free(cdd);

        try resp.generateResponse(buffer, line, cdd);
    }
};

test "CompletionHandler" {
    const alloc = std.testing.allocator;

    var mgr = try DictManager.init(alloc);
    defer mgr.deinit();

    try mgr.loadUrls(&[_][]const u8{
        "testdata/jisyo.utf8",
    }, "");

    var arr = std.ArrayList(u8).init(alloc);
    defer arr.deinit();

    var h = CompletionHandler.init(alloc, &mgr);

    try h.handle(&arr, "1");
    try require.equal("1/1024/1seg/", arr.items);

    arr.clearAndFree();
    try h.handle(&arr, "smile");
    try require.equal("4smile ", arr.items);
}

pub const RawStringHandler = struct {
    allocator: mem.Allocator,
    str: []const u8,

    pub fn init(allocator: mem.Allocator, str: []const u8) !@This() {
        return .{
            .allocator = allocator,
            .str = try allocator.dupe(u8, str),
        };
    }

    fn deinit(self: *@This()) void {
        self.allocator.free(self.str);
    }

    fn handle(self: RawStringHandler, buffer: *std.ArrayList(u8), _: []const u8) !void {
        try buffer.appendSlice(self.str);
    }
};

test "RawStringHandler" {
    var arr = std.ArrayList(u8).init(std.testing.allocator);
    defer arr.deinit();

    var h = try RawStringHandler.init(std.testing.allocator, "a string");
    defer h.deinit();

    try h.handle(&arr, "");
    try require.equal("a string", arr.items);
}

pub const CustomProtocolHandler = struct {
    allocator: mem.Allocator,
    dict_mgr: *DictManager,

    pub fn init(alloc: mem.Allocator, dict_mgr: *DictManager) CustomProtocolHandler {
        return .{
            .allocator = alloc,
            .dict_mgr = dict_mgr,
        };
    }

    fn handle(self: CustomProtocolHandler, _: *std.ArrayList(u8), req: []const u8) !void {
        if (mem.eql(u8, req, "reload")) {
            log.info("Reload", .{});

            self.reload() catch |err| {
                log.err("Failed to reload dictionaries due to {}", .{err});
            };
            return;
        }

        log.err("Not implemented command {s}", .{req});
    }

    fn reload(self: CustomProtocolHandler) !void {
        const cfg = try config.loadConfig(self.allocator);
        defer cfg.deinit(self.allocator);

        try reloadDicts(self.dict_mgr, cfg.dictionaries, cfg.dictionary_directory);
    }
};

fn reloadDicts(dict_mgr: *DictManager, dicts: []const []const u8, dictionary_path: []const u8) !void {
    try dict_mgr.reloadUrls(dicts, dictionary_path);
}
