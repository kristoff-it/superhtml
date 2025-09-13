const std = @import("std");
const Allocator = std.mem.Allocator;
const Element = @import("../Element.zig");
const Ast = @import("../Ast.zig");
const Content = Ast.Node.Categories;

pub const kbd: Element = .{
    .tag = .kbd,
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
    \\The `<kbd>` HTML element represents a span of inline text denoting
    \\textual user input from a keyboard, voice input, or any other text
    \\entry device. By convention, the user agent defaults to rendering
    \\the contents of a `<kbd>` element using its default monospace font,
    \\although this is not mandated by the HTML standard.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/kbd)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-kbd-element)
    ,
};
