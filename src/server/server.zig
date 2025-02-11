const std = @import("std");
const network = @import("network");
const euc_jp = @import("euc-jis-2004-zig");

const handlers = @import("handlers.zig");
const utils = @import("../utils/utils.zig");
const version = @import("../version.zig");
const DictManager = @import("../dict.zig").DictManager;

const Context = struct {
    listen_addr: []const u8,
    dictionary_directory: []const u8,
    use_google: bool,
};

pub const Server = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    dict_mgr: *DictManager,
    listen_addr: []const u8,
    dictionary_directory: []const u8,
    handlers: *std.AutoArrayHashMap(u8, handlers.Handler),

    pub fn init(allocator: std.mem.Allocator, context: Context) !Self {
        const dict_mgr = try allocator.create(DictManager);
        dict_mgr.* = try DictManager.init(allocator);

        const hdls = try allocator.create(std.AutoArrayHashMap(u8, handlers.Handler));
        hdls.* = std.AutoArrayHashMap(u8, handlers.Handler).init(allocator);
        {
            const handler = try allocator.create(handlers.DisconnectHandler);
            try hdls.put('0', handlers.Handler{ .disconnect_handler = handler });
        }
        {
            const handler = try allocator.create(handlers.CandidateHandler);
            handler.* = handlers.CandidateHandler.init(allocator, dict_mgr, context.use_google);
            try hdls.put('1', handlers.Handler{ .candidate_handler = handler });
        }
        {
            const handler = try allocator.create(handlers.RawStringHandler);
            handler.* = try handlers.RawStringHandler.init(allocator, version.FullDescription);
            try hdls.put('2', handlers.Handler{ .raw_string_handler = handler });
        }
        {
            const handler = try allocator.create(handlers.RawStringHandler);
            handler.* = try handlers.RawStringHandler.init(allocator, context.listen_addr);
            try hdls.put('3', handlers.Handler{ .raw_string_handler = handler });
        }
        {
            const handler = try allocator.create(handlers.CompletionHandler);
            handler.* = handlers.CompletionHandler.init(allocator, dict_mgr);
            try hdls.put('4', handlers.Handler{ .completion_handler = handler });
        }
        {
            const handler = try allocator.create(handlers.CustomProtocolHandler);
            handler.* = handlers.CustomProtocolHandler.init(allocator, dict_mgr);
            try hdls.put('c', handlers.Handler{ .custom_protocol_handler = handler });
        }

        return .{
            .allocator = allocator,
            .dict_mgr = dict_mgr,
            .listen_addr = try allocator.dupe(u8, context.listen_addr),
            .dictionary_directory = try allocator.dupe(u8, context.dictionary_directory),
            .handlers = hdls,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self.dict_mgr);
    }

    pub fn serve(self: *Self, dicts: []const []const u8) !void {
        try self.dict_mgr.loadUrls(dicts, self.dictionary_directory);

        try network.init();
        var server_socket = try network.Socket.create(network.AddressFamily.ipv4, network.Protocol.tcp);
        const endpoint = try network.EndPoint.parse(self.listen_addr);
        try server_socket.enablePortReuse(true);

        try server_socket.bind(endpoint);
        try server_socket.listen();

        var ss = try network.SocketSet.init(self.allocator);

        const socket_event: network.SocketEvent = .{
            .read = true,
            .write = false,
        };
        try ss.add(server_socket, socket_event);

        var arr = std.ArrayList(network.Socket).init(self.allocator);
        defer {
            arr.deinit();
        }

        utils.log.info("Listening at {s}", .{self.listen_addr});

        var buf = [_]u8{0} ** 4096;
        var write_buf = std.ArrayList(u8).init(self.allocator);

        while (true) {
            _ = try network.waitForSocketEvent(&ss, null);

            if (ss.isReadyRead(server_socket)) {
                const client_socket = try server_socket.accept();

                const addr = try client_socket.getRemoteEndPoint();
                utils.log.info("New connection from {}", .{addr});

                try arr.append(client_socket);
                try ss.add(client_socket, socket_event);
            }

            for (arr.items, 0..) |socket, i| {
                if (ss.isReadyRead(socket)) {
                    self.handleMessage(socket, &buf, &write_buf) catch {
                        utils.log.info("Connection disconnected", .{});
                        socket.close();
                        ss.remove(socket);
                        _ = arr.swapRemove(i);
                    };
                }
            }
        }
    }

    fn handleMessage(self: *Self, socket: network.Socket, buf: []u8, output: *std.ArrayList(u8)) !void {
        output.clearAndFree();

        const read = try socket.receive(buf);
        if (read == 0) {
            return error.ConnectionDisconnected;
        }

        var conv_buf = [_]u8{0} ** 4096;
        const line = try euc_jp.convertEucJpToUtf8(std.mem.trim(u8, buf[0..read], " \n"), &conv_buf);

        utils.log.info("Request: {s}", .{line});
        if (line.len == 0) {
            return;
        }

        if (self.handlers.get(line[0])) |h| {
            try (h.handle(output, line[1..]));
            try output.append('\n');
            _ = try socket.send(output.items);
        } else {
            utils.log.info("Invalid request: {s}", .{line});
        }
    }
};
