const Document = @This();

const std = @import("std");
const assert = std.debug.assert;
const super = @import("superhtml");

const log = std.log.scoped(.lsp_document);

language: super.Language,
src: []const u8,
html: super.html.Ast,
super_ast: ?super.Ast = null,

pub fn deinit(doc: *Document, gpa: std.mem.Allocator) void {
    doc.html.deinit(gpa);
    if (doc.super_ast) |s| s.deinit(gpa);
}

pub fn init(
    gpa: std.mem.Allocator,
    src: []const u8,
    language: super.Language,
    options: super.html.Ast.ParseOptions,
) error{OutOfMemory}!Document {
    var doc: Document = .{
        .src = src,
        .language = language,
        .html = try super.html.Ast.init(gpa, src, language, options),
    };
    errdefer doc.html.deinit(gpa);

    if (language == .superhtml and doc.html.errors.len == 0) {
        const super_ast = try super.Ast.init(gpa, doc.html, src);
        errdefer super_ast.deinit(gpa);
        doc.super_ast = super_ast;
    }

    return doc;
}

pub fn reparse(
    doc: *Document,
    gpa: std.mem.Allocator,
    options: super.html.Ast.ParseOptions,
) !void {
    doc.deinit(gpa);
    doc.html = try super.html.Ast.init(gpa, doc.src, doc.language, options);
    errdefer doc.html.deinit(gpa);

    if (doc.language == .superhtml and doc.html.errors.len == 0) {
        doc.super_ast = try super.Ast.init(gpa, doc.html, doc.src);
    } else {
        doc.super_ast = null;
    }

    return;
}
