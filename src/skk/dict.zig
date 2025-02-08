const std = @import("std");
const btree = @import("btree-zig");
const c = @cImport({
    @cInclude("btree.h");
});
const log = @import("../log.zig");
const utils = @import("utils.zig");
const download = @import("download.zig").download;
const euc_jp = @import("../japanese/euc_jp.zig");
const require = @import("protest").require;

pub const Encoding = enum {
    euc_jp,
    utf8,
    undecided,
};

const Entry = struct {
    key: []const u8,
    candidate: []const u8,

    fn compare(a: *Entry, b: *Entry, _: ?*void) c_int {
        const order = std.mem.order(u8, a.key, b.key);
        switch (order) {
            .lt => {
                return -1;
            },
            .eq => {
                return 0;
            },
            .gt => {
                return 1;
            },
        }
    }
};

pub const DictManager = struct {
    allocator: std.mem.Allocator,
    tree: *btree.Btree(Entry, void) = undefined,

    pub fn init(allocator: std.mem.Allocator) !@This() {
        var manager: @This() = undefined;
        manager.allocator = allocator;

        manager.tree = try allocator.create(btree.Btree(Entry, void));
        manager.tree.* = btree.Btree(Entry, void).init(0, Entry.compare, null);

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
        std.fs.cwd().makeDir(dictionary_path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => {
                return err;
            },
        };

        // jdz allocator will crash
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer {
            const deinit_status = gpa.deinit();
            if (deinit_status == .leak) unreachable;
        }
        const alloc = gpa.allocator();

        log.info("Downloading missing files", .{});
        const result = try downloadFiles(alloc, urls, dictionary_path, false);
        log.info("Download done ({d}/{d} downloaded, {d} skipped)", .{ result.downloaded, urls.len, result.failed });

        const files = try utils.translateUrlsToFiles(self.allocator, urls);
        defer self.allocator.free(files);

        try self.loadFiles(files, dictionary_path);
    }

    pub fn findCandidate(self: *const @This(), key: []const u8) []const u8 {
        if (key.len == 0) {
            return "";
        }
        const found: Entry = .{
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
            fn iter(a: *Entry, context: ?*Ctx) bool {
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

        const pivot = Entry{
            .key = key,
            .candidate = "",
        };
        _ = self.tree.ascend(Ctx, &ctx, &pivot, cb.iter);
        if (arr.items.len > 0) {
            arr.append('/') catch {};
        }

        return try arr.toOwnedSlice();
    }

    fn loadFiles(self: *const @This(), filenames: []const []const u8, base_path: []const u8) !void {
        log.info("Start loading dictionaries", .{});

        var loaded: i16 = 0;
        for (filenames) |filename| {
            const path = if (std.mem.startsWith(u8, filename, "~/"))
                try utils.expandTilde(self.allocator, filename)
            else
                try std.fs.path.join(self.allocator, &[_][]const u8{
                    base_path,
                    filename,
                });
            defer self.allocator.free(path);

            const full_path = std.fs.cwd().realpathAlloc(self.allocator, path) catch |err| {
                log.err("Failed to get full path of {s} due to {}", .{ path, err });
                continue;
            };
            defer self.allocator.free(full_path);

            loadFile(self.allocator, self.tree, full_path) catch |err| {
                log.err("Failed to open file {s} due to {}", .{ filename, err });
                continue;
            };

            loaded += 1;
        }
        log.info("Loaded {d}/{d} dictionaries", .{ loaded, filenames.len });
    }
};

fn loadFile(allocator: std.mem.Allocator, tree: *btree.Btree(Entry, void), filename: []const u8) !void {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var reader = buf_reader.reader();

    var encoding: Encoding = if (std.mem.endsWith(u8, filename, ".utf8")) blk: {
        log.debug("Prcoessing file: {s} in encode: {s}", .{ utils.extractFilename(filename), "utf8" });
        break :blk .utf8;
    } else .undecided;

    var line_buf: [8192]u8 = undefined;

    while (reader.readUntilDelimiterOrEof(&line_buf, '\n') catch "") |line| {
        if (encoding == .undecided) {
            encoding = utils.detectEncoding(line);
            log.debug("Prcoessing file: {s} in encode: {s}", .{ utils.extractFilename(filename), @tagName(encoding) });
        }
        if (std.mem.startsWith(u8, line, ";;")) {
            continue;
        }
        if (encoding == .utf8) {
            processLine(allocator, tree, line);
        } else {
            if (euc_jp.convertEucJpToUtf8(allocator, line)) |utf8_line| {
                defer allocator.free(utf8_line);

                processLine(allocator, tree, utf8_line);
            } else |_| {}
        }
    }
}

test "DictManager" {
    const url = "https://github.com/uasi/skk-emoji-jisyo/raw/refs/heads/master/SKK-JISYO.emoji.utf8";

    const alloc = std.testing.allocator;

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
    try require.equal("/😄/", mgr.findCandidate("smile"));
    try require.equal("", mgr.findCandidate("smilesmile"));

    {
        const comp = try mgr.findCompletion(alloc, "");
        defer alloc.free(comp);
        try require.equal("", comp);
    }
    {
        const comp = try mgr.findCompletion(alloc, "smi");
        defer alloc.free(comp);
        try require.equal("/smile/smile_cat/smiley/smiley_cat/smiling_face_with_tear/smiling_face_with_three_hearts/smiling_imp/smirk/smirk_cat/", comp);
    }

    // reload
    try mgr.reloadUrls(&[_][]const u8{}, path);
    try require.equal("", mgr.findCandidate("smile"));

    try mgr.reloadUrls(&[_][]const u8{url}, path);
    try require.equal("/😄/", mgr.findCandidate("smile"));
}

fn processLine(allocator: std.mem.Allocator, tree: *btree.Btree(Entry, void), line: []const u8) void {
    const key, const cdd = utils.splitFirstSpace(line);
    if (cdd.len == 0) {
        log.info("Invalid line: {s}", .{cdd});
        return;
    }

    const found: Entry = .{
        .key = key,
        .candidate = "",
    };

    if (tree.get(&found)) |ent| {
        if (false) {} else {
            if (utils.concatCandidats(allocator, ent.candidate, cdd)) |concated| {
                allocator.free(ent.candidate);
                ent.candidate = concated;
            } else |err| {
                log.err("Failed to concatCandidate {}", .{err});
            }
        }
    } else {
        const ent: Entry = .{
            .key = allocator.dupe(u8, key) catch unreachable,
            .candidate = allocator.dupe(u8, cdd) catch unreachable,
        };

        _ = tree.set(&ent);
    }
}

fn clearBtree(alloc: std.mem.Allocator, tree: *btree.Btree(Entry, void)) void {
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
    var tree = btree.Btree(Entry, void).init(0, Entry.compare, null);
    defer {
        clearBtree(alloc, &tree);
        tree.deinit();
    }

    var found: Entry = .{
        .key = "",
        .candidate = "",
    };
    {
        processLine(alloc, &tree, "test /abc/");

        found.key = "test";
        const ret = tree.get(&found);
        try require.equal("/abc/", ret.?.candidate);
    }
    {
        processLine(alloc, &tree, "test2 /123/");

        found.key = "test2";
        const ret = tree.get(&found);
        try require.equal("/123/", ret.?.candidate);
    }
    {
        processLine(alloc, &tree, "test /def/");

        found.key = "test";
        const ret = tree.get(&found);
        try require.equal("/abc/def/", ret.?.candidate);
    }
}

fn downloadFiles(alloc: std.mem.Allocator, urls: []const []const u8, base_path: []const u8, force_download: bool) !struct {
    downloaded: i16,
    skipped: i16,
    failed: i16,
} {
    var downloaded: i16 = 0;
    var skipped: i16 = 0;
    var failed: i16 = 0;
    for (urls) |url| {
        if (!utils.isHttpUrl(url)) {
            skipped += 1;
            continue;
        }
        const filename = utils.extractFilename(url);
        const full_path = try std.fs.path.join(alloc, &[_][]const u8{
            base_path,
            filename,
        });
        defer alloc.free(full_path);

        if (!force_download and utils.isFileExisting(full_path)) {
            skipped += 1;
            continue;
        }

        log.info("Downloading {s}", .{full_path});
        download(alloc, url, full_path) catch |err| {
            log.err("Failed to download file {s} to {s} due to {}", .{ url, full_path, err });
            failed += 1;
            continue;
        };

        downloaded += 1;
    }

    return .{
        .downloaded = downloaded,
        .skipped = skipped,
        .failed = failed,
    };
}

test "downloadFiles leak check" {
    const alloc = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(tmp_path);

    const urls = [_][]const u8{
        "https://github.com/uasi/skk-emoji-jisyo/raw/refs/heads/master/SKK-JISYO.emoji.utf8",
    };
    {
        const result = try downloadFiles(std.testing.allocator, &urls, tmp_path, true);
        try require.equal(@as(i16, 1), result.downloaded);
    }
    {
        const result = try downloadFiles(std.testing.allocator, &urls, tmp_path, false);
        try require.equal(@as(i16, 0), result.downloaded);
        try require.equal(@as(i16, 1), result.skipped);
    }
    {
        const result = try downloadFiles(std.testing.allocator, &urls, tmp_path, true);
        try require.equal(@as(i16, 1), result.downloaded);
        try require.equal(@as(i16, 0), result.skipped);
    }
}
