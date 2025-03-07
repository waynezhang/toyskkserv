const std = @import("std");
const config = @import("../config.zig");
const zutils = @import("zutils");
const log = std.log;

pub fn reload(alloc: std.mem.Allocator) !void {
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
