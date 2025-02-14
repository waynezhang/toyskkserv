const std = @import("std");
const temp = @import("temp");
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
    if (std.fs.path.isAbsolute(path)) {
        return alloc.dupe(u8, path);
    }

    const expanded_path = try expandTilde(alloc, path);
    defer alloc.free(expanded_path);

    const expanded_base = try expandTilde(alloc, base_path orelse "./");
    defer alloc.free(expanded_base);

    const absolute_dir = try std.fs.cwd().realpathAlloc(alloc, expanded_base);
    defer alloc.free(absolute_dir);

    return try std.fs.path.resolve(alloc, &[_][]const u8{
        absolute_dir,
        expanded_path,
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

/// Caller own the memory
pub fn sha256(alloc: std.mem.Allocator, path: []const u8) ![]const u8 {
    const fullpath = try toAbsolutePath(alloc, path, ".");
    defer alloc.free(fullpath);

    const file = try std.fs.cwd().openFile(fullpath, .{});
    defer file.close();

    var hash = std.crypto.hash.sha2.Sha256.init(.{});

    var buffered = std.io.bufferedReader(file.reader());
    var buffer: [8192]u8 = undefined;
    while (true) {
        const len = try buffered.read(&buffer);
        if (len == 0) {
            break;
        }
        hash.update(buffer[0..len]);
    }

    var digest = hash.finalResult();
    return try std.fmt.allocPrint(
        alloc,
        "{s}",
        .{std.fmt.fmtSliceHexLower(&digest)},
    );
}

test "sha256" {
    const expected = "5ab8d6b1ba16dfed8ca2a5bb301b8bc703bedabcb4f460b30f2ed00021000f4a";

    const sha256sum = try sha256(std.testing.allocator, "testdata/jisyo.utf8");
    defer std.testing.allocator.free(sha256sum);

    try require.equal(expected, sha256sum);
}

pub const TmpFile = struct {
    path: []const u8,
    dirPath: []const u8,
    tmpDir: temp.TempDir,

    pub fn deinit(self: *TmpFile, alloc: std.mem.Allocator) void {
        alloc.free(self.path);
        alloc.free(self.dirPath);
        self.tmpDir.deinit();
    }
};

pub fn GetTmpFile(alloc: std.mem.Allocator) !TmpFile {
    var tmp_dir = try temp.create_dir(alloc, "toyskkserv-tmp-*");

    var dir = try tmp_dir.open(.{});
    defer dir.close();

    const dir_path = try dir.realpathAlloc(alloc, ".");

    const path = try std.fs.path.join(alloc, &[_][]const u8{
        dir_path,
        "tmp-file",
    });
    return TmpFile{
        .path = path,
        .dirPath = dir_path,
        .tmpDir = tmp_dir,
    };
}

pub fn IsDiff(alloc: std.mem.Allocator, path_a: []const u8, path_b: []const u8) bool {
    const checksum_a = sha256(alloc, path_a) catch "";
    defer alloc.free(checksum_a);

    const checksum_b = sha256(alloc, path_b) catch "";
    defer alloc.free(checksum_b);

    return !std.mem.eql(u8, checksum_a, checksum_b);
}

test "IsDiff" {
    const alloc = std.testing.allocator;

    try require.isFalse(IsDiff(alloc, "testdata/jisyo.utf8", "testdata/jisyo.utf8"));
    try require.isFalse(IsDiff(alloc, "", ""));
    try require.isTrue(IsDiff(alloc, "testdata/jisyo.utf8", ""));
    try require.isTrue(IsDiff(alloc, "testdata/jisyo.utf8", "testdata/jisyo.euc-jp"));
}
