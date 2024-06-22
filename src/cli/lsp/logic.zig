const std = @import("std");
const lsp = @import("lsp");
const super = @import("super");
const Handler = @import("../lsp.zig").Handler;
const Document = @import("Document.zig");

const log = std.log.scoped(.ziggy_lsp);

pub fn loadFile(
    self: *Handler,
    arena: std.mem.Allocator,
    new_text: [:0]const u8,
    uri: []const u8,
    language: Document.Language,
) !void {
    var res: lsp.types.PublishDiagnosticsParams = .{
        .uri = uri,
        .diagnostics = &.{},
    };

    var doc = try Document.init(
        self.gpa,
        new_text,
        language,
    );
    errdefer doc.deinit();

    log.debug("document init", .{});

    const gop = try self.files.getOrPut(self.gpa, uri);
    errdefer _ = self.files.remove(uri);

    if (gop.found_existing) {
        gop.value_ptr.deinit();
    } else {
        gop.key_ptr.* = try self.gpa.dupe(u8, uri);
    }

    gop.value_ptr.* = doc;

    if (doc.ast.errors.len != 0) {
        const diags = try arena.alloc(lsp.types.Diagnostic, doc.ast.errors.len);
        for (doc.ast.errors, diags) |err, *d| {
            const range = getRange(err.span, doc.bytes);
            d.* = .{
                .range = range,
                .severity = .Error,
                .message = switch (err.tag) {
                    .token => |t| @tagName(t),
                    .ast => |t| @tagName(t),
                },
            };
        }

        res.diagnostics = diags;
    }

    log.debug("sending diags!", .{});
    const msg = try self.server.sendToClientNotification(
        "textDocument/publishDiagnostics",
        res,
    );

    defer self.gpa.free(msg);
}

pub fn getRange(
    self: super.html.Tokenizer.Span,
    code: []const u8,
) lsp.types.Range {
    var selection: lsp.types.Range = .{
        .start = .{ .line = 0, .character = 0 },
        .end = undefined,
    };

    for (code[0..self.start]) |c| {
        if (c == '\n') {
            selection.start.line += 1;
            selection.start.character = 1;
        } else selection.start.character += 1;
    }

    selection.end = selection.start;
    for (code[self.start..self.end]) |c| {
        if (c == '\n') {
            selection.end.line += 1;
            selection.end.character = 1;
        } else selection.end.character += 1;
    }
    return selection;
}
