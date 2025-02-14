const std = @import("std");
const require = @import("protest").require;

pub fn contains(haystack: []const []const u8, needle: []const u8) bool {
    for (haystack) |n| {
        if (std.mem.eql(u8, n, needle)) {
            return true;
        }
    }

    return false;
}

test "contains" {
    const arr = [_][]const u8{ "abc", "def", "ghi" };

    try require.isTrue(contains(&arr, "ghi"));
    try require.isFalse(contains(&arr, "jkl"));
}
