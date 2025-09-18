const std = @import("std");
const Allocator = std.mem.Allocator;
const Element = @import("../Element.zig");
const Tokenizer = @import("../Tokenizer.zig");
const Ast = @import("../Ast.zig");
const root = @import("../../root.zig");
const Language = root.Language;
const Span = root.Span;

pub const legend: Element = .{
    .tag = .legend,
    .model = .{
        .categories = .none,
        .content = .{ .phrasing = true },
    },
    .meta = .{ .categories_superset = .{ .phrasing = true } },
    .attributes = .static,
    .content = .{
        .custom = .{
            .validate = validateContent,
            .completions = completionsContent,
        },
    },

    .desc =
    \\The `<legend>` HTML element represents a caption for the content of
    \\its parent `<fieldset>`.
    \\
    \\In customizable <select> elements, the `<legend>` element is allowed
    \\as a child of `<optgroup>`, to provide a label that is easy to
    \\target and style. This replaces any text set in the `<optgroup>`
    \\element's `label` attribute, and it has the same semantics.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/legend)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/semantics.html#the-legend-element)
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
    const parent = nodes[parent_idx];
    const parent_span = parent.span(src);

    const mode: enum { optgroup, fieldset } = switch (nodes[parent.parent_idx].kind) {
        .optgroup => .optgroup,
        .fieldset => .fieldset,
        else => return errors.append(gpa, .{
            .tag = .{
                .invalid_nesting = .{
                    .span = nodes[parent.parent_idx].span(src),
                    .reason = "must be a child of <optgroup> or <fieldset>",
                },
            },
            .main_location = parent_span,
            .node_idx = parent_idx,
        }),
    };

    switch (mode) {
        // If the element is a child of an optgroup element: Phrasing content, but there must be no interactive content and no descendant with the tabindex attribute.
        .optgroup => {
            if (parent.first_child_idx == 0) return;
            const stop_idx = parent.stop(nodes);

            var next_idx = parent.first_child_idx;
            while (next_idx < stop_idx) {
                const node_idx = next_idx;
                const node = nodes[next_idx];

                if (node.kind == .___) {
                    next_idx = node.stop(nodes);
                    continue;
                } else if (node.kind == .svg or node.kind == .math) {
                    next_idx = node.stop(nodes);
                } else {
                    next_idx += 1;
                    if (!node.kind.isElement()) continue;
                }

                var l = legend;
                l.meta.content_reject.interactive = true;
                l.meta.extra_reject.tabindex = true;
                if (l.modelRejects(
                    nodes,
                    src,
                    parent,
                    parent_span,
                    &Element.all.get(node.kind),
                    node.model,
                )) |rejection| try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = rejection.span,
                            .reason = rejection.reason,
                        },
                    },
                    .main_location = node.span(src),
                    .node_idx = node_idx,
                });
            }
        },
        // Otherwise: Phrasing content, optionally intermixed with heading content.
        .fieldset => {
            var child_idx = parent.first_child_idx;
            while (child_idx != 0) {
                const child = nodes[child_idx];
                defer child_idx = child.next_idx;

                const child_span = child.span(src);

                switch (child.kind) {
                    .text,
                    .comment,
                    .h1,
                    .h2,
                    .h3,
                    .h4,
                    .h5,
                    .h6,
                    .hgroup,
                    => continue,
                    else => {},
                }

                if (!child.model.categories.phrasing) try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{ .span = parent_span },
                    },
                    .main_location = child_span,
                    .node_idx = child_idx,
                });
            }
        },
    }
}
fn completionsContent(
    arena: Allocator,
    ast: Ast,
    src: []const u8,
    node_idx: u32,
    offset: u32,
) error{OutOfMemory}![]const Ast.Completion {
    _ = src;
    _ = offset;

    const parent = ast.nodes[node_idx];
    const mode: enum { optgroup, fieldset } = switch (ast.nodes[parent.parent_idx].kind) {
        .optgroup => .optgroup,
        .fieldset => .fieldset,
        else => return &.{},
    };

    return switch (mode) {
        .optgroup => Element.simpleCompletions(
            arena,
            &.{},
            .{ .phrasing = true },
            .{ .interactive = true },
            .{ .forbidden_descendants_extra = .{ .tabindex = true } },
        ),
        .fieldset => Element.simpleCompletions(
            arena,
            &.{},
            .{ .phrasing = true },
            .none,
            .{
                .extra_children = &.{
                    .h1,
                    .h2,
                    .h3,
                    .h4,
                    .h5,
                    .h6,
                    .hgroup,
                },
            },
        ),
    };
}
