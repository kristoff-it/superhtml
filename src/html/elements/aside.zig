const std = @import("std");
const Allocator = std.mem.Allocator;
const Ast = @import("../Ast.zig");
const root = @import("../../root.zig");
const Span = root.Span;
const Language = root.Language;
const Element = @import("../Element.zig");
const Categories = Element.Categories;
const Model = Element.Model;
const CompletionMode = Element.CompletionMode;
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;

pub const aside: Element = .{
    .tag = .aside,
    .model = .{
        .categories = .{
            .flow = true,
            .sectioning = true,
        },
        .content = .{ .flow = true },
    },

    .meta = .{
        .categories_superset = .{
            .flow = true,
            .sectioning = true,
        },
    },

    .attributes = .static,
    .content = .model,
    .desc =
    \\The `<aside>` HTML element represents a portion of a document whose
    \\content is only indirectly related to the document's main content.
    \\Asides are frequently presented as sidebars or call-out boxes.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/aside)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-aside-element)
    ,
};
