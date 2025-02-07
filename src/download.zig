const std = @import("std");
const log = std.log;
const http = std.http;
const mem = std.mem;
const require = @import("protest").require;

pub fn download(allocator: mem.Allocator, url: []const u8, dst: []const u8) !void {
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

    const file = try std.fs.cwd().createFile(dst, .{
        .read = true,
        .truncate = true,
    });
    defer file.close();

    var buf_writer = std.io.bufferedWriter(file.writer());

    const buffer = try allocator.alloc(u8, 1025 * 1024);
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
