comptime {
    _ = @import("config.zig");
    _ = @import("file.zig");
    _ = @import("http/download.zig");
    _ = @import("http/url.zig");
    _ = @import("japanese/euc_jp.zig");
    _ = @import("server/google_api.zig");
    _ = @import("server/handlers.zig");
    _ = @import("server/ip.zig");
    _ = @import("server/response.zig");
    _ = @import("skk/dict.zig");
    _ = @import("skk/utils.zig");
}

test {
    @import("std").testing.refAllDecls(@This());
}
