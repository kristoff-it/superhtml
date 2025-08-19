const std = @import("std");
const Element = @import("../Element.zig");

pub const nav: Element = .{
    .tag = .nav,
    .model = .{
        .categories = .{
            .flow = true,
            .sectioning = true,
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
    \\The `<nav>` HTML element represents a section of a page whose
    \\purpose is to provide navigation links, either within the current
    \\document or to other documents. Common examples of navigation
    \\sections are menus, tables of contents, and indexes.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/nav)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-nav-element)
    ,
};
