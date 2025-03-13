const std = @import("std");
const utils = @import("../utils/utils.zig");
const zutils = @import("zutils");
const log = zutils.log;

const require = @import("protest").require;

const Self = @This();

url: []const u8 = &.{},
files: []const []const u8 = &.{},

pub fn fileList(alloc: std.mem.Allocator, locations: []const Self, base_path: []const u8) ![]const []const u8 {
    var arr = std.ArrayList([]const u8).init(alloc);
    defer arr.deinit();

    for (locations) |loc| {
        if (utils.url.isGzip(loc.url)) {
            try arr.append(try zutils.fs.toAbsolutePathAlloc(alloc, std.mem.trimRight(u8, std.fs.path.basename(loc.url), ".gz"), base_path));
        } else if (utils.url.isTar(loc.url)) {
            for (loc.files) |f| {
                try arr.append(try zutils.fs.toAbsolutePathAlloc(alloc, std.fs.path.basename(f), base_path));
            }
        } else if (utils.url.isHttpUrl(loc.url)) {
            try arr.append(try zutils.fs.toAbsolutePathAlloc(alloc, std.fs.path.basename(loc.url), base_path));
        } else {
            try arr.append(try zutils.fs.toAbsolutePathAlloc(alloc, loc.url, base_path));
        }
    }

    return try arr.toOwnedSlice();
}

test "fileList" {
    const alloc = std.testing.allocator;

    const cwd = try std.fs.cwd().realpathAlloc(alloc, ".");
    defer alloc.free(cwd);

    const home = try zutils.fs.expandTildeAlloc(alloc, "~");
    defer alloc.free(home);

    const locations: []const Self = &.{
        .{ .url = "http://abc.com/test01.txt", .files = &.{} },
        .{ .url = "http://abc.com/test02.txt", .files = &.{} },
        .{ .url = "test03.txt", .files = &.{} },
        .{ .url = "~/test04.txt", .files = &.{} },
        .{ .url = "/test05.txt", .files = &.{} },
        .{ .url = "http://abc.com/test06.txt.gz", .files = &.{} },
        .{ .url = "http://abc.com/test07.tar.gz", .files = &.{ "test07-01.txt", "test07-02.txt" } },
    };

    const translated = try Self.fileList(alloc, locations, cwd);
    defer {
        for (translated) |t| alloc.free(t);
        alloc.free(translated);
    }

    {
        const p = try std.fs.path.join(alloc, &[_][]const u8{ cwd, "test01.txt" });
        defer alloc.free(p);
        try require.equal(p, translated[0]);
    }
    {
        const p = try std.fs.path.join(alloc, &[_][]const u8{ cwd, "test02.txt" });
        defer alloc.free(p);
        try require.equal(p, translated[1]);
    }
    {
        const p = try std.fs.path.join(alloc, &[_][]const u8{ cwd, "test03.txt" });
        defer alloc.free(p);
        try require.equal(p, translated[2]);
    }
    {
        const p = try std.fs.path.join(alloc, &[_][]const u8{ home, "test04.txt" });
        defer alloc.free(p);
        try require.equal(p, translated[3]);
    }
    {
        try require.equal("/test05.txt", translated[4]);
    }
    {
        const p = try std.fs.path.join(alloc, &[_][]const u8{ cwd, "test06.txt" });
        defer alloc.free(p);
        try require.equal(p, translated[5]);
    }
    {
        const p = try std.fs.path.join(alloc, &[_][]const u8{ cwd, "test07-01.txt" });
        defer alloc.free(p);
        try require.equal(p, translated[6]);
    }
    {
        const p = try std.fs.path.join(alloc, &[_][]const u8{ cwd, "test07-02.txt" });
        defer alloc.free(p);
        try require.equal(p, translated[7]);
    }
}

pub fn downloadDicts(
    alloc: std.mem.Allocator,
    locations: []const Self,
    base_path: []const u8,
    force_download: bool,
) !void {
    const abs_base_path = try zutils.fs.toAbsolutePathAlloc(alloc, base_path, null);
    defer alloc.free(abs_base_path);

    std.fs.cwd().makeDir(abs_base_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => {
            return err;
        },
    };

    for (locations) |loc| {
        var dsm = DownloadSM.init(loc, base_path, force_download);
        while (dsm.state != .Finsihed) {
            dsm.do(alloc) catch {
                log.err("Failed to download {s}", .{loc.url});
                break;
            };
        }
        dsm.deinit(alloc);
    }
}

