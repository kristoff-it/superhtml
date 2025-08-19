const std = @import("std");
const Element = @import("../Element.zig");

pub const title: Element = .{
    .tag = .title,
    .model = .{
        .categories = .{ .metadata = true },
        .content = .{ .text = true },
    },
    .meta = .{ .categories_superset = .{ .metadata = true } },
    .attributes = .static,
    .content = .model,
    .desc =
    \\The `<title>` HTML element defines the document's title that is
    \\shown in a browser's title bar or a page's tab. It only contains
    \\text; HTML tags within the element, if any, are also treated as
    \\plain text.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/title)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-title-element)
    ,
};
