const std = @import("std");
const mem = std.mem;
const net = std.net;
const network = @import("network");
const build_options = @import("build_options");

const ip = @import("ip.zig");
const log = @import("../log.zig");
const Handler = @import("handlers.zig").Handler;
const CandidateHandler = @import("handlers.zig").CandidateHandler;
const CompletionHandler = @import("handlers.zig").CompletionHandler;
const DisconnectHandler = @import("handlers.zig").DisconnectHandler;
const RawStringHandler = @import("handlers.zig").RawStringHandler;
const CustomProtocolHandler = @import("handlers.zig").CustomProtocolHandler;

const version = @import("../version.zig");
const euc_jp = @import("../japanese/euc_jp.zig");
const DictManager = @import("../skk/dict.zig").DictManager;

pub const ServerError = error{
    Disconnect,
};

const Context = struct {
    listen_addr: []const u8,
    dictionary_directory: []const u8,
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
            try handlers.put('0', Handler{ .disconnect_handler = handler });
        }
        {
            const handler = try allocator.create(CandidateHandler);
            handler.* = CandidateHandler.init(allocator, dict_mgr, context.use_google);
            try handlers.put('1', Handler{ .candidate_handler = handler });
        }
        {
            const handler = try allocator.create(RawStringHandler);
            handler.* = try RawStringHandler.init(allocator, version.FullDescription);
            try handlers.put('2', Handler{ .raw_string_handler = handler });
        }
        {
            const handler = try allocator.create(RawStringHandler);
            handler.* = try RawStringHandler.init(allocator, context.listen_addr);
            try handlers.put('3', Handler{ .raw_string_handler = handler });
        }
        {
            const handler = try allocator.create(CompletionHandler);
            handler.* = CompletionHandler.init(allocator, dict_mgr);
            try handlers.put('4', Handler{ .completion_handler = handler });
        }
        {
            const handler = try allocator.create(CustomProtocolHandler);
            handler.* = CustomProtocolHandler.init(allocator, dict_mgr);
            try handlers.put('c', Handler{ .custom_protocol_handler = handler });
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

        log.info("Listening at {s}", .{self.listen_addr});

        var buf = [_]u8{0} ** 4096;
        var write_buf = std.ArrayList(u8).init(self.allocator);

        while (true) {
            _ = try network.waitForSocketEvent(&ss, null);

            if (ss.isReadyRead(server_socket)) {
                const client_socket = try server_socket.accept();

                const addr = try client_socket.getRemoteEndPoint();
                log.info("New connection from {}", .{addr});

                try arr.append(client_socket);
                try ss.add(client_socket, socket_event);
            }

            for (arr.items, 0..) |socket, i| {
                if (ss.isReadyRead(socket)) {
                    self.handleMessage(socket, &buf, &write_buf) catch {
                        log.info("Connection disconnected", .{});
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

        const line = try euc_jp.convertEucJpToUtf8(self.allocator, mem.trim(u8, buf[0..read], " \n"));

        log.info("Request: {s}", .{line});
        if (line.len == 0) {
            return;
        }

        if (self.handlers.get(line[0])) |h| {
            try (h.handle(output, line[1..]));
            try output.append('\n');
            _ = try socket.send(output.items);
        } else {
            log.info("Invalid request: {s}", .{line});
        }
    }
};
