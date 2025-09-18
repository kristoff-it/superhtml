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

pub const details: Element = .{
    .tag = .details,
    .model = .{
        .categories = .{
            .flow = true,
            .interactive = true,
        },
        .content = .{ .flow = true },
    },
    .meta = .{
        .categories_superset = .{
            .flow = true,
            .interactive = true,
        },
    },
    .attributes = .static,
    .content = .{
        .custom = .{
            .validate = validateContent,
            .completions = completionsContent,
        },
    },
    .desc =
    \\The `<details>` HTML element creates a disclosure widget in which
    \\information is visible only when the widget is toggled into an open
    \\state. A summary or label must be provided using the `<summary>`
    \\element.
    \\
    \\A disclosure widget is typically presented onscreen using a small
    \\triangle that rotates (or twists) to indicate open/closed state,
    \\with a label next to the triangle. The contents of the `<summary>`
    \\element are used as the label for the disclosure widget. The
    \\contents of the `<details>` provide the accessible description for
    \\the `<summary>`.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/details)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-details-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "open",
        .model = .{
            .rule = .bool,
            .desc = "This Boolean attribute indicates whether the details — that is, the contents of the `<details>` element — are currently visible. The details are shown when this attribute exists, or hidden when this attribute is absent. By default this attribute is absent which means the details are not visible.",
        },
    },
    .{
        .name = "name",
        .model = .{
            .rule = .not_empty,
            .desc =
            \\This attribute enables multiple `<details>` elements to
            \\be connected, with only one open at a time. This allows
            \\developers to easily create UI features such as accordions
            \\without scripting.
            \\
            \\The name attribute specifies a group name — give multiple
            \\`<details>` elements the same name value to group them. Only
            \\one of the grouped `<details>` elements can be open at a
            \\time — opening one will cause another to close. If multiple
            \\grouped `<details>` elements are given the open attribute,
            \\only the first one in the source order will be rendered
            \\open.
            \\
            \\Note: `<details>` elements don't have to be adjacent to one
            \\another in the source to be part of the same group.
            ,
        },
    },
});

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
    // One summary element followed by flow content.
    const parent = nodes[parent_idx];
    const parent_span = parent.span(src);

    var summary_span: ?Span = null;

    var child_idx = parent.first_child_idx;
    while (child_idx != 0) {
        const child = nodes[child_idx];
        defer child_idx = child.next_idx;
        switch (child.kind) {
            .text, .comment => continue,
            else => {},
        }

        if (child.kind == .summary) {
            if (summary_span) |ss| {
                try errors.append(gpa, .{
                    .tag = .{ .duplicate_child = .{ .span = ss } },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                });
            } else {
                summary_span = child.span(src);
                if (child_idx != parent.first_child_idx) {
                    try errors.append(gpa, .{
                        .tag = .{ .wrong_position = .first },
                        .main_location = summary_span.?,
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

    log.debug("summary = {any}", .{summary_span});
    if (summary_span == null) {
        try errors.append(gpa, .{
            .tag = .{ .missing_child = .summary },
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
    const has_summary = while (child_idx != 0) {
        const child = ast.nodes[child_idx];
        defer child_idx = child.next_idx;
        if (child.kind == .summary) break true;
    } else false;

    const prefix: []const Ast.Kind = if (has_summary) &.{} else &.{.summary};
    return Element.simpleCompletions(
        arena,
        prefix,
        details.model.content,
        .none,
        .{},
    );
}
