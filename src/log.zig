const std = @import("std");

pub const Level = enum {
    err,
    info,
    debug,
};

var current_level: Level = .info;
const stdOut = std.io.getStdOut().writer();
const stdErr = std.io.getStdErr().writer();

pub fn setLevel(level: Level) void {
    current_level = level;
}

pub inline fn err(comptime format: []const u8, args: anytype) void {
    stdErr.print(format ++ "\n", args) catch {};
}

pub inline fn info(comptime format: []const u8, args: anytype) void {
    if (@intFromEnum(current_level) >= @intFromEnum(Level.info)) {
        stdOut.print(format ++ "\n", args) catch {};
    }
}

pub inline fn debug(comptime format: []const u8, args: anytype) void {
    if (@intFromEnum(current_level) >= @intFromEnum(Level.debug)) {
        stdOut.print(format ++ "\n", args) catch {};
    }
}