test "downloadDicts" {
    const alloc = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(path);

    const locations: []const Self = &.{
        .{ .url = "https://github.com/uasi/skk-emoji-jisyo/raw/refs/heads/master/SKK-JISYO.emoji.utf8", .files = &.{} },
        .{ .url = "https://skk-dev.github.io/dict/SKK-JISYO.itaiji.JIS3_4.gz", .files = &.{} },
        .{ .url = "https://skk-dev.github.io/dict/SKK-JISYO.edict.tar.gz", .files = &.{"SKK-JISYO.edict"} },
    };
    try downloadDicts(alloc, locations, path, false);

    for (&[_][]const u8{
        "SKK-JISYO.emoji.utf8",
        "SKK-JISYO.itaiji.JIS3_4",
        "SKK-JISYO.edict",
    }) |file| {
        const p = try std.fs.path.join(alloc, &[_][]const u8{ path, file });
        defer alloc.free(p);

        try require.isTrue(zutils.fs.isExisting(p));
    }
}

const DownloadSM = struct {
    const State = enum {
        NotStarted,
        WaitForDowload,
        WaitForExtract,
        WaitForUpdate,
        WaitForNotification,
        Finsihed,
    };
    const FileInfo = struct {
        const Result = enum {
            Updated,
            NotUpdated,
            Skipped,
            Failed,
        };
        filename: []const u8,
        path: []const u8,
        result: Result,
    };

    loc: Self,
    base_path: []const u8,
    force_download: bool,

    state: State = .NotStarted,
    is_skipped: bool = false,
    tmp_file: utils.fs.TmpFile = undefined,
    file_infos: []*FileInfo = &.{},

    fn init(loc: Self, base_path: []const u8, force_download: bool) @This() {
        return .{
            .loc = loc,
            .base_path = base_path,
            .force_download = force_download,
        };
    }

    fn deinit(self: *DownloadSM, alloc: std.mem.Allocator) void {
        if (self.file_infos.len > 0) {
            for (self.file_infos) |f| {
                alloc.free(f.filename);
                alloc.free(f.path);
                alloc.destroy(f);
            }
            alloc.free(self.file_infos);
        }

        if (!self.is_skipped) {
            self.tmp_file.deinit(alloc);
        }
    }

    fn do(self: *DownloadSM, alloc: std.mem.Allocator) !void {
        switch (self.state) {
            .NotStarted => {
                const skip = try shouldSkip(alloc, self.loc, self.base_path, self.force_download);
                if (skip) {
                    self.is_skipped = true;
                    self.state = .WaitForNotification;
                    return;
                }
                defer self.state = .WaitForDowload;

                self.tmp_file = try utils.fs.GetTmpFile(alloc);
                return;
            },
            .WaitForDowload => {
                try zutils.http.download(alloc, self.loc.url, self.tmp_file.path);

                self.state = .WaitForExtract;
                return;
            },
            .WaitForExtract => {
                defer self.state = .WaitForUpdate;

                var file_infos = std.ArrayList(*FileInfo).init(alloc);
                defer file_infos.deinit();

                if (!utils.url.isGzip(self.loc.url) and !utils.url.isTar(self.loc.url)) {
                    const info = try alloc.create(FileInfo);
                    info.path = try alloc.dupe(u8, self.tmp_file.path);
                    info.filename = try alloc.dupe(u8, std.fs.path.basename(self.loc.url));

                    try file_infos.append(info);
                    self.file_infos = try file_infos.toOwnedSlice();

                    self.state = .WaitForUpdate;
                    return;
                }

                if (utils.url.isGzip(self.loc.url)) {
                    const decompressed_path = try std.fmt.allocPrint(alloc, "{s}-decompressed", .{self.tmp_file.path});
                    errdefer alloc.free(decompressed_path);

                    try zutils.gzip.unarchive(self.tmp_file.path, decompressed_path);

                    const info = try alloc.create(FileInfo);
                    info.path = decompressed_path;
                    info.filename = try alloc.dupe(u8, std.mem.trimRight(u8, std.fs.path.basename(self.loc.url), ".gz"));

                    try file_infos.append(info);
                    self.file_infos = try file_infos.toOwnedSlice();

                    self.state = .WaitForUpdate;
                    return;
                }

                // tar
                try zutils.gzip.extractTarball(self.tmp_file.path, self.tmp_file.dirPath);

                for (self.loc.files) |f| {
                    const decompressed_path = try zutils.fs.toAbsolutePathAlloc(alloc, f, self.tmp_file.dirPath);

                    const info = try alloc.create(FileInfo);
                    info.path = decompressed_path;
                    info.filename = try alloc.dupe(u8, std.fs.path.basename(f));

                    try file_infos.append(info);
                }
                self.file_infos = try file_infos.toOwnedSlice();
            },
            .WaitForUpdate => {
                defer self.state = .WaitForNotification;

                for (self.file_infos) |f| {
                    const dst_file = try zutils.fs.toAbsolutePathAlloc(alloc, f.filename, self.base_path);
                    defer alloc.free(dst_file);

                    const updated = zutils.fs.isDifferent(alloc, f.path, dst_file);
                    if (updated) {
                        if (std.fs.renameAbsolute(f.path, dst_file)) {
                            f.result = .Updated;
                        } else |_| {
                            f.result = .Failed;
                        }
                    } else {
                        f.result = .Skipped;
                    }
                }
            },
            .WaitForNotification => {
                defer self.state = .Finsihed;

                if (self.is_skipped) {
                    log.debug("{s} skipped", .{std.fs.path.basename(self.loc.url)});
                    return;
                }

                for (self.file_infos) |f| {
                    switch (f.result) {
                        .Failed => log.err("{s} failed", .{f.filename}),
                        .Updated => log.info("{s} updated", .{f.filename}),
                        .NotUpdated => log.debug("{s} not updated", .{f.filename}),
                        .Skipped => log.debug("{s} skipped", .{f.filename}),
                    }
                }
            },
            .Finsihed => {},
        }
    }
};

