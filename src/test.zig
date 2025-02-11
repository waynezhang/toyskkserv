comptime {
    _ = @import("config.zig");
    _ = @import("dict.zig");
    _ = @import("file.zig");
    _ = @import("http/download.zig");
    _ = @import("http/url.zig");
    _ = @import("server/google_api.zig");
    _ = @import("server/handlers.zig");
    _ = @import("server/ip.zig");
    _ = @import("server/response.zig");
    _ = @import("skk/skk.zig");
}

test {
    @import("std").testing.refAllDecls(@This());
}
