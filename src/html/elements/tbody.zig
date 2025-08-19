const std = @import("std");
const Element = @import("../Element.zig");

pub const tbody: Element = .{
    .tag = .tbody,
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
    \\The `<tbody>` HTML element encapsulates a set of table rows (`<tr>`
    \\elements), indicating that they comprise the body of a table's
    \\(main) data.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/tbody)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/grouping-content.html#the-tbody-element)
    ,
};
