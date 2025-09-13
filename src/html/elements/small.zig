const std = @import("std");
const Element = @import("../Element.zig");

pub const small: Element = .{
    .tag = .small,
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
    \\The `<small>` HTML element represents side-comments and small
    \\print, like copyright and legal text, independent of its styled
    \\presentation. By default, it renders text within it one font-size
    \\`smaller`, such as from `small` to `x-small`.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/small)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/grouping-content.html#the-small-element)
    ,
};
