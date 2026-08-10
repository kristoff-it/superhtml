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
        .categories = .{
            .flow = true,
            .phrasing = true,
        },
        .content = .none,
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
    \\The `<math>` MathML element is the top-level MathML element, used
    \\to write a single mathematical formula. It can be placed in HTML
    \\content where flow content is permitted.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/MathML/Reference/Element/math)
    \\ - [MathML Spec](https://w3c.github.io/mathml-core/#the-top-level-math-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "display",
        .model = .{
            .rule = .{
                .list = .init(.none, .one, &.{
                    .{
                        .label = "block",
                        .desc = "Element will be displayed in its own block outside the current span of text.",
                    },
                    .{
                        .label = "inline",
                        .desc = "(default) Element will be displayed inside the current span of text.",
                    },
                }),
            },
            .desc = "The `display` attribute is an enumerated attribute that specifies how the enclosed MathML markup should be rendered. Defaults to 'inline' if missing or invalid. ",
        },
    },
    .{
        .name = "alttext",
        .model = .{
            .rule = .any,
            .desc = "The `alttext` attribute provides a text-based description of the mathematical content.",
        },
    },
});

test "math - bad display attribute" {
    const case = "<math " ++
    \\display="bad"
    ++ "></math>\n";
    const ast = try Ast.init(std.testing.allocator, case, .html, false);
    defer ast.deinit(std.testing.allocator);
    try std.testing.expect(1 == ast.errors.len);
}

test "math - display attribute" {
    const case = "<math " ++
    \\display="block"
    ++ "></math>\n";
    const ast = try Ast.init(std.testing.allocator, case, .html, false);
    defer ast.deinit(std.testing.allocator);
    try std.testing.expect(0 == ast.errors.len);
}
test "math - alttext attribute" {
    const case = "<math " ++
    \\alttext="x equals y sqaured"
    ++ "></math>\n";
    const ast = try Ast.init(std.testing.allocator, case, .html, false);
    defer ast.deinit(std.testing.allocator);
    try std.testing.expect(0 == ast.errors.len);
}

test "math display - completion" {
    const case = "<math " ++
    \\display=""
    ++ "></math>\n";
    const ast = try Ast.init(std.testing.allocator, case, .html, false);
    defer ast.deinit(std.testing.allocator);

    var arena: std.heap.ArenaAllocator= .init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const comp = try ast.completions(alloc,case, 14);
    const expected = "inline";
    try std.testing.expectEqualStrings(expected,comp[1].label);
    try std.testing.expect(2 == comp.len);}
