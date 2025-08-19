const std = @import("std");
const Allocator = std.mem.Allocator;
const Element = @import("../Element.zig");
const Model = Element.Model;
const Ast = @import("../Ast.zig");
const Content = Ast.Node.Categories;
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;

pub const div: Element = .{
    .tag = .div,
    .model = .{
        .categories = .{ .flow = true },
        .content = .{ .flow = true },
    },
    .meta = .{ .categories_superset = .{ .flow = true } },
    .attributes = .static,
    .content = .{
        .custom = .{
            .validate = validateContent,
            .completions = completions,
        },
    },
    .desc =
    \\The `<div>` HTML element is the generic container for flow
    \\content. It has no effect on the content or layout until styled
    \\in some way using CSS (e.g., styling is directly applied to
    \\it, or some kind of layout model like Flexbox is applied to its
    \\parent element).
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/div)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-div-element)
    ,
};

pub fn validateContent(
    gpa: Allocator,
    nodes: []const Ast.Node,
    errors: *std.ArrayListUnmanaged(Ast.Error),
    src: []const u8,
    parent_idx: u32,
) error{OutOfMemory}!void {

    // If the element is a child of a dl element: One or more dt elements followed by one or more dd elements, optionally intermixed with script-supporting elements.
    // Otherwise, if the element is a descendant of an option element: Zero or more option element inner content elements.
    // Otherwise, if the element is a descendant of an optgroup element: Zero or more optgroup element inner content elements.
    // Otherwise, if the element is a descendant of a select element: Zero or more select element inner content elements.
    // Otherwise: flow content.

    const parent = nodes[parent_idx];
    const parent_span = parent.span(src);

    var ancestor_idx = parent.parent_idx;
    const state: enum { dl, option, optgroup, select, flow } = while (ancestor_idx != 0) {
        const ancestor = nodes[ancestor_idx];
        defer ancestor_idx = ancestor.parent_idx;
        if (ancestor_idx == parent.parent_idx and ancestor.kind == .dl) break .dl;
        switch (ancestor.kind) {
            .option => break .option,
            .optgroup => break .optgroup,
            .select => break .select,
            else => continue,
        }
    } else .flow;

    switch (state) {
        .dl => {
            var dlstate: enum { dt, dd } = .dt;
            var child_idx = parent.first_child_idx;
            while (child_idx != 0) {
                const child = nodes[child_idx];
                defer child_idx = child.next_idx;

                switch (child.kind) {
                    .script, .template => continue,
                    else => {},
                }

                switch (dlstate) {
                    .dt => {
                        if (child.kind == .dt) {
                            // do nothing
                        } else if (child.kind == .dd) {
                            dlstate = .dd;
                        } else {
                            try errors.append(gpa, .{
                                .tag = .{
                                    .invalid_nesting = .{
                                        .span = parent_span,
                                        .reason = "as a child of <dl> it only accepts <dt>, <dd>, <script> or <template>",
                                    },
                                },
                                .main_location = child.span(src),
                                .node_idx = child_idx,
                            });
                        }
                    },
                    .dd => {
                        if (child.kind == .dt) {
                            try errors.append(gpa, .{
                                .tag = .{
                                    .invalid_nesting = .{
                                        .span = parent_span,
                                        .reason = "<dt> elements must go before all others",
                                    },
                                },
                                .main_location = child.span(src),
                                .node_idx = child_idx,
                            });
                        } else if (child.kind == .dd) {
                            // do nothing
                        } else {
                            try errors.append(gpa, .{
                                .tag = .{
                                    .invalid_nesting = .{
                                        .span = parent_span,
                                        .reason = "<div> under <dl> only accepts <dt>, <dd>, <srcipt> or <template>",
                                    },
                                },
                                .main_location = child.span(src),
                                .node_idx = child_idx,
                            });
                        }
                    },
                }
            }
        },
        .flow => {
            var child_idx = parent.first_child_idx;
            while (child_idx != 0) {
                const child = nodes[child_idx];
                defer child_idx = child.next_idx;

                if (div.modelRejects(
                    nodes,
                    src,
                    parent,
                    parent_span,
                    &Element.all.get(child.kind),
                    child.model,
                )) |rejection| {
                    try errors.append(gpa, .{
                        .tag = .{
                            .invalid_nesting = .{
                                .span = rejection.span,
                                .reason = rejection.reason,
                            },
                        },
                        .main_location = child.span(src),
                        .node_idx = child_idx,
                    });
                }
            }
        },
        .optgroup, .select => {
            var child_idx = parent.first_child_idx;
            while (child_idx != 0) {
                const child = nodes[child_idx];
                defer child_idx = child.next_idx;

                switch (child.kind) {
                    .option, .script, .template, .noscript, .div => continue,
                    .optgroup, .hr => {
                        if (state == .select) continue;
                    },
                    else => {},
                }

                try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = parent_span,
                            .reason = if (state == .select)
                                \\as descendant of <select> it only accepts <optgroup>, <hr>, <option>, <script>, <template>, <noscript> or <div>
                            else
                                \\as descendant of <optgroup> it only accepts <option>, <script>, <template>, <noscript> or <div>
                            ,
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                });
            }
        },
        .option => {
            var child_idx = parent.first_child_idx;
            while (child_idx != 0) {
                const child = nodes[child_idx];
                defer child_idx = child.next_idx;

                if (child.kind == .div) continue;

                var elem = div;
                elem.model.content = .{ .phrasing = true };
                elem.meta.content_reject = .{ .interactive = true };
                elem.meta.extra_reject = .{ .tabindex = true };

                if (elem.modelRejects(
                    nodes,
                    src,
                    parent,
                    parent_span,
                    &Element.all.get(child.kind),
                    child.model,
                )) |rejection| {
                    try errors.append(gpa, .{
                        .tag = .{
                            .invalid_nesting = .{
                                .span = rejection.span,
                                .reason = rejection.reason,
                            },
                        },
                        .main_location = child.span(src),
                        .node_idx = child_idx,
                    });
                    continue;
                }

                if (child.kind == .datalist or child.kind == .object) {
                    try errors.append(gpa, .{
                        .tag = .{ .invalid_nesting = .{ .span = parent_span } },
                        .main_location = child.span(src),
                        .node_idx = child_idx,
                    });
                    continue;
                }
            }
        },
    }
}

