const std = @import("std");
const builtin = @import("builtin");

pub const Level = enum {
    none,
    err,
    info,
    debug,
};

var current_level: u3 = @intFromEnum(Level.info);

pub fn setLevel(level: Level) void {
    current_level = @intFromEnum(level);
}

pub inline fn err(comptime format: []const u8, args: anytype) void {
    std.debug.print(format ++ "\n", args);
}

pub inline fn info(comptime format: []const u8, args: anytype) void {
    if (current_level >= @intFromEnum(Level.info) and !builtin.is_test) {
        std.debug.print(format ++ "\n", args);
    }
}

pub inline fn debug(comptime format: []const u8, args: anytype) void {
    if (current_level >= @intFromEnum(Level.debug) and !builtin.is_test) {
        std.debug.print(format ++ "\n", args);
    }
}
