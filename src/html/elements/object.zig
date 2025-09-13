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

pub const object: Element = .{
    .tag = .object,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
            // .embedded = true,
        },
        .content = .transparent,
    },
    .meta = .{
        .categories_superset = .{
            .flow = true,
            .phrasing = true,
            // .embedded = true,
        },
    },
    .attributes = .{
        .dynamic = validate,
    },
    .content = .model,
    .desc =
    \\The `<object>` HTML element represents an external resource, which
    \\can be treated as an image, a nested browsing context, or a resource
    \\to be handled by a plugin.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/object)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-object-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "data",
        .model = .{
            .rule = .{ .url = .not_empty },
            .desc = "The address of the resource as a valid URL. It's a required attribute.",
        },
    },
    .{
        .name = "type",
        .model = .{
            .rule = .mime,
            .desc = "The content type of the resource specified by `data`.",
        },
    },
    .{
        .name = "name",
        .model = .{
            .rule = .not_empty,
            .desc = "The name of valid browsing context. The name becomes a property of the Window and Document objects, containing a reference to the embedded window or the element itself.",
        },
    },
    .{
        .name = "form",
        .model = .{
            .rule = .not_empty,
            .desc = "The form element, if any, that the object element is associated with (its form owner). The value of the attribute must be an ID of a `<form>` element in the same document.",
        },
    },
    .{
        .name = "height",
        .model = .{
            .rule = .{ .non_neg_int = .{} },
            .desc = "The height of the displayed resource, as in `<integer>` in CSS pixels.",
        },
    },
    .{
        .name = "width",
        .model = .{
            .rule = .{ .non_neg_int = .{} },
            .desc = "The width of the displayed resource, as in `<integer>` in CSS pixels.",
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

    var has_data = false;
    while (try vait.next(gpa, src)) |attr| {
        const name = attr.name.slice(src);
        const model = if (attributes.index(name)) |idx| blk: {
            if (idx == attributes.comptimeIndex("data")) {
                has_data = true;
            }
            break :blk attributes.list[idx].model;
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

    if (!has_data) try errors.append(gpa, .{
        .tag = .{ .missing_required_attr = "data" },
        .main_location = vait.name,
        .node_idx = node_idx,
    });

    return object.model;
}
