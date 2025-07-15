const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const assert = std.debug.assert;
const lsp = @import("lsp");
const types = lsp.types;
const offsets = lsp.offsets;
const super = @import("superhtml");
const Document = @import("lsp/Document.zig");
const logic = @import("lsp/logic.zig");

const log = std.log.scoped(.super_lsp);

pub fn run(gpa: std.mem.Allocator, args: []const []const u8) !void {
    _ = args;

    log.debug("SuperHTML LSP started!", .{});

    var buf: [4096]u8 = undefined;
    var stdio: lsp.Transport.Stdio = .init(
        &buf,
        std.fs.File.stdin(),
        std.fs.File.stdout(),
    );

    var handler: Handler = .{
        .gpa = gpa,
        .transport = &stdio.transport,
    };
    defer handler.deinit();

    try lsp.basic_server.run(
        gpa,
        &stdio.transport,
        &handler,
        log.err,
    );
}

pub const Handler = @This();

gpa: std.mem.Allocator,
transport: *lsp.Transport,
files: std.StringHashMapUnmanaged(Document) = .{},
offset_encoding: offsets.Encoding = .@"utf-16",

fn deinit(self: *Handler) void {
    var file_it = self.files.valueIterator();
    while (file_it.next()) |file| file.deinit(self.gpa);
    self.files.deinit(self.gpa);
    self.* = undefined;
}

fn windowNotification(
    self: *Handler,
    lvl: types.MessageType,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const txt = try std.fmt.allocPrint(self.gpa, fmt, args);

    try self.transport.writeNotification(
        self.gpa,
        "window/showMessage",
        types.ShowMessageParams,
        .{ .type = lvl, .message = txt },
        .{ .emit_null_optional_fields = false },
    );
}

pub fn initialize(
    self: *Handler,
    _: std.mem.Allocator,
    request: types.InitializeParams,
) types.InitializeResult {
    if (request.clientInfo) |clientInfo| {
        log.info("client is '{s}-{s}'", .{ clientInfo.name, clientInfo.version orelse "<no version>" });
    }

    if (request.capabilities.general) |general| {
        for (general.positionEncodings orelse &.{}) |encoding| {
            self.offset_encoding = switch (encoding) {
                .@"utf-8" => .@"utf-8",
                .@"utf-16" => .@"utf-16",
                .@"utf-32" => .@"utf-32",
                .custom_value => continue,
            };
            break;
        }
    }

    log.debug("init!", .{});

    const capabilities: types.ServerCapabilities = .{
        .positionEncoding = switch (self.offset_encoding) {
            .@"utf-8" => .@"utf-8",
            .@"utf-16" => .@"utf-16",
            .@"utf-32" => .@"utf-32",
        },
        .textDocumentSync = .{
            .TextDocumentSyncOptions = .{
                .openClose = true,
                .change = .Full,
            },
        },
        .documentFormattingProvider = .{ .bool = true },
    };

    if (@import("builtin").mode == .Debug) {
        lsp.basic_server.validateServerCapabilities(Handler, capabilities);
    }

    return .{
        .serverInfo = .{
            .name = "SuperHTML LSP",
            .version = build_options.version,
        },
        .capabilities = capabilities,
    };
}

pub fn @"textDocument/didOpen"(
    self: *Handler,
    arena: std.mem.Allocator,
    notification: types.DidOpenTextDocumentParams,
) !void {
    const new_text = try self.gpa.dupe(u8, notification.textDocument.text);
    errdefer self.gpa.free(new_text);

    const language_id = notification.textDocument.languageId;
    const language = super.Language.fromSliceResilient(language_id) orelse {
        log.err("unrecognized language id: '{s}'", .{language_id});
        try self.windowNotification(
            .Error,
            "Unrecognized languageId, expected are: html, superhtml, xml",
            .{},
        );
        @panic("unrecognized language id, exiting");
    };

    try logic.loadFile(
        self,
        arena,
        new_text,
        notification.textDocument.uri,
        language,
    );
}

pub fn @"textDocument/didChange"(
    self: *Handler,
    arena: std.mem.Allocator,
    notification: types.DidChangeTextDocumentParams,
) !void {
    if (notification.contentChanges.len == 0) {
        return;
    }

    const file = self.files.get(notification.textDocument.uri) orelse {
        log.err("changeDocument failed: unknown file: {any}", .{notification.textDocument.uri});

        try self.windowNotification(
            .Error,
            "Unrecognized languageId, expected are: html, superhtml, xml",
            .{},
        );
        return error.InvalidParams;
    };

    var buffer: std.ArrayListUnmanaged(u8) = .fromOwnedSlice(@constCast(file.src));
    errdefer buffer.deinit(self.gpa);

    for (notification.contentChanges) |content_change| {
        switch (content_change) {
            .literal_1 => |change| {
                buffer.clearRetainingCapacity();
                try buffer.appendSlice(self.gpa, change.text);
            },
            .literal_0 => |change| {
                const loc = offsets.rangeToLoc(buffer.items, change.range, self.offset_encoding);
                try buffer.replaceRange(self.gpa, loc.start, loc.end - loc.start, change.text);
            },
        }
    }

    const new_text = try buffer.toOwnedSlice(self.gpa);
    errdefer self.gpa.free(new_text);

    // TODO: this is a hack while we wait for actual incremental reloads
    try logic.loadFile(
        self,
        arena,
        new_text,
        notification.textDocument.uri,
        file.language,
    );
}

pub fn @"textDocument/didClose"(
    self: *Handler,
    _: std.mem.Allocator,
    notification: types.DidCloseTextDocumentParams,
) void {
    var kv = self.files.fetchRemove(notification.textDocument.uri) orelse return;
    self.gpa.free(kv.key);
    kv.value.deinit(self.gpa);
}

pub fn @"textDocument/formatting"(
    self: *const Handler,
    arena: std.mem.Allocator,
    request: types.DocumentFormattingParams,
) !?[]const types.TextEdit {
    log.debug("format request!!", .{});

    const doc = self.files.getPtr(request.textDocument.uri) orelse return null;
    if (doc.html.errors.len != 0) {
        return null;
    }

    const range: offsets.Range = .{
        .start = .{ .line = 0, .character = 0 },
        .end = offsets.indexToPosition(doc.src, doc.src.len, self.offset_encoding),
    };

    log.debug("format!!", .{});

    var aw = std.Io.Writer.Allocating.init(arena);
    try doc.html.render(doc.src, &aw.writer);

    return try arena.dupe(types.TextEdit, &.{.{
        .range = range,
        .newText = aw.getWritten(),
    }});
}

pub fn onResponse(
    _: *Handler,
    _: std.mem.Allocator,
    response: lsp.JsonRPCMessage.Response,
) void {
    log.warn("received unexpected response from client with id '{?}'!", .{response.id});
}

pub fn getRange(span: super.Span, src: []const u8) types.Range {
    const r = span.range(src);
    return .{
        .start = .{ .line = r.start.row, .character = r.start.col },
        .end = .{ .line = r.end.row, .character = r.end.col },
    };
}
