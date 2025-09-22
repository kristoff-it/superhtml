const std = @import("std");
const Element = @import("../Element.zig");

pub const super: Element = .{
    .tag = .super,
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
