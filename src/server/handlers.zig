const std = @import("std");
const mem = std.mem;
const log = std.log;
const resp = @import("response.zig");
const ServerError = @import("server.zig").ServerError;
const DictManager = @import("../skk/dict.zig").DictManager;
const google_api = @import("google_api.zig");
const require = @import("protest").require;

pub const Handler = union(enum) {
    disconnectHandler: *DisconnectHandler,
    candidateHandler: *CandidateHandler,
    rawStringHandler: *RawStringHandler,
    completionHandler: *CompletionHandler,

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
        return ServerError.Disconnect;
    }
};

test "DisconnectHandler" {
    var arr = std.ArrayList(u8).init(std.testing.allocator);
    defer arr.deinit();

    var h = DisconnectHandler{};
    const err = h.handle(&arr, "");

    try require.equalError(ServerError.Disconnect, err);
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
        log.info("Fallback to google", .{});

        if (!self.use_google) {
            return try resp.generateResponse(buffer, line, "");
        }
        const fallback = google_api.transliterateRequest(self.allocator, line) catch |err| {
            log.info("Failed to make request due to {}", .{err});
            return;
        };
        defer self.allocator.free(fallback);
        return try resp.generateResponse(buffer, line, fallback);
    }
};

test "CandidateHandler" {
    const alloc = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(path);

    var mgr = try DictManager.init(alloc);
    defer mgr.deinit();

    try mgr.loadUrls(&[_][]const u8{
        "https://github.com/uasi/skk-emoji-jisyo/raw/refs/heads/master/SKK-JISYO.emoji.utf8",
    }, path);

    var arr = std.ArrayList(u8).init(alloc);
    defer arr.deinit();

    var h = CandidateHandler.init(alloc, &mgr, true);

    try h.handle(&arr, "smile");
    try require.equal("1/😄/", arr.items);

    arr.clearAndFree();
    try h.handle(&arr, "smilesmile");
    try require.equal("", arr.items);

    arr.clearAndFree();
    try h.handle(&arr, "=1+1");
    try require.equal("1/2/2=1+1/＝１＋１/=1+1/", arr.items);

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

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(path);

    var mgr = try DictManager.init(alloc);
    defer mgr.deinit();

    try mgr.loadUrls(&[_][]const u8{
        "https://github.com/uasi/skk-emoji-jisyo/raw/refs/heads/master/SKK-JISYO.emoji.utf8",
    }, path);

    var arr = std.ArrayList(u8).init(alloc);
    defer arr.deinit();

    var h = CompletionHandler.init(alloc, &mgr);

    try h.handle(&arr, "smi");
    try require.equal("1/smile/smile_cat/smiley/smiley_cat/smiling_face_with_tear/smiling_face_with_three_hearts/smiling_imp/smirk/smirk_cat/", arr.items);

    arr.clearAndFree();
    try h.handle(&arr, "smilesmile");
    try require.equal("4smilesmile ", arr.items);
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
