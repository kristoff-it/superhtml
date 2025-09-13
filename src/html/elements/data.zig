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
const log = std.log.scoped(.button);

pub const data: Element = .{
    .tag = .data,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
        },
        .content = .{ .phrasing = true },
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
    \\The `<data>` HTML element links a given piece of content with
    \\a machine-readable translation. If the content is time- or
    \\date-related, the `<time>` element must be used.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/data)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-data-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "value",
        .model = .{
            .rule = .not_empty,
            .desc = "This attribute specifies the machine-readable translation of the content of the element.",
        },
    },
});

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

    var has_value = false;
    while (try vait.next(gpa, src)) |attr| {
        const name = attr.name.slice(src);
        const model = if (attributes.get(name)) |model| blk: {
            has_value = true;
            break :blk model;
        } else Attribute.global.get(name) orelse {
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

    if (!has_value) try errors.append(gpa, .{
        .tag = .{ .missing_required_attr = "value" },
        .main_location = vait.name,
        .node_idx = node_idx,
    });

    return data.model;
}
