const std = @import("std");
const Element = @import("../Element.zig");

pub const noscript: Element = .{
    .tag = .noscript,
    .model = .{
        .categories = .{
            .metadata = true,
            .flow = true,
            .phrasing = true,
        },
        .content = .transparent,
    },
    .meta = .{
        .categories_superset = .{
            .metadata = true,
            .flow = true,
            .phrasing = true,
        },
    },
    .attributes = .static,
    .content = .{
        .simple = .{
            .forbidden_descendants = .init(.{ .noscript = true }),
        },
    },
    .desc =
    \\The `<noscript>` HTML element defines a section of HTML to be
    \\inserted if a script type on the page is unsupported or if scripting
    \\is currently turned off in the browser.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/noscript)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-noscript-element)
    ,
};
