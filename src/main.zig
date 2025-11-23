const std = @import("std");
const builtin = @import("builtin");
const pargs = @import("parg");
const log = @import("zutils").log;
const version = @import("version.zig");
const cmd = @import("cmd/cmd.zig");

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    const alloc, const is_debug = alloc: {
        break :alloc switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        std.debug.assert(debug_allocator.deinit() == .ok);
    };

    log.init();

    var verbose = false;
    var cmd_str: ?[]const u8 = null;

    var p = try pargs.parseProcess(alloc, .{});
    defer p.deinit();
    _ = p.nextValue(); // skip executable name

    while (p.next()) |token| {
        switch (token) {
            .flag => |flag| {
                if (flag.isLong("verbose") or flag.isShort("v")) {
                    verbose = true;
                } else if (flag.isLong("help") or flag.isShort("h")) {
                    cmd_str = "help";
                }
            },
            .arg => |val| {
                if (cmd_str == null)
                    cmd_str = val;
            },
            .unexpected_value => @panic("Invalid argumnts"),
        }
    }

    if (verbose) log.setLevel(.debug);

    const fallback = cmd_str orelse "help";
    runCmd(fallback, alloc) catch |err| {
        log.err("Failed to {s} due to {s}", .{ fallback, @errorName(err) });
    };
}

fn runCmd(c: []const u8, alloc: std.mem.Allocator) !void {
    if (std.mem.eql(u8, c, "serve")) {
        try cmd.serve(alloc);
    } else if (std.mem.eql(u8, c, "update")) {
        try cmd.update(alloc);
    } else if (std.mem.eql(u8, c, "reload")) {
        try cmd.reload(alloc);
    } else if (std.mem.eql(u8, c, "version")) {
        showVersion();
    } else {
        showHelp();
    }
}

fn showHelp() void {
    const help =
        \\usage: toyskkserv command [flags]
        \\
        \\commands:
        \\  serve    Start skkserv
        \\  update   Force re-download all dictionaires
        \\  reload   Tell skkserv to reload dictionaries
        \\  version  Show version information
        \\
        \\flags:
        \\  -h, --help            Show this help output
        \\  -v, --verbose         Verbose mode
    ;
    log.info("{s}", .{help});
    std.process.exit(0);
}

fn showVersion() void {
    log.info("{s}", .{version.FullDescription});
    std.process.exit(0);
}
