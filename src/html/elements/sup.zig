const std = @import("std");
const Element = @import("../Element.zig");

pub const sup: Element = .{
    .tag = .sup,
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
    \\The `<sup>` HTML element specifies inline text which is to
    \\be displayed as superscript for solely typographical reasons.
    \\Superscripts are usually rendered with a raised baseline using
    \\smaller text.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/sup)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/grouping-content.html#the-sup-element)
    ,
};
