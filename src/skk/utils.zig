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
