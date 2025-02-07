const std = @import("std");

const RequestError = error{
    HttpError,
    NotFound,
};

/// No need to free memory of result
pub fn transliterateRequest(allocator: std.mem.Allocator, key: []const u8) ![]const u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    const writer = buffer.writer();

    try std.Uri.Component.percentEncode(writer, key, struct {
        fn isValidChar(c: u8) bool {
            const str = "!#$&'()*+,/:;=?@[] ";
            return if (std.mem.indexOf(u8, str, &[_]u8{c})) |_| false else true;
        }
    }.isValidChar);

    const base_url = "http://www.google.com/transliterate?langpair=ja-Hira|ja&text=";
    const url = try std.fmt.allocPrint(allocator, "{s}{s}", .{ base_url, buffer.items });
    defer allocator.free(url);

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    buffer.clearAndFree();
    const uri = try std.Uri.parse(url);
    std.log.info("Request to google {}", .{uri});

    buffer.clearAndFree();
    try buffer.ensureTotalCapacity(1024 * 1024);
    buffer.expandToCapacity();
    var req = try client.open(.GET, uri, .{
        .server_header_buffer = buffer.items,
    });
    defer req.deinit();

    try req.send();
    try req.finish();
    try req.wait();

    if (req.response.status != .ok) {
        return RequestError.HttpError;
    }

    buffer.clearAndFree();
    var rdr = req.reader();
    try rdr.readAllArrayList(&buffer, 1024 * 1024);
    return try parseResponse(allocator, buffer.items, key);
}

fn parseResponse(allocator: std.mem.Allocator, resp: []const u8, key: []const u8) ![]const u8 {
    var parsed = try std.json.parseFromSlice([]std.json.Value, allocator, resp, .{});
    defer parsed.deinit();

    if (parsed.value.len == 0) {
        return RequestError.NotFound;
    }

    const first = parsed.value[0];
    const nested = switch (first) {
        .array => |v| v,
        else => return RequestError.NotFound,
    };

    if (nested.items.len != 2) {
        return RequestError.NotFound;
    }

    const k = switch (nested.items[0]) {
        .string => |v| v,
        else => return RequestError.NotFound,
    };
    if (!std.mem.eql(u8, k, key)) {
        return RequestError.NotFound;
    }

    const array = switch (nested.items[1]) {
        .array => |v| v,
        else => return RequestError.NotFound,
    };
    if (array.items.len == 0) {
        return RequestError.NotFound;
    }

    var result_arr = std.ArrayList(u8).init(allocator);
    defer result_arr.deinit();

    try result_arr.append('/');
    for (array.items) |item| {
        const s = switch (item) {
            .string => |v| v,
            else => return RequestError.NotFound,
        };
        try result_arr.appendSlice(s);
        try result_arr.append('/');
    }
    return result_arr.toOwnedSlice();
}

const require = @import("protest").require;

test "test 1+1" {
    const resp = try transliterateRequest(std.testing.allocator, "=1+1");
    defer std.testing.allocator.free(resp);
    try require.equal("/2/2=1+1/＝１＋１/=1+1/", resp);
}

test "test parseResponse =1+1" {
    const json_str =
        \\[
        \\  [
        \\    "=1+1",
        \\    [
        \\      "2",
        \\      "2=1+1",
        \\      "＝１＋１",
        \\      "=1+1"
        \\    ]
        \\  ]
        \\]
    ;

    const resp = try parseResponse(std.testing.allocator, json_str, "=1+1");
    defer std.testing.allocator.free(resp);
    try require.equal("/2/2=1+1/＝１＋１/=1+1/", resp);
}

test "test parseResponse unmatch 1" {
    const json_str =
        \\[
        \\  [
        \\    "=1+1",
        \\    [
        \\      "2",
        \\      "2=1+1",
        \\      "＝１＋１",
        \\      "=1+1"
        \\    ]
        \\  ]
        \\]
    ;

    if (parseResponse(std.testing.allocator, json_str, "1+1")) |_| {
        try require.fail("should not success");
    } else |_| {}
}

test "test parseResponse unmatch 2" {
    const json_str =
        \\[
        \\  [
        \\    "=1+1",
        \\    [
        \\    ]
        \\  ]
        \\]
    ;

    if (parseResponse(std.testing.allocator, json_str, "1+1")) |_| {
        try require.fail("should not success");
    } else |_| {}
}

test "test parseResponse unmatch 3" {
    const json_str =
        \\[
        \\  [
        \\    1,
        \\    [
        \\      "2",
        \\      "2=1+1",
        \\      "＝１＋１",
        \\      "=1+1"
        \\    ]
        \\  ]
        \\]
    ;

    if (parseResponse(std.testing.allocator, json_str, "1+1")) |_| {
        try require.fail("should not success");
    } else |_| {}
}

test "test parseResponse unmatch 4" {
    const json_str =
        \\[
        \\  [
        \\    "=1+1",
        \\    "abc",
        \\  ]
        \\]
    ;

    if (parseResponse(std.testing.allocator, json_str, "1+1")) |_| {
        try require.fail("should not success");
    } else |_| {}
}

test "test parseResponse unstructured 2" {
    const json_str =
        \\{
        \\  {
        \\    "=1+1",
        \\    -
        \\      "2",
        \\      "2=1+1",
        \\      "＝１＋１",
        \\      "=1+1"
        \\    ]
        \\  ]
        \\}
    ;

    if (parseResponse(std.testing.allocator, json_str, "1+1")) |_| {
        try require.fail("should not success");
    } else |_| {}
}
