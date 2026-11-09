const std = @import("std");
const config = @import("../config.zig");
const utils = @import("../utils/utils.zig");
const log = std.log;

pub fn reload(alloc: std.mem.Allocator) !void {
    const cfg = config.loadConfig(alloc) catch |err| {
        log.err("Failed to load config file due to {}", .{err});
        return;
    };
    defer cfg.deinit(alloc);

    try utils.net.sendTCPMessage(cfg.listen_addr, "5reload");
}
