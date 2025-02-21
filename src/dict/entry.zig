const std = @import("std");
const utils = @import("../utils/utils.zig");

const require = @import("protest").require;

const Entry = @This();

// key_len    cdd_len    key    cdd
//  0...1      2...3     4..    ..
data: [*]u8,

pub fn key(self: Entry) []const u8 {
    return self.data[4..(4 + self.keyLen())];
}

pub fn candidate(self: Entry) []const u8 {
    const offset = 4 + self.keyLen();
    return self.data[offset..(offset + self.candidateLen())];
}

pub fn compare(a: *Entry, b: *Entry, _: ?*void) c_int {
    const order = std.mem.order(u8, a.key(), b.key());
    switch (order) {
        .lt => {
            return -1;
        },
        .eq => {
            return 0;
        },
        .gt => {
            return 1;
        },
    }
}

pub fn initFrom(alloc: std.mem.Allocator, k: []const u8, c: []const u8) !Entry {
    const len = 4 + k.len + c.len;
    const data = try alloc.alloc(u8, len);
    var entry = Entry{ .data = data.ptr };
    entry.writeKey(k);
    entry.writeCandidate(c);

    return entry;
}

pub fn deinit(self: Entry, alloc: std.mem.Allocator) void {
    const len = 4 + self.keyLen() + self.candidateLen();
    alloc.free(self.data[0..len]);
}

fn keyLen(self: Entry) usize {
    return self.readU16(0);
}

fn candidateLen(self: Entry) usize {
    return self.readU16(2);
}

fn writeKey(self: Entry, val: []const u8) void {
    self.writeU16(0, val.len);
    std.mem.copyBackwards(u8, self.data[4..(4 + val.len)], val);
}

fn writeCandidate(self: Entry, val: []const u8) void {
    self.writeU16(2, val.len);
    const offset = 4 + self.keyLen();
    std.mem.copyBackwards(u8, self.data[offset..(offset + val.len)], val);
}

fn readU16(self: Entry, offset: usize) usize {
    const high: usize = self.data[offset];
    const low: usize = self.data[offset + 1];
    return (high << 8) | low;
}

fn writeU16(self: Entry, offset: usize, value: usize) void {
    self.data[offset] = @intCast(value >> 8);
    self.data[offset + 1] = @intCast(value & 0xFF);
}

test "entry" {
    const alloc = std.testing.allocator;
    {
        var ent = try Entry.initFrom(alloc, "", "");
        defer ent.deinit(alloc);

        try require.equal(ent.keyLen(), @as(usize, 0));
        try require.equal(ent.key(), "");

        try require.equal(ent.candidateLen(), @as(usize, 0));
        try require.equal(ent.candidate(), "");
    }

    {
        var ent = try Entry.initFrom(alloc, "test_key", "");
        defer ent.deinit(alloc);

        try require.equal(ent.keyLen(), @as(usize, 8));
        try require.equal(ent.key(), "test_key");

        try require.equal(ent.candidateLen(), @as(usize, 0));
        try require.equal(ent.candidate(), "");
    }

    {
        var ent = try Entry.initFrom(alloc, "", "test_candidate");
        defer ent.deinit(alloc);

        try require.equal(ent.keyLen(), @as(usize, 0));
        try require.equal(ent.key(), "");

        try require.equal(ent.candidateLen(), @as(usize, 14));
        try require.equal(ent.candidate(), "test_candidate");
    }
    {
        var ent = try Entry.initFrom(alloc, "test_key", "test_candidate");
        defer ent.deinit(alloc);

        try require.equal(ent.keyLen(), @as(usize, 8));
        try require.equal(ent.key(), "test_key");

        try require.equal(ent.candidateLen(), @as(usize, 14));
        try require.equal(ent.candidate(), "test_candidate");
    }
}

test "entry compare" {
    const alloc = std.testing.allocator;
    var a = try Entry.initFrom(alloc, "a", "");
    defer a.deinit(alloc);
    var b = try Entry.initFrom(alloc, "b", "");
    defer b.deinit(alloc);

    {
        const ret = a.compare(&b, null);
        try require.isTrue(ret < 0);
    }
    {
        const ret = b.compare(&a, null);
        try require.isTrue(ret > 0);
    }
    {
        const ret = a.compare(&a, null);
        try require.isTrue(ret == 0);
    }
}
