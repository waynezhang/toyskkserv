const std = @import("std");
const require = @import("protest").require;
const Encoding = @import("dict.zig").Encoding;

pub fn concatCandidats(allocator: std.mem.Allocator, first: []const u8, second: []const u8) ![]u8 {
    const trimmed_second = if (std.mem.startsWith(u8, second, "/"))
        second[1..]
    else
        second;

    return std.mem.concat(allocator, u8, &[_][]const u8{ first, trimmed_second });
}

test "concatCandidats" {
    const alloc = std.testing.allocator;
    {
        const cdd = try concatCandidats(alloc, "/abc/", "/def/");
        defer alloc.free(cdd);

        try require.equal("/abc/def/", cdd);
    }
    {
        const cdd = try concatCandidats(alloc, "/abc/", "def/");
        defer alloc.free(cdd);

        try require.equal("/abc/def/", cdd);
    }
    {
        const cdd = try concatCandidats(alloc, "/abc/", "");
        defer alloc.free(cdd);

        try require.equal("/abc/", cdd);
    }
}

pub fn detectEncoding(line: []const u8) Encoding {
    if (!std.mem.startsWith(u8, line, ";;")) {
        return .euc_jp;
    }

    const prefix = "coding: ";
    if (std.mem.indexOf(u8, line, prefix)) |index| {
        const after = line[index + prefix.len ..];
        if (after.len >= "utf-8".len and std.mem.startsWith(u8, after, "utf-8")) {
            return .utf8;
        }
    }

    return .euc_jp;
}

test "detectEncoding" {
    try require.equal(Encoding.utf8, detectEncoding(";; coding: utf-8"));
    try require.equal(Encoding.utf8, detectEncoding(";; coding: utf-8  "));
    try require.equal(Encoding.utf8, detectEncoding(";; coding: utf-8 -*- mode: listp -*-"));

    try require.equal(Encoding.euc_jp, detectEncoding(";; coding: euc "));
    try require.equal(Encoding.euc_jp, detectEncoding("coding: utf-8"));
    try require.equal(Encoding.euc_jp, detectEncoding(";;"));
    try require.equal(Encoding.euc_jp, detectEncoding(""));

    try require.equal(Encoding.euc_jp, detectEncoding(";; codg: utf-8"));
    try require.equal(Encoding.utf8, detectEncoding(";;; coding: utf-8 coding: euc_jp"));
}

pub fn splitFirstSpace(input: []const u8) struct { []const u8, []const u8 } {
    const space_index = std.mem.indexOfScalar(u8, input, ' ') orelse return .{ input, "" };
    return .{ input[0..space_index], std.mem.trim(u8, input[space_index + 1 ..], " ") };
}

test "splitFirstSpace" {
    {
        const result = splitFirstSpace("hello world");
        try require.equal("hello", result.@"0");
        try require.equal("world", result.@"1");
    }
    {
        const result = splitFirstSpace("hello   world  test");
        try require.equal("hello", result.@"0");
        try require.equal("world  test", result.@"1");
    }
    {
        const result = splitFirstSpace("");
        try require.equal("", result.@"0");
        try require.equal("", result.@"1");
    }
    {
        const result = splitFirstSpace("helloworld");
        try require.equal("helloworld", result.@"0");
        try require.equal("", result.@"1");
    }
    {
        const result = splitFirstSpace(" ");
        try require.equal("", result.@"0");
        try require.equal("", result.@"1");
    }
}

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

pub fn extractFilename(url: []const u8) []const u8 {
    if (url.len == 0) {
        return url;
    }
    if (std.mem.lastIndexOf(u8, url, "/")) |idx| {
        return url[idx + 1 ..];
    }

    return url;
}

test "extractFilename" {
    try require.equal("", extractFilename(""));
    try require.equal("file", extractFilename("http://abc.com/path/file"));
    try require.equal("file", extractFilename("file"));
    try require.equal("file", extractFilename("~/file"));
}

pub fn isFileExisting(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch {
        return false;
    };
    return true;
}

test "isFileExisting" {
    try require.isTrue(isFileExisting("/usr"));
    try require.isFalse(isFileExisting("/some_nonexisting_dir"));
}

pub fn expandTilde(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (!std.mem.startsWith(u8, path, "~/")) {
        return try allocator.dupe(u8, path);
    }

    const home_dir = if (std.process.getEnvVarOwned(allocator, "HOME")) |home|
        home
    else |err|
        return err;
    defer allocator.free(home_dir);

    return try std.fs.path.join(allocator, &[_][]const u8{
        home_dir, path[2..],
    });
}

test "expandTilde" {
    const alloc = std.testing.allocator;
    {
        const path = try expandTilde(alloc, "/test.txt");
        defer alloc.free(path);
        try require.equal("/test.txt", path);
    }

    {
        const path = try expandTilde(alloc, "~/test.txt");
        defer alloc.free(path);
        try require.isTrue(std.mem.startsWith(u8, path, "/"));
    }
}

pub fn translateUrlsToFiles(allocator: std.mem.Allocator, urls: []const []const u8) ![]const []const u8 {
    var arr = try std.ArrayList([]const u8).initCapacity(allocator, urls.len);
    defer arr.deinit();

    for (urls) |url| {
        if (isHttpUrl(url)) {
            try arr.append(extractFilename(url));
        } else {
            try arr.append(url);
        }
    }

    return try arr.toOwnedSlice();
}
test "translateUrlsToFiles" {
    const alloc = std.testing.allocator;

    const files = [_][]const u8{
        "http://abc.com/test01.txt",
        "http://abc.com/test02.txt",
        "test03.txt",
        "~/test04.txt",
    };

    const translated = try translateUrlsToFiles(alloc, &files);
    defer alloc.free(translated);

    try require.equal("test01.txt", translated[0]);
    try require.equal("test02.txt", translated[1]);
    try require.equal("test03.txt", translated[2]);
    try require.equal("~/test04.txt", translated[3]);
}
