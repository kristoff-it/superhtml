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
        .strict = true,
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
strict: bool,

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

        .codeActionProvider = .{ .bool = true },

        .renameProvider = .{
            .RenameOptions = .{
                .prepareProvider = true,
            },
        },

        .referencesProvider = .{ .bool = true },

        .completionProvider = .{
            .triggerCharacters = &.{ "<", "/" },
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

pub fn @"textDocument/codeAction"(
    self: *Handler,
    arena: std.mem.Allocator,
    request: types.CodeActionParams,
) error{OutOfMemory}!lsp.ResultType("textDocument/codeAction") {
    const doc = self.files.getPtr(request.textDocument.uri) orelse return null;
    const offset = lsp.offsets.positionToIndex(
        doc.src,
        request.range.start,
        self.offset_encoding,
    );

    if (!self.strict) return null;

    for (doc.html.errors) |err| {
        if (err.tag != .ast or err.tag.ast != .invalid_html_tag_name) continue;

        const span = err.main_location;
        if (span.start <= offset and span.end > offset) {
            const edits = try arena.alloc(lsp.types.TextEdit, 2);
            edits[0] = .{
                .range = getRange(span, doc.src),
                .newText = "div",
            };

            const edits_len: usize = if (err.node_idx != 0) blk: {
                const node = doc.html.nodes[err.node_idx];
                if (node.kind != .element) break :blk 1;

                const close = node.close;
                if (close.end < 2 or close.start > close.end - 2) break :blk 1;

                edits[1] = .{
                    .range = getRange(.{
                        .start = close.start + 1,
                        .end = close.end - 1,
                    }, doc.src),
                    .newText = "/div",
                };

                break :blk 2;
            } else 1;

            const result: lsp.ResultType("textDocument/codeAction") = &.{
                .{
                    .CodeAction = .{
                        .title = "Replace with 'div'",
                        .kind = .quickfix,
                        .isPreferred = true,
                        .edit = .{
                            .changes = .{
                                .map = try .init(
                                    arena,
                                    &.{request.textDocument.uri},
                                    &.{edits[0..edits_len]},
                                ),
                            },
                        },
                    },
                },
            };

            return try arena.dupe(@typeInfo(@TypeOf(result.?)).pointer.child, result.?);
        }
    }

    return null;
}

pub fn @"textDocument/prepareRename"(
    self: *Handler,
    arena: std.mem.Allocator,
    request: types.PrepareRenameParams,
) error{OutOfMemory}!lsp.ResultType("textDocument/prepareRename") {
    _ = arena;

    const doc = self.files.getPtr(request.textDocument.uri) orelse return null;
    const offset = lsp.offsets.positionToIndex(
        doc.src,
        request.position,
        self.offset_encoding,
    );

    const node_idx = findNode(doc, @intCast(offset));
    if (node_idx == 0) return null;

    const node = doc.html.nodes[node_idx];
    const it = node.startTagIterator(doc.src, doc.language);

    const range = lsp.offsets.locToRange(doc.src, .{
        .start = it.name_span.start,
        .end = it.name_span.end,
    }, self.offset_encoding);

    return .{
        .Range = range,
    };
}
pub fn @"textDocument/rename"(
    self: *Handler,
    arena: std.mem.Allocator,
    request: types.RenameParams,
) error{OutOfMemory}!lsp.ResultType("textDocument/rename") {
    const doc = self.files.getPtr(request.textDocument.uri) orelse return null;
    const offset = lsp.offsets.positionToIndex(
        doc.src,
        request.position,
        self.offset_encoding,
    );

    const node_idx: u32 = for (doc.html.errors) |err| {
        // Find erroneous end tags in the error list but also any other error that
        // has a node associated that happens to match our offset.
        const span = err.main_location;
        if (span.start <= offset and span.end > offset) {
            if (err.tag == .ast and err.tag.ast == .erroneous_end_tag) {
                const edits = try arena.alloc(lsp.types.TextEdit, 1);
                edits[0] = .{
                    .range = getRange(span, doc.src),
                    .newText = request.newName,
                };
                return .{
                    .changes = .{
                        .map = try .init(
                            arena,
                            &.{request.textDocument.uri},
                            &.{edits},
                        ),
                    },
                };
            }
            if (err.node_idx != 0) break err.node_idx;
        }
    } else findNode(doc, @intCast(offset));

    const node = doc.html.nodes[node_idx];
    var edits: []lsp.types.TextEdit = undefined;
    blk: switch (node.kind) {
        else => return null,
        .element => {
            edits = try arena.alloc(lsp.types.TextEdit, 2);

            const it = node.startTagIterator(doc.src, doc.language);
            edits[0] = .{
                .range = getRange(it.name_span, doc.src),
                .newText = request.newName,
            };

            const close = node.close;
            if (close.end < 2 or close.start > close.end - 2) {
                edits = edits[0..1];
                break :blk;
            }

            edits[1] = .{
                .range = getRange(.{
                    .start = close.start + 1,
                    .end = close.end - 1,
                }, doc.src),
                .newText = try std.fmt.allocPrint(arena, "/{s}", .{request.newName}),
            };
        },
        .element_void, .element_self_closing => {
            edits = try arena.alloc(lsp.types.TextEdit, 1);

            const it = node.startTagIterator(doc.src, doc.language);
            edits[0] = .{
                .range = getRange(it.name_span, doc.src),
                .newText = request.newName,
            };
        },
    }

    return .{
        .changes = .{
            .map = try .init(
                arena,
                &.{request.textDocument.uri},
                &.{edits},
            ),
        },
    };
}

pub fn @"textDocument/references"(
    self: *Handler,
    arena: std.mem.Allocator,
    request: types.ReferenceParams,
) error{OutOfMemory}!lsp.ResultType("textDocument/references") {
    const doc = self.files.getPtr(request.textDocument.uri) orelse return null;
    const offset = lsp.offsets.positionToIndex(
        doc.src,
        request.position,
        self.offset_encoding,
    );

    const node_idx = findNode(doc, @intCast(offset));
    log.debug("------ References request! (node: {}) ------", .{node_idx});
    if (node_idx == 0) return null;

    const class = blk: {
        const node = doc.html.nodes[node_idx];
        var it = node.startTagIterator(doc.src, doc.language);
        while (it.next(doc.src)) |attr| {
            if (std.ascii.eqlIgnoreCase(attr.name.slice(doc.src), "class")) {
                const value = attr.value orelse return null;
                const slice = value.span.slice(doc.src);
                if (slice.len == 0 or slice[0] == '$') return null;
                if (offset < value.span.start or offset >= value.span.end) return null;

                const rel_offset = offset - value.span.start;

                var vit = std.mem.tokenizeScalar(u8, slice, ' ');

                while (vit.next()) |cls| {
                    if (rel_offset < vit.index - cls.len) return null;
                    if (vit.index > rel_offset) {
                        break :blk cls;
                    }
                } else return null;
            }
        } else return null;
    };

    log.debug("------ CLASS: '{s}' ------", .{class});

    var locations: std.ArrayListUnmanaged(lsp.types.Location) = .empty;
    for (doc.html.nodes) |n| {
        switch (n.kind) {
            .element, .element_void, .element_self_closing => {},
            else => continue,
        }

        var it = n.startTagIterator(doc.src, doc.language);
        outer: while (it.next(doc.src)) |attr| {
            if (std.ascii.eqlIgnoreCase(attr.name.slice(doc.src), "class")) {
                const value = attr.value orelse break :outer;
                const slice = value.span.slice(doc.src);
                if (slice.len == 0 or slice[0] == '$') break :outer;
                var vit = std.mem.tokenizeScalar(u8, slice, ' ');
                while (vit.next()) |cls| {
                    if (std.mem.eql(u8, class, cls)) {
                        const range = lsp.offsets.locToRange(doc.src, .{
                            .start = value.span.start + vit.index - cls.len,
                            .end = value.span.start + vit.index,
                        }, self.offset_encoding);

                        try locations.append(arena, .{
                            .uri = request.textDocument.uri,
                            .range = range,
                        });
                        break :outer;
                    }
                }
            }
        }
    }

    return locations.items;
}

pub fn @"textDocument/completion"(
    self: *Handler,
    arena: std.mem.Allocator,
    request: types.CompletionParams,
) error{OutOfMemory}!lsp.ResultType("textDocument/completion") {
    const doc = self.files.getPtr(request.textDocument.uri) orelse return null;
    const offset = lsp.offsets.positionToIndex(
        doc.src,
        request.position,
        self.offset_encoding,
    );

    _ = offset;
    _ = arena;
    return null;
    // const completions = doc.html.completions(arena, @intCast(offset));

    // _ = completions;
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

// Returns a node index, 0 == not found
pub fn findNode(doc: *const Document, offset: u32) u32 {
    if (doc.html.nodes.len < 2) return 0;
    var cur_idx: u32 = 1;
    while (cur_idx != 0) {
        const n = doc.html.nodes[cur_idx];
        if (n.open.start <= offset and n.open.end > offset) {
            break;
        }
        if (n.close.end != 0 and n.close.start <= offset and n.close.end > offset) {
            break;
        }

        if (n.open.end <= offset and n.close.start > offset) {
            cur_idx = n.first_child_idx;
        } else {
            cur_idx = n.next_idx;
        }
    }

    return cur_idx;
}
