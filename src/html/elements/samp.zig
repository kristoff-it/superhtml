const std = @import("std");
const Element = @import("../Element.zig");

pub const samp: Element = .{
    .tag = .samp,
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
    \\The `<samp>` HTML element is used to enclose inline text which
    \\represents sample (or quoted) output from a computer program.
    \\Its contents are typically rendered using the browser's default
    \\monospaced font (such as Courier or Lucida Console).
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/samp)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/grouping-content.html#the-samp-element)
    ,
};
