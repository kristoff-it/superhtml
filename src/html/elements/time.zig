const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../../root.zig");
const Span = root.Span;
const Ast = @import("../Ast.zig");
const Element = @import("../Element.zig");
const Model = Element.Model;
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;

pub const time: Element = .{
    .tag = .time,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
        },
        .content = .{ .phrasing = true },
    },
    .meta = .{
        .categories_superset = .{
            .metadata = true,
            .flow = true,
            .phrasing = true,
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
    \\The `<time>` HTML element represents a specific period in time.
    \\It may include the datetime attribute to translate dates into
    \\machine-readable format, allowing for better search engine results
    \\or custom features such as reminders.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/time)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-time-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "datetime",
        .model = .{
            .rule = .{ .custom = @import("ins_del.zig").validateDatetime },
            .desc = "The name of the control.",
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

    var text_only = true;
    while (try vait.next(gpa, src)) |attr| {
        const name = attr.name.slice(src);
        const model = if (attributes.get(name)) |model| blk: {
            text_only = false;
            break :blk model;
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

    var child_idx = parent.first_child_idx;
    while (child_idx != 0) {
        const child = nodes[child_idx];
        defer child_idx = child.next_idx;
        switch (child.kind) {
            .text, .comment => continue,
            else => {},
        }

        if (text_only) try errors.append(gpa, .{
            .tag = .{
                .invalid_nesting = .{
                    .span = vait.name,
                    .reason = "only text allowed when [datetime] is defined",
                },
            },
            .main_location = child.span(src),
            .node_idx = child_idx,
        }) else if (time.modelRejects(
            nodes,
            src,
            parent,
            vait.name,
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
    const text_only = while (it.next(src)) |attr| {
        const name = attr.name.slice(src);
        if (attributes.has(name)) {
            break false;
        }
    } else true;

    if (text_only) return &.{};

    return Element.simpleCompletions(arena, &.{}, time.model.content, .none, .{});
}
