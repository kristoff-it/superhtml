const std = @import("std");
const Element = @import("../Element.zig");

pub const comment: Element = .{
    .tag = .comment,
    .model = .{
        .categories = .none,
        .content = .none,
    },
    .meta = .{ .categories_superset = .none },
    .attributes = .static,
    .content = .model,
    .desc = "An HTML comment.",
};
