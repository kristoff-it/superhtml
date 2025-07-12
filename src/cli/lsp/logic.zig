const std = @import("std");
const lsp = @import("lsp");
const super = @import("superhtml");
const lsp_namespace = @import("../lsp.zig");
const Handler = lsp_namespace.Handler;
const getRange = Handler.getRange;
const Document = @import("Document.zig");

const log = std.log.scoped(.ziggy_lsp);

pub fn loadFile(
    self: *Handler,
    arena: std.mem.Allocator,
    new_text: []const u8,
    uri: []const u8,
    language: super.Language,
) !void {
    errdefer @panic("error while loading document!");

    var res: lsp.types.PublishDiagnosticsParams = .{
        .uri = uri,
        .diagnostics = &.{},
    };

    const doc = try Document.init(
        self.gpa,
        new_text,
        language,
    );

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
        if (doc.super_ast) |super_ast| {
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

    try self.transport.writeNotification(
        self.gpa,
        "textDocument/publishDiagnostics",
        lsp.types.PublishDiagnosticsParams,
        res,
        .{ .emit_null_optional_fields = false },
    );
}
