const std = @import("std");
const utils = @import("../utils/utils.zig");

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

pub fn init(alloc: std.mem.Allocator, k: []const u8, c: []const u8) !Entry {
    const len = 4 + k.len + c.len;
    const data = try alloc.alloc(u8, len);
    var entry = Entry{ .data = data.ptr };
    entry.write(k, c);

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

fn write(self: Entry, k: []const u8, c: []const u8) void {
    self.writeU16(0, k.len);
    std.mem.copyBackwards(u8, self.data[4..(4 + k.len)], k);

    self.writeU16(2, c.len);
    const offset = 4 + k.len;
    std.mem.copyBackwards(u8, self.data[offset..(offset + c.len)], c);
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
        var ent = try Entry.init(alloc, "", "");
        defer ent.deinit(alloc);

        try std.testing.expectEqual(ent.keyLen(), @as(usize, 0));
        try std.testing.expectEqualStrings(ent.key(), "");

        try std.testing.expectEqual(ent.candidateLen(), @as(usize, 0));
        try std.testing.expectEqualStrings(ent.candidate(), "");
    }

    {
        var ent = try Entry.init(alloc, "test_key", "");
        defer ent.deinit(alloc);

        try std.testing.expectEqual(ent.keyLen(), @as(usize, 8));
        try std.testing.expectEqualStrings(ent.key(), "test_key");

        try std.testing.expectEqual(ent.candidateLen(), @as(usize, 0));
        try std.testing.expectEqualStrings(ent.candidate(), "");
    }

    {
        var ent = try Entry.init(alloc, "", "test_candidate");
        defer ent.deinit(alloc);

        try std.testing.expectEqual(ent.keyLen(), @as(usize, 0));
        try std.testing.expectEqualStrings(ent.key(), "");

        try std.testing.expectEqual(ent.candidateLen(), @as(usize, 14));
        try std.testing.expectEqualStrings(ent.candidate(), "test_candidate");
    }
    {
        var ent = try Entry.init(alloc, "test_key", "test_candidate");
        defer ent.deinit(alloc);

        try std.testing.expectEqual(ent.keyLen(), @as(usize, 8));
        try std.testing.expectEqualStrings(ent.key(), "test_key");

        try std.testing.expectEqual(ent.candidateLen(), @as(usize, 14));
        try std.testing.expectEqualStrings(ent.candidate(), "test_candidate");
    }
}

test "entry compare" {
    const alloc = std.testing.allocator;
    var a = try Entry.init(alloc, "a", "");
    defer a.deinit(alloc);
    var b = try Entry.init(alloc, "b", "");
    defer b.deinit(alloc);

    {
        const ret = a.compare(&b, null);
        try std.testing.expect(ret < 0);
    }
    {
        const ret = b.compare(&a, null);
        try std.testing.expect(ret > 0);
    }
    {
        const ret = a.compare(&a, null);
        try std.testing.expect(ret == 0);
    }
}
