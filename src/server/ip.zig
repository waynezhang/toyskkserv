const std = @import("std");
const mem = std.mem;
const net = std.net;
const require = @import("protest").require;

/// Parses an address:port string. If only :port is provided, uses 127.0.0.1 as address
/// Format: "ip_addr:port" or ":port"
/// Returns ParseResult containing the IP address and port
pub fn parseAddrPort(str: []const u8) !net.Address {
    const localhost = "127.0.0.1";

    // Find the colon separator
    const colon_idx = mem.indexOf(u8, str, ":");
    if (colon_idx == null) {
        return net.IPv4ParseError.Incomplete;
    }

    // Extract IP and port parts
    const ip_part = if (colon_idx.? == 0)
        localhost
    else
        str[0..colon_idx.?];

    const port_part = str[colon_idx.? + 1 ..];

    // Validate port
    const port = std.fmt.parseInt(u16, port_part, 10) catch {
        return net.IPv4ParseError.Incomplete;
    };

    return net.Address.parseIp4(ip_part, port);
}

test "parseAddrPort" {
    var ipAddrBuffer: [16]u8 = undefined;

    // Test full address:port
    {
        const addr = try parseAddrPort("192.168.1.1:8080");
        const ipv4 = std.fmt.bufPrint(ipAddrBuffer[0..], "{}", .{addr}) catch unreachable;
        try require.equal("192.168.1.1:8080", ipAddrBuffer[0..ipv4.len]);
    }

    // Test :port only (should default to localhost)
    {
        const addr = try parseAddrPort(":8080");
        const ipv4 = std.fmt.bufPrint(ipAddrBuffer[0..], "{}", .{addr}) catch unreachable;
        try require.equal("127.0.0.1:8080", ipAddrBuffer[0..ipv4.len]);
    }

    // Test invalid port
    {
        const err = parseAddrPort("192.168.1.1:invalid");
        try require.equalError(net.IPv4ParseError.Incomplete, err);
    }

    // Test invalid IP
    {
        const err = parseAddrPort("300.168.1.1:8080");
        try require.equalError(net.IPv4ParseError.Overflow, err);
    }

    // Test invalid format
    {
        const err = parseAddrPort("invalid");
        try require.equalError(net.IPv4ParseError.Incomplete, err);
    }
}
