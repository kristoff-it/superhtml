const std = @import("std");
const Allocator = std.mem.Allocator;
const Element = @import("../Element.zig");
const Ast = @import("../Ast.zig");
const Content = Ast.Node.Categories;

pub const em: Element = .{
    .tag = .em,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
            // .palpable = true,
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
    .attributes = .static,
    .content = .model,
    .desc =
    \\The `<em>` HTML element marks text that has stress emphasis. The
    \\`<em>` element can be nested, with each level of nesting indicating a
    \\greater degree of emphasis.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/em)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-em-element)
    ,
};
