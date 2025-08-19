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

pub const dt: Element = .{
    .tag = .dt,
    .model = .{
        .categories = .none,
        .content = .{ .flow = true },
    },
    .meta = .{ .categories_superset = .none },
    .attributes = .static,
    .content = .{
        .simple = .{
            .forbidden_descendants = .init(.{
                .header = true,
                .footer = true,
                .article = true,
                .aside = true,
                .nav = true,
                .section = true,
                .h1 = true,
                .h2 = true,
                .h3 = true,
                .h4 = true,
                .h5 = true,
                .h6 = true,
                .hgroup = true,
            }),
        },
    },
    .desc =
    \\The `<dt>` HTML element specifies a term in a description or
    \\definition list, and as such must be used inside a `<dl>` element.
    \\It is usually followed by a `<dd>` element; however, multiple `<dt>`
    \\elements in a row indicate several terms that are all defined by the
    \\immediate next `<dd>` element.
    \\
    \\The subsequent `<dd>` (Description Details) element provides the
    \\definition or other related text associated with the term specified
    \\using `<dt>`.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/dt)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-dt-element)
    ,
};
