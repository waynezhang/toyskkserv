const std = @import("std");
const config = @import("../config.zig");
const utils = @import("../utils/utils.zig");
const download = @import("../http/download.zig");
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
    download.downloadFiles(
        alloc,
        cfg.dictionaries,
        cfg.dictionary_directory,
        true,
        downloadProgress,
    ) catch |err| {
        utils.log.err("Download failed due to {}", .{err});
    };
}

fn downloadProgress(url: []const u8, result: download.Result) void {
    switch (result) {
        .Failed => utils.log.err("{s} {s}", .{ utils.fs.extractFilename(url), result.toString() }),
        .Downloaded => utils.log.info("{s} {s}", .{ utils.fs.extractFilename(url), result.toString() }),
        else => utils.log.debug("{s} {s}", .{ utils.fs.extractFilename(url), result.toString() }),
    }
}
