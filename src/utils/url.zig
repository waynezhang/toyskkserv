const std = @import("std");
const fs = @import("fs.zig");
const require = @import("protest").require;

pub fn isHttpUrl(url: []const u8) bool {
    return std.mem.startsWith(u8, url, "http://") or
        std.mem.startsWith(u8, url, "https://");
}

test "isHttpUrl" {
    try require.isTrue(isHttpUrl("http://google.com"));
    try require.isTrue(isHttpUrl("https://google.com"));
    try require.isFalse(isHttpUrl("/usr/bin"));
    try require.isFalse(isHttpUrl("~/.config"));
}

pub fn isGzip(url: []const u8) bool {
    return std.mem.endsWith(u8, url, ".gz") and !isTar(url);
}

test "isGzip" {
    try require.isTrue(isGzip("/abc/def/a.gz"));
    try require.isFalse(isGzip("/abc/def/a.tar.gz"));
    try require.isFalse(isGzip("/abc/def/a.txt"));
}

pub fn isTar(url: []const u8) bool {
    return std.mem.endsWith(u8, url, ".tar.gz");
}

test "isTar" {
    try require.isTrue(isTar("/abc/def/a.tar.gz"));
    try require.isFalse(isTar("/abc/def/a.gz"));
    try require.isFalse(isTar("/abc/def/a.txt"));
}

pub fn download(allocator: std.mem.Allocator, url: []const u8, dst: []const u8) !void {
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
