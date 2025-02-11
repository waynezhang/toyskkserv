const std = @import("std");
const config = @import("../config.zig");
const utils = @import("../utils/utils.zig");
const log = std.log;

pub fn reload() !void {
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

    try utils.net.sendMessage(cfg.listen_addr, "creload");
}
