const std = @import("std");
const Element = @import("../Element.zig");

pub const u: Element = .{
    .tag = .u,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
        },
        .content = .{
            .phrasing = true,
        },
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
    \\The `<u>` HTML element represents a span of inline text which should be
    \\rendered in a way that indicates that it has a non-textual annotation.
    \\This is rendered by default as a single solid underline, but may be
    \\altered using CSS.
    \\
    \\> This element used to be called the "Underline" element in older versions
    \\> of HTML, and is still sometimes misused in this way. To underline text,
    \\> you should instead apply a style that includes the CSS text-decoration
    \\> property set to underline.
    \\
    \\In most cases, another element is likely to be more appropriate: for
    \\marking stress emphasis, the `em` element should be used; for marking
    \\key words or phrases either the `b` element or the `mark` element
    \\should be used, depending on the context; for marking book titles, the
    \\`cite` element should be used; for labeling text with explicit textual
    \\annotations, the `ruby` element should be used; for technical terms,
    \\taxonomic designation, transliteration, or a thought, the `i` element
    \\should be used.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/u)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-u-element)
    ,
};
