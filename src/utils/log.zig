const std = @import("std");
const builtin = @import("builtin");

pub const Level = enum {
    none,
    err,
    info,
    debug,
};

pub fn setLevel(level: Level) void {
    current_level = @intFromEnum(level);
}

pub fn init() void {
    config = std.io.tty.detectConfig(std.fs.File.stdout());
}

pub inline fn fatal(comptime format: []const u8, args: anytype) void {
    if (current_level >= @intFromEnum(Level.err) and !builtin.is_test) {
        colorPrint(.red, format, args);
        std.process.exit(1);
    }
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
    var log_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&log_buffer);

    config.?.setColor(&stdout_writer.interface, c) catch {};
    stdout_writer.interface.print(fmt ++ "\n", args) catch {};
    config.?.setColor(&stdout_writer.interface, .reset) catch {};

    stdout_writer.interface.flush() catch {};
}

var config: ?std.io.tty.Config = null;
var current_level: u3 = @intFromEnum(Level.info);
