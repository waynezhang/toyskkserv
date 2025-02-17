const std = @import("std");
const cli = @import("zig-cli");
const builtin = @import("builtin");
const version = @import("version.zig");
const cmd = @import("cmd/cmd.zig");

pub const std_options = .{
    .log_level = .err,
};

var verbose: bool = false;

pub fn main() !void {
    var buf: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const allocator = fba.allocator();

    var r = try cli.AppRunner.init(allocator);
    const app = cli.App{
        .command = cli.Command{
            .name = "toyskkserv",
            .target = cli.CommandTarget{
                .subcommands = &[_]cli.Command{
                    .{
                        .name = "serve",
                        .description = .{
                            .one_line = "Start skkserv",
                        },
                        .target = cli.CommandTarget{
                            .action = cli.CommandAction{ .exec = serve },
                        },
                        .options = &[_]cli.Option{
                            .{
                                .long_name = "verbose",
                                .short_alias = 'v',
                                .help = "Enable more output",
                                .value_ref = r.mkRef(&verbose),
                            },
                        },
                    },
                    .{
                        .name = "update",
                        .description = .{
                            .one_line = "Force re-download all dictionaires",
                        },
                        .target = cli.CommandTarget{
                            .action = cli.CommandAction{ .exec = update },
                        },
                        .options = &[_]cli.Option{
                            .{
                                .long_name = "verbose",
                                .short_alias = 'v',
                                .help = "Enable more output",
                                .value_ref = r.mkRef(&verbose),
                            },
                        },
                    },
                    .{
                        .name = "reload",
                        .description = .{
                            .one_line = "Tell skkserv to reload dictionaries",
                        },
                        .target = cli.CommandTarget{
                            .action = cli.CommandAction{ .exec = cmd.reload },
                        },
                    },
                },
            },
        },
        .version = version.Version,
        .help_config = .{
            .color_usage = .never,
        },
    };
    return r.run(&app);
}

fn serve() !void {
    if (verbose) {
        @import("utils/utils.zig").log.setLevel(.debug);
    }
    try cmd.serve();
}

fn update() !void {
    if (verbose) {
        @import("utils/utils.zig").log.setLevel(.debug);
    }
    try cmd.update();
}
