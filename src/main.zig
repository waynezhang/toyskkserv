const std = @import("std");
const cli = @import("zig-cli");
const builtin = @import("builtin");
const ver = @import("version_cmd.zig");
const server = @import("server_cmd.zig");

pub fn main() !void {
    var buf: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const allocator = fba.allocator();

    var r = try cli.AppRunner.init(allocator);
    const app = cli.App{ .command = cli.Command{ .name = "toyskkserv", .target = cli.CommandTarget{
        .subcommands = &[_]cli.Command{
            .{
                .name = "serve",
                .target = cli.CommandTarget{
                    .action = cli.CommandAction{ .exec = server.serve },
                },
            },
            .{
                .name = "version",
                .target = cli.CommandTarget{
                    .action = cli.CommandAction{ .exec = ver.show_version },
                },
            },
        },
    } } };
    return r.run(&app);
}
