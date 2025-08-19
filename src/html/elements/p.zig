const std = @import("std");
const Allocator = std.mem.Allocator;
const Element = @import("../Element.zig");
const Ast = @import("../Ast.zig");
const Content = Ast.Node.Categories;

pub const p: Element = .{
    .tag = .p,
    .model = .{
        .categories = .{
            .flow = true,
            // .palpable = true,
        },
        .content = .{
            .phrasing = true,
        },
    },
    .meta = .{
        .categories_superset = .{
            .flow = true,
        },
    },
    .attributes = .static,
    .content = .model,
    .desc =
    \\The `<p>` HTML element represents a paragraph. Paragraphs are usually
    \\represented in visual media as blocks of text separated from
    \\adjacent blocks by blank lines and/or first-line indentation, but
    \\HTML paragraphs can be any structural grouping of related content,
    \\such as images or form fields.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/p)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/grouping-content.html#the-p-element)
    ,
};
