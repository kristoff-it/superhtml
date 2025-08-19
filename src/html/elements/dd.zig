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

pub const dd: Element = .{
    .tag = .dd,
    .model = .{
        .categories = .none,
        .content = .{ .flow = true },
    },
    .meta = .{ .categories_superset = .none },
    .attributes = .static,
    .content = .model,
    .desc =
    \\The `<dd>` HTML element provides the description, definition,
    \\or value for the preceding term (`<dt>`) in a description list
    \\(`<dl>`).
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/dd)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-dd-element)
    ,
};
