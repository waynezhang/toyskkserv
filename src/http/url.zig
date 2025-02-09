const std = @import("std");
const file = @import("../file.zig");
const require = @import("protest").require;

pub fn translateUrlsToFiles(allocator: std.mem.Allocator, urls: []const []const u8, base_path: []const u8) ![]const []const u8 {
    var arr = try std.ArrayList([]const u8).initCapacity(allocator, urls.len);
    defer arr.deinit();

    for (urls) |url| {
        const f = if (isHttpUrl(url)) file.extractFilename(url) else url;
        const path = try file.toAbsolutePath(allocator, f, base_path);

        try arr.append(path);
    }

    return try arr.toOwnedSlice();
}
test "translateUrlsToFiles" {
    const alloc = std.testing.allocator;

    const cwd = try std.fs.cwd().realpathAlloc(alloc, ".");
    defer alloc.free(cwd);

    const home = try file.expandTilde(alloc, "~");
    defer alloc.free(home);

    const files = [_][]const u8{
        "http://abc.com/test01.txt",
        "http://abc.com/test02.txt",
        "test03.txt",
        "~/test04.txt",
        "/test05.txt",
    };

    const translated = try translateUrlsToFiles(
        alloc,
        &files,
        cwd,
    );
    defer {
        for (translated) |t| alloc.free(t);
        alloc.free(translated);
    }

    {
        const p = try std.fs.path.join(alloc, &[_][]const u8{
            cwd, "test01.txt",
        });
        defer alloc.free(p);
        try require.equal(p, translated[0]);
    }
    {
        const p = try std.fs.path.join(alloc, &[_][]const u8{
            cwd, "test02.txt",
        });
        defer alloc.free(p);
        try require.equal(p, translated[1]);
    }
    {
        const p = try std.fs.path.join(alloc, &[_][]const u8{
            cwd, "test03.txt",
        });
        defer alloc.free(p);
        try require.equal(p, translated[2]);
    }
    {
        const p = try std.fs.path.join(alloc, &[_][]const u8{
            home, "test04.txt",
        });
        defer alloc.free(p);
        try require.equal(p, translated[3]);
    }
    {
        try require.equal("/test05.txt", translated[4]);
    }
}

pub fn isHttpUrl(url: []const u8) bool {
    return std.mem.startsWith(u8, url, "http://") or
        std.mem.startsWith(u8, url, "https://");
}

test "isHttpUrl" {
    try require.isTrue(isHttpUrl("http://google.com"));
    try require.isTrue(isHttpUrl("https://google.com"));
    try require.isFalse(isHttpUrl("/usr/bin"));
    try require.isFalse(isHttpUrl("~/.config"));
}
