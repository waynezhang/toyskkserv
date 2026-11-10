const std = @import("std");
const config = @import("../config.zig");
const utils = @import("../utils/utils.zig");
const log = std.log;

pub fn reload(io: std.Io, alloc: std.mem.Allocator) !void {
    const cfg = config.loadConfig(io, alloc) catch |err| {
        log.err("Failed to load config file due to {}", .{err});
        return;
    };
    defer cfg.deinit(alloc);

    try utils.net.sendTCPMessage(io, cfg.listen_addr, "5reload");
}
