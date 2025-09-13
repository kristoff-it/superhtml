const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../../root.zig");
const Span = root.Span;
const Tokenizer = @import("../Tokenizer.zig");
const Ast = @import("../Ast.zig");
const Content = Ast.Node.Categories;
const Element = @import("../Element.zig");
const Model = Element.Model;
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;
const log = std.log.scoped(.button);

pub const caption: Element = .{
    .tag = .caption,
    .model = .{
        .categories = .none,
        .content = .{ .flow = true },
    },
    .meta = .{
        .categories_superset = .{ .flow = true },
    },
    .attributes = .static,
    .content = .{
        .simple = .{
            .forbidden_descendants = .init(.{ .table = true }),
        },
    },
    .desc =
    \\The `<caption>` HTML element specifies the caption (or title) of a
    \\table, providing the table an accessible description.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/caption)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-caption-element)
    ,
};
