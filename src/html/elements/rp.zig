const std = @import("std");
const Element = @import("../Element.zig");

pub const rp: Element = .{
    .tag = .rp,
    .model = .{
        .categories = .none,
        .content = .none,
    },
    .meta = .{ .categories_superset = .none },
    .attributes = .static,
    .content = .{ .simple = .{ .extra_children = &.{.text} } },
    .desc =
    \\The `<rp>` HTML element is used to provide fall-back parentheses
    \\for browsers that do not support display of ruby annotations using
    \\the `<ruby>` element. One `<rp>` element should enclose each of the
    \\opening and closing parentheses that wrap the `<rt>` element that
    \\contains the annotation's text.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/rp)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/grouping-content.html#the-rp-element)
    ,
};
