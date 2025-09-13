const std = @import("std");
const Element = @import("../Element.zig");

pub const tr: Element = .{
    .tag = .tr,
    .model = .{
        .categories = .none,
        .content = .none,
    },
    .meta = .{ .categories_superset = .none },
    .attributes = .static,
    .content = .{
        .simple = .{
            .extra_children = &.{ .td, .th, .script, .template },
        },
    },
    .desc =
    \\The `<tr>` HTML element defines a row of cells in a table. The
    \\row's cells can then be established using a mix of `<td>` (data
    \\cell) and `<th>` (header cell) elements.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/tr)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-tr-element)
    ,
};
