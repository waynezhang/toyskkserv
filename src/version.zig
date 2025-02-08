const std = @import("std");
const build_options = @import("build_options");

pub const FullDescription = fullDescription();

fn fullDescription() []const u8 {
    return build_options.name ++ " " ++ build_options.version ++ "+" ++ build_options.commit;
}

pub fn showVersion() !void {
    var stdout = std.io.getStdIn().writer();
    try stdout.print("{s}\n", .{FullDescription});
}
