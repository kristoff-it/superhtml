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
const log = std.log.scoped(.details);

pub const header: Element = .{
    .tag = .header,
    .model = .{
        .categories = .{ .flow = true },
        .content = .{ .flow = true },
    },
    .meta = .{
        .categories_superset = .{ .flow = true },
    },
    .attributes = .static,
    .content = .{
        .simple = .{
            .forbidden_children = &.{ .header, .footer },
        },
    },
    .desc =
    \\The `<header>` HTML element represents introductory content,
    \\typically a group of introductory or navigational aids. It may
    \\contain some heading elements but also a logo, a search form, an
    \\author name, and other elements.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/header)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-header-element)
    ,
};
