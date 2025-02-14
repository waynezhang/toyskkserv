const std = @import("std");
const Server = @import("../server/server.zig").Server;
const config = @import("../config.zig");
const jdz_allocator = @import("jdz_allocator");
const utils = @import("../utils/utils.zig");
const dict_location = @import("../dict/dict_location.zig");

pub fn serve() !void {
    var jdz = jdz_allocator.JdzAllocator(.{}).init();
    defer jdz.deinit();
    const allocator = jdz.allocator();

    const config_files = [_][]const u8{
        "./toyskkserv.zon",
        "~/.config/toyskkserv.zon",
    };
    var cfg = config.loadConfig(allocator) catch |err| switch (err) {
        error.NoConfigFound => {
            utils.log.err("No config file found in following paths.\n{s}", .{config_files});
            return;
        },
        else => {
            utils.log.err("Failed to parse config due to {}", .{err});
            return;
        },
    };
    defer {
        cfg.deinit(allocator);
    }
    const fmt =
        \\Config loaded:
        \\    Dictionary directory: {s}
        \\    Listen Addr: {s}
        \\    Fallback to Google: {}
        \\    Dictionaries Count: {d}
    ;
    utils.log.info(fmt, .{ cfg.dictionary_directory, cfg.listen_addr, cfg.fallback_to_google, cfg.dictionaries.len });

    {
        // jdz is causing crash  on download
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const download_alloc = gpa.allocator();

        utils.log.info("Start downloading missing dictionaries", .{});
        dict_location.DictLocation.Download.downloadDicts(
            download_alloc,
            cfg.dictionaries,
            cfg.dictionary_directory,
            false,
        ) catch |err| {
            utils.log.err("Download failed due to {}", .{err});
        };

        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) unreachable;
    }

    const server = try allocator.create(Server);
    defer {
        server.deinit();
        allocator.destroy(server);
    }
    server.* = try Server.init(allocator, .{
        .dictionary_directory = cfg.dictionary_directory,
        .listen_addr = cfg.listen_addr,
        .use_google = cfg.fallback_to_google,
    });

    server.serve(cfg.dictionaries) catch |err| {
        utils.log.err("Failed to start server due to {}", .{err});
    };
    utils.log.info("Server exited", .{});
}
