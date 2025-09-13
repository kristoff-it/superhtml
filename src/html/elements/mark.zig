const std = @import("std");
const assert = std.debug.assert;
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

pub const mark: Element = .{
    .tag = .mark,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
        },
        .content = .{ .phrasing = true },
    },
    .meta = .{
        .categories_superset = .{
            .flow = true,
            .phrasing = true,
        },
    },
    .attributes = .static,
    .content = .model,
    .desc =
    \\The `<mark>` HTML element represents text which is marked or
    \\highlighted for reference or notation purposes due to the marked
    \\passage's relevance in the enclosing context.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/mark)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-mark-element)
    ,
};
