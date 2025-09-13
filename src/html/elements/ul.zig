const std = @import("std");
const Allocator = std.mem.Allocator;
const Tokenizer = @import("../Tokenizer.zig");
const Ast = @import("../Ast.zig");
const Element = @import("../Element.zig");
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;

pub const ul: Element = .{
    .tag = .ul,
    .model = .{
        .categories = .{ .flow = true },
        .content = .none,
    },
    .meta = .{
        .categories_superset = .{ .flow = true },
    },
    .attributes = .static,
    .content = .{
        .simple = .{
            .extra_children = &.{ .li, .script, .template },
        },
    },
    .desc =
    \\The `<ul>` HTML element represents an unordered list of items,
    \\typically rendered as a bulleted list.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/ul)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-ul-element)
    ,
};
