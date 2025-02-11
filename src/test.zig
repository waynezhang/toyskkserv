comptime {
    _ = @import("config.zig");
    _ = @import("dict.zig");
    _ = @import("http/download.zig");
    _ = @import("server/google_api.zig");
    _ = @import("server/handlers.zig");
    _ = @import("server/response.zig");
    _ = @import("skk/skk.zig");
    _ = @import("utils/fs.zig");
    _ = @import("utils/net.zig");
    _ = @import("utils/url.zig");
}

test {
    @import("std").testing.refAllDecls(@This());
}
