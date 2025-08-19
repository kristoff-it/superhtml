const std = @import("std");
const Element = @import("../Element.zig");
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;

pub const blockquote: Element = .{
    .tag = .blockquote,
    .model = .{
        .categories = .{ .flow = true },
        .content = .{ .flow = true },
    },
    .meta = .{
        .categories_superset = .{ .flow = true },
    },
    .attributes = .static,
    .content = .model,
    .desc =
    \\The `<blockquote>` HTML element indicates that the enclosed text
    \\is an extended quotation. Usually, this is rendered visually by
    \\indentation (see Notes for how to change it). A URL for the source
    \\of the quotation may be given using the `cite` attribute, while a
    \\text representation of the source can be given using the `<cite>`
    \\element.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/blockquote)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-blockquote-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "cite",
        .model = .{
            .rule = .{ .url = .not_empty },
            .desc =
            \\A URL that designates a source document or message for the
            \\information quoted. This attribute is intended to point
            \\to information explaining the context or the reference for
            \\the quote.
            ,
        },
    },
});
