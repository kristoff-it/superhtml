const std = @import("std");
const Element = @import("../Element.zig");

pub const bdi: Element = .{
    .tag = .bdi,
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
    \\The `<bdi>` HTML element tells the browser's bidirectional algorithm
    \\to treat the text it contains in isolation from its surrounding
    \\text. It's particularly useful when a website dynamically inserts
    \\some text and doesn't know the directionality of the text being
    \\inserted.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/bdi)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-bdi-element)
    ,
};
