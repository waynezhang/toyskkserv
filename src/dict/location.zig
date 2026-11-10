const std = @import("std");
const utils = @import("../utils/utils.zig");
const log = utils.log;

const Self = @This();

url: []const u8 = &.{},
files: []const []const u8 = &.{},

pub fn fileList(io: std.Io, alloc: std.mem.Allocator, locations: []const Self, base_path: []const u8) ![]const []const u8 {
    var arr = try std.ArrayList([]const u8).initCapacity(alloc, 0);
    defer arr.deinit(alloc);

    for (locations) |loc| {
        if (utils.url.isGzip(loc.url)) {
            try arr.append(alloc, try utils.fs.toAbsolutePathAlloc(io, alloc, std.mem.trimEnd(u8, std.fs.path.basename(loc.url), ".gz"), base_path));
        } else if (utils.url.isTar(loc.url)) {
            for (loc.files) |f| {
                try arr.append(alloc, try utils.fs.toAbsolutePathAlloc(io, alloc, std.fs.path.basename(f), base_path));
            }
        } else if (utils.url.isHttpUrl(loc.url)) {
            try arr.append(alloc, try utils.fs.toAbsolutePathAlloc(io, alloc, std.fs.path.basename(loc.url), base_path));
        } else {
            try arr.append(alloc, try utils.fs.toAbsolutePathAlloc(io, alloc, loc.url, base_path));
        }
    }

    return try arr.toOwnedSlice(alloc);
}

test "fileList" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    const cwd = try std.Io.Dir.cwd().realPathFileAlloc(io, ".", alloc);
    defer alloc.free(cwd);

    const home = try utils.fs.expandTildeAlloc(alloc, "~");
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

    const translated = try Self.fileList(io, alloc, locations, cwd);
    defer {
        for (translated) |t| alloc.free(t);
        alloc.free(translated);
    }

    {
        const p = try std.fs.path.join(alloc, &[_][]const u8{ cwd, "test01.txt" });
        defer alloc.free(p);
        try std.testing.expectEqualStrings(p, translated[0]);
    }
    {
        const p = try std.fs.path.join(alloc, &[_][]const u8{ cwd, "test02.txt" });
        defer alloc.free(p);
        try std.testing.expectEqualStrings(p, translated[1]);
    }
    {
        const p = try std.fs.path.join(alloc, &[_][]const u8{ cwd, "test03.txt" });
        defer alloc.free(p);
        try std.testing.expectEqualStrings(p, translated[2]);
    }
    {
        const p = try std.fs.path.join(alloc, &[_][]const u8{ home, "test04.txt" });
        defer alloc.free(p);
        try std.testing.expectEqualStrings(p, translated[3]);
    }
    {
        try std.testing.expectEqualStrings("/test05.txt", translated[4]);
    }
    {
        const p = try std.fs.path.join(alloc, &[_][]const u8{ cwd, "test06.txt" });
        defer alloc.free(p);
        try std.testing.expectEqualStrings(p, translated[5]);
    }
    {
        const p = try std.fs.path.join(alloc, &[_][]const u8{ cwd, "test07-01.txt" });
        defer alloc.free(p);
        try std.testing.expectEqualStrings(p, translated[6]);
    }
    {
        const p = try std.fs.path.join(alloc, &[_][]const u8{ cwd, "test07-02.txt" });
        defer alloc.free(p);
        try std.testing.expectEqualStrings(p, translated[7]);
    }
}

pub fn downloadDicts(
    io: std.Io,
    alloc: std.mem.Allocator,
    locations: []const Self,
    base_path: []const u8,
    force_download: bool,
) !void {
    const abs_base_path = try utils.fs.toAbsolutePathAlloc(io, alloc, base_path, null);
    defer alloc.free(abs_base_path);

    std.Io.Dir.cwd().createDir(io, abs_base_path, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => {
            return err;
        },
    };

    for (locations) |loc| {
        var dsm = DownloadSM.init(loc, base_path, force_download);
        while (dsm.state != .Finsihed) {
            dsm.do(io, alloc) catch {
                log.err("Failed to download {s}", .{loc.url});
                break;
            };
        }
        dsm.deinit(io, alloc);
    }
}

