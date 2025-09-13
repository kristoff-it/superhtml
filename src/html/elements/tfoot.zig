const std = @import("std");
const Element = @import("../Element.zig");

pub const tfoot: Element = .{
    .tag = .tfoot,
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
    \\The `<tfoot>` HTML element encapsulates a set of table rows
    \\(`<tr>` elements), indicating that they comprise the foot of
    \\a table with information about the table's columns. This is
    \\usually a summary of the columns, e.g., a sum of the given
    \\numbers in a column.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/tfoot)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/grouping-content.html#the-tfoot-element)
    ,
};
