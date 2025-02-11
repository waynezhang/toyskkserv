const std = @import("std");
const btree = @import("btree-zig");
const skk = @import("skk/skk.zig");
const utils = @import("utils/utils.zig");

const require = @import("protest").require;

pub const DictManager = struct {
    allocator: std.mem.Allocator,
    tree: *btree.Btree(skk.Entry, void) = undefined,

    pub fn init(allocator: std.mem.Allocator) !@This() {
        var manager: @This() = undefined;
        manager.allocator = allocator;

        manager.tree = try allocator.create(btree.Btree(skk.Entry, void));
        manager.tree.* = btree.Btree(skk.Entry, void).init(0, skk.Entry.compare, null);

        return manager;
    }

    pub fn deinit(self: *@This()) void {
        clearBtree(self.allocator, self.tree);
        self.tree.deinit();
        self.allocator.destroy(self.tree);
    }

    pub fn reloadUrls(self: *@This(), urls: []const []const u8, dictionary_path: []const u8) !void {
        clearBtree(self.allocator, self.tree);
        try self.loadUrls(urls, dictionary_path);
    }

    pub fn loadUrls(self: *@This(), urls: []const []const u8, dictionary_path: []const u8) !void {
        const files = try utils.url.translateUrlsToFiles(self.allocator, urls, dictionary_path);
        defer {
            for (files) |f| {
                self.allocator.free(f);
            }
            self.allocator.free(files);
        }

        try self.loadFiles(files);
    }

    pub fn findCandidate(self: *const @This(), key: []const u8) []const u8 {
        if (key.len == 0) {
            return "";
        }
        const found: skk.Entry = .{
            .key = key,
            .candidate = "",
        };
        if (self.tree.get(&found)) |ent| {
            return ent.candidate;
        }
        return "";
    }

    pub fn findCompletion(self: *const @This(), alloc: std.mem.Allocator, key: []const u8) ![]const u8 {
        if (key.len == 0) {
            return alloc.dupe(u8, key);
        }
        const Ctx = struct {
            pivo_key: []const u8,
            arr: *std.ArrayList(u8),
        };
        const cb = struct {
            fn iter(a: *skk.Entry, context: ?*Ctx) bool {
                if (std.mem.startsWith(u8, a.key, context.?.pivo_key)) {
                    context.?.arr.append('/') catch {
                        return false;
                    };
                    context.?.arr.appendSlice(a.key) catch {
                        return false;
                    };
                    return true;
                }
                return false;
            }
        };

        var arr = std.ArrayList(u8).init(alloc);
        defer arr.deinit();

        var ctx: Ctx = .{
            .pivo_key = key,
            .arr = &arr,
        };

        const pivot = skk.Entry{
            .key = key,
            .candidate = "",
        };
        _ = self.tree.ascend(Ctx, &ctx, &pivot, cb.iter);
        if (arr.items.len > 0) {
            arr.append('/') catch {};
        }

        return try arr.toOwnedSlice();
    }

    fn loadFiles(self: *const @This(), filenames: []const []const u8) !void {
        utils.log.info("Start loading dictionaries", .{});

        var loaded: i16 = 0;
        for (filenames) |filename| {
            loadFile(self.allocator, self.tree, filename) catch |err| {
                utils.log.err("Failed to open file {s} due to {}", .{ filename, err });
                continue;
            };

            loaded += 1;
        }

        utils.log.info("Loaded {d}/{d} dictionaries", .{ loaded, filenames.len });
    }
};

fn loadFile(allocator: std.mem.Allocator, tree: *btree.Btree(skk.Entry, void), filename: []const u8) !void {
    utils.log.info("Processing file {s}", .{utils.fs.extractFilename(filename)});

    var line_buf = [_]u8{0} ** 4096;
    var conv_buf = [_]u8{0} ** 4096;

    var ite = try skk.OpenDictionaryFile(filename, &line_buf);
    defer ite.deinit();

    while (try ite.next(&conv_buf)) |pair| {
        processLine(allocator, tree, pair.key, pair.candidate);
    }
}

