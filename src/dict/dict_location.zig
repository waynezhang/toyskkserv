const std = @import("std");
const temp = @import("temp");

const utils = @import("../utils/utils.zig");

const require = @import("protest").require;

pub const DictLocation = struct {
    url: []const u8,
    files: []const []const u8,

    pub fn fileList(alloc: std.mem.Allocator, locations: []const DictLocation, base_path: []const u8) ![]const []const u8 {
        var arr = std.ArrayList([]const u8).init(alloc);
        defer arr.deinit();

        for (locations) |loc| {
            if (utils.url.isGzip(loc.url)) {
                try arr.append(try utils.fs.toAbsolutePath(alloc, std.mem.trimRight(u8, std.fs.path.basename(loc.url), ".gz"), base_path));
            } else if (utils.url.isTar(loc.url)) {
                for (loc.files) |f| {
                    try arr.append(try utils.fs.toAbsolutePath(alloc, std.fs.path.basename(f), base_path));
                }
            } else if (utils.url.isHttpUrl(loc.url)) {
                try arr.append(try utils.fs.toAbsolutePath(alloc, std.fs.path.basename(loc.url), base_path));
            } else {
                try arr.append(try utils.fs.toAbsolutePath(alloc, loc.url, base_path));
            }
        }

        return try arr.toOwnedSlice();
    }

    test "fileList" {
        const alloc = std.testing.allocator;

        const cwd = try std.fs.cwd().realpathAlloc(alloc, ".");
        defer alloc.free(cwd);

        const home = try utils.fs.expandTilde(alloc, "~");
        defer alloc.free(home);

        const locations: []const DictLocation = &.{
            .{ .url = "http://abc.com/test01.txt", .files = &.{} },
            .{ .url = "http://abc.com/test02.txt", .files = &.{} },
            .{ .url = "test03.txt", .files = &.{} },
            .{ .url = "~/test04.txt", .files = &.{} },
            .{ .url = "/test05.txt", .files = &.{} },
            .{ .url = "http://abc.com/test06.txt.gz", .files = &.{} },
            .{ .url = "http://abc.com/test07.tar.gz", .files = &.{ "test07-01.txt", "test07-02.txt" } },
        };

        const translated = try DictLocation.fileList(alloc, locations, cwd);
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

    pub const Download = struct {
        const Result = enum {
            Downloaded,
            Skipped,
            Failed,
            NotUpdated,
        };

        const ProgressFn = fn (url: []const u8, subFile: []const u8, result: Result) void;

        /// Note: jdz allocator is casuing crash.
        pub fn downloadDicts(
            alloc: std.mem.Allocator,
            locations: []const DictLocation,
            base_path: []const u8,
            force_download: bool,
        ) !void {
            const progress = struct {
                fn log(url: []const u8, subFile: []const u8, result: Result) void {
                    const filename = std.mem.trimRight(u8, std.mem.trimRight(u8, std.fs.path.basename(url), ".gz"), ".tar");

                    switch (result) {
                        .Failed => utils.log.err("{s}{s} failed", .{ filename, subFile }),
                        .Downloaded => utils.log.info("{s}{s} downloaded", .{ filename, subFile }),
                        .NotUpdated => utils.log.debug("{s}{s} not updated", .{ filename, subFile }),
                        .Skipped => utils.log.debug("{s}{s} skipped", .{ filename, subFile }),
                    }
                }
            }.log;

            const abs_base_path = try utils.fs.toAbsolutePath(alloc, base_path, null);
            defer alloc.free(abs_base_path);

            std.fs.cwd().makeDir(abs_base_path) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => {
                    return err;
                },
            };

            for (locations) |loc| {
                if (shouldSkip(alloc, loc, base_path, force_download)) |skip| {
                    if (skip) {
                        progress(loc.url, "", .Skipped);
                        continue;
                    }
                } else |_| {
                    progress(loc.url, "", .Failed);
                }

                downloadDictionary(alloc, loc, base_path, progress);
            }
        }

        test "downloadDicts" {
            const alloc = std.testing.allocator;

            var tmp = std.testing.tmpDir(.{});
            defer tmp.cleanup();
            const path = try tmp.dir.realpathAlloc(alloc, ".");
            defer alloc.free(path);

            const locations: []const DictLocation = &.{
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

                try require.isTrue(utils.fs.isFileExisting(p));
            }
        }
    };
};

