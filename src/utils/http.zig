const std = @import("std");

/// Download a file to dst path
pub fn download(allocator: std.mem.Allocator, url: []const u8, dst: []const u8) !void {
    const uri = try std.Uri.parse(url);

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const f = try std.fs.cwd().createFile(dst, .{
        .read = true,
        .truncate = true,
    });
    defer f.close();

    var write_buffer: [8 * 1024]u8 = undefined;
    var file_writer = f.writer(&write_buffer);

    var redirect_buffer: [8 * 1024]u8 = undefined;
    const response = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = .GET,
        .redirect_buffer = &redirect_buffer,
        .response_writer = &file_writer.interface,
    });

    if (response.status != .ok) {
        return error.HttpError;
    }

    try file_writer.interface.flush();
}
