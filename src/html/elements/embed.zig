const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../../root.zig");
const Span = root.Span;
const Ast = @import("../Ast.zig");
const Content = Ast.Node.Categories;
const Element = @import("../Element.zig");
const Model = Element.Model;
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;

pub const embed: Element = .{
    .tag = .embed,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
            // .embedded = true,
            .interactive = true,
        },
        .content = .none,
    },
    .meta = .{
        .categories_superset = .{
            .flow = true,
            .phrasing = true,
            // .embedded = true,
            .interactive = true,
        },
    },
    .attributes = .{ .dynamic = validate },
    .content = .model,
    .desc =
    \\The `<embed>` HTML element embeds external content at the specified
    \\point in the document. This content is provided by an external
    \\application or other source of interactive content such as a browser
    \\plug-in.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/embed)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-embed-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "src",
        .model = .{
            .rule = .{ .url = .not_empty },
            .desc = "The URL of the resource being embedded.",
        },
    },
    .{
        .name = "type",
        .model = .{
            .rule = .mime,
            .desc = "The MIME type to use to select the plug-in to instantiate.",
        },
    },
    .{
        .name = "width",
        .model = .{
            .rule = .{ .non_neg_int = .{} },
            .desc = "The displayed width of the resource, in CSS pixels. This must be an absolute value; percentages are not allowed.",
        },
    },
    .{
        .name = "height",
        .model = .{
            .rule = .{ .non_neg_int = .{} },
            .desc = "The displayed height of the resource, in CSS pixels. This must be an absolute value; percentages are not allowed.",
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

    // If the itemprop attribute is specified on an embed element, then the src attribute must also be specified.

    var has_src = false;
    var has_itemprop = false;
    while (try vait.next(gpa, src)) |attr| {
        const name = attr.name.slice(src);
        const model = if (attributes.index(name)) |idx| blk: {
            if (idx == attributes.comptimeIndex("src")) {
                has_src = true;
            }

            break :blk attributes.list[idx].model;
        } else if (Attribute.global.index(name)) |idx| blk: {
            if (idx == Attribute.global.comptimeIndex("itemprop")) {
                has_itemprop = true;
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

    if (has_itemprop and !has_src) try errors.append(gpa, .{
        .tag = .{
            .invalid_attr_combination = "[itemprop] requires [src] to be defined",
        },
        .main_location = vait.name,
        .node_idx = node_idx,
    });

    return embed.model;
}
