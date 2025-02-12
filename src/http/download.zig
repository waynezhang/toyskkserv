const std = @import("std");
const utils = @import("../utils/utils.zig");
const require = @import("protest").require;

/// Download URLs to `base_path` directory. `base_path` is created if it doesn't exist.
/// Note: jdz allocator is casuing crash.
pub const Result = enum {
    Downloaded,
    Skipped,
    Failed,
    NotUpdated,

    pub fn toString(self: Result) []const u8 {
        return switch (self) {
            .Downloaded => "downloaded",
            .Skipped => "skipped",
            .Failed => "failed",
            .NotUpdated => "not updated",
        };
    }
};

pub const ProgressFn = fn (url: []const u8, result: Result) void;

pub fn downloadFiles(alloc: std.mem.Allocator, urls: []const []const u8, base_path: []const u8, force_download: bool, progress: ProgressFn) !void {
    const abs_base_path = try utils.fs.toAbsolutePath(alloc, base_path, null);
    defer alloc.free(abs_base_path);

    std.fs.cwd().makeDir(abs_base_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => {
            return err;
        },
    };

    for (urls) |url| {
        if (!utils.url.isHttpUrl(url)) {
            progress(url, .Skipped);
            continue;
        }
        const filename = utils.fs.extractFilename(url);
        const full_path = try std.fs.path.join(alloc, &[_][]const u8{
            abs_base_path,
            filename,
        });
        defer alloc.free(full_path);

        if (!force_download and utils.fs.isFileExisting(full_path)) {
            progress(url, .Skipped);
            continue;
        }

        const checksum = utils.fs.sha256(alloc, full_path) catch blk: {
            if (utils.fs.isFileExisting(full_path)) {
                progress(url, .Failed);
                continue;
            }
            break :blk "";
        };
        defer alloc.free(checksum);

        download(alloc, url, full_path) catch {
            progress(url, .Failed);
            continue;
        };

        const new_checksum = utils.fs.sha256(alloc, full_path) catch {
            progress(url, .Failed);
            continue;
        };
        defer alloc.free(new_checksum);

        if (std.mem.eql(u8, checksum, new_checksum)) {
            progress(url, .NotUpdated);
        } else {
            progress(url, .Downloaded);
        }
    }
}

fn download(allocator: std.mem.Allocator, url: []const u8, dst: []const u8) !void {
    const uri = try std.Uri.parse(url);

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const header_buf = try allocator.alloc(u8, 1024 * 1024);
    defer allocator.free(header_buf);

    var req = try client.open(.GET, uri, .{ .server_header_buffer = header_buf });
    defer req.deinit();

    try req.send();
    try req.finish();
    try req.wait();

    if (req.response.status != .ok) {
        return error.HttpError;
    }

    const f = try std.fs.cwd().createFile(dst, .{
        .read = true,
        .truncate = true,
    });
    defer f.close();

    var buf_writer = std.io.bufferedWriter(f.writer());

    const buffer = try allocator.alloc(u8, 1024 * 1024);
    defer allocator.free(buffer);

    while (true) {
        const read = try req.reader().read(buffer);
        if (read == 0) {
            break;
        }

        const written = try buf_writer.write(buffer[0..read]);
        if (written != read) {
            return error.WriteError;
        }
    }

    try buf_writer.flush();
}

test "download file from URL" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const dst = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(dst);

    // Test download
    try download(allocator, "https://github.com/arrow2nd/skk-jisyo-emoji-ja/raw/refs/heads/main/skk-jisyo-emoji-ja.utf8", dst);
}

// FIXME
// test "downloadFiles leak check" {
//     const alloc = std.testing.allocator;
//
//     var tmp = std.testing.tmpDir(.{});
//     defer tmp.cleanup();
//
//     const tmp_path = try tmp.dir.realpathAlloc(alloc, ".");
//     defer alloc.free(tmp_path);
//
//     const urls = [_][]const u8{
//         "https://github.com/uasi/skk-emoji-jisyo/raw/refs/heads/master/SKK-JISYO.emoji.utf8",
//     };
//     {
//         const result = try downloadFiles(std.testing.allocator, &urls, tmp_path, true, progressFn(.Downloaded).f);
//         try require.equal(@as(i16, 1), result.downloaded);
//     }
//     {
//         const result = try downloadFiles(std.testing.allocator, &urls, tmp_path, false);
//         try require.equal(@as(i16, 0), result.downloaded);
//         try require.equal(@as(i16, 1), result.skipped);
//     }
//     {
//         const result = try downloadFiles(std.testing.allocator, &urls, tmp_path, true);
//         try require.equal(@as(i16, 1), result.downloaded);
//         try require.equal(@as(i16, 0), result.skipped);
//     }
// }
