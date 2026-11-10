const std = @import("std");
const builtin = @import("builtin");
const temp = @import("temp");

/// Home directory, set once at startup from the HOME environment variable.
pub var home_dir: ?[]const u8 = null;

fn homeDir() ![]const u8 {
    if (home_dir) |home| return home;
    if (builtin.is_test) {
        if (std.testing.environ.getPosix("HOME")) |home| return home;
    }
    return error.EnvironmentVariableMissing;
}

pub const TmpFile = struct {
    path: []const u8,
    dirPath: [:0]const u8,
    tmpDir: temp.TempDir,

    pub fn deinit(self: *TmpFile, io: std.Io, alloc: std.mem.Allocator) void {
        alloc.free(self.path);
        alloc.free(self.dirPath);
        self.tmpDir.deinit(io);
    }
};

pub fn GetTmpFile(io: std.Io, alloc: std.mem.Allocator) !TmpFile {
    var tmp_dir = try temp.create_dir(alloc, io, "toyskkserv-tmp-*");
    errdefer tmp_dir.deinit(io);

    var dir = try tmp_dir.open(io, .{});
    defer dir.close(io);

    const dir_path = try dir.realPathFileAlloc(io, ".", alloc);
    errdefer alloc.free(dir_path);

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

/// Check if a file or directory is existing or not.
pub fn isExisting(io: std.Io, path: []const u8) bool {
    std.Io.Dir.cwd().access(io, path, .{}) catch {
        return false;
    };
    return true;
}

test "isFileExisting" {
    const io = std.testing.io;
    try std.testing.expect(isExisting(io, "testdata/test_file"));
    try std.testing.expect(!isExisting(io, "testdata/non_existing_file"));
}

/// Expand tidle to home directory
pub fn expandTildeAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (!std.mem.startsWith(u8, path, "~")) {
        return try allocator.dupe(u8, path);
    }

    return try std.fs.path.join(allocator, &[_][]const u8{
        try homeDir(), path[1..],
    });
}

test "expandTildeAlloc" {
    const alloc = std.testing.allocator;
    {
        const path = try expandTildeAlloc(alloc, "/test.txt");
        defer alloc.free(path);
        try std.testing.expectEqualStrings("/test.txt", path);
    }

    {
        const path = try expandTildeAlloc(alloc, "~/test.txt");
        defer alloc.free(path);

        const home = try homeDir();

        const expected = try std.fs.path.join(alloc, &[_][]const u8{
            home, "test.txt",
        });
        defer alloc.free(expected);

        try std.testing.expectEqualStrings(expected, path);
    }
}

/// Resolve a file path to absolute path
pub fn toAbsolutePathAlloc(io: std.Io, alloc: std.mem.Allocator, path: []const u8, base_path: ?[]const u8) ![]const u8 {
    if (std.fs.path.isAbsolute(path)) {
        return alloc.dupe(u8, path);
    }

    const expanded_path = try expandTildeAlloc(alloc, path);
    defer alloc.free(expanded_path);

    const expanded_base = try expandTildeAlloc(alloc, base_path orelse "./");
    defer alloc.free(expanded_base);

    const absolute_dir = try std.Io.Dir.cwd().realPathFileAlloc(io, expanded_base, alloc);
    defer alloc.free(absolute_dir);

    return try std.fs.path.resolveAlloc(alloc, &[_][]const u8{
        absolute_dir,
        expanded_path,
    });
}

test "toAbsolutePathAlloc" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    const cwd = try std.Io.Dir.cwd().realPathFileAlloc(io, ".", alloc);
    defer alloc.free(cwd);

    const home = try homeDir();

    {
        const p = try toAbsolutePathAlloc(io, alloc, "/tmp/test.txt", cwd);
        defer alloc.free(p);

        try std.testing.expectEqualStrings("/tmp/test.txt", p);
    }
    {
        const p = try toAbsolutePathAlloc(io, alloc, "test.txt", cwd);
        defer alloc.free(p);

        const expected = try std.fs.path.join(alloc, &[_][]const u8{
            cwd,
            "test.txt",
        });
        defer alloc.free(expected);

        try std.testing.expectEqualStrings(expected, p);
    }
    {
        const p = try toAbsolutePathAlloc(io, alloc, "~/test.txt", cwd);
        defer alloc.free(p);

        const expected = try std.fs.path.join(alloc, &[_][]const u8{
            home,
            "test.txt",
        });
        defer alloc.free(expected);

        try std.testing.expectEqualStrings(expected, p);
    }
    {
        const p = try toAbsolutePathAlloc(io, alloc, "test.txt", "~");
        defer alloc.free(p);

        const expected = try std.fs.path.join(alloc, &[_][]const u8{
            home,
            "test.txt",
        });
        defer alloc.free(expected);

        try std.testing.expectEqualStrings(expected, p);
    }
}

/// Calculate sha256 sum of a file. The caller owns the memory.
pub fn sha256Alloc(io: std.Io, alloc: std.mem.Allocator, path: []const u8) ![]const u8 {
    const fullpath = try toAbsolutePathAlloc(io, alloc, path, ".");
    defer alloc.free(fullpath);

    const file = try std.Io.Dir.cwd().openFile(io, fullpath, .{});
    defer file.close(io);

    var hash = std.crypto.hash.sha2.Sha256.init(.{});

    var reader_buffer: [8192]u8 = undefined;
    var reader = file.reader(io, &reader_buffer);

    var buffer: [8192]u8 = undefined;
    while (true) {
        const len = try reader.interface.readSliceShort(&buffer);
        if (len == 0) {
            break;
        }
        hash.update(buffer[0..len]);
    }

    var digest = hash.finalResult();
    return try std.fmt.allocPrint(
        alloc,
        "{x}",
        .{&digest},
    );
}

test "sha256Alloc" {
    const expected = "bff459dcf3b39fbd2e38a9b9e80b1ad87ed47331941ac86d9770db307ba4b282";

    const sha256sum = try sha256Alloc(std.testing.io, std.testing.allocator, "testdata/test_file");
    defer std.testing.allocator.free(sha256sum);

    try std.testing.expectEqualStrings(expected, sha256sum);
}

/// Compare two files
pub fn isDifferent(io: std.Io, alloc: std.mem.Allocator, path_a: []const u8, path_b: []const u8) bool {
    const checksum_a = sha256Alloc(io, alloc, path_a) catch "";
    defer alloc.free(checksum_a);

    const checksum_b = sha256Alloc(io, alloc, path_b) catch "";
    defer alloc.free(checksum_b);

    return !std.mem.eql(u8, checksum_a, checksum_b);
}

test "isDifferent" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    try std.testing.expect(!isDifferent(io, alloc, "testdata/test_file", "testdata/test_file"));
    try std.testing.expect(!isDifferent(io, alloc, "", ""));
    try std.testing.expect(isDifferent(io, alloc, "testdata/test_file", ""));
    try std.testing.expect(isDifferent(io, alloc, "testdata/test_file", "testdata/test_file2"));
}
