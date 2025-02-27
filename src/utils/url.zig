const std = @import("std");
const fs = @import("fs.zig");
const require = @import("protest").require;

pub fn isHttpUrl(url: []const u8) bool {
    return std.mem.startsWith(u8, url, "http://") or
        std.mem.startsWith(u8, url, "https://");
}

test "isHttpUrl" {
    try require.isTrue(isHttpUrl("http://google.com"));
    try require.isTrue(isHttpUrl("https://google.com"));
    try require.isFalse(isHttpUrl("/usr/bin"));
    try require.isFalse(isHttpUrl("~/.config"));
}

pub fn isGzip(url: []const u8) bool {
    return std.mem.endsWith(u8, url, ".gz") and !isTar(url);
}

test "isGzip" {
    try require.isTrue(isGzip("/abc/def/a.gz"));
    try require.isFalse(isGzip("/abc/def/a.tar.gz"));
    try require.isFalse(isGzip("/abc/def/a.txt"));
}

pub fn isTar(url: []const u8) bool {
    return std.mem.endsWith(u8, url, ".tar.gz");
}

test "isTar" {
    try require.isTrue(isTar("/abc/def/a.tar.gz"));
    try require.isFalse(isTar("/abc/def/a.gz"));
    try require.isFalse(isTar("/abc/def/a.txt"));
}
