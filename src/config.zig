const std = @import("std");
const zgf = @import("zon_get_fields");
const utils = @import("utils/utils.zig");
const Location = @import("dict/dict_location.zig").Location;

const require = @import("protest").require;

pub const Config = struct {
    dictionary_directory: []const u8 = &.{},
    listen_addr: []const u8 = &.{},
    fallback_to_google: bool = false,
    dictionaries: []Location = &.{},
    update_schedule: []const u8 = &.{},

    pub fn init(alloc: std.mem.Allocator, ast: std.zig.Ast) !Config {
        var cfg = Config{};

        cfg.dictionary_directory = try utils.fs.toAbsolutePath(
            alloc,
            zgf.getFieldVal([]const u8, ast, "dictionary_directory") catch "./toyskkserv-cache",
            null,
        );
        cfg.listen_addr = try alloc.dupe(u8, zgf.getFieldVal([]const u8, ast, "listen_addr") catch "127.0.0.1:1178");
        cfg.fallback_to_google = zgf.getFieldVal(bool, ast, "fallback_to_google") catch false;

        var dict_arr = std.ArrayList(Location).init(alloc);
        defer dict_arr.deinit();

        var idx: i16 = 0;
        while (true) {
            const location = loadLocation(alloc, ast, idx) catch break;
            try dict_arr.append(location);
            idx += 1;
        }
        cfg.dictionaries = try dict_arr.toOwnedSlice();

        return cfg;
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.dictionary_directory);
        allocator.free(self.listen_addr);
        allocator.free(self.update_schedule);
        for (self.dictionaries) |d| {
            allocator.free(d.url);
            for (d.files) |f| {
                allocator.free(f);
            }
            allocator.free(d.files);
        }
        allocator.free(self.dictionaries);
    }
};

fn loadLocation(alloc: std.mem.Allocator, ast: std.zig.Ast, index: i16) !Location {
    const buf = try alloc.alloc(u8, 1024);
    defer alloc.free(buf);

    const key = try std.fmt.bufPrint(buf[0..], "dictionaries[{d}].url", .{index});
    const url = try zgf.getFieldVal([]const u8, ast, key);

    var file_arr = std.ArrayList([]const u8).init(alloc);
    defer file_arr.deinit();

    const file_key = try std.fmt.bufPrint(buf[0..], "dictionaries[{d}].files", .{index});
    if (zgf.getFieldVal([]const u8, ast, file_key)) |files| {
        var ite = std.mem.splitScalar(u8, files, ',');
        while (ite.next()) |file| {
            try file_arr.append(try alloc.dupe(u8, std.mem.trim(u8, file, " ")));
        }
    } else |_| {}
    return .{
        .url = try alloc.dupe(u8, url),
        .files = try file_arr.toOwnedSlice(),
    };
}

pub fn loadConfig(alloc: std.mem.Allocator) !*Config {
    const config_files = [_][]const u8{
        "./toyskkserv.zon",
        "~/.config/toyskkserv.zon",
    };

    return try parseConfig(alloc, &config_files);
}

fn parseConfig(allocator: std.mem.Allocator, files: []const []const u8) !*Config {
    for (files) |file| {
        const path = utils.fs.toAbsolutePath(allocator, file, null) catch {
            continue;
        };
        defer allocator.free(path);

        utils.log.debug("Found config file at {s}", .{path});
        const txt = std.fs.cwd().readFileAllocOptions(allocator, path, std.math.maxInt(usize), null, @alignOf(u8), 0) catch {
            continue;
        };
        defer allocator.free(txt);

        var ast = try std.zig.Ast.parse(allocator, txt, .zon);
        defer ast.deinit(allocator);

        const cfg = try allocator.create(Config);
        cfg.* = try Config.init(allocator, ast);
        return cfg;
    }

    return error.NoConfigFound;
}

test "config" {
    const alloc = std.testing.allocator;

    const cfg = try parseConfig(alloc, &[_][]const u8{
        "./conf/toyskkserv.zon",
    });
    defer {
        cfg.deinit(alloc);
        alloc.destroy(cfg);
    }

    try require.isTrue(std.mem.endsWith(u8, cfg.dictionary_directory, "dict_cache"));
    try require.isTrue(std.fs.path.isAbsolute(cfg.dictionary_directory));
    try require.equal("127.0.0.1:1178", cfg.listen_addr);
    try require.isTrue(cfg.fallback_to_google);

    try require.equal("https://skk-dev.github.io/dict/SKK-JISYO.L.gz", cfg.dictionaries[0].url);
    // ...
    try require.equal("https://skk-dev.github.io/dict/zipcode.tar.gz", cfg.dictionaries[18].url);
    try require.equal("zipcode/SKK-JISYO.zipcode", cfg.dictionaries[18].files[0]);
    try require.equal("zipcode/SKK-JISYO.office.zipcode", cfg.dictionaries[18].files[1]);
}
