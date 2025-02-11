const std = @import("std");
const require = @import("protest").require;

pub fn isFileExisting(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch {
        return false;
    };
    return true;
}

test "isFileExisting" {
    try require.isTrue(isFileExisting("/usr"));
    try require.isFalse(isFileExisting("/some_nonexisting_dir"));
}

pub fn extractFilename(url: []const u8) []const u8 {
    if (url.len == 0) {
        return url;
    }
    if (std.mem.lastIndexOf(u8, url, "/")) |idx| {
        return url[idx + 1 ..];
    }

    return url;
}

test "extractFilename" {
    try require.equal("", extractFilename(""));
    try require.equal("file", extractFilename("http://abc.com/path/file"));
    try require.equal("file", extractFilename("file"));
    try require.equal("file", extractFilename("~/file"));
}

pub fn expandTilde(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (!std.mem.startsWith(u8, path, "~")) {
        return try allocator.dupe(u8, path);
    }

    const home_dir = if (std.process.getEnvVarOwned(allocator, "HOME")) |home|
        home
    else |err|
        return err;
    defer allocator.free(home_dir);

    return try std.fs.path.join(allocator, &[_][]const u8{
        home_dir, path[1..],
    });
}

test "expandTilde" {
    const alloc = std.testing.allocator;
    {
        const path = try expandTilde(alloc, "/test.txt");
        defer alloc.free(path);
        try require.equal("/test.txt", path);
    }

    {
        const path = try expandTilde(alloc, "~/test.txt");
        defer alloc.free(path);
        try require.isTrue(std.mem.startsWith(u8, path, "/"));
    }
}

pub fn toAbsolutePath(alloc: std.mem.Allocator, path: []const u8, base_path: ?[]const u8) ![]const u8 {
    const base = try expandTilde(alloc, base_path orelse "./");
    defer alloc.free(base);

    if (std.mem.startsWith(u8, path, "~/")) {
        return try expandTilde(alloc, path);
    }
    if (std.mem.startsWith(u8, path, "/")) {
        return alloc.dupe(u8, path);
    }

    return std.fs.path.join(alloc, &[_][]const u8{
        base,
        path,
    });
}

test "toAbsolutePath" {
    const alloc = std.testing.allocator;

    const cwd = try std.fs.cwd().realpathAlloc(alloc, ".");
    defer alloc.free(cwd);

    const home = try expandTilde(alloc, "~");
    defer alloc.free(home);

    {
        const p = try toAbsolutePath(alloc, "/tmp/test.txt", cwd);
        defer alloc.free(p);

        try require.equal("/tmp/test.txt", p);
    }
    {
        const p = try toAbsolutePath(alloc, "test.txt", cwd);
        defer alloc.free(p);

        const expected = try std.fs.path.join(alloc, &[_][]const u8{
            cwd,
            "test.txt",
        });
        defer alloc.free(expected);

        try require.equal(expected, p);
    }
    {
        const p = try toAbsolutePath(alloc, "~/test.txt", cwd);
        defer alloc.free(p);

        const expected = try std.fs.path.join(alloc, &[_][]const u8{
            home,
            "test.txt",
        });
        defer alloc.free(expected);

        try require.equal(expected, p);
    }
    {
        const p = try toAbsolutePath(alloc, "test.txt", "~");
        defer alloc.free(p);

        const expected = try std.fs.path.join(alloc, &[_][]const u8{
            home,
            "test.txt",
        });
        defer alloc.free(expected);

        try require.equal(expected, p);
    }
}
