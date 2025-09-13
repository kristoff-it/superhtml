const std = @import("std");
const Element = @import("../Element.zig");

pub const svg: Element = .{
    .tag = .svg,
    .model = .{
        .categories = .{ .flow = true },
        .content = .none,
    },
    .meta = .{
        .categories_superset = .{ .flow = true },
    },
    .attributes = .manual, // we just don't do it
    .content = .model,
    .desc =
    \\The `<svg>` SVG element is a container that defines a new
    \\coordinate system and viewport. It is used as the outermost
    \\element of SVG documents, but it can also be used to embed an
    \\SVG fragment inside an SVG or HTML document.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/SVG/Reference/Element/svg)
    \\ - [SVG Spec](https://svgwg.org/svg2-draft/struct.html#NewDocument)
    ,
};
