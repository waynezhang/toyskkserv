const std = @import("std");
const mem = std.mem;

pub fn generateResponse(writer: *std.Io.Writer, req: []const u8, res: []const u8) !void {
    if (res.len > 0) {
        // 1/cdd1/cdd1/\n
        try writer.writeByte('1');
        _ = try writer.write(res);
        return;
    }

    // 4req \n
    try writer.writeByte('4');
    _ = try writer.write(req);
    try writer.writeByte(' ');
    return;
}

test "generateResponse with non-empty response" {
    const allocator = std.testing.allocator;

    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    const req = "test request";
    const res = "test response";

    try generateResponse(&buf.writer, req, res);

    try std.testing.expectEqualStrings("1test response", buf.written());
}

test "generateResponse with empty response" {
    const allocator = std.testing.allocator;
    const req = "test request";
    const res = "";

    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try generateResponse(&buf.writer, req, res);

    try std.testing.expectEqualStrings("4test request ", buf.written());
}
