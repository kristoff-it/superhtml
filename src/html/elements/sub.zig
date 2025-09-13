const std = @import("std");
const Element = @import("../Element.zig");

pub const sub: Element = .{
    .tag = .sub,
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
    \\The `<sub>` HTML element specifies inline text which should be
    \\displayed as subscript for solely typographical reasons. Subscripts
    \\are typically rendered with a lowered baseline using smaller text.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/sub)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/grouping-content.html#the-sub-element)
    ,
};