fn shouldSkip(alloc: std.mem.Allocator, loc: Self, base_path: []const u8, force_download: bool) !bool {
    if (!utils.url.isHttpUrl(loc.url)) {
        return true;
    }

    if (force_download) {
        return false;
    }

    if (utils.url.isGzip(loc.url)) {
        const path = try std.fs.path.join(alloc, &[_][]const u8{
            base_path,
            std.mem.trimRight(u8, std.fs.path.basename(loc.url), ".gz"),
        });
        defer alloc.free(path);
        return zutils.fs.isExisting(path);
    }

    if (utils.url.isTar(loc.url)) {
        for (loc.files) |f| {
            const path = try zutils.fs.toAbsolutePathAlloc(alloc, std.fs.path.basename(f), base_path);
            defer alloc.free(path);

            if (!zutils.fs.isExisting(path)) {
                return false;
            }
        }
        return true;
    }

    const path = try std.fs.path.join(alloc, &[_][]const u8{ base_path, std.fs.path.basename(loc.url) });
    defer alloc.free(path);
    return zutils.fs.isExisting(path);
}

test "shouldSkip" {
    const alloc = std.testing.allocator;
    {
        const loc: Self = .{ .url = "/tmp/filepath", .files = &.{} };
        try require.isTrue(try shouldSkip(alloc, loc, ".", true));
        try require.isTrue(try shouldSkip(alloc, loc, ".", false));
    }
    {
        const loc: Self = .{ .url = "https://abc.com/path/testdata/jisyo.utf8", .files = &.{} };
        try require.isTrue(try shouldSkip(alloc, loc, "testdata", false));
        try require.isFalse(try shouldSkip(alloc, loc, "testdata", true));
    }
    {
        const loc: Self = .{ .url = "https://abc.com/path/testdata/jisyo-notexisting.utf8", .files = &.{} };
        try require.isFalse(try shouldSkip(alloc, loc, "testdata", false));
    }
    {
        const loc: Self = .{ .url = "https://abc.com/path/testdata/jisyo.utf8.gz", .files = &.{} };
        try require.isTrue(try shouldSkip(alloc, loc, "testdata", false));
        try require.isFalse(try shouldSkip(alloc, loc, "testdata", true));
    }
    {
        const loc: Self = .{ .url = "https://abc.com/path/testdata/jisyo-notexisting.utf8.gz", .files = &.{} };
        try require.isFalse(try shouldSkip(alloc, loc, "testdata", false));
    }
    {
        const loc: Self = .{ .url = "https://abc.com/path/testdata/somefile.tar.gz", .files = &.{"jisyo.utf8"} };
        try require.isTrue(try shouldSkip(alloc, loc, "testdata", false));
        try require.isFalse(try shouldSkip(alloc, loc, "testdata", true));
    }
    {
        const loc: Self = .{ .url = "https://abc.com/path/testdata/somefile.tar.gz", .files = &.{"jisyo.utf8,notexisting.utf8"} };
        try require.isFalse(try shouldSkip(alloc, loc, "testdata", false));
    }
}
