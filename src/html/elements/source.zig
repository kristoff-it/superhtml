const std = @import("std");
const Allocator = std.mem.Allocator;
const Element = @import("../Element.zig");
const AttributeSet = @import("../Attribute.zig").AttributeSet;

pub const source: Element = .{
    .tag = .source,
    .model = .{
        .categories = .none,
        .content = .none,
    },
    .meta = .{
        .categories_superset = .none,
    },
    .attributes = .static,
    .content = .model,
    .desc =
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/u)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-u-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "src",
        .model = .{
            .rule = .any,
            .desc = "Specifies the URL of the media resource.",
            .only_under = &.{ .audio, .video },
            .required = true,
        },
    },
    .{
        .name = "type",
        .model = .{
            .rule = .mime,
            .desc =
            \\Specifies the MIME media type, optionally including a `codecs` parameter.
            ,
        },
    },
    .{
        .name = "media",
        .model = .{
            .rule = .any,
            .desc = "Specifies the media query for the resource's intended media.",
        },
    },
    .{ .name = "srcset", .model = .{
        .rule = .any,
        .desc = "",
    } },
    .{ .name = "sizes", .model = .{
        .rule = .any,
        .desc = "",
    } },
    .{ .name = "width", .model = .{
        .rule = .any,
        .desc = "",
    } },
    .{ .name = "height", .model = .{
        .rule = .any,
        .desc = "",
    } },
});