fn shouldSkip(alloc: std.mem.Allocator, loc: DictLocation, base_path: []const u8, force_download: bool) !bool {
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
        return utils.fs.isFileExisting(path);
    }

    if (utils.url.isTar(loc.url)) {
        for (loc.files) |f| {
            const path = try utils.fs.toAbsolutePath(alloc, std.fs.path.basename(f), base_path);
            defer alloc.free(path);

            if (!utils.fs.isFileExisting(path)) {
                return false;
            }
        }
        return true;
    }

    const path = try std.fs.path.join(alloc, &[_][]const u8{ base_path, std.fs.path.basename(loc.url) });
    defer alloc.free(path);
    return utils.fs.isFileExisting(path);
}

test "shouldSkip" {
    const alloc = std.testing.allocator;
    {
        const loc: DictLocation = .{ .url = "/tmp/filepath", .files = &.{} };
        try require.isTrue(try shouldSkip(alloc, loc, ".", true));
        try require.isTrue(try shouldSkip(alloc, loc, ".", false));
    }
    {
        const loc: DictLocation = .{ .url = "https://abc.com/path/testdata/jisyo.utf8", .files = &.{} };
        try require.isTrue(try shouldSkip(alloc, loc, "testdata", false));
        try require.isFalse(try shouldSkip(alloc, loc, "testdata", true));
    }
    {
        const loc: DictLocation = .{ .url = "https://abc.com/path/testdata/jisyo-notexisting.utf8", .files = &.{} };
        try require.isFalse(try shouldSkip(alloc, loc, "testdata", false));
    }
    {
        const loc: DictLocation = .{ .url = "https://abc.com/path/testdata/jisyo.utf8.gz", .files = &.{} };
        try require.isTrue(try shouldSkip(alloc, loc, "testdata", false));
        try require.isFalse(try shouldSkip(alloc, loc, "testdata", true));
    }
    {
        const loc: DictLocation = .{ .url = "https://abc.com/path/testdata/jisyo-notexisting.utf8.gz", .files = &.{} };
        try require.isFalse(try shouldSkip(alloc, loc, "testdata", false));
    }
    {
        const loc: DictLocation = .{ .url = "https://abc.com/path/testdata/somefile.tar.gz", .files = &.{"jisyo.utf8"} };
        try require.isTrue(try shouldSkip(alloc, loc, "testdata", false));
        try require.isFalse(try shouldSkip(alloc, loc, "testdata", true));
    }
    {
        const loc: DictLocation = .{ .url = "https://abc.com/path/testdata/somefile.tar.gz", .files = &.{"jisyo.utf8,notexisting.utf8"} };
        try require.isFalse(try shouldSkip(alloc, loc, "testdata", false));
    }
}

