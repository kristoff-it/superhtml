const std = @import("std");
const Element = @import("../Element.zig");

pub const b: Element = .{
    .tag = .b,
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
    \\The `<b>` HTML element is used to draw the reader's attention to the element's
    \\contents, which are not otherwise granted special importance. This was
    \\formerly known as the Boldface element, and most browsers still draw the
    \\text in boldface. However, you should not use <b> for styling text or
    \\granting importance. If you wish to create boldface text, you should use the
    \\CSS font-weight property. If you wish to indicate an element is of special
    \\importance, you should use the <strong> element.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/b)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-b-element)
    ,
};
