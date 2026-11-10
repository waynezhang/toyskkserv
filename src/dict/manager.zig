const std = @import("std");
const log = @import("../utils/utils.zig").log;
const btree = @import("btree_zig");
const Location = @import("location.zig");
const skk = @import("../skk/skk.zig");
const Entry = @import("entry.zig");

const Self = @This();

allocator: std.mem.Allocator,
io: std.Io,
tree: *btree.Btree(Entry, void) = undefined,
/// Owns every Entry in the tree, so a reload can free them all at once
/// instead of one by one (which fragments the heap).
arena: std.heap.ArenaAllocator,

pub fn init(io: std.Io, allocator: std.mem.Allocator) !Self {
    var manager: @This() = undefined;
    manager.allocator = allocator;
    manager.io = io;
    manager.arena = .init(allocator);

    manager.tree = try allocator.create(btree.Btree(Entry, void));
    manager.tree.* = btree.Btree(Entry, void).init(0, Entry.compare, null);

    return manager;
}

pub fn deinit(self: *Self) void {
    self.tree.deinit();
    self.arena.deinit();
    self.allocator.destroy(self.tree);
}

pub fn reloadLocations(self: *Self, locations: []const Location, dictionary_path: []const u8) !void {
    self.tree.clear();
    _ = self.arena.reset(.free_all);

    const files = try Location.fileList(self.io, self.allocator, locations, dictionary_path);
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
    const found = Entry.init(alloc, key, "") catch return "";
    defer found.deinit(alloc);

    if (self.tree.get(&found)) |ent| {
        return ent.candidate();
    }
    return "";
}

pub fn findCompletion(self: *const Self, alloc: std.mem.Allocator, key: []const u8, limit: u16) ![]const u8 {
    if (key.len == 0) {
        return alloc.dupe(u8, key);
    }
    const Ctx = struct {
        pivo_key: []const u8,
        writer: *std.Io.Writer,
        count: u16,
        limit: u16,
    };
    const cb = struct {
        fn iter(a: *Entry, context: ?*Ctx) bool {
            if (std.mem.startsWith(u8, a.key(), context.?.pivo_key)) {
                context.?.writer.writeByte('/') catch {
                    return false;
                };
                _ = context.?.writer.write(a.key()) catch {
                    return false;
                };
                context.?.count += 1;
                if (context.?.count > context.?.limit) {
                    return false;
                }
                return true;
            }
            return false;
        }
    };

    var allocating = std.Io.Writer.Allocating.init(alloc);
    defer allocating.deinit();

    var ctx: Ctx = .{
        .pivo_key = key,
        .writer = &allocating.writer,
        .count = 0,
        .limit = limit,
    };

    const pivot = try Entry.init(alloc, key, "");
    defer pivot.deinit(alloc);

    _ = self.tree.ascend(Ctx, &ctx, &pivot, cb.iter);
    if (ctx.count > 0) {
        allocating.writer.writeByte('/') catch {};
    }

    return try allocating.toOwnedSlice();
}

test "DictManager" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    const url = try std.Io.Dir.cwd().realPathFileAlloc(io, "testdata/jisyo.utf8", alloc);
    defer alloc.free(url);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tmp.dir.realPathFileAlloc(io, ".", alloc);
    defer alloc.free(path);

    var mgr = try init(io, alloc);
    defer mgr.deinit();

    const locations: []const Location = &.{
        .{
            .url = url,
            .files = &.{},
        },
    };
    try mgr.reloadLocations(locations, path);

    try std.testing.expectEqualStrings("", mgr.findCandidate(alloc, ""));
    try std.testing.expectEqualStrings("/キロ/", mgr.findCandidate(alloc, "1024"));
    try std.testing.expectEqualStrings("", mgr.findCandidate(alloc, "1000000"));

    {
        const comp = try mgr.findCompletion(alloc, "", 100);
        defer alloc.free(comp);
        try std.testing.expectEqualStrings("", comp);
    }
    {
        const comp = try mgr.findCompletion(alloc, "1", 100);
        defer alloc.free(comp);
        try std.testing.expectEqualStrings("/1024/1seg/", comp);
    }

    // reload
    try mgr.reloadLocations(&[_]Location{}, path);
    try std.testing.expectEqualStrings("", mgr.findCandidate(alloc, "1024"));

    try mgr.reloadLocations(locations, path);
    try std.testing.expectEqualStrings("/キロ/", mgr.findCandidate(alloc, "1024"));
}

