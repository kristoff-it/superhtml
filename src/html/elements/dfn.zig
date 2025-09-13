const std = @import("std");
const Allocator = std.mem.Allocator;
const Element = @import("../Element.zig");
const Ast = @import("../Ast.zig");
const Content = Ast.Node.Categories;

pub const dfn: Element = .{
    .tag = .dfn,
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
    .content = .{
        .simple = .{
            .forbidden_descendants = .init(.{ .dfn = true }),
        },
    },
    .desc =
    \\The `<dfn>` HTML element indicates a term to be defined. The `<dfn>`
    \\element should be used in a complete definition statement, where the
    \\full definition of the term can be one of the following:
    \\
    \\- The ancestor paragraph (a block of text, sometimes marked by a `<p>`
    \\  element)
    \\- The `<dt>`/`<dd>` pairing
    \\- The nearest section ancestor of the `<dfn>` element    
    \\
    \\## Attributes
    \\
    \\The `title` attribute has special semantics on this element: Full
    \\term or expansion of abbreviation
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/dfn)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-dfn-element)
    ,
};
