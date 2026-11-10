const std = @import("std");
const dict = @import("dict/dict.zig");
const utils = @import("utils/utils.zig");

const Self = @This();

/// Owns all memory of the parsed fields.
arena: std.heap.ArenaAllocator,

dictionary_directory: []const u8,
listen_addr: []const u8,
fallback_to_google: bool,
dictionaries: []dict.Location,

/// Fields read from the ZON config file.
const Fields = struct {
    dictionary_directory: []const u8 = &.{},
    listen_addr: []const u8 = &.{},
    fallback_to_google: bool = false,
    dictionaries: []dict.Location = &.{},
};

pub fn deinit(self: @This(), _: std.mem.Allocator) void {
    self.arena.deinit();
}

pub fn loadConfig(io: std.Io, alloc: std.mem.Allocator) !Self {
    const config_files = [_][]const u8{
        "./toyskkserv.zon",
        "~/.config/toyskkserv.zon",
    };

    return try parseConfig(io, alloc, &config_files);
}

fn parseConfig(io: std.Io, allocator: std.mem.Allocator, files: []const []const u8) !Self {
    for (files) |file| {
        const path = utils.fs.toAbsolutePathAlloc(io, allocator, file, null) catch {
            continue;
        };
        defer allocator.free(path);

        utils.log.debug("Found config file at {s}", .{path});
        const txt = std.Io.Dir.cwd().readFileAllocOptions(io, path, allocator, .unlimited, .of(u8), 0) catch {
            continue;
        };
        defer allocator.free(txt);

        var arena: std.heap.ArenaAllocator = .init(allocator);
        errdefer arena.deinit();

        var diagnostics: std.zon.parse.Diagnostics = undefined;
        const fields = try std.zon.parse.fromSlice(Fields, .{
            .gpa = allocator,
            .arena = arena.allocator(),
            .source = txt,
            .diagnostics = &diagnostics,
            .ignore_unknown_fields = true,
        });

        return .{
            .arena = arena,
            .dictionary_directory = fields.dictionary_directory,
            .listen_addr = fields.listen_addr,
            .fallback_to_google = fields.fallback_to_google,
            .dictionaries = fields.dictionaries,
        };
    }

    return error.NoConfigFound;
}

test "config" {
    const alloc = std.testing.allocator;

    const cfg = try parseConfig(std.testing.io, alloc, &[_][]const u8{
        "./conf/toyskkserv.zon",
    });
    defer cfg.deinit(alloc);

    try std.testing.expectStringEndsWith(cfg.dictionary_directory, "dict_cache");
    try std.testing.expectEqualStrings("127.0.0.1:1178", cfg.listen_addr);
    try std.testing.expect(cfg.fallback_to_google);

    try std.testing.expectEqualStrings("https://skk-dev.github.io/dict/SKK-JISYO.L.gz", cfg.dictionaries[0].url);
    // ...
    try std.testing.expectEqualStrings("https://skk-dev.github.io/dict/zipcode.tar.gz", cfg.dictionaries[18].url);
    try std.testing.expectEqualStrings("zipcode/SKK-JISYO.zipcode", cfg.dictionaries[18].files[0]);
    try std.testing.expectEqualStrings("zipcode/SKK-JISYO.office.zipcode", cfg.dictionaries[18].files[1]);
}
