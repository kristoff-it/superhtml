const std = @import("std");
const Allocator = std.mem.Allocator;
const Element = @import("../Element.zig");
const Ast = @import("../Ast.zig");
const Content = Ast.Node.Categories;

pub const figcaption: Element = .{
    .tag = .figcaption,
    .model = .{
        .categories = .none,
        .content = .{ .flow = true },
    },
    .meta = .{
        .categories_superset = .{ .flow = true },
    },
    .attributes = .static,
    .content = .model,
    .desc =
    \\The `<figcaption>` HTML element represents a caption or legend
    \\describing the rest of the contents of its parent `<figure>`
    \\element, providing the `<figure>` an accessible description.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/figcaption)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-figcaption-element)
    ,
};
