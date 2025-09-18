const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../../root.zig");
const Span = root.Span;
const Tokenizer = @import("../Tokenizer.zig");
const Ast = @import("../Ast.zig");
const Content = Ast.Node.Categories;
const Element = @import("../Element.zig");
const Model = Element.Model;
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;
const log = std.log.scoped(.details);

pub const head: Element = .{
    .tag = .head,
    .model = .{
        .categories = .none,
        .content = .{ .metadata = true },
    },
    .meta = .{ .categories_superset = .none },
    .attributes = .static,
    .content = .{
        .custom = .{
            .validate = validateContent,
            .completions = completionsContent,
        },
    },
    .desc =
    \\The `<head>` HTML element contains machine-readable information
    \\(metadata) about the document, like its title, scripts, and style
    \\sheets. There can be only one `<head>` element in an HTML document.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/head)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-head-element)
    ,
};

pub fn validateContent(
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
    // If the document is an iframe srcdoc document or if title information is
    // available from a higher-level protocol: Zero or more elements of metadata
    // content, of which no more than one is a title element and no more than
    // one is a base element.
    //
    // Otherwise: One or more elements of metadata content, of which exactly one
    // is a title element and no more than one is a base element.

    // We don't validate uniqueness for <base> because it already does it by itself.

    // There must be no more than one title element per document.

    const parent = nodes[parent_idx];
    const parent_span = parent.span(src);

    var has_title: ?Span = null;
    var child_idx = parent.first_child_idx;
    while (child_idx != 0) {
        const child = nodes[child_idx];
        defer child_idx = child.next_idx;
        switch (child.kind) {
            .comment => continue,
            .text => {
                try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = parent_span,
                            .reason = "only metadata children allowed",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                });
                continue;
            },
            else => {},
        }

        if (child.kind == .title) {
            if (has_title) |t| {
                try errors.append(gpa, .{
                    .tag = .{ .duplicate_child = .{ .span = t } },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                });
            } else has_title = child.span(src);
        } else if (!child.model.categories.metadata) {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_nesting = .{
                        .span = parent_span,
                        .reason = "only metadata children allowed",
                    },
                },
                .main_location = child.span(src),
                .node_idx = child_idx,
            });
        }
    }

    if (has_title == null) {
        try errors.append(gpa, .{
            .tag = .{ .missing_child = .title },
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
    _ = src;
    _ = offset;

    const parent = ast.nodes[parent_idx];
    var child_idx = parent.first_child_idx;
    const has_title = while (child_idx != 0) {
        const child = ast.nodes[child_idx];
        defer child_idx = child.next_idx;
        if (child.kind == .title) break true;
    } else false;

    const prefix: []const Ast.Kind = if (has_title) &.{} else &.{.title};
    return Element.simpleCompletions(
        arena,
        prefix,
        head.model.content,
        .none,
        .{
            .forbidden_children = if (has_title) &.{.title} else &.{},
        },
    );
}
