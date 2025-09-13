const std = @import("std");
const Allocator = std.mem.Allocator;
const Ast = @import("../Ast.zig");
const root = @import("../../root.zig");
const Span = root.Span;
const Language = root.Language;
const Element = @import("../Element.zig");
const Categories = Element.Categories;
const Model = Element.Model;
const CompletionMode = Element.CompletionMode;
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;

pub const article: Element = .{
    .tag = .article,
    .model = .{
        .categories = .{
            .flow = true,
            .sectioning = true,
        },
        .content = .{
            .flow = true,
            .sectioning = true,
        },
    },

    .meta = .{
        .categories_superset = .{ .flow = true },
    },

    .attributes = .static,
    .content = .model,
    .desc =
    \\The `<article>` HTML element represents a self-contained composition
    \\in a document, page, application, or site, which is intended to
    \\be independently distributable or reusable (e.g., in syndication).
    \\Examples include: a forum post, a magazine or newspaper article,
    \\or a blog entry, a product card, a user-submitted comment, an
    \\interactive widget or gadget, or any other independent item of
    \\content.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/article)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-article-element)
    ,
};
