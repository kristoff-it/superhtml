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
const log = std.log.scoped(.button);

pub const output: Element = .{
    .tag = .output,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
        },
        .content = .{ .phrasing = true },
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
    \\The `<output>` HTML element is a container element into which
    \\a site or app can inject the results of a calculation or the
    \\outcome of a user action.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/output)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-output-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "for",
        .model = .{
            .desc = "A space-separated list of other elements' ids, indicating that those elements contributed input values to (or otherwise affected) the calculation.",
            .rule = .{
                .list = .init(.{ .custom = validateFor }, .many_unique, &.{
                    .{
                        .label = "ID",
                        .value = "myElementId",
                        .desc = "[id] of an element",
                    },
                }),
            },
        },
    },
    .{
        .name = "form",
        .model = .{
            .rule = .not_empty,
            .desc =
            \\The `<form>` element to associate the output with (its form
            \\owner). The value of this attribute must be the id of a
            \\`<form>` in the same document. (If this attribute is not
            \\set, the `<output>` is associated with its ancestor `<form>`
            \\element, if any.)
            \\
            \\This attribute lets you associate `<output>` elements to
            \\`<form>`s anywhere in the document, not just inside a
            \\`<form>`. It can also override an ancestor `<form>` element.
            \\The `<output>` element's name and content are not submitted
            \\when the form is submitted.
            ,
        },
    },
    .{
        .name = "name",
        .model = .{
            .rule = .not_empty,
            .desc = "The element's name. Used in the `form.elements` API.",
        },
    },
});

fn validateFor(value: []const u8) ?Attribute.Rule.ValueRejection {
    assert(value.len != 0);
    return null;
}
