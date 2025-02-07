const std = @import("std");
const table = @import("euc_jp_table.zig");
const require = @import("protest").require;

pub const ConvertError = error{InvalidCharacter};

pub fn convertEucJpToUtf8(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();

    var i: usize = 0;
    while (i < input.len) {
        switch (input[i]) {
            0x00...0x7E => {
                try output.append(input[i]);
                i += 1;
            },
            0x8E => {
                if (i + 1 == input.len) {
                    return error.InvalidCharacter;
                }
                const c1 = input[i + 1];
                if (c1 < 0xA1 or c1 > 0xDF) {
                    return error.InvalidCharacter;
                }
                const val = @as(u21, c1) + @as(u21, 0xFF61 - 0xA1);
                try append(&output, val);
                i += 2;
            },
            0x8F => {
                if (i + 2 >= input.len) {
                    return error.InvalidCharacter;
                }
                const c1 = input[i + 1];
                if (c1 < 0xA1 or c1 > 0xFE) {
                    return error.InvalidCharacter;
                }
                const c2 = input[i + 2];
                if (c2 < 0xA1 or (c1 == 0xFE and c2 > 0xF6)) {
                    return error.InvalidCharacter;
                }
                const idx = (@as(u21, c1) << 8) + @as(u21, c2) - 0xA1A1;
                const val = table.eucJis2ndMap[idx];
                try append(&output, val);
                i += 3;
            },
            0xA1...0xFE => {
                if (i + 1 == input.len) {
                    return error.InvalidCharacter;
                }

                const c1 = input[i + 1];
                if (c1 < 0xA1 or c1 > 0xFE) {
                    return error.InvalidCharacter;
                }

                const idx = (@as(u21, input[i]) << 8) + @as(u21, c1);
                switch (idx) {
                    0xA4F7 => {
                        try append(&output, 0x304B);
                        try append(&output, 0x309A);
                    },
                    0xA4F8 => {
                        try append(&output, 0x304D);
                        try append(&output, 0x309A);
                    },
                    0xA4F9 => {
                        try append(&output, 0x304F);
                        try append(&output, 0x309A);
                    },
                    0xA4FA => {
                        try append(&output, 0x3051);
                        try append(&output, 0x309A);
                    },
                    0xA4FB => {
                        try append(&output, 0x3053);
                        try append(&output, 0x309A);
                    },
                    0xA5F7 => {
                        try append(&output, 0x30AB);
                        try append(&output, 0x309A);
                    },
                    0xA5F8 => {
                        try append(&output, 0x30AD);
                        try append(&output, 0x309A);
                    },
                    0xA5F9 => {
                        try append(&output, 0x30AF);
                        try append(&output, 0x309A);
                    },
                    0xA5FA => {
                        try append(&output, 0x30B1);
                        try append(&output, 0x309A);
                    },
                    0xA5FB => {
                        try append(&output, 0x30B3);
                        try append(&output, 0x309A);
                    },
                    0xA5FC => {
                        try append(&output, 0x30BB);
                        try append(&output, 0x309A);
                    },
                    0xA5FD => {
                        try append(&output, 0x30C4);
                        try append(&output, 0x309A);
                    },
                    0xA5FE => {
                        try append(&output, 0x30C8);
                        try append(&output, 0x309A);
                    },
                    0xA6F8 => {
                        try append(&output, 0x31F7);
                        try append(&output, 0x309A);
                    },
                    0xABC4 => {
                        try append(&output, 0xE6);
                        try append(&output, 0x300);
                    },
                    0xABC8 => {
                        try append(&output, 0x254);
                        try append(&output, 0x300);
                    },
                    0xABC9 => {
                        try append(&output, 0x254);
                        try append(&output, 0x301);
                    },
                    0xABCA => {
                        try append(&output, 0x28C);
                        try append(&output, 0x300);
                    },
                    0xABCB => {
                        try append(&output, 0x28C);
                        try append(&output, 0x301);
                    },
                    0xABCC => {
                        try append(&output, 0x259);
                        try append(&output, 0x300);
                    },
                    0xABCD => {
                        try append(&output, 0x259);
                        try append(&output, 0x301);
                    },
                    0xABCE => {
                        try append(&output, 0x25A);
                        try append(&output, 0x300);
                    },
                    0xABCF => {
                        try append(&output, 0x25A);
                        try append(&output, 0x301);
                    },
                    0xABE5 => {
                        try append(&output, 0x2E9);
                        try append(&output, 0x2E5);
                    },
                    0xABE6 => {
                        try append(&output, 0x2E5);
                        try append(&output, 0x2E9);
                    },
                    else => {
                        try append(&output, table.eucJis1stMap[idx - 0xA1A1]);
                    },
                }
                i += 2;
            },
            else => {
                return error.InvalidCharacter;
            },
        }
    }

    return output.toOwnedSlice();
}

fn append(output: *std.ArrayList(u8), n: u21) !void {
    var buf: [4]u8 = undefined;
    const len = std.unicode.utf8Encode(n, &buf) catch |err| {
        return err;
    };
    try output.appendSlice(buf[0..len]);
}

test "decode" {
    const allocator = std.testing.allocator;

    const efile = try std.fs.cwd().openFile("testdata/euc-jis-2004-with-char-u8.txt", .{});
    defer efile.close();

    const cfile = try std.fs.cwd().openFile("testdata/euc-jis-2004-with-char.txt", .{});
    defer cfile.close();

    var ebuf_reader = std.io.bufferedReader(efile.reader());
    var cbuf_reader = std.io.bufferedReader(cfile.reader());

    var ebuf_stream = ebuf_reader.reader();
    var cbuf_stream = cbuf_reader.reader();

    var expect_buf = std.ArrayList(u8).init(allocator);
    defer expect_buf.deinit();
    var convert_buf = std.ArrayList(u8).init(allocator);
    defer convert_buf.deinit();

    while (true) {
        _ = ebuf_stream.streamUntilDelimiter(expect_buf.writer(), '\n', null) catch |err| switch (err) {
            error.EndOfStream => break,
            else => try require.fail("Failed to read file"),
        };
        _ = cbuf_stream.streamUntilDelimiter(convert_buf.writer(), '\n', null) catch |err| switch (err) {
            error.EndOfStream => break,
            else => try require.fail("Failed to read file"),
        };

        const line = try convertEucJpToUtf8(std.testing.allocator, convert_buf.items);
        defer std.testing.allocator.free(line);

        try require.equal(expect_buf.items, line);
        expect_buf.clearRetainingCapacity();
        convert_buf.clearRetainingCapacity();
    }
}
