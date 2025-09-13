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

pub const footer: Element = .{
    .tag = .footer,
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
    \\The `<footer>` HTML element represents a footer for its nearest
    \\ancestor sectioning content or sectioning root element. A `<footer>`
    \\typically contains information about the author of the section,
    \\copyright data or links to related documents.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/footer)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-footer-element)
    ,
};
