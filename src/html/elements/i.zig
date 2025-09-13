const std = @import("std");
const Allocator = std.mem.Allocator;
const Element = @import("../Element.zig");
const Ast = @import("../Ast.zig");
const Content = Ast.Node.Categories;

pub const i: Element = .{
    .tag = .i,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
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
    \\The `<i>` HTML element represents a range of text that is set off from
    \\the normal text for some reason, such as idiomatic text, technical
    \\terms, taxonomical designations, among others. Historically, these
    \\have been presented using italicized type, which is the original
    \\source of the `<i>` naming of this element.
    \\
    \\
    \\Authors are encouraged to consider whether other elements might
    \\be more applicable than the `i` element, for instance the `em` element
    \\for marking up stress emphasis, or the `dfn` element to mark up the
    \\defining instance of a term.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/i)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-i-element)
    ,
};