fn downloadDictionary(alloc: std.mem.Allocator, loc: DictLocation, base_path: []const u8, progress: DictLocation.Download.ProgressFn) void {
    if (!utils.url.isHttpUrl(loc.url)) {
        unreachable;
    }

    const url = loc.url;

    var tmpFile = utils.fs.GetTmpFile(alloc) catch {
        progress(url, "", .Failed);
        return;
    };
    defer tmpFile.deinit(alloc);

    utils.url.download(alloc, url, tmpFile.path) catch {
        progress(url, "", .Failed);
        return;
    };

    if (utils.url.isGzip(loc.url)) {
        const decompressed_path = std.fmt.allocPrint(alloc, "{s}-decompressed", .{tmpFile.path}) catch {
            progress(url, "", .Failed);
            return;
        };
        defer alloc.free(decompressed_path);

        utils.compress.decompress(tmpFile.path, decompressed_path) catch {
            progress(url, "", .Failed);
        };

        const existing_path = utils.fs.toAbsolutePath(
            alloc,
            std.mem.trimRight(u8, std.fs.path.basename(url), ".gz"),
            base_path,
        ) catch {
            progress(url, "", .Failed);
            return;
        };
        defer {
            alloc.free(existing_path);
        }

        checkAndUpdateFile(alloc, url, decompressed_path, existing_path, "", progress);
        return;
    }

    if (utils.url.isTar(loc.url)) {
        utils.compress.extractTar(tmpFile.path, tmpFile.dirPath) catch {
            progress(url, "", .Failed);
        };

        for (loc.files) |f| {
            const subFile = std.fmt.allocPrint(alloc, "/{s}", .{std.fs.path.basename(f)}) catch {
                progress(url, "", .Failed);
                return;
            };
            defer alloc.free(subFile);

            const existing_path = utils.fs.toAbsolutePath(alloc, std.fs.path.basename(f), base_path) catch {
                progress(url, subFile, .Failed);
                return;
            };
            defer alloc.free(existing_path);

            const decompressed_path = utils.fs.toAbsolutePath(alloc, f, tmpFile.dirPath) catch {
                progress(url, subFile, .Failed);
                return;
            };
            defer alloc.free(decompressed_path);

            checkAndUpdateFile(alloc, url, decompressed_path, existing_path, subFile, progress);
        }
        return;
    }

    // raw http
    const existing_path = utils.fs.toAbsolutePath(alloc, std.fs.path.basename(url), base_path) catch {
        progress(url, "", .Failed);
        return;
    };
    defer alloc.free(existing_path);

    checkAndUpdateFile(alloc, url, tmpFile.path, existing_path, "", progress);
}

fn checkAndUpdateFile(alloc: std.mem.Allocator, url: []const u8, src_file: []const u8, dst_file: []const u8, subFile: []const u8, progress: DictLocation.Download.ProgressFn) void {
    const updated = utils.fs.IsDiff(alloc, src_file, dst_file);
    if (updated) {
        if (std.fs.renameAbsolute(src_file, dst_file)) {
            progress(url, subFile, .Downloaded);
        } else |_| {
            progress(url, subFile, .NotUpdated);
        }
    } else {
        progress(url, subFile, .NotUpdated);
    }
}

test "checkAndUpdateFile" {
    const alloc = std.testing.allocator;

    const downloadProgress = struct {
        fn log(_: []const u8, _: []const u8, result: DictLocation.Download.Result) void {
            require.equal(DictLocation.Download.Result.Downloaded, result) catch unreachable;
        }
    }.log;

    const notUpdatedProgress = struct {
        fn log(_: []const u8, _: []const u8, result: DictLocation.Download.Result) void {
            require.equal(DictLocation.Download.Result.NotUpdated, result) catch unreachable;
        }
    }.log;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(path);

    const org = try std.fs.cwd().realpathAlloc(alloc, "testdata/jisyo.utf8");
    defer alloc.free(org);

    const src = try std.fs.path.join(alloc, &[_][]const u8{ path, "src.utf8" });
    defer alloc.free(src);

    try std.fs.copyFileAbsolute(org, src, .{});

    const dst = try std.fs.path.join(alloc, &[_][]const u8{ path, "dst.utf8" });
    defer alloc.free(dst);

    checkAndUpdateFile(alloc, "url", src, dst, "", downloadProgress);

    try require.isFalse(utils.fs.isFileExisting(src));
    try require.isFalse(utils.fs.IsDiff(alloc, org, dst));

    try std.fs.copyFileAbsolute(org, src, .{});
    checkAndUpdateFile(alloc, "url", src, dst, "", notUpdatedProgress);
}
