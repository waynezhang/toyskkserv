const std = @import("std");
const mem = std.mem;
const require = @import("protest").require;
const DictManager = @import("../skk/dict.zig").DictManager;

pub fn generateResponse(buffer: *std.ArrayList(u8), req: []const u8, res: []const u8) !void {
    if (res.len > 0) {
        // 1/cdd1/cdd1/\n
        try buffer.append('1');
        try buffer.appendSlice(res);
        return;
    }

    // 4req \n
    try buffer.append('4');
    try buffer.appendSlice(req);
    try buffer.append(' ');
    return;
}

test "generateResponse with non-empty response" {
    const allocator = std.testing.allocator;

    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    const req = "test request";
    const res = "test response";

    try generateResponse(&buf, req, res);

    try require.equal("1test response", buf.items);
}

test "generateResponse with empty response" {
    const allocator = std.testing.allocator;
    const req = "test request";
    const res = "";

    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    try generateResponse(&buf, req, res);

    try require.equal("4test request ", buf.items);
}
