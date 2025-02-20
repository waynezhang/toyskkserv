const std = @import("std");
const euc_jp = @import("euc-jis-2004-zig");

const require = @import("protest").require;

pub const Encoding = enum {
    euc_jp,
    utf8,
    undecided,
};

pub const Pair = struct {
    key: []const u8,
    candidate: []const u8,
};

pub const Iterator = IteratorLine(4096);

fn IteratorLine(comptime size: usize) type {
    return struct {
        encoding: Encoding,

        file: std.fs.File,
        buffered: std.io.BufferedReader(size, std.fs.File.Reader),
        line_buf: []u8,

        pub fn next(self: *Iterator, convert_buf: []u8) !?Pair {
            while (true) {
                const line = self.buffered.reader().readUntilDelimiter(self.line_buf, '\n') catch |err| switch (err) {
                    error.EndOfStream => {
                        return null;
                    },
                    else => {
                        return err;
                    },
                };
                if (self.encoding == .undecided) {
                    self.encoding = detectEncoding(line);
                }

                switch (self.encoding) {
                    .utf8 => {
                        if (parsePair(line)) |ent| {
                            return ent;
                        }
                    },
                    .euc_jp => {
                        if (euc_jp.convertEucJpToUtf8(line, convert_buf)) |utf8_line| {
                            if (parsePair(utf8_line)) |ent| {
                                return ent;
                            }
                        } else |_| {}
                    },
                    else => unreachable,
                }
            }
        }

        pub fn deinit(self: *Iterator) void {
            self.file.close();
        }
    };
}

pub fn OpenDictionaryFile(filepath: []const u8, line_buffer: []u8) !Iterator {
    const encoding: Encoding = if (std.mem.endsWith(u8, filepath, ".utf8")) .utf8 else .undecided;

    const file = try std.fs.cwd().openFile(filepath, .{});
    const buf_reader = std.io.bufferedReader(file.reader());

    return .{
        .encoding = encoding,
        .file = file,
        .buffered = buf_reader,
        .line_buf = line_buffer,
    };
}

test "skk utf-8 with header" {
    const alloc = std.testing.allocator;

    var map = std.StringHashMap([]const u8).init(alloc);
    defer {
        var ite = map.iterator();
        while (ite.next()) |ent| {
            alloc.free(ent.key_ptr.*);
            alloc.free(ent.value_ptr.*);
        }
        map.deinit();
    }

    var buf = [_]u8{0} ** 4096;
    var conv_buf = [_]u8{0} ** 4096;

    var ite = try OpenDictionaryFile("testdata/jisyo.utf8.withheader", &buf);
    defer ite.deinit();

    while (try ite.next(&conv_buf)) |ent| {
        try map.put(
            try alloc.dupe(u8, ent.key),
            try alloc.dupe(u8, ent.candidate),
        );
    }
    try require.equal(Encoding.utf8, ite.encoding);

    try require.equal("/キロ/", map.get("1024") orelse "");
    try require.equal("/ワンセグ/", map.get("1seg") orelse "");
    try require.equal("/５０/五〇/五十/", map.get("50") orelse "");
    try require.equal("/ＡＢＣ/", map.get("ABC") orelse "");
    try require.equal("/台湾/", map.get("taiwan") orelse "");
}

test "skk utf-8 no header" {
    const alloc = std.testing.allocator;

    var map = std.StringHashMap([]const u8).init(alloc);
    defer {
        var ite = map.iterator();
        while (ite.next()) |ent| {
            alloc.free(ent.key_ptr.*);
            alloc.free(ent.value_ptr.*);
        }
        map.deinit();
    }

    var buf = [_]u8{0} ** 4096;
    var conv_buf = [_]u8{0} ** 4096;
    var ite = try OpenDictionaryFile("testdata/jisyo.utf8", &buf);
    defer ite.deinit();

    while (try ite.next(&conv_buf)) |ent| {
        try map.put(
            try alloc.dupe(u8, ent.key),
            try alloc.dupe(u8, ent.candidate),
        );
    }
    try require.equal(Encoding.utf8, ite.encoding);

    try require.equal("/キロ/", map.get("1024") orelse "");
    try require.equal("/ワンセグ/", map.get("1seg") orelse "");
    try require.equal("/５０/五〇/五十/", map.get("50") orelse "");
    try require.equal("/ＡＢＣ/", map.get("ABC") orelse "");
    try require.equal("/台湾/", map.get("taiwan") orelse "");
}

test "skk euc-jp no header" {
    const alloc = std.testing.allocator;

    var map = std.StringHashMap([]const u8).init(alloc);
    defer {
        var ite = map.iterator();
        while (ite.next()) |ent| {
            alloc.free(ent.key_ptr.*);
            alloc.free(ent.value_ptr.*);
        }
        map.deinit();
    }

    var buf = [_]u8{0} ** 4096;
    var conv_buf = [_]u8{0} ** 4096;

    var ite = try OpenDictionaryFile("testdata/jisyo.euc-jp", &buf);
    defer ite.deinit();

    while (try ite.next(&conv_buf)) |ent| {
        try map.put(
            try alloc.dupe(u8, ent.key),
            try alloc.dupe(u8, ent.candidate),
        );
    }
    try require.equal(Encoding.euc_jp, ite.encoding);

    try require.equal("/̀;accent grave (diacritic)/", map.get("`") orelse "");
    try require.equal("/á/ά;発音記号/ʌ́;発音記号/ə́;発音記号/", map.get("a'") orelse "");
    try require.equal("/æ/", map.get("ae") orelse "");
}

fn detectEncoding(line: []const u8) Encoding {
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

fn parsePair(input: []const u8) ?Pair {
    if (std.mem.startsWith(u8, input, ";;")) {
        return null;
    }

    const space_index = std.mem.indexOfScalar(u8, input, ' ') orelse return null;
    const key = std.mem.trim(u8, input[0..space_index], " ");
    if (key.len == 0) {
        return null;
    }
    const candidate = std.mem.trim(u8, input[space_index + 1 ..], " ");
    if (candidate.len == 0) {
        return null;
    }

    return .{
        .key = key,
        .candidate = candidate,
    };
}

test "parsePair" {
    {
        const result = parsePair("hello world").?;
        try require.equal("hello", result.key);
        try require.equal("world", result.candidate);
    }
    {
        const result = parsePair("hello   world  test").?;
        try require.equal("hello", result.key);
        try require.equal("world  test", result.candidate);
    }
    {
        const result = parsePair("");
        try require.isNull(result);
    }
    {
        const result = parsePair("helloworld");
        try require.isNull(result);
    }
    {
        const result = parsePair(" ");
        try require.isNull(result);
    }
    {
        const result = parsePair(";; some line here");
        try require.isNull(result);
    }
}
