const std = @import("std");
const config = @import("../config.zig");
const log = @import("../utils/utils.zig").log;
const dict = @import("../dict/dict.zig");

pub fn update(io: std.Io, alloc: std.mem.Allocator) !void {
    const cfg = config.loadConfig(io, alloc) catch |err| {
        log.err("Failed to load config file due to {}", .{err});
        return;
    };
    defer cfg.deinit(alloc);

    log.info("Start updating at {s}", .{cfg.dictionary_directory});
    dict.Location.downloadDicts(
        io,
        alloc,
        cfg.dictionaries,
        cfg.dictionary_directory,
        true,
    ) catch |err| {
        log.err("Download failed due to {}", .{err});
    };
}
