const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const lsp = @import("lsp");
const types = lsp.types;
const offsets = lsp.offsets;
const ResultType = lsp.server.ResultType;
const Message = lsp.server.Message;
const super = @import("superhtml");
const Document = @import("lsp/Document.zig");
const version = @import("../cli.zig").version;

const log = std.log.scoped(.super_lsp);

const SuperLsp = lsp.server.Server(Handler);

pub fn run(gpa: std.mem.Allocator, args: []const []const u8) !void {
    _ = args;

    log.debug("SuperHTML LSP started!", .{});

    var transport = lsp.Transport.init(
        std.io.getStdIn().reader(),
        std.io.getStdOut().writer(),
    );
    transport.message_tracing = false;

    var server: SuperLsp = undefined;
    var handler: Handler = .{
        .gpa = gpa,
        .server = &server,
    };
    server = try SuperLsp.init(gpa, &transport, &handler);

    try server.loop();
}

pub const Handler = struct {
    gpa: std.mem.Allocator,
    server: *SuperLsp,
    files: std.StringHashMapUnmanaged(Document) = .{},
    offset_encoding: offsets.Encoding = .@"utf-16",

    usingnamespace @import("lsp/logic.zig");

    fn windowNotification(
        self: *Handler,
        lvl: types.MessageType,
        comptime fmt: []const u8,
        args: anytype,
    ) !void {
        const txt = try std.fmt.allocPrint(self.gpa, fmt, args);
        const msg = try self.server.sendToClientNotification(
            "window/showMessage",
            .{ .type = lvl, .message = txt },
        );
        defer self.gpa.free(msg);
    }

    pub fn initialize(
        self: *Handler,
        _: std.mem.Allocator,
        request: types.InitializeParams,
        offset_encoding_: offsets.Encoding,
    ) !lsp.types.InitializeResult {
        self.offset_encoding = offset_encoding_;

        if (request.clientInfo) |clientInfo| {
            log.info("client is '{s}-{s}'", .{ clientInfo.name, clientInfo.version orelse "<no version>" });
        }

        log.debug("init!", .{});

        return .{
            .serverInfo = .{
                .name = "SuperHTML LSP",
                .version = version,
            },
            .capabilities = .{
                .positionEncoding = switch (offset_encoding_) {
                    .@"utf-8" => .@"utf-8",
                    .@"utf-16" => .@"utf-16",
                    .@"utf-32" => .@"utf-32",
                },
                .textDocumentSync = .{
                    .TextDocumentSyncOptions = .{
                        .openClose = true,
                        .change = .Full,
                        .save = .{ .bool = true },
                    },
                },
                .completionProvider = .{
                    .triggerCharacters = &[_][]const u8{"<"},
                },
                .hoverProvider = .{ .bool = false },
                .definitionProvider = .{ .bool = false },
                .referencesProvider = .{ .bool = false },
                .documentFormattingProvider = .{ .bool = true },
                .semanticTokensProvider = .{
                    .SemanticTokensOptions = .{
                        .full = .{ .bool = false },
                        .legend = .{
                            .tokenTypes = std.meta.fieldNames(types.SemanticTokenTypes),
                            .tokenModifiers = std.meta.fieldNames(types.SemanticTokenModifiers),
                        },
                    },
                },
                .inlayHintProvider = .{ .bool = false },
            },
        };
    }

    pub fn initialized(
        self: *Handler,
        _: std.mem.Allocator,
        notification: types.InitializedParams,
    ) !void {
        _ = self;
        _ = notification;
    }

    pub fn shutdown(
        _: Handler,
        _: std.mem.Allocator,
        notification: void,
    ) !?void {
        _ = notification;
    }

    pub fn exit(
        _: Handler,
        _: std.mem.Allocator,
        notification: void,
    ) !void {
        _ = notification;
    }

    pub fn openDocument(
        self: *Handler,
        arena: std.mem.Allocator,
        notification: types.DidOpenTextDocumentParams,
    ) !void {
        const new_text = try self.gpa.dupeZ(u8, notification.textDocument.text); // We informed the client that we only do full document syncs
        errdefer self.gpa.free(new_text);

        const language_id = notification.textDocument.languageId;
        const language = std.meta.stringToEnum(super.Language, language_id) orelse {
            log.err("unrecognized language id: '{s}'", .{language_id});
            try self.windowNotification(
                .Error,
                "Unrecognized languageId, expected are: html, superhtml, xml",
                .{},
            );
            @panic("unrecognized language id, exiting");
        };
        try self.loadFile(
            arena,
            new_text,
            notification.textDocument.uri,
            language,
        );
    }

    pub fn changeDocument(
        self: *Handler,
        arena: std.mem.Allocator,
        notification: types.DidChangeTextDocumentParams,
    ) !void {
        errdefer |e| log.err("changeDocument failed: {any}", .{e});

        if (notification.contentChanges.len == 0) {
            log.warn("changeDocument failed: no changes", .{});
            return error.InternalError;
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

        for (notification.contentChanges) |change_| {
            const new_text = switch (change_) {
                .literal_1 => |change| try self.gpa.dupeZ(u8, change.text),
                .literal_0 => |change| blk: {
                    const old_text = file.src;
                    const range = change.range;
                    const start_idx = offsets.maybePositionToIndex(old_text, range.start, self.offset_encoding) orelse {
                        log.warn("changeDocument failed: invalid start position: {any}", .{range.start});
                        return error.InternalError;
                    };
                    const end_idx = offsets.maybePositionToIndex(old_text, range.end, self.offset_encoding) orelse {
                        log.warn("changeDocument failed: invalid end position: {any}", .{range.end});
                        return error.InternalError;
                    };
                    var new_text = std.ArrayList(u8).init(self.gpa);
                    errdefer new_text.deinit();
                    try new_text.appendSlice(old_text[0..start_idx]);
                    try new_text.appendSlice(change.text);
                    try new_text.appendSlice(old_text[end_idx..]);
                    break :blk try new_text.toOwnedSliceSentinel(0);
                },
            };
            errdefer self.gpa.free(new_text);

            // TODO: this is a hack while we wait for actual incremental reloads
            try self.loadFile(
                arena,
                new_text,
                notification.textDocument.uri,
                file.language,
            );
        }
    }

    pub fn saveDocument(
        _: Handler,
        arena: std.mem.Allocator,
        notification: types.DidSaveTextDocumentParams,
    ) !void {
        _ = arena;
        _ = notification;
    }

    pub fn closeDocument(
        self: *Handler,
        _: std.mem.Allocator,
        notification: types.DidCloseTextDocumentParams,
    ) error{}!void {
        var kv = self.files.fetchRemove(notification.textDocument.uri) orelse return;
        self.gpa.free(kv.key);
        kv.value.deinit(self.gpa);
    }

    pub fn completion(
        self: Handler,
        arena: std.mem.Allocator,
        request: types.CompletionParams,
    ) !ResultType("textDocument/completion") {
        _ = self;
        _ = arena;
        _ = request;
        return .{
            .CompletionList = types.CompletionList{
                .isIncomplete = false,
                .items = &.{},
            },
        };
    }

    pub fn gotoDefinition(
        self: Handler,
        arena: std.mem.Allocator,
        request: types.DefinitionParams,
    ) !ResultType("textDocument/definition") {
        _ = self;
        _ = arena;
        _ = request;
        return null;
    }

    pub fn hover(
        self: Handler,
        arena: std.mem.Allocator,
        request: types.HoverParams,
        offset_encoding: offsets.Encoding,
    ) !?types.Hover {
        _ = self;
        _ = arena; // autofix
        _ = request;
        _ = offset_encoding; // autofix

        return types.Hover{
            .contents = .{
                .MarkupContent = .{
                    .kind = .markdown,
                    .value = "",
                },
            },
        };
    }

    pub fn references(
        _: Handler,
        arena: std.mem.Allocator,
        request: types.ReferenceParams,
    ) !?[]types.Location {
        _ = arena;
        _ = request;
        return null;
    }

    pub fn formatting(
        self: Handler,
        arena: std.mem.Allocator,
        request: types.DocumentFormattingParams,
    ) !?[]const types.TextEdit {
        log.debug("format request!!", .{});

        const doc = self.files.getPtr(request.textDocument.uri) orelse return null;
        if (doc.html.errors.len != 0) {
            return null;
        }

        log.debug("format!!", .{});

        var buf = std.ArrayList(u8).init(arena);
        try doc.html.render(doc.src, buf.writer());

        const edits = try lsp.diff.edits(
            arena,
            doc.src,
            buf.items,
            self.offset_encoding,
        );

        if (builtin.mode == .Debug) {
            if (std.mem.eql(u8, buf.items, doc.src)) {
                std.debug.assert(edits.items.len == 0);
            }
        }

        return edits.items;
    }

    pub fn semanticTokensFull(
        _: Handler,
        arena: std.mem.Allocator,
        request: types.SemanticTokensParams,
    ) !?types.SemanticTokens {
        _ = arena;
        _ = request;
        return null;
    }

    pub fn inlayHint(
        _: Handler,
        arena: std.mem.Allocator,
        request: types.InlayHintParams,
    ) !?[]types.InlayHint {
        _ = arena;
        _ = request;
        return null;
    }

    /// Handle a reponse that we have received from the client.
    /// Doesn't usually happen unless we explicitly send a request to the client.
    pub fn response(self: Handler, _response: Message.Response) !void {
        _ = self;
        const id: []const u8 = switch (_response.id) {
            .string => |id| id,
            .integer => |id| {
                log.warn("received response from client with id '{d}' that has no handler!", .{id});
                return;
            },
        };

        if (_response.data == .@"error") {
            const err = _response.data.@"error";
            log.err("Error response for '{s}': {}, {s}", .{ id, err.code, err.message });
            return;
        }

        log.warn("received response from client with id '{s}' that has no handler!", .{id});
    }
};

pub fn getRange(span: super.Span, src: []const u8) lsp.types.Range {
    const r = span.range(src);
    return .{
        .start = .{ .line = r.start.row, .character = r.start.col },
        .end = .{ .line = r.end.row, .character = r.end.col },
    };
}
