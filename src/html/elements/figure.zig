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

pub const figure: Element = .{
    .tag = .figure,
    .model = .{
        .categories = .{ .flow = true },
        .content = .{ .flow = true },
    },
    .meta = .{
        .categories_superset = .{ .flow = true },
    },
    .attributes = .static,
    .content = .{
        .custom = .{
            .validate = validateContent,
            .completions = completionsContent,
        },
    },
    .desc =
    \\The `<figure>` HTML element represents self-contained content,
    \\potentially with an optional caption, which is specified using the
    \\`<figcaption>` element. The figure, its caption, and its contents
    \\are referenced as a single unit.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/figure)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-figure-element)
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
    // Either: one figcaption element followed by flow content.
    // Or: flow content followed by one figcaption element.
    // Or: flow content.

    const parent = nodes[parent_idx];
    const parent_span = parent.span(src);

    var has_fc: ?Span = null;

    var child_idx = parent.first_child_idx;
    while (child_idx != 0) {
        const child = nodes[child_idx];
        defer child_idx = child.next_idx;
        switch (child.kind) {
            .text, .comment => continue,
            else => {},
        }

        if (child.kind == .figcaption) {
            if (has_fc) |lg| {
                try errors.append(gpa, .{
                    .tag = .{ .duplicate_child = .{ .span = lg } },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                });
            } else {
                has_fc = child.span(src);
                if (child_idx != parent.first_child_idx and child.next_idx != 0) {
                    try errors.append(gpa, .{
                        .tag = .{ .wrong_position = .first_or_last },
                        .main_location = has_fc.?,
                        .node_idx = child_idx,
                    });
                }
            }
        } else if (!child.model.categories.flow) {
            try errors.append(gpa, .{
                .tag = .{ .invalid_nesting = .{ .span = parent_span } },
                .main_location = child.span(src),
                .node_idx = child_idx,
            });
        }
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
    const has_fc = while (child_idx != 0) {
        const child = ast.nodes[child_idx];
        defer child_idx = child.next_idx;
        if (child.kind == .figcaption) break true;
    } else false;

    const prefix: []const Ast.Kind = if (has_fc) &.{} else &.{.figcaption};
    return Element.simpleCompletions(
        arena,
        prefix,
        figure.model.content,
        .none,
        .{},
    );
}
