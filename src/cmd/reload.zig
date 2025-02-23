const std = @import("std");
const config = @import("../config.zig");
const zutils = @import("zutils");
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

    try zutils.net.sendTCPMessage(cfg.listen_addr, "5reload");
}
