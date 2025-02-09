const std = @import("std");
const builtin = @import("builtin");

pub const Level = enum {
    none,
    err,
    info,
    debug,
};

var current_level: u3 = @intFromEnum(Level.info);
const stdErr = std.io.getStdErr().writer();

pub fn setLevel(level: Level) void {
    current_level = @intFromEnum(level);
}

pub inline fn err(comptime format: []const u8, args: anytype) void {
    stdErr.print(format ++ "\n", args) catch {};
}

pub inline fn info(comptime format: []const u8, args: anytype) void {
    if (current_level >= @intFromEnum(Level.info) and !builtin.is_test) {
        stdErr.print(format ++ "\n", args) catch {};
    }
}

pub inline fn debug(comptime format: []const u8, args: anytype) void {
    if (current_level >= @intFromEnum(Level.debug) and !builtin.is_test) {
        stdErr.print(format ++ "\n", args) catch {};
    }
}
