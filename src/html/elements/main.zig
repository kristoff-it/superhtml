const std = @import("std");
const Allocator = std.mem.Allocator;
const Element = @import("../Element.zig");
const Ast = @import("../Ast.zig");
const Content = Ast.Node.Categories;

// A hierarchically correct main element is one whose ancestor elements are
// limited to html, body, div, form without an accessible name, and autonomous
// custom elements. Each main element must be a hierarchically correct main
// element.
//
// The above property is checked on tree construction.
//
// TODO: what is the accessible name for `form`?
pub const main: Element = .{
    .tag = .main,
    .model = .{
        .categories = .{
            .flow = true,
        },
        .content = .{
            .flow = true,
        },
    },
    .meta = .{
        .categories_superset = .{
            .flow = true,
        },
    },
    .attributes = .static,
    .content = .model,

    .desc =
    \\The `<main>` HTML element represents the dominant content of the
    \\`<body>` of a document. The main content area consists of content
    \\that is directly related to or expands upon the central topic of a
    \\document, or the central functionality of an application.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/main)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/grouping-content.html#the-main-element)
    ,
};
