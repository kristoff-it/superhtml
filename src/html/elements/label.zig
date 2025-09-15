const std = @import("std");
const Allocator = std.mem.Allocator;
const Ast = @import("../Ast.zig");
const Content = Ast.Node.Categories;
const Element = @import("../Element.zig");
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;

pub const label: Element = .{
    .tag = .label,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
            .interactive = true,
        },
        .content = .{ .phrasing = true },
    },
    .meta = .{
        .categories_superset = .{
            .flow = true,
            .phrasing = true,
            .interactive = true,
        },
    },
    .attributes = .static,
    .content = .{
        .simple = .{
            .forbidden_descendants = .init(.{ .label = true }),
        },
    },
    .desc =
    \\The `<label>` HTML element represents a caption for an item in a
    \\user interface.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/label)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-label-element)
    ,
};
pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "for",
        .model = .{
            .rule = .not_empty,
            .desc = "The value is the `id` of the labelable form control in the same document, associating the `<label>` with that form control. Note that its JavaScript reflection property is `htmlFor`.",
        },
    },
});
