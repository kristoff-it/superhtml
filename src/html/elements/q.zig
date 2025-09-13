const std = @import("std");
const Allocator = std.mem.Allocator;
const Element = @import("../Element.zig");
const Ast = @import("../Ast.zig");
const Content = Ast.Node.Categories;
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;

pub const q: Element = .{
    .tag = .q,
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
    .attributes = .static,
    .content = .model,
    .desc =
    \\The `<q>` HTML element indicates that the enclosed text is a short
    \\inline quotation. Most modern browsers implement this by surrounding
    \\the text in quotation marks. This element is intended for short
    \\quotations that don't require paragraph breaks; for long quotations
    \\use the `<blockquote>` element.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/q)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/grouping-content.html#the-q-element)
    ,
};
pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "cite",
        .model = .{
            .rule = .{ .url = .not_empty },
            .desc = "The value of this attribute is a URL that designates a source document or message for the information quoted. This attribute is intended to point to information explaining the context or the reference for the quote.",
        },
    },
});
