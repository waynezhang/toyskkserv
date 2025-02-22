const std = @import("std");
const builtin = @import("builtin");

pub const Level = enum {
    none,
    err,
    info,
    debug,
};

var config: ?std.io.tty.Config = null;
var current_level: u3 = @intFromEnum(Level.info);

pub fn setLevel(level: Level) void {
    current_level = @intFromEnum(level);
}

pub inline fn err(comptime format: []const u8, args: anytype) void {
    if (current_level >= @intFromEnum(Level.err) and !builtin.is_test) {
        colorPrint(.red, format, args);
    }
}

pub inline fn info(comptime format: []const u8, args: anytype) void {
    if (current_level >= @intFromEnum(Level.info) and !builtin.is_test) {
        colorPrint(.white, format, args);
    }
}

pub inline fn debug(comptime format: []const u8, args: anytype) void {
    if (current_level >= @intFromEnum(Level.debug) and !builtin.is_test) {
        colorPrint(.bright_black, format, args);
    }
}

inline fn colorPrint(c: std.io.tty.Color, fmt: []const u8, args: anytype) void {
    if (config == null) {
        config = std.io.tty.detectConfig(std.io.getStdOut());
    }

    const out = std.io.getStdOut();

    config.?.setColor(out, c) catch {};
    out.writer().print(fmt ++ "\n", args) catch {};
    config.?.setColor(out, .reset) catch {};
}
