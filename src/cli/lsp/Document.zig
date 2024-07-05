const Document = @This();

const std = @import("std");
const assert = std.debug.assert;
const super = @import("super");

const log = std.log.scoped(.lsp_document);

pub const Language = enum { super, html };

language: Language,
arena: std.heap.ArenaAllocator,
bytes: []const u8,
ast: super.html.Ast,

pub fn deinit(doc: *Document) void {
    doc.arena.deinit();
}

pub fn init(
    gpa: std.mem.Allocator,
    bytes: []const u8,
    language: Language,
) error{OutOfMemory}!Document {
    var doc: Document = .{
        .arena = std.heap.ArenaAllocator.init(gpa),
        .language = language,
        .bytes = bytes,
        .ast = undefined,
    };
    const ast = try super.html.Ast.init(doc.arena.allocator(), bytes);
    doc.ast = ast;

    return doc;
}
