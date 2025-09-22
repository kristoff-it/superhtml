const std = @import("std");
const Element = @import("../Element.zig");

pub const text: Element = .{
    .tag = .text,
    .model = .{
        .categories = .{
            .text = true,
            .phrasing = true,
            .flow = true,
        },
        .content = .none,
    },
    .meta = .{
        .categories_superset = .{
            .text = true,
            .phrasing = true,
            .flow = true,
        },
    },
    .attributes = .static,
    .content = .model,
    .desc = "An HTML text node",
};
