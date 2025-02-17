const std = @import("std");
const config = @import("../config.zig");
const utils = @import("../utils/utils.zig");
const dict = @import("../dict/dict.zig");

pub fn update() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) unreachable;
    }
    const alloc = gpa.allocator();

    const cfg = config.loadConfig(alloc) catch |err| {
        utils.log.err("Failed to load config file due to {}", .{err});
        return;
    };
    defer {
        cfg.deinit(alloc);
        alloc.destroy(cfg);
    }

    utils.log.info("Start updating at {s}", .{cfg.dictionary_directory});
    dict.Location.downloadDicts(
        alloc,
        cfg.dictionaries,
        cfg.dictionary_directory,
        true,
    ) catch |err| {
        utils.log.err("Download failed due to {}", .{err});
    };
}
