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

pub const math: Element = .{
    .tag = .math,
    .model = .{
        .categories = .{ .flow = true },
        .content = .none,
    },
    .meta = .{
        .categories_superset = .{ .flow = true },
    },
    .attributes = .static,
    .content = .model,
    .desc =
    \\The `<math>` MathML element is the top-level MathML element, used
    \\to write a single mathematical formula. It can be placed in HTML
    \\content where flow content is permitted.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/MathML/Reference/Element/math)
    \\ - [MathML Spec](https://w3c.github.io/mathml-core/#the-top-level-math-element)
    ,
};
