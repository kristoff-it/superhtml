const std = @import("std");
const Element = @import("../Element.zig");

pub const thead: Element = .{
    .tag = .thead,
    .model = .{
        .categories = .none,
        .content = .none,
    },
    .meta = .{ .categories_superset = .none },
    .attributes = .static,
    .content = .{
        .simple = .{
            .extra_children = &.{ .tr, .script, .template },
        },
    },
    .desc =
    \\The `<thead>` HTML element encapsulates a set of table rows (`<tr>`
    \\elements), indicating that they comprise the head of a table with
    \\information about the table's columns. This is usually in the form
    \\of column headers (`<th>` elements).
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/thead)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/grouping-content.html#the-thead-element)
    ,
};
