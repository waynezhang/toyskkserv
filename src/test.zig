comptime {
    _ = @import("config.zig");
    _ = @import("skk/dict.zig");
    _ = @import("skk/utils.zig");
    _ = @import("skk/download.zig");
    _ = @import("server/server.zig");
    _ = @import("server/ip.zig");
    _ = @import("server/handlers.zig");
    _ = @import("server/response.zig");
    _ = @import("server/google_api.zig");
    _ = @import("server/google_api.zig");
}

test {
    @import("std").testing.refAllDecls(@This());
}
