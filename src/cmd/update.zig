const std = @import("std");
const config = @import("../config.zig");
const log = @import("zutils").log;
const dict = @import("../dict/dict.zig");

pub fn update(alloc: std.mem.Allocator) !void {
    const cfg = config.loadConfig(alloc) catch |err| {
        log.err("Failed to load config file due to {}", .{err});
        return;
    };
    defer cfg.deinit(alloc);

    log.info("Start updating at {s}", .{cfg.dictionary_directory});
    dict.Location.downloadDicts(
        alloc,
        cfg.dictionaries,
        cfg.dictionary_directory,
        true,
    ) catch |err| {
        log.err("Download failed due to {}", .{err});
    };
}
