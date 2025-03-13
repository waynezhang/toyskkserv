const std = @import("std");
const dict = @import("dict/dict.zig");
const zutils = @import("zutils");

const require = @import("protest").require;

const Self = @This();

dictionary_directory: []const u8 = &.{},
listen_addr: []const u8 = &.{},
fallback_to_google: bool = false,
dictionaries: []dict.Location = &.{},

pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
    std.zon.parse.free(allocator, self);
}

pub fn loadConfig(alloc: std.mem.Allocator) !Self {
    const config_files = [_][]const u8{
        "./toyskkserv.zon",
        "~/.config/toyskkserv.zon",
    };

    return try parseConfig(alloc, &config_files);
}

fn parseConfig(allocator: std.mem.Allocator, files: []const []const u8) !Self {
    for (files) |file| {
        const path = zutils.fs.toAbsolutePathAlloc(allocator, file, null) catch {
            continue;
        };
        defer allocator.free(path);

        zutils.log.debug("Found config file at {s}", .{path});
        const txt = std.fs.cwd().readFileAllocOptions(allocator, path, std.math.maxInt(usize), null, @alignOf(u8), 0) catch {
            continue;
        };
        defer allocator.free(txt);

        return try std.zon.parse.fromSlice(Self, allocator, txt, null, .{
            .free_on_error = true,
            .ignore_unknown_fields = true,
        });
    }

    return error.NoConfigFound;
}

test "config" {
    const alloc = std.testing.allocator;

    const cfg = try parseConfig(alloc, &[_][]const u8{
        "./conf/toyskkserv.zon",
    });
    defer cfg.deinit(alloc);

    try require.isTrue(std.mem.endsWith(u8, cfg.dictionary_directory, "dict_cache"));
    try require.equal("127.0.0.1:1178", cfg.listen_addr);
    try require.isTrue(cfg.fallback_to_google);

    try require.equal("https://skk-dev.github.io/dict/SKK-JISYO.L.gz", cfg.dictionaries[0].url);
    // ...
    try require.equal("https://skk-dev.github.io/dict/zipcode.tar.gz", cfg.dictionaries[18].url);
    try require.equal("zipcode/SKK-JISYO.zipcode", cfg.dictionaries[18].files[0]);
    try require.equal("zipcode/SKK-JISYO.office.zipcode", cfg.dictionaries[18].files[1]);
}
