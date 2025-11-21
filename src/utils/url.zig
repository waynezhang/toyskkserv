const std = @import("std");
const fs = @import("fs.zig");

pub fn isHttpUrl(url: []const u8) bool {
    return std.mem.startsWith(u8, url, "http://") or
        std.mem.startsWith(u8, url, "https://");
}

test "isHttpUrl" {
    try std.testing.expect(isHttpUrl("http://google.com"));
    try std.testing.expect(isHttpUrl("https://google.com"));
    try std.testing.expect(!isHttpUrl("/usr/bin"));
    try std.testing.expect(!isHttpUrl("~/.config"));
}

pub fn isGzip(url: []const u8) bool {
    return std.mem.endsWith(u8, url, ".gz") and !isTar(url);
}

test "isGzip" {
    try std.testing.expect(isGzip("/abc/def/a.gz"));
    try std.testing.expect(!isGzip("/abc/def/a.tar.gz"));
    try std.testing.expect(!isGzip("/abc/def/a.txt"));
}

pub fn isTar(url: []const u8) bool {
    return std.mem.endsWith(u8, url, ".tar.gz");
}

test "isTar" {
    try std.testing.expect(isTar("/abc/def/a.tar.gz"));
    try std.testing.expect(!isTar("/abc/def/a.gz"));
    try std.testing.expect(!isTar("/abc/def/a.txt"));
}
