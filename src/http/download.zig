const std = @import("std");
const http = std.http;
const mem = std.mem;

const log = @import("../log.zig");
const isHttpUrl = @import("url.zig").isHttpUrl;
const file = @import("../file.zig");

const require = @import("protest").require;

/// Download URLs to `base_path` directory. `base_path` is created if it doesn't exist.
/// Note: jdz allocator is casuing crash.
pub fn downloadFiles(alloc: mem.Allocator, urls: []const []const u8, base_path: []const u8, force_download: bool) !struct {
    downloaded: i16,
    skipped: i16,
    failed: i16,
} {
    std.fs.cwd().makeDir(base_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => {
            return err;
        },
    };

    var downloaded: i16 = 0;
    var skipped: i16 = 0;
    var failed: i16 = 0;

    for (urls) |url| {
        if (!isHttpUrl(url)) {
            skipped += 1;
            continue;
        }
        const filename = file.extractFilename(url);
        const full_path = try std.fs.path.join(alloc, &[_][]const u8{
            base_path,
            filename,
        });
        defer alloc.free(full_path);

        if (!force_download and file.isFileExisting(full_path)) {
            skipped += 1;
            continue;
        }

        log.debug("Downloading {s}", .{full_path});
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

fn download(allocator: mem.Allocator, url: []const u8, dst: []const u8) !void {
    const uri = try std.Uri.parse(url);

    var client = http.Client{ .allocator = allocator };
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
