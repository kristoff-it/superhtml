const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../../root.zig");
const Span = root.Span;
const Element = @import("../Element.zig");
const Model = Element.Model;
const Ast = @import("../Ast.zig");
const Content = Ast.Node.Categories;
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;

pub const dl: Element = .{
    .tag = .dl,
    .model = .{
        .categories = .{ .flow = true },
        .content = .none,
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
    \\The `<dl>` HTML element represents a description list. The element
    \\encloses a list of groups of terms (specified using the `<dt>`
    \\element) and descriptions (provided by `<dd>` elements). Common uses
    \\for this element are to implement a glossary or to display metadata
    \\(a list of key-value pairs).
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/dl)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-dl-element)
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
    // Either: Zero or more groups each consisting of one or more dt elements followed by one or more dd elements, optionally intermixed with script-supporting elements.
    // Or: One or more div elements, optionally intermixed with script-supporting elements.

    const parent = nodes[parent_idx];
    const parent_span = parent.span(src);

    var state: enum { searching, dt, dd, div } = .searching;
    var last_dt: Span = undefined;
    var last_dt_idx: u32 = undefined;
    var child_idx = parent.first_child_idx;
    while (child_idx != 0) {
        const child = nodes[child_idx];
        defer child_idx = child.next_idx;

        switch (child.kind) {
            .script, .template, .comment => continue,
            else => {},
        }

        state: switch (state) {
            .searching => switch (child.kind) {
                .dt => continue :state .dt,
                .dd => {
                    try errors.append(gpa, .{
                        .tag = .{
                            .invalid_nesting = .{
                                .span = parent_span,
                                .reason = "first non-script child must be <dt> or <div>",
                            },
                        },
                        .main_location = child.span(src),
                        .node_idx = child_idx,
                    });
                    state = .dd;
                },
                .div => state = .div,
                else => {
                    try errors.append(gpa, .{
                        .tag = .{
                            .invalid_nesting = .{
                                .span = parent_span,
                                .reason = "first non-script child must be <dt> or <div>",
                            },
                        },
                        .main_location = child.span(src),
                        .node_idx = child_idx,
                    });
                },
            },
            .dt => switch (child.kind) {
                .dt => {
                    state = .dt;
                    last_dt = child.span(src);
                    last_dt_idx = child_idx;
                },
                .dd => state = .dd,
                else => {
                    try errors.append(gpa, .{
                        .tag = .{
                            .invalid_nesting = .{
                                .span = parent_span,
                                .reason = "(in <dd>/<dt> mode) only <dt>, <dd>, <script> or <template> children allowed",
                            },
                        },
                        .main_location = child.span(src),
                        .node_idx = child_idx,
                    });
                },
            },
            .dd => switch (child.kind) {
                .dd => {},
                .dt => continue :state .dt,
                else => {
                    try errors.append(gpa, .{
                        .tag = .{
                            .invalid_nesting = .{
                                .span = parent_span,
                                .reason = "(in <dd>/<dt> mode) only <dt>, <dd>, <script> or <template> children allowed",
                            },
                        },
                        .main_location = child.span(src),
                        .node_idx = child_idx,
                    });
                },
            },
            .div => if (child.kind != .div) {
                try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = parent_span,
                            .reason = "(in <div> mode) only <div>, <script> or <template> children allowed",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                });
            },
        }
    }

    if (state == .dt) try errors.append(gpa, .{
        .tag = .{
            .invalid_nesting = .{
                .span = parent_span,
                .reason = " (in <dd>/<dt> mode) last non-script child must be <dd>",
            },
        },
        .main_location = last_dt,
        .node_idx = last_dt_idx,
    });
}

fn completions(
    arena: Allocator,
    ast: Ast,
    src: []const u8,
    parent_idx: u32,
    offset: u32,
) error{OutOfMemory}![]const Ast.Completion {
    _ = arena;
    _ = src;
    _ = offset;

    const parent = ast.nodes[parent_idx];

    var child_idx = parent.first_child_idx;
    const state: enum { searching, dt_dd, div } = while (child_idx != 0) {
        const child = ast.nodes[child_idx];
        defer child_idx = child.next_idx;

        switch (child.kind) {
            .script, .template, .comment => continue,
            else => {},
        }

        if (child.kind == .div) break .div;
        if (child.kind == .dt or child.kind == .dd) break .dt_dd;
    } else .searching;

    return switch (state) {
        .searching => &.{ dt, dd, div, script, template },
        .dt_dd => &.{ dt, dd, script, template },
        .div => &.{ div, script, template },
    };
}
const dt: Ast.Completion = .{
    .label = "dt",
    .desc = Element.all.get(.dt).desc,
};
const dd: Ast.Completion = .{
    .label = "dd",
    .desc = Element.all.get(.dd).desc,
};
const div: Ast.Completion = .{
    .label = "div",
    .desc = Element.all.get(.div).desc,
};
const script: Ast.Completion = .{
    .label = "script",
    .desc = Element.all.get(.script).desc,
};
const template: Ast.Completion = .{
    .label = "template",
    .desc = Element.all.get(.template).desc,
};
