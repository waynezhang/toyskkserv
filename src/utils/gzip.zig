const std = @import("std");
const fs = @import("fs.zig");
const testing = @import("std").testing;

/// Unarchive a Gzip file to dst path
pub fn unarchive(io: std.Io, src: []const u8, dst: []const u8) !void {
    const src_file = try std.Io.Dir.cwd().openFile(io, src, .{});
    defer src_file.close(io);

    const dst_file = try std.Io.Dir.cwd().createFile(io, dst, .{ .truncate = true });
    defer dst_file.close(io);

    var read_buffer: [8 * 1024]u8 = undefined;
    var reader = src_file.reader(io, &read_buffer);

    var write_buffer: [8 * 1024]u8 = undefined;
    var writer = dst_file.writer(io, &write_buffer);

    var decompress_buffer: [std.compress.flate.max_window_len]u8 = undefined;

    var decompress: std.compress.flate.Decompress = .init(&reader.interface, .gzip, &decompress_buffer);
    _ = try decompress.reader.streamRemaining(&writer.interface);

    try writer.interface.flush();
}

test "unarchive" {
    const io = std.testing.io;
    const src_file = "testdata/test_file.gz";

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(tmp_path);

    const dst_path = try std.fs.path.join(std.testing.allocator, &[_][]const u8{
        tmp_path, "unarchived_file",
    });
    defer std.testing.allocator.free(dst_path);

    try unarchive(io, src_file, dst_path);

    const original_checksum = "bff459dcf3b39fbd2e38a9b9e80b1ad87ed47331941ac86d9770db307ba4b282";

    const checksum = try fs.sha256Alloc(io, std.testing.allocator, dst_path);
    defer std.testing.allocator.free(checksum);

    try testing.expectEqualStrings(original_checksum, checksum);
}

/// Extract a tarball to dst directory
pub fn extractTarball(io: std.Io, src: []const u8, dst_dir: []const u8) !void {
    const src_file = try std.Io.Dir.cwd().openFile(io, src, .{});
    defer src_file.close(io);

    var read_buffer: [8192]u8 = undefined;
    var reader = src_file.reader(io, &read_buffer);

    var gzip_buf: [std.compress.flate.max_window_len]u8 = undefined;
    var decompress: std.compress.flate.Decompress = .init(&reader.interface, .gzip, &gzip_buf);

    var dir = try std.Io.Dir.cwd().openDir(io, dst_dir, .{});
    defer dir.close(io);
    try std.tar.extract(io, dir, &decompress.reader, .{});
}

test "extractTarball" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    const src_file = "testdata/test_file.tar.gz";

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const dst_path = try tmp.dir.realPathFileAlloc(io, ".", alloc);
    defer alloc.free(dst_path);

    try extractTarball(io, src_file, dst_path);

    const expected_checksum = "bff459dcf3b39fbd2e38a9b9e80b1ad87ed47331941ac86d9770db307ba4b282";
    const file_path = try std.fs.path.join(alloc, &[_][]const u8{
        dst_path,
        "test_file",
    });
    defer alloc.free(file_path);

    const checksum = try fs.sha256Alloc(io, alloc, file_path);
    defer alloc.free(checksum);

    try testing.expectEqualStrings(expected_checksum, checksum);
}
