const std = @import("std");
const config = @import("config.zig");
const download = @import("http/download.zig");
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
    const result = try download.downloadFiles(alloc, cfg.dictionaries, cfg.dictionary_directory, true);
    log.info("Update finished: {d}/{d}, {d} skipped. ", .{ result.downloaded, cfg.dictionaries.len, result.skipped });
}
