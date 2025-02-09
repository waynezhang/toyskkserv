const std = @import("std");
const net = std.net;
const log = std.log;
const ip = @import("../server/ip.zig");

pub fn sendMessage(host: []const u8, message: []const u8) !void {
    const addr = try ip.parseAddrPort(host);

    const stream = try net.tcpConnectToAddress(addr);
    defer stream.close();

    var writer = stream.writer();
    _ = try writer.write(message);
}
