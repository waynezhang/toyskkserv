const std = @import("std");

pub fn show_version() !void {
    var stdout = std.io.getStdIn().writer();
    try stdout.print("Version 0.0.1\n", .{});
}
