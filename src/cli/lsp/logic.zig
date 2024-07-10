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
    language: super.Language,
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
    errdefer doc.deinit(self.gpa);

    log.debug("document init", .{});

    const gop = try self.files.getOrPut(self.gpa, uri);
    errdefer _ = self.files.remove(uri);

    if (gop.found_existing) {
        gop.value_ptr.deinit(self.gpa);
    } else {
        gop.key_ptr.* = try self.gpa.dupe(u8, uri);
    }

    gop.value_ptr.* = doc;

    if (doc.html.errors.len != 0) {
        const diags = try arena.alloc(lsp.types.Diagnostic, doc.html.errors.len);
        for (doc.html.errors, diags) |err, *d| {
            const range = getRange(err.main_location, doc.src);
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
    } else {
        if (doc.super) |super_ast| {
            const diags = try arena.alloc(
                lsp.types.Diagnostic,
                super_ast.errors.len,
            );
            for (super_ast.errors, diags) |err, *d| {
                const range = getRange(err.main_location, doc.src);
                d.* = .{
                    .range = range,
                    .severity = .Error,
                    .message = @tagName(err.kind),
                };
            }
            res.diagnostics = diags;
        }
    }

    const msg = try self.server.sendToClientNotification(
        "textDocument/publishDiagnostics",
        res,
    );

    defer self.gpa.free(msg);
}

pub fn getRange(span: super.Span, src: []const u8) lsp.types.Range {
    const r = span.range(src);
    return .{
        .start = .{ .line = r.start.row, .character = r.start.col },
        .end = .{ .line = r.end.row, .character = r.end.col },
    };
}
