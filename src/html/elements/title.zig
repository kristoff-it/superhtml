const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../../root.zig");
const Span = root.Span;
const Ast = @import("../Ast.zig");
const Element = @import("../Element.zig");

pub const title: Element = .{
    .tag = .title,
    .model = .{
        .categories = .{ .metadata = true },
        .content = .{ .text = true },
    },
    .meta = .{ .categories_superset = .{ .metadata = true } },
    .attributes = .static,
    .content = .{
        .custom = .{
            .validate = validateContent,
            .completions = completionsContent,
        },
    },
    .desc =
    \\The `<title>` HTML element defines the document's title that is
    \\shown in a browser's title bar or a page's tab. It only contains
    \\text; HTML tags within the element, if any, are also treated as
    \\plain text.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/title)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/semantics.html#the-title-element)
    ,
};

/// Validates the content model for `<title>`.
/// Per WHATWG spec § 4.2.2: Content model is "Text that is not inter-element whitespace."
/// This means:
/// - No element children allowed (already handled by `.content = .{ .text = true }`)
/// - No comments allowed
/// - Text content must not be only whitespace
fn validateContent(
    gpa: Allocator,
    nodes: []const Ast.Node,
    seen_attrs: *std.StringHashMapUnmanaged(Span),
    seen_ids: *std.StringHashMapUnmanaged(Span),
    errors: *std.ArrayListUnmanaged(Ast.Error),
    src: []const u8,
    parent_idx: u32,
) error{OutOfMemory}!void {
    _ = seen_attrs;
    _ = seen_ids;

    const parent = nodes[parent_idx];
    const parent_span = parent.span(src);

    var has_non_whitespace_text = false;
    var child_idx = parent.first_child_idx;
    while (child_idx != 0) {
        const child = nodes[child_idx];
        defer child_idx = child.next_idx;

        switch (child.kind) {
            .comment => {
                // Comments are not allowed inside <title>
                try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = parent_span,
                            .reason = "comments are not allowed inside <title>",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                });
            },
            .text => {
                // Check if text contains non-whitespace characters
                const text = child.span(src).slice(src);
                for (text) |c| {
                    if (c != ' ' and c != '\t' and c != '\n' and c != '\r') {
                        has_non_whitespace_text = true;
                        break;
                    }
                }
            },
            else => {
                // Element children are rejected by the content model (.text = true)
                // but we still need to validate them through modelRejects
                if (!title.model.content.overlaps(child.model.categories)) {
                    try errors.append(gpa, .{
                        .tag = .{
                            .invalid_nesting = .{
                                .span = parent_span,
                            },
                        },
                        .main_location = child.span(src),
                        .node_idx = child_idx,
                    });
                }
            },
        }
    }

    // <title> must contain text that is not inter-element whitespace
    if (!has_non_whitespace_text) {
        try errors.append(gpa, .{
            .tag = .{
                .invalid_nesting = .{
                    .span = parent_span,
                    .reason = "<title> must contain non-whitespace text",
                },
            },
            .main_location = parent_span,
            .node_idx = parent_idx,
        });
    }
}

fn completionsContent(
    arena: Allocator,
    ast: Ast,
    src: []const u8,
    parent_idx: u32,
    offset: u32,
) error{OutOfMemory}![]const Ast.Completion {
    // <title> only accepts text content, no element completions
    _ = arena;
    _ = ast;
    _ = src;
    _ = parent_idx;
    _ = offset;
    return &.{};
}

test "title element rejects comments" {
    const case =
        \\<!DOCTYPE html><html><head><title><!-- comment --></title></head><body></body></html>
    ;

    const ast = try Ast.init(std.testing.allocator, case, .html, false);
    defer ast.deinit(std.testing.allocator);

    // Should have an error for the comment inside <title>
    try std.testing.expect(ast.errors.len > 0);

    // Check that one of the errors is about invalid nesting in <title>
    var found_title_error = false;
    for (ast.errors) |err| {
        switch (err.tag) {
            .invalid_nesting => |nesting| {
                if (std.mem.indexOf(u8, nesting.reason, "comment") != null) {
                    found_title_error = true;
                    break;
                }
            },
            else => {},
        }
    }
    try std.testing.expect(found_title_error);
}

test "title element rejects whitespace-only content" {
    const case =
        \\<!DOCTYPE html><html><head><title>   </title></head><body></body></html>
    ;

    const ast = try Ast.init(std.testing.allocator, case, .html, false);
    defer ast.deinit(std.testing.allocator);

    // Should have an error for whitespace-only content
    try std.testing.expect(ast.errors.len > 0);

    // Check that one of the errors is about non-whitespace text requirement
    var found_whitespace_error = false;
    for (ast.errors) |err| {
        switch (err.tag) {
            .invalid_nesting => |nesting| {
                if (std.mem.indexOf(u8, nesting.reason, "whitespace") != null) {
                    found_whitespace_error = true;
                    break;
                }
            },
            else => {},
        }
    }
    try std.testing.expect(found_whitespace_error);
}

test "title element accepts valid text content" {
    const case =
        \\<!DOCTYPE html><html><head><title>My Page Title</title></head><body></body></html>
    ;

    const ast = try Ast.init(std.testing.allocator, case, .html, false);
    defer ast.deinit(std.testing.allocator);

    // Should have no errors
    try std.testing.expectEqual(@as(usize, 0), ast.errors.len);
}
