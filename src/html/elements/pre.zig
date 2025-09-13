const std = @import("std");
const Allocator = std.mem.Allocator;
const Element = @import("../Element.zig");
const Ast = @import("../Ast.zig");
const Content = Ast.Node.Categories;

pub const pre: Element = .{
    .tag = .pre,
    .model = .{
        .categories = .{ .flow = true },
        .content = .{ .phrasing = true },
    },
    .meta = .{ .categories_superset = .{ .flow = true } },
    .attributes = .static,
    .content = .model,
    .desc =
    \\The `<pre>` HTML element represents preformatted text which is to be
    \\presented exactly as written in the HTML file. The text is typically
    \\rendered using a non-proportional, or monospaced font.
    \\
    \\Whitespace inside this element is displayed as written, with one
    \\exception. If one or more leading newline characters are included
    \\immediately following the opening `<pre>` tag, the first newline
    \\character is stripped.
    \\
    \\`<pre>` elements' text content is parsed as HTML, so if you want
    \\to ensure that your text content stays as plain text, some syntax
    \\characters, such as `<`, may need to be escaped using their
    \\respective character references.
    \\
    \\`<pre>` elements commonly contain `<code>`, `<samp>`, and `<kbd>` elements, to
    \\represent computer code, computer output, and user input, respectively.
    \\
    \\By default, `<pre>` is a block-level element, i.e., its default
    \\display value is block.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/pre)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/grouping-content.html#the-pre-element)
    ,
};
