const std = @import("std");
const assert = std.debug.assert;
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

pub const map: Element = .{
    .tag = .map,
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
        },
    },
    .attributes = .{ .dynamic = validate },
    .content = .model,
    .desc =
    \\The `<map>` HTML element is used with `<area>` elements to define an
    \\image map (a clickable link area).
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/map)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-map-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "name",
        .model = .{
            .rule = .id,
            .desc = "The `name` attribute gives the map a name so that it can be referenced. The attribute must be present and must have a non-empty value with no space characters. The value of the name attribute must not be equal to the value of the name attribute of another `<map>` element in the same document. If the `id` attribute is also specified, both attributes must have the same value.",
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
    var map_model = map.model;
    map_model.content = nodes[parent_idx].model.content;

    var name_value: ?Span = null;
    var id_value: ?Span = null;
    while (try vait.next(gpa, src)) |attr| {
        const name = attr.name.slice(src);
        const model = if (attributes.has(name)) blk: {
            if (attr.value) |v| name_value = v.span;
            break :blk attributes.list[0].model;
        } else if (Attribute.global.index(name)) |idx| blk: {
            if (idx == Attribute.global.comptimeIndex("id")) {
                if (attr.value) |v| id_value = v.span;
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

    if (name_value == null) {
        try errors.append(gpa, .{
            .tag = .{
                .missing_required_attr = "name",
            },
            .main_location = vait.name,
            .node_idx = node_idx,
        });
        return map_model;
    }

    if (id_value) |span| {
        const name_span = name_value orelse return map_model;
        const name_slice = name_span.slice(src);
        if (!std.mem.eql(u8, name_slice, span.slice(src))) {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "must be equal to the value of [name]",
                    },
                },
                .main_location = span,
                .node_idx = node_idx,
            });
        }
    }

    return map_model;
}
