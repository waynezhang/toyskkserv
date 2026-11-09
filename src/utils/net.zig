const std = @import("std");
const net = std.net;

const testing = @import("std").testing;

/// Send message to TCP port
pub fn sendTCPMessage(host: []const u8, message: []const u8) !void {
    const addr = try parseAddrPort(host);

    const stream = try net.tcpConnectToAddress(addr);
    defer stream.close();

    var writer = stream.writer(&.{});
    _ = try writer.interface.write(message);
}

/// Parses an address:port string supporting both IPv4 and IPv6.
/// For IPv4: "192.168.1.1:8080" or ":8080" (uses 127.0.0.1)
/// For IPv6: "[::1]:8080" (address in brackets to disambiguate from port separator)
pub fn parseAddrPort(str: []const u8) !net.Address {
    const localhost = "127.0.0.1";

    // Check if this is an IPv6 address (surrounded by square brackets)
    if (str.len > 0 and str[0] == '[') {
        // Find the closing bracket
        const closing_bracket = std.mem.indexOf(u8, str, "]");
        if (closing_bracket == null) {
            return net.IPv6ParseError.Incomplete;
        }

        // Extract the IPv6 address without brackets
        const ipv6_addr = str[1..closing_bracket.?];

        // Make sure there's a colon after the closing bracket for the port
        if (closing_bracket.? + 1 >= str.len or str[closing_bracket.? + 1] != ':') {
            return net.IPv6ParseError.Incomplete;
        }

        // Extract the port part after ]:
        const port_part = str[closing_bracket.? + 2 ..];
        const port = std.fmt.parseInt(u16, port_part, 10) catch {
            return error.InvalidPort;
        };

        return net.Address.parseIp6(ipv6_addr, port);
    } else {
        // Handle IPv4 addresses
        const colon_idx = std.mem.indexOf(u8, str, ":");
        if (colon_idx == null) {
            return net.IPv4ParseError.Incomplete;
        }

        const ip_part = if (colon_idx.? == 0)
            localhost
        else
            str[0..colon_idx.?];

        const port_part = str[colon_idx.? + 1 ..];

        const port = std.fmt.parseInt(u16, port_part, 10) catch {
            return error.InvalidPort;
        };

        return net.Address.parseIp4(ip_part, port);
    }
}

test "parseAddrPort" {
    var ipAddrBuffer: [64]u8 = undefined;

    // IPv4 tests
    {
        const addr = try parseAddrPort("192.168.1.1:8080");
        const ipv4 = try std.fmt.bufPrint(ipAddrBuffer[0..], "{f}", .{addr});
        try testing.expectEqualStrings("192.168.1.1:8080", ipAddrBuffer[0..ipv4.len]);
    }
    {
        const addr = try parseAddrPort(":8080");
        const ipv4 = try std.fmt.bufPrint(ipAddrBuffer[0..], "{f}", .{addr});
        try testing.expectEqualStrings("127.0.0.1:8080", ipAddrBuffer[0..ipv4.len]);
    }
    {
        const err = parseAddrPort("192.168.1.1:invalid");
        try testing.expectError(error.InvalidPort, err);
    }
    {
        const err = parseAddrPort("300.168.1.1:8080");
        try testing.expectError(net.IPv4ParseError.Overflow, err);
    }
    {
        const err = parseAddrPort("invalid");
        try testing.expectError(net.IPv4ParseError.Incomplete, err);
    }

    // IPv6 tests
    {
        const addr = try parseAddrPort("[::1]:8080");
        const ipv6 = try std.fmt.bufPrint(ipAddrBuffer[0..], "{f}", .{addr});
        try testing.expectEqualStrings("[::1]:8080", ipAddrBuffer[0..ipv6.len]);
    }
    {
        const addr = try parseAddrPort("[2001:db8::1]:8080");
        const ipv6 = try std.fmt.bufPrint(ipAddrBuffer[0..], "{f}", .{addr});
        try testing.expectEqualStrings("[2001:db8::1]:8080", ipAddrBuffer[0..ipv6.len]);
    }
    {
        const err = parseAddrPort("[::1]");
        try testing.expectError(net.IPv6ParseError.Incomplete, err);
    }
    {
        const err = parseAddrPort("[::1]:invalid");
        try testing.expectError(error.InvalidPort, err);
    }
    {
        const err = parseAddrPort("[invalid]:8080");
        try testing.expectError(error.InvalidCharacter, err);
    }
}

/// Encodes a string for safe use in URL query parameters.
/// Caller must free the returned memory.
/// Preserves alphanumerics, unreserved chars (-._~), and non-ASCII characters (including CJK).
/// Only ASCII special characters are percent-encoded.
pub fn encodeQueryComponentAlloc(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var result = std.Io.Writer.Allocating.init(allocator);
    defer result.deinit();

    // This function preserves alphanumerics, unreserved chars, and all non-ASCII chars
    const isValidQueryChar = struct {
        fn isValid(c: u8) bool {
            return std.ascii.isAlphanumeric(c) or c == '-' or c == '.' or c == '_' or c == '~' or c >= 128;
        }
    }.isValid;

    try std.Uri.Component.percentEncode(&result.writer, input, isValidQueryChar);

    return result.toOwnedSlice();
}

test "encodeQueryComponentAlloc" {
    const allocator = std.testing.allocator;

    // Test basic ASCII encoding
    {
        const input = "hello world";
        const encoded = try encodeQueryComponentAlloc(allocator, input);
        defer allocator.free(encoded);
        try testing.expectEqualStrings("hello%20world", encoded);
    }

    // Test special characters
    {
        const input = "a=1&b=2+c?d/e";
        const encoded = try encodeQueryComponentAlloc(allocator, input);
        defer allocator.free(encoded);
        try testing.expectEqualStrings("a%3D1%26b%3D2%2Bc%3Fd%2Fe", encoded);
    }

    // Test non-ASCII Unicode characters (should be preserved)
    {
        const input = "こんにちは"; // "Hello" in Japanese
        const encoded = try encodeQueryComponentAlloc(allocator, input);
        defer allocator.free(encoded);
        try testing.expectEqualStrings("こんにちは", encoded);
    }
}
