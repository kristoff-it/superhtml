const std = @import("std");
const Element = @import("../Element.zig");

pub const summary: Element = .{
    .tag = .summary,
    .model = .{
        .categories = .none,
        .content = .{ .phrasing = true },
    },
    .meta = .{ .categories_superset = .none },
    .attributes = .static,
    .content = .{
        .simple = .{
            .extra_children = &.{ .h1, .h2, .h3, .h4, .h5, .h6, .hgroup },
        },
    },
    .desc =
    \\The `<summary>` HTML element specifies a summary, caption, or legend
    \\for a `<details>` element's disclosure box. Clicking the `<summary>`
    \\element toggles the state of the parent `<details>` element open
    \\and closed.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/summary)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/grouping-content.html#the-summary-element)
    ,
};
