const std = @import("std");
const Element = @import("../Element.zig");

pub const s: Element = .{
    .tag = .s,
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
    \\The `<s>` HTML element renders text with a strikethrough, or a
    \\line through it. Use the `<s>` element to represent things that
    \\are no longer relevant or no longer accurate. However, `<s>` is
    \\not appropriate when indicating document edits; for that, use
    \\the `<del>` and `<ins>` elements, as appropriate.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/s)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/grouping-content.html#the-s-element)
    ,
};
