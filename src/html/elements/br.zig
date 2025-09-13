const std = @import("std");
const Element = @import("../Element.zig");

pub const br: Element = .{
    .tag = .br,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
        },
        .content = .none,
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
    \\The `<br>` HTML element produces a line break in text
    \\(carriage-return). It is useful for writing a poem or an address,
    \\where the division of lines is significant.
    \\
    \\ *WARNING*: MDN wrongly shows `<br>` as a self-closing element.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/br)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-br-element)
    ,
};