test "DictManager" {
    const alloc = std.testing.allocator;

    const url = try std.fs.cwd().realpathAlloc(alloc, "testdata/jisyo.utf8");
    defer alloc.free(url);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(path);

    var mgr = try DictManager.init(alloc);
    defer mgr.deinit();

    try mgr.loadUrls(&[_][]const u8{
        url,
    }, path);

    try require.equal("", mgr.findCandidate(""));
    try require.equal("/キロ/", mgr.findCandidate("1024"));
    try require.equal("", mgr.findCandidate("1000000"));

    {
        const comp = try mgr.findCompletion(alloc, "");
        defer alloc.free(comp);
        try require.equal("", comp);
    }
    {
        const comp = try mgr.findCompletion(alloc, "1");
        defer alloc.free(comp);
        try require.equal("/1024/1seg/", comp);
    }

    // reload
    try mgr.reloadUrls(&[_][]const u8{}, path);
    try require.equal("", mgr.findCandidate("1024"));

    try mgr.reloadUrls(&[_][]const u8{url}, path);
    try require.equal("/キロ/", mgr.findCandidate("1024"));
}

fn processLine(allocator: std.mem.Allocator, tree: *btree.Btree(skk.Entry, void), key: []const u8, candidate: []const u8) void {
    const found: skk.Entry = .{
        .key = key,
        .candidate = "",
    };

    if (tree.get(&found)) |ent| {
        if (false) {} else {
            if (concatCandidats(allocator, ent.candidate, candidate)) |concated| {
                allocator.free(ent.candidate);
                ent.candidate = concated;
            } else |err| {
                utils.log.err("Failed to concatCandidate {}", .{err});
            }
        }
    } else {
        const ent: skk.Entry = .{
            .key = allocator.dupe(u8, key) catch unreachable,
            .candidate = allocator.dupe(u8, candidate) catch unreachable,
        };

        _ = tree.set(&ent);
    }
}

fn clearBtree(alloc: std.mem.Allocator, tree: *btree.Btree(skk.Entry, void)) void {
    while (true) {
        if (tree.popMin()) |ent| {
            alloc.free(ent.key);
            alloc.free(ent.candidate);
        } else {
            break;
        }
    }
    tree.clear();
}

test "processLine" {
    const alloc = std.testing.allocator;
    var tree = btree.Btree(skk.Entry, void).init(0, skk.Entry.compare, null);
    defer {
        clearBtree(alloc, &tree);
        tree.deinit();
    }

    var found: skk.Entry = .{
        .key = "",
        .candidate = "",
    };
    {
        processLine(alloc, &tree, "test", "/abc/");

        found.key = "test";
        const ret = tree.get(&found);
        try require.equal("/abc/", ret.?.candidate);
    }
    {
        processLine(alloc, &tree, "test2", "/123/");

        found.key = "test2";
        const ret = tree.get(&found);
        try require.equal("/123/", ret.?.candidate);
    }
    {
        processLine(alloc, &tree, "test", "/def/");

        found.key = "test";
        const ret = tree.get(&found);
        try require.equal("/abc/def/", ret.?.candidate);
    }
}

fn concatCandidats(allocator: std.mem.Allocator, first: []const u8, second: []const u8) ![]u8 {
    const trimmed_second = if (std.mem.startsWith(u8, second, "/"))
        second[1..]
    else
        second;

    return std.mem.concat(allocator, u8, &[_][]const u8{ first, trimmed_second });
}

test "concatCandidats" {
    const alloc = std.testing.allocator;
    {
        const cdd = try concatCandidats(alloc, "/abc/", "/def/");
        defer alloc.free(cdd);

        try require.equal("/abc/def/", cdd);
    }
    {
        const cdd = try concatCandidats(alloc, "/abc/", "def/");
        defer alloc.free(cdd);

        try require.equal("/abc/def/", cdd);
    }
    {
        const cdd = try concatCandidats(alloc, "/abc/", "");
        defer alloc.free(cdd);

        try require.equal("/abc/", cdd);
    }
}
