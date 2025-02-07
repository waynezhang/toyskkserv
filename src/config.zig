const std = @import("std");
const zgf = @import("zon_get_fields");
const require = @import("protest").require;

const Config = struct {
    dictionary_directory: []const u8,
    listen_addr: []const u8,
    fallback_to_google: bool = false,
    dictionaries: []const []const u8 = undefined,
    update_schedule: []const u8,

    pub fn init(allocator: std.mem.Allocator, ast: std.zig.Ast) !Config {
        var cfg = Config{
            .dictionary_directory = undefined,
            .listen_addr = undefined,
            .fallback_to_google = true,
            .update_schedule = undefined,
            .dictionaries = undefined,
        };

        cfg.dictionary_directory = try allocator.dupe(u8, zgf.getFieldVal([]const u8, ast, "dictionary_directory") catch "./toyskkserv-cache");
        cfg.listen_addr = try allocator.dupe(u8, zgf.getFieldVal([]const u8, ast, "listen_addr") catch "127.0.0.1:1178");
        cfg.update_schedule = try allocator.dupe(u8, zgf.getFieldVal([]const u8, ast, "update_schedule") catch "");

        var dict_arr = std.ArrayList([]const u8).init(allocator);
        defer dict_arr.deinit();

        const buf = try allocator.alloc(u8, 48);
        defer allocator.free(buf);
        var i: i16 = 0;
        while (true) {
            const slice = try std.fmt.bufPrint(buf[0..], "dictionaries[{d}]", .{i});
            if (zgf.getFieldVal([]const u8, ast, slice)) |dict| {
                try dict_arr.append(try allocator.dupe(u8, dict));
            } else |_| {
                break;
            }
            i = i + 1;
        }
        cfg.dictionaries = try dict_arr.toOwnedSlice();

        return cfg;
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.dictionary_directory);
        allocator.free(self.listen_addr);
        allocator.free(self.update_schedule);
        for (self.dictionaries) |d| {
            allocator.free(d);
        }
        allocator.free(self.dictionaries);
    }
};

pub const ConfigError = error{
    NoConfigFound,
};

pub fn parseConfig(allocator: std.mem.Allocator, files: []const []const u8) !*Config {
    for (files) |file| {
        const path = std.fs.realpathAlloc(allocator, file) catch {
            continue;
        };
        defer allocator.free(path);

        std.log.info("Found config file at {s}", .{path});
        const txt = try std.fs.cwd().readFileAllocOptions(allocator, path, std.math.maxInt(usize), null, @alignOf(u8), 0);
        defer allocator.free(txt);

        var ast = try std.zig.Ast.parse(allocator, txt, .zon);
        defer ast.deinit(allocator);

        const cfg = try allocator.create(Config);
        cfg.* = try Config.init(allocator, ast);
        return cfg;
    }

    return ConfigError.NoConfigFound;
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

    try require.equal("./dict_cache", cfg.dictionary_directory);
    try require.equal("127.0.0.1:1178", cfg.listen_addr);
    try require.isTrue(cfg.fallback_to_google);
    try require.equal("monthly", cfg.update_schedule);

    try require.equal("url", cfg.dictionaries[0]);
    try require.equal("path", cfg.dictionaries[1]);
}
