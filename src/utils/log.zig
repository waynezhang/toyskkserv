const std = @import("std");
const builtin = @import("builtin");

pub const Level = enum {
    none,
    err,
    info,
    debug,
};

pub fn setLevel(level: Level) void {
    current_level = @backingInt(level);
}

pub fn init(io: std.Io) void {
    log_io = io;
    terminal_mode = std.Io.Terminal.Mode.detect(io, std.Io.File.stdout(), false, false) catch .no_color;
}

pub inline fn fatal(comptime format: []const u8, args: anytype) void {
    if (current_level >= @backingInt(Level.err) and !builtin.is_test) {
        colorPrint(.red, format, args);
        std.process.exit(1);
    }
}

pub inline fn err(comptime format: []const u8, args: anytype) void {
    if (current_level >= @backingInt(Level.err) and !builtin.is_test) {
        colorPrint(.red, format, args);
    }
}

pub inline fn info(comptime format: []const u8, args: anytype) void {
    if (current_level >= @backingInt(Level.info) and !builtin.is_test) {
        colorPrint(.white, format, args);
    }
}

pub inline fn debug(comptime format: []const u8, args: anytype) void {
    if (current_level >= @backingInt(Level.debug) and !builtin.is_test) {
        colorPrint(.bright_black, format, args);
    }
}

inline fn colorPrint(c: std.Io.Terminal.Color, fmt: []const u8, args: anytype) void {
    const io = log_io orelse return;

    var log_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &log_buffer);
    const terminal: std.Io.Terminal = .{ .writer = &stdout_writer.interface, .mode = terminal_mode };

    terminal.setColor(c) catch {};
    stdout_writer.interface.print(fmt ++ "\n", args) catch {};
    terminal.setColor(.reset) catch {};

    stdout_writer.interface.flush() catch {};
}

var log_io: ?std.Io = null;
var terminal_mode: std.Io.Terminal.Mode = .no_color;
var current_level: u3 = @backingInt(Level.info);
