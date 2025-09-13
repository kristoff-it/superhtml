const std = @import("std");
const Element = @import("../Element.zig");

pub const selectedcontent: Element = .{
    .tag = .selectedcontent,
    .model = .{
        .categories = .none,
        .content = .none,
    },
    .meta = .{ .categories_superset = .none },
    .attributes = .static,
    .content = .model,
    .desc =
    \\The `<selectedcontent>` HTML is used inside a `<select>` element
    \\to display the contents of its currently selected `<option>`
    \\within its first child `<button>`. This enables you to style
    \\all parts of a `<select>` element, referred to as "customizable
    \\selects".
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/selectedcontent)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/grouping-content.html#the-selectedcontent-element)
    ,
};
