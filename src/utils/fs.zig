const std = @import("std");
const temp = @import("temp");
const require = @import("protest").require;

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
