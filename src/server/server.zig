const std = @import("std");
const builtin = @import("builtin");
const network = @import("network");
const euc_jp = @import("euc_jis_2004_zig");
const req_handlers = @import("handlers.zig");
const log = @import("zutils").log;
const version = @import("../version.zig");
const dict = @import("../dict/dict.zig");

const Self = @This();

pub const Server = Self;

dict_mgr: *dict.Manager,
listen_addr: []const u8,
dictionary_directory: []const u8,
handlers: []const req_handlers.Handler,

const Context = struct {
    listen_addr: []const u8,
    dictionary_directory: []const u8,
    use_google: bool,
};

pub fn init(allocator: std.mem.Allocator, context: Context) !Self {
    const dict_mgr = try allocator.create(dict.Manager);
    dict_mgr.* = try dict.Manager.init(allocator);

    var hdls = try allocator.alloc(req_handlers.Handler, if (builtin.mode == .Debug) 7 else 6);
    hdls[0] = req_handlers.Handler{
        .disconnect_handler = req_handlers.DisconnectHandler{},
    };
    hdls[1] = req_handlers.Handler{
        .candidate_handler = req_handlers.CandidateHandler{
            .dict_mgr = dict_mgr,
            .use_google = context.use_google,
        },
    };
    hdls[2] = req_handlers.Handler{
        .raw_string_handler = req_handlers.RawStringHandler(128).init(version.FullDescription),
    };
    hdls[3] = req_handlers.Handler{
        .raw_string_handler = req_handlers.RawStringHandler(128).init(context.listen_addr),
    };
    hdls[4] = req_handlers.Handler{
        .completion_handler = req_handlers.CompletionHandler{ .dict_mgr = dict_mgr },
    };
    hdls[5] = req_handlers.Handler{
        .custom_protocol_handler = req_handlers.CustomProtocolHandler{ .dict_mgr = dict_mgr },
    };
    if (builtin.mode == .Debug) {
        hdls[6] = req_handlers.Handler{
            .exit_handler = req_handlers.ExitHandler{},
        };
    }

    return .{
        .dict_mgr = dict_mgr,
        .listen_addr = try allocator.dupe(u8, context.listen_addr),
        .dictionary_directory = try allocator.dupe(u8, context.dictionary_directory),
        .handlers = hdls,
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    allocator.free(self.listen_addr);
    allocator.free(self.dictionary_directory);
    allocator.free(self.handlers);
    allocator.destroy(self.dict_mgr);
}

pub fn serve(self: *Self, allocator: std.mem.Allocator, dicts: []dict.Location) !void {
    try self.dict_mgr.reloadLocations(dicts, self.dictionary_directory);
    defer self.dict_mgr.deinit();

    try network.init();

    const listen_addr = try allocator.dupe(u8, self.listen_addr);
    defer allocator.free(listen_addr);

    var len = std.mem.replace(u8, listen_addr, "[", "", listen_addr);
    len += std.mem.replace(u8, listen_addr, "]", "", listen_addr);
    const endpoint = try network.EndPoint.parse(listen_addr[0 .. listen_addr.len - len]);

    var server_socket = try network.Socket.create(@as(network.AddressFamily, endpoint.address), network.Protocol.tcp);
    try server_socket.enablePortReuse(true);

    try server_socket.bind(endpoint);
    try server_socket.listen();

    var ss = try network.SocketSet.init(allocator);
    defer ss.deinit();

    const socket_event: network.SocketEvent = .{
        .read = true,
        .write = false,
    };
    try ss.add(server_socket, socket_event);

    var arr: std.ArrayList(network.Socket) = .init(allocator);
    defer arr.deinit();

    log.info("Listening at {s}", .{self.listen_addr});

    var buf = [_]u8{0} ** 4096;
    var write_buf: std.ArrayList(u8) = .init(allocator);

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
                self.handleMessage(allocator, socket, &buf, &write_buf) catch |err| switch (err) {
                    error.Exit => {
                        return;
                    },
                    else => {
                        log.info("Connection disconnected", .{});
                        socket.close();
                        ss.remove(socket);
                        _ = arr.swapRemove(i);
                    },
                };
            }
        }
    }
}

fn handleMessage(self: *Self, allocator: std.mem.Allocator, socket: network.Socket, buf: []u8, output: *std.ArrayList(u8)) !void {
    output.clearAndFree();

    const read = try socket.receive(buf);
    if (read == 0) {
        return error.ConnectionDisconnected;
    }

    var conv_buf = [_]u8{0} ** 4096;
    const line = try euc_jp.convertEucJpToUtf8(std.mem.trim(u8, buf[0..read], " \n"), &conv_buf);

    log.info("Request: {s}", .{line});
    if (line.len == 0) {
        return;
    }

    const cmd = line[0] - '0';
    if (cmd >= self.handlers.len) {
        log.info("Invalid request: {s}", .{line});
        return;
    }

    try self.handlers[cmd].handle(allocator, output, line[1..]);
    try output.append('\n');
    _ = try socket.send(output.items);
}
