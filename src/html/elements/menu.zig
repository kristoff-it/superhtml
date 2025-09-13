const std = @import("std");
const Element = @import("../Element.zig");

pub const menu: Element = .{
    .tag = .menu,
    .model = .{
        .categories = .{ .flow = true },
        .content = .none,
    },
    .meta = .{
        .categories_superset = .{ .flow = true },
    },
    .attributes = .static,
    .content = .{
        .simple = .{
            .extra_children = &.{ .li, .script, .template },
        },
    },
    .desc =
    \\The `<menu>` HTML element is described in the HTML specification
    \\as a semantic alternative to `<ul>`, but treated by browsers
    \\(and exposed through the accessibility tree) as no different
    \\than `<ul>`. It represents an unordered list of items (which are
    \\represented by `<li>` elements).
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/menu)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-menu-element)
    ,
};
