const std = @import("std");
const Element = @import("../Element.zig");

pub const search: Element = .{
    .tag = .search,
    .model = .{
        .categories = .{ .flow = true },
        .content = .{ .flow = true },
    },
    .meta = .{ .categories_superset = .{ .flow = true } },
    .attributes = .static,
    .content = .model,
    .desc =
    \\The `<search>` HTML element is a container representing the parts
    \\of the document or application with form controls or other content
    \\related to performing a search or filtering operation. The `<search>`
    \\element semantically identifies the purpose of the element's
    \\contents as having search or filtering capabilities. The search or
    \\filtering functionality can be for the website or application, the
    \\current web page or document, or the entire Internet or subsection
    \\thereof.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/search)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/grouping-content.html#the-search-element)
    ,
};
