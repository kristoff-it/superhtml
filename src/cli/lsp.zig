const std = @import("std");
const assert = std.debug.assert;
const lsp = @import("lsp");
const types = lsp.types;
const offsets = lsp.offsets;
const ResultType = lsp.server.ResultType;
const Message = lsp.server.Message;
const super = @import("super");
const Document = @import("lsp/Document.zig");

const log = std.log.scoped(.super_lsp);

const SuperLsp = lsp.server.Server(Handler);

pub fn run(gpa: std.mem.Allocator, args: []const []const u8) !void {
    _ = args;

    log.debug("Super LSP started!", .{});

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

    usingnamespace @import("lsp/logic.zig");

    pub fn initialize(
        self: Handler,
        _: std.mem.Allocator,
        request: types.InitializeParams,
        offset_encoding: offsets.Encoding,
    ) !lsp.types.InitializeResult {
        _ = self;

        if (request.clientInfo) |clientInfo| {
            log.info("client is '{s}-{s}'", .{ clientInfo.name, clientInfo.version orelse "<no version>" });
        }

        return .{
            .serverInfo = .{
                .name = "Super LSP",
                .version = "0.0.1",
            },
            .capabilities = .{
                .positionEncoding = switch (offset_encoding) {
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
                    .triggerCharacters = &[_][]const u8{ ".", ":", "@", "\"" },
                },
                .hoverProvider = .{ .bool = true },
                .definitionProvider = .{ .bool = true },
                .referencesProvider = .{ .bool = true },
                .documentFormattingProvider = .{ .bool = true },
                .semanticTokensProvider = .{
                    .SemanticTokensOptions = .{
                        .full = .{ .bool = true },
                        .legend = .{
                            .tokenTypes = std.meta.fieldNames(types.SemanticTokenTypes),
                            .tokenModifiers = std.meta.fieldNames(types.SemanticTokenModifiers),
                        },
                    },
                },
                .inlayHintProvider = .{ .bool = true },
            },
        };
    }

    pub fn initialized(
        self: Handler,
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
        const language = std.meta.stringToEnum(Document.Language, language_id) orelse {
            log.debug("unrecognized language id: '{s}'", .{language_id});
            return;
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
        if (notification.contentChanges.len == 0) return;

        const new_text = try self.gpa.dupeZ(u8, notification.contentChanges[notification.contentChanges.len - 1].literal_1.text); // We informed the client that we only do full document syncs
        errdefer self.gpa.free(new_text);

        // TODO: this is a hack while we wait for actual incremental reloads
        const file = self.files.get(notification.textDocument.uri) orelse return;
        try self.loadFile(
            arena,
            new_text,
            notification.textDocument.uri,
            file.language,
        );
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
        kv.value.deinit();
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
    ) !?[]types.TextEdit {
        log.debug("format request!!", .{});

        const file = self.files.getPtr(request.textDocument.uri) orelse return null;
        log.debug("file found", .{});
        if (file.ast.errors.len != 0) {
            log.debug("ast has errors - no autoformatting", .{});
            return null;
        }

        log.debug("format!!", .{});

        var buf = std.ArrayList(u8).init(self.gpa);
        errdefer buf.deinit();

        try file.ast.render(file.bytes, buf.writer());

        const edits = try lsp.diff.edits(
            arena,
            file.bytes,
            buf.items,
            .@"utf-8",
        );

        self.gpa.free(file.bytes);
        file.bytes = try buf.toOwnedSlice();

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