test "downloadDicts" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tmp.dir.realPathFileAlloc(io, ".", alloc);
    defer alloc.free(path);

    const locations: []const Self = &.{
        .{ .url = "https://github.com/uasi/skk-emoji-jisyo/raw/refs/heads/master/SKK-JISYO.emoji.utf8", .files = &.{} },
        .{ .url = "https://skk-dev.github.io/dict/SKK-JISYO.itaiji.JIS3_4.gz", .files = &.{} },
        .{ .url = "https://skk-dev.github.io/dict/SKK-JISYO.edict.tar.gz", .files = &.{"SKK-JISYO.edict"} },
    };
    try downloadDicts(io, alloc, locations, path, false);

    for (&[_][]const u8{
        "SKK-JISYO.emoji.utf8",
        "SKK-JISYO.itaiji.JIS3_4",
        "SKK-JISYO.edict",
    }) |file| {
        const p = try std.fs.path.join(alloc, &[_][]const u8{ path, file });
        defer alloc.free(p);

        try std.testing.expect(utils.fs.isExisting(io, p));
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
        result: Result = .NotUpdated,

        /// Takes ownership of `path`, even on failure.
        fn create(alloc: std.mem.Allocator, path: []const u8, filename: []const u8) !*FileInfo {
            errdefer alloc.free(path);
            const info = try alloc.create(FileInfo);
            errdefer alloc.destroy(info);
            info.* = .{
                .path = path,
                .filename = try alloc.dupe(u8, filename),
            };
            return info;
        }

        fn destroy(self: *FileInfo, alloc: std.mem.Allocator) void {
            alloc.free(self.filename);
            alloc.free(self.path);
            alloc.destroy(self);
        }
    };

    loc: Self,
    base_path: []const u8,
    force_download: bool,

    state: State = .NotStarted,
    is_skipped: bool = false,
    /// Null until created, so deinit is safe if an earlier step failed.
    tmp_file: ?utils.fs.TmpFile = null,
    file_infos: []*FileInfo = &.{},

    fn init(loc: Self, base_path: []const u8, force_download: bool) @This() {
        return .{
            .loc = loc,
            .base_path = base_path,
            .force_download = force_download,
        };
    }

    fn deinit(self: *DownloadSM, io: std.Io, alloc: std.mem.Allocator) void {
        if (self.file_infos.len > 0) {
            for (self.file_infos) |f| f.destroy(alloc);
            alloc.free(self.file_infos);
        }

        if (self.tmp_file) |*tmp_file| {
            tmp_file.deinit(io, alloc);
        }
    }

    fn do(self: *DownloadSM, io: std.Io, alloc: std.mem.Allocator) !void {
        switch (self.state) {
            .NotStarted => {
                const skip = try shouldSkip(io, alloc, self.loc, self.base_path, self.force_download);
                if (skip) {
                    self.is_skipped = true;
                    self.state = .WaitForNotification;
                    return;
                }
                defer self.state = .WaitForDowload;

                self.tmp_file = try utils.fs.GetTmpFile(io, alloc);
                return;
            },
            .WaitForDowload => {
                try utils.http.download(io, alloc, self.loc.url, self.tmp_file.?.path);

                self.state = .WaitForExtract;
                return;
            },
            .WaitForExtract => {
                defer self.state = .WaitForUpdate;
                const tmp_file = &self.tmp_file.?;

                var file_infos = try std.ArrayList(*FileInfo).initCapacity(alloc, 0);
                defer file_infos.deinit(alloc);
                errdefer for (file_infos.items) |f| f.destroy(alloc);

                if (!utils.url.isGzip(self.loc.url) and !utils.url.isTar(self.loc.url)) {
                    const path = try alloc.dupe(u8, tmp_file.path);
                    const info = try FileInfo.create(alloc, path, std.fs.path.basename(self.loc.url));
                    errdefer info.destroy(alloc);
                    try file_infos.append(alloc, info);
                } else if (utils.url.isGzip(self.loc.url)) {
                    const decompressed_path = try std.fmt.allocPrint(alloc, "{s}-decompressed", .{tmp_file.path});
                    utils.gzip.unarchive(io, tmp_file.path, decompressed_path) catch |err| {
                        alloc.free(decompressed_path);
                        return err;
                    };

                    const info = try FileInfo.create(alloc, decompressed_path, std.mem.trimEnd(u8, std.fs.path.basename(self.loc.url), ".gz"));
                    errdefer info.destroy(alloc);
                    try file_infos.append(alloc, info);
                } else {
                    // tar
                    try utils.gzip.extractTarball(io, tmp_file.path, tmp_file.dirPath);

                    for (self.loc.files) |f| {
                        const decompressed_path = try utils.fs.toAbsolutePathAlloc(io, alloc, f, tmp_file.dirPath);
                        const info = try FileInfo.create(alloc, decompressed_path, std.fs.path.basename(f));
                        errdefer info.destroy(alloc);
                        try file_infos.append(alloc, info);
                    }
                }

                self.file_infos = try file_infos.toOwnedSlice(alloc);
            },
            .WaitForUpdate => {
                defer self.state = .WaitForNotification;

                for (self.file_infos) |f| {
                    const dst_file = try utils.fs.toAbsolutePathAlloc(io, alloc, f.filename, self.base_path);
                    defer alloc.free(dst_file);

                    const updated = utils.fs.isDifferent(io, alloc, f.path, dst_file);
                    if (updated) {
                        if (std.Io.Dir.renameAbsolute(f.path, dst_file, io)) {
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

fn shouldSkip(io: std.Io, alloc: std.mem.Allocator, loc: Self, base_path: []const u8, force_download: bool) !bool {
    if (!utils.url.isHttpUrl(loc.url)) {
        return true;
    }

    if (force_download) {
        return false;
    }

    if (utils.url.isGzip(loc.url)) {
        const path = try std.fs.path.join(alloc, &[_][]const u8{
            base_path,
            std.mem.trimEnd(u8, std.fs.path.basename(loc.url), ".gz"),
        });
        defer alloc.free(path);
        return utils.fs.isExisting(io, path);
    }

    if (utils.url.isTar(loc.url)) {
        for (loc.files) |f| {
            const path = try utils.fs.toAbsolutePathAlloc(io, alloc, std.fs.path.basename(f), base_path);
            defer alloc.free(path);

            if (!utils.fs.isExisting(io, path)) {
                return false;
            }
        }
        return true;
    }

    const path = try std.fs.path.join(alloc, &[_][]const u8{ base_path, std.fs.path.basename(loc.url) });
    defer alloc.free(path);
    return utils.fs.isExisting(io, path);
}

test "shouldSkip" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;
    {
        const loc: Self = .{ .url = "/tmp/filepath", .files = &.{} };
        try std.testing.expect(try shouldSkip(io, alloc, loc, ".", true));
        try std.testing.expect(try shouldSkip(io, alloc, loc, ".", false));
    }
    {
        const loc: Self = .{ .url = "https://abc.com/path/testdata/jisyo.utf8", .files = &.{} };
        try std.testing.expect(try shouldSkip(io, alloc, loc, "testdata", false));
        try std.testing.expect(!try shouldSkip(io, alloc, loc, "testdata", true));
    }
    {
        const loc: Self = .{ .url = "https://abc.com/path/testdata/jisyo-notexisting.utf8", .files = &.{} };
        try std.testing.expect(!try shouldSkip(io, alloc, loc, "testdata", false));
    }
    {
        const loc: Self = .{ .url = "https://abc.com/path/testdata/jisyo.utf8.gz", .files = &.{} };
        try std.testing.expect(try shouldSkip(io, alloc, loc, "testdata", false));
        try std.testing.expect(!try shouldSkip(io, alloc, loc, "testdata", true));
    }
    {
        const loc: Self = .{ .url = "https://abc.com/path/testdata/jisyo-notexisting.utf8.gz", .files = &.{} };
        try std.testing.expect(!try shouldSkip(io, alloc, loc, "testdata", false));
    }
    {
        const loc: Self = .{ .url = "https://abc.com/path/testdata/somefile.tar.gz", .files = &.{"jisyo.utf8"} };
        try std.testing.expect(try shouldSkip(io, alloc, loc, "testdata", false));
        try std.testing.expect(!try shouldSkip(io, alloc, loc, "testdata", true));
    }
    {
        const loc: Self = .{ .url = "https://abc.com/path/testdata/somefile.tar.gz", .files = &.{"jisyo.utf8,notexisting.utf8"} };
        try std.testing.expect(!try shouldSkip(io, alloc, loc, "testdata", false));
    }
}
