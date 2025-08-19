const std = @import("std");
const Element = @import("../Element.zig");

pub const wbr: Element = .{
    .tag = .wbr,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
        },
        .content = .none,
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
    \\The `<wbr>` HTML element represents a word break opportunity — a
    \\position within text where the browser may optionally break a line,
    \\though its line-breaking rules would not otherwise create a break at
    \\that location.
    \\
    \\ *WARNING*: MDN wrongly shows `<wbr>` as a self-closing element.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/wbr)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-wbr-element)
    ,
};
