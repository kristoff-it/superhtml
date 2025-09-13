const std = @import("std");
const Element = @import("../Element.zig");

pub const strong: Element = .{
    .tag = .strong,
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
    \\The `<strong>` HTML element indicates that its contents have strong
    \\importance, seriousness, or urgency. Browsers typically render the
    \\contents in bold type.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/strong)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/grouping-content.html#the-strong-element)
    ,
};
