const std = @import("std");
const Element = @import("../Element.zig");

pub const section: Element = .{
    .tag = .section,
    .model = .{
        .categories = .{
            .flow = true,
        },
        .content = .{ .flow = true },
    },
    .meta = .{
        .categories_superset = .{
            .flow = true,
            .sectioning = true,
        },
    },
    .attributes = .static,
    .content = .model,
    .desc =
    \\The `<section>` HTML element represents a generic standalone section
    \\of a document, which doesn't have a more specific semantic element
    \\to represent it. Sections should always have a heading, with very
    \\few exceptions.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/section)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/grouping-content.html#the-section-element)
    ,
};
