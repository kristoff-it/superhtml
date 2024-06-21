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
    _ = arena;

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

    res.diagnostics = &.{};

    log.debug("sending diags!", .{});
    const msg = try self.server.sendToClientNotification(
        "textDocument/publishDiagnostics",
        res,
    );

    defer self.gpa.free(msg);
}