fn completions(
    arena: Allocator,
    ast: Ast,
    src: []const u8,
    parent_idx: u32,
    offset: u32,
) error{OutOfMemory}![]const Ast.Completion {
    _ = src;

    const nodes = ast.nodes;
    const parent = nodes[parent_idx];

    var ancestor_idx = parent.parent_idx;
    const state: enum { dl, option, optgroup, select, flow } = while (ancestor_idx != 0) {
        const ancestor = nodes[ancestor_idx];
        defer ancestor_idx = ancestor.parent_idx;
        if (ancestor_idx == parent.parent_idx and ancestor.kind == .dl) break .dl;
        switch (ancestor.kind) {
            .option => break .option,
            .optgroup => break .optgroup,
            .select => break .select,
            else => continue,
        }
    } else .flow;

    switch (state) {
        .dl => {
            var dlstate: enum { dt, dd } = .dt;
            var after_cursor: Ast.Kind = .dd;
            var child_idx = parent.first_child_idx;
            while (child_idx != 0) {
                const child = nodes[child_idx];
                defer child_idx = child.next_idx;

                switch (child.kind) {
                    .script, .template => continue,
                    else => {},
                }

                if (child.open.start > offset) {
                    after_cursor = child.kind;
                    break;
                }

                switch (dlstate) {
                    .dt => if (child.kind == .dd) {
                        dlstate = .dd;
                    },
                    .dd => {},
                }
            }

            const all: [2]Ast.Completion = .{
                .{
                    .label = "dt",
                    .desc = comptime Element.all.get(.dt).desc,
                },
                .{
                    .label = "dd",
                    .desc = comptime Element.all.get(.dd).desc,
                },
            };

            return switch (dlstate) {
                .dt => if (after_cursor == .dt) all[0..1] else all[0..2],
                .dd => all[1..],
            };
        },
        .flow => {
            return Element.simpleCompletions(
                arena,
                &.{},
                .{ .flow = true },
                .none,
                .{},
            );
        },
        .optgroup, .select => {
            const all: [7]Ast.Completion = comptime blk: {
                const tags = &.{
                    .hr,       .optgroup, .option, .script,
                    .template, .noscript, .div,
                };

                var all: [7]Ast.Completion = undefined;
                for (&all, tags) |*a, t| a.* = .{
                    .label = @tagName(t),
                    .desc = Element.all.get(t).desc,
                };
                break :blk all;
            };

            if (state == .select) return &all;
            return all[2..];
        },
        .option => {
            var elem = div;
            elem.model.content = .{ .phrasing = true };
            elem.meta.content_reject = .{ .interactive = true };
            elem.meta.extra_reject = .{ .tabindex = true };

            return Element.simpleCompletions(
                arena,
                &.{},
                elem.model.content,
                elem.meta.content_reject,
                .{
                    .extra_children = &.{.div},
                    .forbidden_children = &.{ .datalist, .object },
                    .forbidden_descendants_extra = elem.meta.extra_reject,
                },
            );
        },
    }
}