fn loadFiles(self: *Self, filenames: []const []const u8) !void {
    log.info("Start loading dictionaries", .{});

    var loaded: i16 = 0;
    for (filenames) |filename| {
        loadFile(self.io, self.arena.allocator(), self.allocator, self.tree, filename) catch |err| {
            log.err("Failed to open file {s} due to {}", .{ filename, err });
            continue;
        };

        loaded += 1;
    }

    log.info("Loaded {d}/{d} dictionaries, {d} entries", .{ loaded, filenames.len, self.tree.count() });
}

fn loadFile(io: std.Io, entry_alloc: std.mem.Allocator, tmp_alloc: std.mem.Allocator, tree: *btree.Btree(Entry, void), filename: []const u8) !void {
    log.debug("Processing file {s}", .{std.fs.path.basename(filename)});

    var line_buf: [4096]u8 = @splat(0);
    var conv_buf: [4096]u8 = @splat(0);

    var ite = try skk.open(io, filename, &line_buf);
    defer ite.deinit();

    while (try ite.next(&conv_buf)) |pair| {
        processLine(entry_alloc, tmp_alloc, tree, pair.key, pair.candidate) catch |err| {
            log.err("Failed to process line {s} due to {}", .{ pair.key, err });
        };
    }
}

/// `entry_alloc` owns the entries stored in the tree (the manager's arena);
/// `tmp_alloc` is used for scratch buffers freed before returning.
fn processLine(entry_alloc: std.mem.Allocator, tmp_alloc: std.mem.Allocator, tree: *btree.Btree(Entry, void), key: []const u8, candidate: []const u8) !void {
    const found: Entry = try Entry.init(tmp_alloc, key, "");
    defer found.deinit(tmp_alloc);

    const new_ent = if (tree.get(&found)) |ent| blk: {
        const new_cdd = try std.mem.concat(tmp_alloc, u8, &[_][]const u8{
            ent.candidate(),
            candidate[1..],
        });
        defer tmp_alloc.free(new_cdd);

        // If this fails the existing entry stays in the tree untouched.
        break :blk try Entry.init(entry_alloc, key, new_cdd);
    } else try Entry.init(entry_alloc, key, candidate);

    // Replaces the old entry if there was one; its memory belongs to the arena.
    _ = tree.set(&new_ent);
    if (tree.oom()) return error.OutOfMemory;
}

test "processLine" {
    const alloc = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(alloc);
    defer arena.deinit();
    var tree = btree.Btree(Entry, void).init(0, Entry.compare, null);
    defer tree.deinit();

    {
        try processLine(arena.allocator(), alloc, &tree, "test", "/abc/");

        var found = try Entry.init(alloc, "test", "");
        defer found.deinit(alloc);

        const ret = tree.get(&found);
        try std.testing.expectEqualStrings("/abc/", ret.?.candidate());
    }
    {
        try processLine(arena.allocator(), alloc, &tree, "test2", "/123/");

        var found = try Entry.init(alloc, "test2", "");
        defer found.deinit(alloc);

        const ret = tree.get(&found);
        try std.testing.expectEqualStrings("/123/", ret.?.candidate());
    }
    {
        try processLine(arena.allocator(), alloc, &tree, "test", "/def/");

        var found = try Entry.init(alloc, "test", "");
        defer found.deinit(alloc);

        const ret = tree.get(&found);
        try std.testing.expectEqualStrings("/abc/def/", ret.?.candidate());
    }
}
