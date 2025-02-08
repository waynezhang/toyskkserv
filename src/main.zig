const std = @import("std");
const cli = @import("zig-cli");
const builtin = @import("builtin");
const ver = @import("version.zig");
const server = @import("server_cmd.zig");

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
                        .name = "version",
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
        @import("log.zig").setLevel(.debug);
    }
    try server.serve();
}
