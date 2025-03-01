const std = @import("std");
const log = @import("zutils").log;
const Server = @import("../server/server.zig").Server;
const config = @import("../config.zig");
const jdz_allocator = @import("jdz_allocator");
const dict = @import("../dict/dict.zig");

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
            log.err("No config file found in following paths.\n{s}", .{config_files});
            return;
        },
        else => {
            log.err("Failed to parse config due to {}", .{err});
            return;
        },
    };
    defer {
        cfg.deinit(allocator);
        allocator.destroy(cfg);
    }
    const fmt =
        \\Config loaded:
        \\    Dictionary directory: {s}
        \\    Listen Addr: {s}
        \\    Fallback to Google: {}
        \\    Dictionaries Count: {d}
    ;
    log.info(fmt, .{ cfg.dictionary_directory, cfg.listen_addr, cfg.fallback_to_google, cfg.dictionaries.len });

    {
        // jdz is causing crash on download
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const download_alloc = gpa.allocator();
        defer {
            const deinit_status = gpa.deinit();
            if (deinit_status == .leak) unreachable;
        }

        log.info("Start downloading missing dictionaries", .{});
        dict.Location.downloadDicts(
            download_alloc,
            cfg.dictionaries,
            cfg.dictionary_directory,
            false,
        ) catch |err| {
            log.err("Download failed due to {}", .{err});
        };
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
        log.err("Failed to start server due to {}", .{err});
    };
    log.info("Server exited", .{});
}
