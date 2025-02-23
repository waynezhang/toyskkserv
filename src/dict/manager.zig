const std = @import("std");
const btree = @import("btree-zig");
const Location = @import("location.zig");
const skk = @import("../skk/skk.zig");
const utils = @import("../utils/utils.zig");
const Entry = @import("entry.zig");
const require = @import("protest").require;

const Self = @This();

allocator: std.mem.Allocator,
tree: *btree.Btree(Entry, void) = undefined,

pub fn init(allocator: std.mem.Allocator) !Self {
    var manager: @This() = undefined;
    manager.allocator = allocator;

    manager.tree = try allocator.create(btree.Btree(Entry, void));
    manager.tree.* = btree.Btree(Entry, void).init(0, Entry.compare, null);

    return manager;
}

pub fn deinit(self: *Self) void {
    clearBtree(self.allocator, self.tree);
    self.tree.deinit();
    self.allocator.destroy(self.tree);
}

pub fn reloadLocations(self: *Self, locations: []const Location, dictionary_path: []const u8) !void {
    clearBtree(self.allocator, self.tree);

    const files = try Location.fileList(self.allocator, locations, dictionary_path);
    defer {
        for (files) |f| {
            self.allocator.free(f);
        }
        self.allocator.free(files);
    }

    try self.loadFiles(files);
}

pub fn findCandidate(self: *const Self, alloc: std.mem.Allocator, key: []const u8) []const u8 {
    if (key.len == 0) {
        return "";
    }
    const found = Entry.initFrom(alloc, key, "") catch return "";
    defer found.deinit(alloc);

    if (self.tree.get(&found)) |ent| {
        return ent.candidate();
    }
    return "";
}

pub fn findCompletion(self: *const Self, alloc: std.mem.Allocator, key: []const u8) ![]const u8 {
    if (key.len == 0) {
        return alloc.dupe(u8, key);
    }
    const Ctx = struct {
        pivo_key: []const u8,
        arr: *std.ArrayList(u8),
    };
    const cb = struct {
        fn iter(a: *Entry, context: ?*Ctx) bool {
            if (std.mem.startsWith(u8, a.key(), context.?.pivo_key)) {
                context.?.arr.append('/') catch {
                    return false;
                };
                context.?.arr.appendSlice(a.key()) catch {
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

    const pivot = try Entry.initFrom(alloc, key, "");
    defer pivot.deinit(alloc);

    _ = self.tree.ascend(Ctx, &ctx, &pivot, cb.iter);
    if (arr.items.len > 0) {
        arr.append('/') catch {};
    }

    return try arr.toOwnedSlice();
}

test "DictManager" {
    const alloc = std.testing.allocator;

    const url = try std.fs.cwd().realpathAlloc(alloc, "testdata/jisyo.utf8");
    defer alloc.free(url);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(path);

    var mgr = try init(alloc);
    defer mgr.deinit();

    const locations: []const Location = &.{
        .{
            .url = url,
            .files = &.{},
        },
    };
    try mgr.reloadLocations(locations, path);

    try require.equal("", mgr.findCandidate(alloc, ""));
    try require.equal("/キロ/", mgr.findCandidate(alloc, "1024"));
    try require.equal("", mgr.findCandidate(alloc, "1000000"));

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
    try mgr.reloadLocations(&[_]Location{}, path);
    try require.equal("", mgr.findCandidate(alloc, "1024"));

    try mgr.reloadLocations(locations, path);
    try require.equal("/キロ/", mgr.findCandidate(alloc, "1024"));
}

fn loadFiles(self: *const Self, filenames: []const []const u8) !void {
    utils.log.info("Start loading dictionaries", .{});

    var loaded: i16 = 0;
    for (filenames) |filename| {
        loadFile(self.allocator, self.tree, filename) catch |err| {
            utils.log.err("Failed to open file {s} due to {}", .{ filename, err });
            continue;
        };

        loaded += 1;
    }

    utils.log.info("Loaded {d}/{d} dictionaries, {d} entries", .{ loaded, filenames.len, self.tree.count() });
}

fn loadFile(allocator: std.mem.Allocator, tree: *btree.Btree(Entry, void), filename: []const u8) !void {
    utils.log.debug("Processing file {s}", .{std.fs.path.basename(filename)});

    var line_buf = [_]u8{0} ** 4096;
    var conv_buf = [_]u8{0} ** 4096;

    var ite = try skk.OpenDictionaryFile(filename, &line_buf);
    defer ite.deinit();

    while (try ite.next(&conv_buf)) |pair| {
        processLine(allocator, tree, pair.key, pair.candidate) catch |err| {
            utils.log.err("Failed to process line {s} due to {}", .{ pair.key, err });
        };
    }
}

fn processLine(allocator: std.mem.Allocator, tree: *btree.Btree(Entry, void), key: []const u8, candidate: []const u8) !void {
    const found: Entry = try Entry.initFrom(allocator, key, "");
    defer found.deinit(allocator);

    if (tree.delete(&found)) |ent| {
        defer ent.deinit(allocator);

        const new_cdd = try std.mem.concat(allocator, u8, &[_][]const u8{
            ent.candidate(),
            candidate[1..],
        });
        defer allocator.free(new_cdd);

        var new_ent = try Entry.initFrom(allocator, key, new_cdd);
        _ = tree.set(&new_ent);
    } else {
        const ent = try Entry.initFrom(allocator, key, candidate);
        _ = tree.set(&ent);
    }
}

test "processLine" {
    const alloc = std.testing.allocator;
    var tree = btree.Btree(Entry, void).init(0, Entry.compare, null);
    defer {
        clearBtree(alloc, &tree);
        tree.deinit();
    }

    {
        try processLine(alloc, &tree, "test", "/abc/");

        var found = try Entry.initFrom(alloc, "test", "");
        defer found.deinit(alloc);

        const ret = tree.get(&found);
        try require.equal("/abc/", ret.?.candidate());
    }
    {
        try processLine(alloc, &tree, "test2", "/123/");

        var found = try Entry.initFrom(alloc, "test2", "");
        defer found.deinit(alloc);

        const ret = tree.get(&found);
        try require.equal("/123/", ret.?.candidate());
    }
    {
        try processLine(alloc, &tree, "test", "/def/");

        var found = try Entry.initFrom(alloc, "test", "");
        defer found.deinit(alloc);

        const ret = tree.get(&found);
        try require.equal("/abc/def/", ret.?.candidate());
    }
}

fn clearBtree(alloc: std.mem.Allocator, tree: *btree.Btree(Entry, void)) void {
    while (true) {
        if (tree.popMin()) |ent| {
            ent.deinit(alloc);
        } else {
            break;
        }
    }
    tree.clear();
}
