const std = @import("std");
const Allocator = std.mem.Allocator;
const Element = @import("../Element.zig");
const Ast = @import("../Ast.zig");
const Content = Ast.Node.Categories;

pub const h1: Element = .{
    .tag = .h1,
    .model = .{
        .categories = .{
            .flow = true,
            .heading = true,
        },
        .content = .{ .phrasing = true },
    },
    .meta = .{
        .categories_superset = .{
            .flow = true,
            .heading = true,
        },
    },
    .attributes = .static,
    .content = .model,
    .desc =
    \\The `<h1>` to `<h6>` HTML elements represent six levels of section
    \\headings. `<h1>` is the highest section level and `<h6>` is the lowest.
    \\By default, all heading elements create a block-level box in
    \\the layout, starting on a new line and taking up the full width
    \\available in their containing block.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/Heading_Elements)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/dom.html#heading-content)
    ,
};

pub const h2 = blk: {
    var h = h1;
    h.tag = .h2;
    break :blk h;
};

pub const h3 = blk: {
    var h = h1;
    h.tag = .h3;
    break :blk h;
};

pub const h4 = blk: {
    var h = h1;
    h.tag = .h4;
    break :blk h;
};

pub const h5 = blk: {
    var h = h1;
    h.tag = .h5;
    break :blk h;
};

pub const h6 = blk: {
    var h = h1;
    h.tag = .h6;
    break :blk h;
};
