comptime {
    _ = @import("config.zig");
    _ = @import("dict/entry.zig");
    _ = @import("dict/location.zig");
    _ = @import("dict/manager.zig");
    _ = @import("server/google_api.zig");
    _ = @import("server/handlers.zig");
    _ = @import("server/response.zig");
    _ = @import("skk/skk.zig");
    _ = @import("utils/url.zig");
}

test {
    @import("std").testing.refAllDecls(@This());
}
