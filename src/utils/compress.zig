const std = @import("std");
const fs = @import("fs.zig");
const strings = @import("strings.zig");
const require = @import("protest").require;

const gzip = std.compress.gzip;

pub fn decompress(src: []const u8, dst: []const u8) !void {
    const src_file = try std.fs.cwd().openFile(src, .{});
    defer src_file.close();

    const dst_file = try std.fs.cwd().createFile(dst, .{ .truncate = true });
    defer dst_file.close();

    var buffered_reader = std.io.bufferedReader(src_file.reader());
    const reader = buffered_reader.reader();

    var buffered_writer = std.io.bufferedWriter(dst_file.writer());
    const writer = buffered_writer.writer();

    try gzip.decompress(reader, writer);

    try buffered_writer.flush();
}

test "decompress" {
    const src_file = "testdata/jisyo.utf8.gz";

    var tmp = std.testing.tmpDir(.{});

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    const dst_path = try std.fs.path.join(std.testing.allocator, &[_][]const u8{
        tmp_path, "decompressed_file",
    });
    defer std.testing.allocator.free(dst_path);

    try decompress(src_file, dst_path);

    const original_checksum = "5ab8d6b1ba16dfed8ca2a5bb301b8bc703bedabcb4f460b30f2ed00021000f4a";

    const checksum = try fs.sha256(std.testing.allocator, dst_path);
    defer std.testing.allocator.free(checksum);

    try require.equal(original_checksum, checksum);
}

pub fn extractTar(src: []const u8, dst_dir: []const u8) !void {
    const src_file = try std.fs.cwd().openFile(src, .{});
    defer src_file.close();

    var buffered_reader = std.io.bufferedReader(src_file.reader());
    const reader = buffered_reader.reader();

    var gzip_stream = std.compress.gzip.decompressor(reader);
    const gzip_reader = gzip_stream.reader();

    var dir = try std.fs.cwd().openDir(dst_dir, .{});
    defer dir.close();
    try std.tar.pipeToFileSystem(dir, gzip_reader, .{});
}

test "extractTarGz" {
    const alloc = std.testing.allocator;

    const src_file = "testdata/jisyo.tar.gz";

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const dst_path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(dst_path);

    try extractTar(src_file, dst_path);

    const expected_utf8_checksum = "5ab8d6b1ba16dfed8ca2a5bb301b8bc703bedabcb4f460b30f2ed00021000f4a";
    const utf8_path = try std.fs.path.join(alloc, &[_][]const u8{
        dst_path,
        "utf8/jisyo.utf8",
    });
    defer alloc.free(utf8_path);

    const utf8_checksum = try fs.sha256(alloc, utf8_path);
    defer alloc.free(utf8_checksum);
    try require.equal(expected_utf8_checksum, utf8_checksum);

    const expected_eucjp_checksum = "958702239a75fa89cce8e5b06d0bb1af87a979db264989f76abe01eb61e074d4";
    const eucjp_path = try std.fs.path.join(alloc, &[_][]const u8{
        dst_path,
        "euc-jp/jisyo.euc-jp",
    });
    defer alloc.free(eucjp_path);

    const eucjp_checksum = try fs.sha256(alloc, eucjp_path);
    defer alloc.free(eucjp_checksum);
    try require.equal(expected_eucjp_checksum, eucjp_checksum);
}
