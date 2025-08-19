const std = @import("std");
const Element = @import("../Element.zig");

pub const @"var": Element = .{
    .tag = .@"var",
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
    \\The `<var>` HTML element represents the name of a variable in a
    \\mathematical expression or a programming context. It's typically
    \\presented using an italicized version of the current typeface,
    \\although that behavior is browser-dependent.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/var)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/grouping-content.html#the-var-element)
    ,
};
