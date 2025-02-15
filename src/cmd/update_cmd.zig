const std = @import("std");
const config = @import("../config.zig");
const utils = @import("../utils/utils.zig");
const dict_location = @import("../dict/dict_location.zig");
const log = std.log;

pub fn updateDicts() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) unreachable;
    }
    const alloc = gpa.allocator();

    const cfg = config.loadConfig(alloc) catch |err| {
        log.err("Failed to load config file due to {}", .{err});
        return;
    };
    defer {
        cfg.deinit(alloc);
        alloc.destroy(cfg);
    }

    log.info("Start updating at {s}", .{cfg.dictionary_directory});
    dict_location.Location.Download.downloadDicts(
        alloc,
        cfg.dictionaries,
        cfg.dictionary_directory,
        true,
    ) catch |err| {
        utils.log.err("Download failed due to {}", .{err});
    };
}
