const std = @import("std");
const dict = @import("skk/dict.zig");
const Server = @import("server/server.zig").Server;
const config = @import("config.zig");

pub fn serve() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    var allocator = arena.allocator();

    const config_files = [_][]const u8{
        "./toyskkserv.zon",
        "~/.config/toyskkserv.zon",
    };
    var cfg = config.parseConfig(allocator, &config_files) catch |err| switch (err) {
        config.ConfigError.NoConfigFound => {
            std.log.err("No config file found in following paths.\n{s}", .{config_files});
            return;
        },
        else => {
            std.log.err("Failed to parse config due to {}", .{err});
            return;
        },
    };
    const fmt =
        \\ Config loaded:
        \\     Dictionary directory: {s}
        \\     Listen Addr: {s}
        \\     Fallback to Google: {}
        \\     Dictionaries Count: {d}
    ;

    std.log.info(fmt, .{ cfg.dictionary_directory, cfg.listen_addr, cfg.fallback_to_google, cfg.dictionaries.len });
    defer cfg.deinit(allocator);

    const server = try allocator.create(Server);
    server.* = try Server.init(allocator, .{
        .dictionary_directory = cfg.dictionary_directory,
        .listen_addr = cfg.listen_addr,
        .version = "toyskkserv v0.0.1",
        .use_google = cfg.fallback_to_google,
    });

    server.serve(cfg.dictionaries) catch |err| {
        std.log.err("Failed to start server due to {}", .{err});
    };
}
