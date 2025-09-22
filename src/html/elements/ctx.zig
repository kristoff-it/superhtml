const std = @import("std");
const Element = @import("../Element.zig");

pub const ctx: Element = .{
    .tag = .ctx,
    .model = .{
        .categories = .none,
        .content = .none,
    },
    .meta = .{ .categories_superset = .none },
    .attributes = .static,
    .content = .model,
    .desc =
    \\TODO
    ,
};
