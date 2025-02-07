const std = @import("std");
const mem = std.mem;
const net = std.net;
const log = std.log;

const ip = @import("ip.zig");
const euc_jp = @import("../japanese/euc_jp.zig");
const DictManager = @import("../skk/dict.zig").DictManager;
const Handler = @import("handlers.zig").Handler;
const CandidateHandler = @import("handlers.zig").CandidateHandler;
const CompletionHandler = @import("handlers.zig").CompletionHandler;
const DisconnectHandler = @import("handlers.zig").DisconnectHandler;
const RawStringHandler = @import("handlers.zig").RawStringHandler;

pub const ServerError = error{
    Disconnect,
};

const Context = struct {
    listen_addr: []const u8,
    dictionary_directory: []const u8,
    version: []const u8,
    use_google: bool,
};

pub const Server = struct {
    const Self = @This();

    allocator: mem.Allocator,
    dict_mgr: *DictManager,
    listen_addr: []const u8,
    dictionary_directory: []const u8,
    handlers: *std.AutoArrayHashMap(u8, Handler),

    pub fn init(allocator: mem.Allocator, context: Context) !Self {
        const dict_mgr = try allocator.create(DictManager);
        dict_mgr.* = try DictManager.init(allocator);

        const handlers = try allocator.create(std.AutoArrayHashMap(u8, Handler));
        handlers.* = std.AutoArrayHashMap(u8, Handler).init(allocator);
        {
            const handler = try allocator.create(DisconnectHandler);
            try handlers.put('0', Handler{ .disconnectHandler = handler });
        }
        {
            const handler = try allocator.create(CandidateHandler);
            handler.* = CandidateHandler.init(allocator, dict_mgr, context.use_google);
            try handlers.put('1', Handler{ .candidateHandler = handler });
        }
        {
            const handler = try allocator.create(RawStringHandler);
            handler.* = try RawStringHandler.init(allocator, context.version);
            try handlers.put('2', Handler{ .rawStringHandler = handler });
        }
        {
            const handler = try allocator.create(RawStringHandler);
            handler.* = try RawStringHandler.init(allocator, context.listen_addr);
            try handlers.put('3', Handler{ .rawStringHandler = handler });
        }
        {
            const handler = try allocator.create(CompletionHandler);
            handler.* = CompletionHandler.init(allocator, dict_mgr);
            try handlers.put('4', Handler{ .completionHandler = handler });
        }

        return .{
            .allocator = allocator,
            .dict_mgr = dict_mgr,
            .listen_addr = try allocator.dupe(u8, context.listen_addr),
            .dictionary_directory = try allocator.dupe(u8, context.dictionary_directory),
            .handlers = handlers,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self.dict_mgr);
    }

    pub fn serve(self: *Self, dicts: []const []const u8) !void {
        const address = try ip.parseAddrPort(self.listen_addr);

        var server = try address.listen(.{ .reuse_port = true });
        defer server.deinit();

        try self.dict_mgr.loadUrls(dicts, self.dictionary_directory);

        log.info("Listening to 127.0.0.1:1178", .{});

        while (true) {
            const conn = try server.accept();
            const thread = try std.Thread.spawn(.{}, handleConnection, .{ self, conn });
            thread.detach();
        }
    }

    fn handleConnection(self: *Self, conn: std.net.Server.Connection) !void {
        defer conn.stream.close();
        log.info("New connection", .{});

        var request_buf: [1024]u8 = undefined;
        var response_buf = std.ArrayList(u8).init(self.allocator);
        defer response_buf.deinit();

        while (true) {
            const len = try conn.stream.read(&request_buf);
            if (len == 0) {
                log.info("Connection disconnected", .{});
                break;
            }
            const line = try euc_jp.convertEucJpToUtf8(self.allocator, mem.trim(u8, request_buf[0..len], " \n"));
            defer self.allocator.free(line);

            log.info("Request: {s}", .{line});
            if (line.len == 0) {
                continue;
            }

            if (self.handlers.get(line[0])) |h| {
                if (h.handle(&response_buf, line[1..])) {
                    defer response_buf.clearAndFree();

                    try response_buf.append('\n');
                    try conn.stream.writeAll(response_buf.items);
                } else |err| {
                    switch (err) {
                        ServerError.Disconnect => {
                            return;
                        },
                        else => {},
                    }
                }
            } else {
                log.err("Invalid request: {s}", .{line});
            }
        }
    }
};
