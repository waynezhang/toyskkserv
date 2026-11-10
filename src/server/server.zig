const std = @import("std");
const builtin = @import("builtin");
const euc_jp = @import("euc_jis_2004_zig");
const req_handlers = @import("handlers.zig");
const utils = @import("../utils/utils.zig");
const log = utils.log;
const version = @import("../version.zig");
const dict = @import("../dict/dict.zig");

const Self = @This();

pub const Server = Self;

dict_mgr: *dict.Manager,
listen_addr: []const u8,
dictionary_directory: []const u8,
handlers: []const req_handlers.Handler,
/// Guards the dictionary: reload takes it exclusively, lookups share it.
dict_lock: std.Io.RwLock = .init,

const Context = struct {
    listen_addr: []const u8,
    dictionary_directory: []const u8,
    use_google: bool,
};

pub fn init(io: std.Io, allocator: std.mem.Allocator, context: Context) !Self {
    const dict_mgr = try allocator.create(dict.Manager);
    dict_mgr.* = try dict.Manager.init(io, allocator);

    const hdls = blk: {
        var hdls = try allocator.alloc(req_handlers.Handler, if (builtin.mode == .debug) 7 else 6);
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
        if (builtin.mode == .debug) {
            hdls[6] = req_handlers.Handler{
                .exit_handler = req_handlers.ExitHandler{},
            };
        }

        break :blk hdls;
    };

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

pub fn serve(self: *Self, io: std.Io, allocator: std.mem.Allocator, dicts: []dict.Location) !void {
    try self.dict_mgr.reloadLocations(dicts, self.dictionary_directory);
    defer self.dict_mgr.deinit();

    const address = try utils.net.parseAddrPort(self.listen_addr);
    var server = try address.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);

    log.info("Listening at {s}", .{self.listen_addr});

    var clients: std.Io.Group = .init;
    defer clients.cancel(io);

    // Set when the accept loop stops or a client asks the server to exit.
    var done: std.Io.Event = .unset;

    var accept_task = try io.concurrent(acceptLoop, .{ self, io, allocator, &server, &clients, &done });
    done.waitUncancelable(io);
    accept_task.cancel(io) catch |err| switch (err) {
        error.Canceled => {},
        else => return err,
    };
}

fn acceptLoop(
    self: *Self,
    io: std.Io,
    allocator: std.mem.Allocator,
    server: *std.Io.net.Server,
    clients: *std.Io.Group,
    done: *std.Io.Event,
) !void {
    defer done.set(io);

    while (true) {
        const stream = try server.accept(io);
        log.info("New connection from {f}", .{stream.socket.address});

        clients.concurrent(io, handleClient, .{ self, io, allocator, stream, done }) catch |err| {
            log.err("Failed to handle connection due to {}", .{err});
            stream.close(io);
        };
    }
}

fn handleClient(self: *Self, io: std.Io, allocator: std.mem.Allocator, stream: std.Io.net.Stream, done: *std.Io.Event) std.Io.Cancelable!void {
    defer stream.close(io);

    var buf: [4096]u8 = @splat(0);
    var write_allocating = std.Io.Writer.Allocating.init(allocator);
    defer write_allocating.deinit();

    while (true) {
        self.handleMessage(io, allocator, stream, &buf, &write_allocating) catch |err| switch (err) {
            error.Canceled => return error.Canceled,
            error.Exit => {
                done.set(io);
                return;
            },
            else => {
                log.info("Connection disconnected due to {}", .{err});
                return;
            },
        };
    }
}

fn handleMessage(self: *Self, io: std.Io, allocator: std.mem.Allocator, stream: std.Io.net.Stream, buf: []u8, writer_allocating: *std.Io.Writer.Allocating) !void {
    writer_allocating.clearRetainingCapacity();

    var bufs = [_][]u8{buf};
    const read = try stream.read(io, &bufs);
    if (read == 0) {
        return error.ConnectionDisconnected;
    }

    var conv_buf: [4096]u8 = @splat(0);
    const line = try euc_jp.convertEucJpToUtf8(std.mem.trim(u8, buf[0..read], " \n"), &conv_buf);

    log.info("Request: {s}", .{line});
    if (line.len == 0) {
        return;
    }

    const cmd = line[0] -% '0';
    if (cmd >= self.handlers.len) {
        log.info("Invalid request: {s}", .{line});
        return;
    }

    {
        // Only the custom protocol handler (reload) changes the dictionary.
        const exclusive = self.handlers[cmd] == .custom_protocol_handler;
        if (exclusive) try self.dict_lock.lock(io) else try self.dict_lock.lockShared(io);
        defer if (exclusive) self.dict_lock.unlock(io) else self.dict_lock.unlockShared(io);

        try self.handlers[cmd].handle(io, allocator, &writer_allocating.writer, line[1..]);
    }
    try writer_allocating.writer.writeByte('\n');

    var writer = stream.writer(io, &.{});
    try writer.interface.writeAll(writer_allocating.written());
    try writer.interface.flush();
}
