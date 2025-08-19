const std = @import("std");
const Allocator = std.mem.Allocator;
const Ast = @import("../Ast.zig");
const Element = @import("../Element.zig");
const Model = Element.Model;
const Attribute = @import("../Attribute.zig");

pub const bdo: Element = .{
    .tag = .bdo,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
        },
        .content = .{
            .phrasing = true,
        },
    },
    .meta = .{
        .categories_superset = .{
            .flow = true,
            .phrasing = true,
        },
    },
    .attributes = .{
        .dynamic = validate,
    },
    .content = .model,
    .desc =
    \\The `<bdo>` HTML element overrides the current directionality
    \\of text, so that the text within is rendered in a different
    \\direction.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/bdo)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-bdo-element)
    ,
};

fn validate(
    gpa: Allocator,
    errors: *std.ArrayListUnmanaged(Ast.Error),
    src: []const u8,
    nodes: []const Ast.Node,
    parent_idx: u32,
    node_idx: u32,
    vait: *Attribute.ValidatingIterator,
) error{OutOfMemory}!Model {
    _ = nodes;
    _ = parent_idx;

    var has_dir = false;
    while (try vait.next(gpa, src)) |attr| {
        const name = attr.name.slice(src);
        const model = if (Attribute.global.index(name)) |idx| blk: {
            switch (idx) {
                else => {},
                Attribute.global.comptimeIndex("dir") => {
                    has_dir = true;
                },
            }

            break :blk Attribute.global.list[idx].model;
        } else {
            if (Attribute.isData(name)) continue;
            try errors.append(gpa, .{
                .tag = .invalid_attr,
                .main_location = attr.name,
                .node_idx = node_idx,
            });

            continue;
        };

        try model.rule.validate(gpa, errors, src, node_idx, attr);
    }

    if (!has_dir) {
        try errors.append(gpa, .{
            .tag = .{ .missing_required_attr = "dir" },
            .main_location = vait.name,
            .node_idx = node_idx,
        });
    }

    return bdo.model;
}
