const std = @import("std");
const cli = @import("zig-cli");
const builtin = @import("builtin");
const ver = @import("version.zig");
const update = @import("cmd/update_cmd.zig");
const server = @import("cmd/server_cmd.zig");
const reload = @import("cmd/reload.zig");

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
                            .action = cli.CommandAction{ .exec = update.updateDicts },
                        },
                    },
                    .{
                        .name = "reload",
                        .description = .{
                            .one_line = "Tell skkserv to reload dictionaries",
                        },
                        .target = cli.CommandTarget{
                            .action = cli.CommandAction{ .exec = reload.reload },
                        },
                    },
                    .{
                        .name = "version",
                        .description = .{
                            .one_line = "Show skkserv version",
                        },
                        .target = cli.CommandTarget{
                            .action = cli.CommandAction{ .exec = ver.showVersion },
                        },
                    },
                },
            },
        },
    };
    return r.run(&app);
}

fn serve() !void {
    if (verbose) {
        @import("utils/utils.zig").log.setLevel(.debug);
    }
    try server.serve();
}
