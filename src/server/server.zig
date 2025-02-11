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
    handlers: []const handlers.Handler,

    pub fn init(allocator: std.mem.Allocator, context: Context) !Self {
        const dict_mgr = try allocator.create(DictManager);
        dict_mgr.* = try DictManager.init(allocator);

        var hdls = try allocator.alloc(handlers.Handler, 6);
        hdls[0] = handlers.Handler{
            .disconnect_handler = handlers.DisconnectHandler{},
        };
        hdls[1] = handlers.Handler{
            .candidate_handler = handlers.CandidateHandler{
                .dict_mgr = dict_mgr,
                .use_google = context.use_google,
            },
        };
        hdls[2] = handlers.Handler{
            .raw_string_handler = handlers.RawStringHandler(128).init(version.FullDescription),
        };
        hdls[3] = handlers.Handler{
            .raw_string_handler = handlers.RawStringHandler(128).init(context.listen_addr),
        };
        hdls[4] = handlers.Handler{
            .completion_handler = handlers.CompletionHandler{ .dict_mgr = dict_mgr },
        };
        hdls[5] = handlers.Handler{
            .custom_protocol_handler = handlers.CustomProtocolHandler{ .dict_mgr = dict_mgr },
        };

        return .{
            .allocator = allocator,
            .dict_mgr = dict_mgr,
            .listen_addr = try allocator.dupe(u8, context.listen_addr),
            .dictionary_directory = try allocator.dupe(u8, context.dictionary_directory),
            .handlers = hdls,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.listen_addr);
        self.allocator.free(self.dictionary_directory);
        self.allocator.free(self.handlers);
        self.allocator.destroy(self.dict_mgr);
    }

    pub fn serve(self: *Self, dicts: []const []const u8) !void {
        try self.dict_mgr.loadUrls(dicts, self.dictionary_directory);
        defer self.dict_mgr.deinit();

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

        const cmd = line[0] - '0';
        if (cmd >= self.handlers.len) {
            utils.log.info("Invalid request: {s}", .{line});
            return;
        }

        try self.handlers[cmd].handle(output, line[1..]);
        try output.append('\n');
        _ = try socket.send(output.items);
    }
};
