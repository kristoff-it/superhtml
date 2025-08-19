const std = @import("std");
const Element = @import("../Element.zig");

pub const rt: Element = .{
    .tag = .rt,
    .model = .{
        .categories = .none,
        .content = .{ .phrasing = true },
    },
    .meta = .{ .categories_superset = .none },
    .attributes = .static,
    .content = .model,
    .desc =
    \\The `<rt>` HTML element specifies the ruby text component of
    \\a ruby annotation, which is used to provide pronunciation,
    \\translation, or transliteration information for East Asian
    \\typography. The `<rt>` element must always be contained within a
    \\`<ruby>` element.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/rt)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/grouping-content.html#the-rt-element)
    ,
};
