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

pub const option: Element = .{
    .tag = .option,
    .model = .{
        .categories = .none,
        .content = .none,
    },
    .meta = .{ .categories_superset = .none },
    .attributes = .manual, // in validateContent
    .content = .{
        .custom = .{
            .validate = validateContent,
            .completions = completionsContent,
        },
    },
    .desc =
    \\The `<option>` HTML element is used to define an item contained
    \\in a `<select>`, an `<optgroup>`, or a `<datalist>` element.
    \\As such, <option> can represent menu items in popups and other
    \\lists of items in an HTML document.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/option)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-option-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "label",
        .model = .{
            .rule = .not_empty,
            .desc = "This attribute is text for the label indicating the meaning of the option. If the `label` attribute isn't defined, its value is that of the element text content.",
        },
    },
    .{
        .name = "value",
        .model = .{
            .rule = .any,
            .desc = "The content of this attribute represents the value to be submitted with the form, should this option be selected. If this attribute is omitted, the value is taken from the text content of the option element.",
        },
    },
    .{
        .name = "disabled",
        .model = .{
            .rule = .bool,
            .desc = "If this Boolean attribute is set, this option is not checkable. Often browsers grey out such control and it won't receive any browsing event, like mouse clicks or focus-related ones. If this attribute is not set, the element can still be disabled if one of its ancestors is a disabled `<optgroup>` element.",
        },
    },
    .{
        .name = "selected",
        .model = .{
            .rule = .bool,
            .desc = "If present, this Boolean attribute indicates that the option is initially selected. If the `<option>` element is the descendant of a `<select>` element whose `multiple` attribute is not set, only one single `<option>` of this `<select>` element may have the selected attribute.",
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
    var has_value = false;
    while (try vait.next(gpa, src)) |attr| {
        const name = attr.name.slice(src);
        const model = if (attributes.index(name)) |idx| blk: {
            switch (idx) {
                attributes.comptimeIndex("label") => has_label = true,
                attributes.comptimeIndex("value") => has_value = true,
                else => {},
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

    // If the element has a label attribute and a value attribute: Nothing.
    // If the element has a label attribute but no value attribute: Text.
    // If the element has no label attribute and is not a descendant of a datalist element: Zero or more option element inner content elements.
    // If the element has no label attribute and is a descendant of a datalist element: Text.

    var opt = option;
    if (has_label) {
        opt.model.content = .{ .text = !has_value };
        opt.content = .{ .simple = .{} };
    } else {
        var ancestor_idx = parent.parent_idx;
        const datalist_descendant = while (ancestor_idx != 0) {
            const ancestor = nodes[ancestor_idx];
            if (ancestor.kind == .datalist) break true;
            ancestor_idx = ancestor.parent_idx;
        } else false;

        if (datalist_descendant) {
            opt.model.content = .{ .text = true };
            opt.content = .{ .simple = .{} };
        } else {
            opt.model.content = .{ .phrasing = true };
            opt.meta.content_reject = .{ .interactive = true };
            opt.meta.extra_reject = .{ .tabindex = true };
            opt.content = .{
                .simple = .{
                    .extra_children = &.{.div},
                    .forbidden_descendants = .init(.{
                        .object = true,
                        .datalist = true,
                    }),
                    .forbidden_descendants_extra = .{ .tabindex = true },
                },
            };
        }
    }
    try validateChildren(
        gpa,
        nodes,
        errors,
        src,
        opt.model,
        parent_idx,
        opt.content.simple,
    );
}

fn completionsContent(
    arena: Allocator,
    ast: Ast,
    src: []const u8,
    parent_idx: u32,
    offset: u32,
) error{OutOfMemory}![]const Ast.Completion {
    _ = offset;
    const parent = ast.nodes[parent_idx];

    var it = parent.startTagIterator(src, .html);
    var has_label = false;
    var has_value = false;
    while (it.next(src)) |attr| {
        const name = attr.name.slice(src);
        if (attributes.index(name)) |idx| switch (idx) {
            attributes.comptimeIndex("label") => has_label = true,
            attributes.comptimeIndex("value") => has_value = true,
            else => {},
        };
    }

    // If the element has a label attribute and a value attribute: Nothing.
    // If the element has a label attribute but no value attribute: Text.
    if (has_label) {
        return &.{};
    }

    var ancestor_idx = parent.parent_idx;
    const datalist_descendant = while (ancestor_idx != 0) {
        const ancestor = ast.nodes[ancestor_idx];
        if (ancestor.kind == .datalist) break true;
        ancestor_idx = ancestor.parent_idx;
    } else false;

    // If the element has no label attribute and is not a descendant of a datalist element: Zero or more option element inner content elements.
    // If the element has no label attribute and is a descendant of a datalist element: Text.
    if (datalist_descendant) {
        return &.{};
    }

    return Element.simpleCompletions(
        arena,
        &.{},
        .{ .phrasing = true },
        .{ .interactive = true },
        .{
            .extra_children = &.{.div},
            .forbidden_descendants = .init(.{
                .object = true,
                .datalist = true,
            }),
            .forbidden_descendants_extra = .{ .tabindex = true },
        },
    );
}

fn validateChildren(
    gpa: Allocator,
    nodes: []const Ast.Node,
    errors: *std.ArrayList(Ast.Error),
    src: []const u8,
    parent_model: Model,
    parent_idx: u32,
    simple: Element.Simple,
) !void {
    const parent = nodes[parent_idx];
    const parent_span = parent.startTagIterator(src, .html).name_span;
    assert(parent.kind.isElement());
    assert(parent.kind != .___);
    const first_child_idx = nodes[parent_idx].first_child_idx;

    var child_idx = first_child_idx;
    outer: while (child_idx != 0) {
        const child = nodes[child_idx];
        defer child_idx = child.next_idx;

        switch (child.kind) {
            else => {},
            .doctype => continue,
            .text => {
                if (!parent_model.content.phrasing and
                    !parent_model.content.text)
                {
                    try errors.append(gpa, .{
                        .tag = .{
                            .invalid_nesting = .{
                                .span = parent_span,
                            },
                        },
                        .main_location = child.open,
                        .node_idx = child_idx,
                    });
                }

                continue;
            },
        }

        assert(simple.extra_children.len < 10);
        for (simple.extra_children) |extra| {
            if (child.kind == extra) continue :outer;
        }

        if (!parent_model.content.overlaps(child.model.categories)) {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_nesting = .{
                        .span = parent_span,
                    },
                },
                .main_location = child.span(src),
                .node_idx = child_idx,
            });
            continue;
        }

        assert(simple.forbidden_children.len < 10);
        for (simple.forbidden_children) |forbidden| {
            if (child.kind == forbidden) {
                try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = parent_span,
                        },
                    },
                    .main_location = child.startTagIterator(src, .html).name_span,
                    .node_idx = child_idx,
                });
                continue :outer;
            }
        }
    }

    if (simple.forbidden_descendants == null and
        simple.forbidden_descendants_extra.empty())
    {
        return;
    }

    // check descendants
    if (first_child_idx == 0) return;
    const stop_idx = parent.stop(nodes);

    var next_idx = first_child_idx;
    outer: while (next_idx != stop_idx) {
        assert(next_idx != 0);

        const node_idx = next_idx;
        const node = nodes[node_idx];

        if (node.kind == .___) {
            next_idx = node.stop(nodes);
            continue;
        } else if (node.kind == .svg or node.kind == .math) {
            next_idx = node.stop(nodes);
        } else if (node.kind == .comment or node.kind == .text) {
            next_idx += 1;
            continue;
        } else {
            next_idx += 1;
        }

        if (simple.forbidden_descendants) |forbidden| {
            if (forbidden.contains(node.kind)) {
                try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = parent_span,
                        },
                    },
                    .main_location = node.startTagIterator(src, .html).name_span,
                    .node_idx = node_idx,
                });
                continue :outer;
            }
        }

        if (simple.forbidden_descendants_extra.tabindex and
            node.model.extra.tabindex)
        {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_nesting = .{
                        .span = parent_span,
                        .reason = "presence of [tabindex]",
                    },
                },
                .main_location = node.startTagIterator(src, .html).name_span,
                .node_idx = node_idx,
            });
            continue :outer;
        }
    }
}
