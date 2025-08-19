const std = @import("std");
const Element = @import("../Element.zig");
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;

pub const extend: Element = .{
    .tag = .extend,
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

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "template",
        .model = .{
            .rule = .not_empty,
            .desc = "",
        },
    },
});
