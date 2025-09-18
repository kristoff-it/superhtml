const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Ast = @import("../Ast.zig");
const root = @import("../../root.zig");
const Span = root.Span;
const Language = root.Language;
const Element = @import("../Element.zig");
const Categories = Element.Categories;
const Model = Element.Model;
const CompletionMode = Element.CompletionMode;
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;

pub const optgroup: Element = .{
    .tag = .optgroup,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
        },
        .content = .transparent,
    },

    .meta = .{
        .categories_superset = .{
            .flow = true,
            .phrasing = true,
            .interactive = true,
        },
        .content_reject = .{
            .interactive = true,
        },
    },

    .attributes = .manual, // in validateContent
    .content = .{
        .custom = .{
            .validate = validateContent,
            .completions = completionsContent,
        },
    },
    .desc =
    \\The `<optgroup>` HTML element creates a grouping of options within a
    \\`<select>` element.
    \\
    \\In customizable `<select>` elements, the `<legend>` element is
    \\allowed as a child of `<optgroup>`, to provide a label that is easy
    \\to target and style. This replaces any text set in the `<optgroup>`
    \\element's label attribute, and it has the same semantics.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/optgroup)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-optgroup-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "disabled",
        .model = .{
            .rule = .bool,
            .desc = "If this Boolean attribute is set, none of the items in this option group is selectable. Often browsers grey out such control and it won't receive any browsing events, like mouse clicks or focus-related ones.",
        },
    },
    .{
        .name = "label",
        .model = .{
            .rule = .not_empty,
            .desc = "The name of the group of options, which the browser can use when labeling the options in the user interface. This element is mandatory if no `<legend>` children is present.",
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
    // Zero or one legend element followed by zero or more optgroup element inner
    // content elements.
    const parent = nodes[parent_idx];
    var vait: Attribute.ValidatingIterator = .init(
        errors,
        seen_attrs,
        seen_ids,
        .html,
        parent.open,
        src,
        parent_idx,
    );

    var has_label = false;
    while (try vait.next(gpa, src)) |attr| {
        const name = attr.name.slice(src);
        const model = if (attributes.index(name)) |idx| blk: {
            if (idx == attributes.comptimeIndex("label")) {
                has_label = true;
            }
            break :blk attributes.list[idx].model;
        } else Attribute.global.get(name) orelse {
            if (Attribute.isData(name)) continue;
            try errors.append(gpa, .{
                .tag = .invalid_attr,
                .main_location = attr.name,
                .node_idx = parent_idx,
            });
            continue;
        };

        try model.rule.validate(gpa, errors, src, parent_idx, attr);
    }

    var has_legend = false;
    var state: enum { legend, rest } = .legend;
    var child_idx = parent.first_child_idx;
    while (child_idx != 0) {
        const child = nodes[child_idx];
        defer child_idx = child.next_idx;
        if (child.kind == .comment) continue;

        state: switch (state) {
            .legend => switch (child.kind) {
                .legend => has_legend = true,
                else => {
                    state = .rest;
                    continue :state .rest;
                },
            },
            .rest => switch (child.kind) {
                .option,
                .script,
                .template,
                .noscript,
                .div,
                => {},
                .legend => try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = vait.name,
                            .reason = "<legend> children must go above all others",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
                else => try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = vait.name,
                            .reason = "only <option>, <script>, <template>, <noscript>, and <div> children are allowed",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
            },
        }
    }

    if (!has_legend and !has_label) try errors.append(gpa, .{
        .tag = .{
            .missing_required_attr = "[label] must be defined when no <legend> child is present",
        },
        .main_location = vait.name,
        .node_idx = parent_idx,
    });
}

fn completionsContent(
    arena: Allocator,
    ast: Ast,
    src: []const u8,
    parent_idx: u32,
    offset: u32,
) error{OutOfMemory}![]const Ast.Completion {
    _ = src;
    const parent = ast.nodes[parent_idx];

    var state: enum { legend, rest } = .legend;
    var kind_after_cursor: Ast.Kind = .root;
    var child_idx = parent.first_child_idx;
    while (child_idx != 0) {
        const child = ast.nodes[child_idx];
        defer child_idx = child.next_idx;
        if (child.kind == .comment) continue;

        if (child.open.start > offset) {
            kind_after_cursor = child.kind;
            break;
        }

        switch (state) {
            .legend => if (child.kind != .legend) {
                state = .rest;
                break;
            },
            .rest => unreachable,
        }
    }

    switch (state) {
        .legend => switch (kind_after_cursor) {
            .legend => return &.{
                .{
                    .label = "legend",
                    .desc = comptime Element.all.get(.legend).desc,
                },
            },
            else => return Element.simpleCompletions(
                arena,
                &.{.legend},
                .none,
                .none,
                .{
                    .extra_children = &.{
                        .option,
                        .script,
                        .template,
                        .noscript,
                        .div,
                    },
                },
            ),
        },
        .rest => return Element.simpleCompletions(
            arena,
            &.{},
            .none,
            .none,
            .{
                .extra_children = &.{
                    .option,
                    .script,
                    .template,
                    .noscript,
                    .div,
                },
            },
        ),
    }
}
