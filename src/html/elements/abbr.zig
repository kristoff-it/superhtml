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

pub const abbr: Element = .{
    .tag = .abbr,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
        },
        .content = .{ .phrasing = true },
    },

    .meta = .{
        .categories_superset = .{ .phrasing = true },
    },

    .attributes = .static,
    .content = .model,
    .desc =
    \\The `<abbr>` HTML element represents an abbreviation or acronym.
    \\
    \\When including an abbreviation or acronym, provide a full expansion
    \\of the term in plain text on first use, along with the `<abbr>`
    \\to mark up the abbreviation. This informs the user what the
    \\abbreviation or acronym means.
    \\
    \\The optional title attribute can provide an expansion for the
    \\abbreviation or acronym when a full expansion is not present.
    \\This provides a hint to user agents on how to announce/display the
    \\content while informing all users what the abbreviation means. If
    \\present, title must contain this full description and nothing else.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/abbr)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-abbr-element)
    ,
};
