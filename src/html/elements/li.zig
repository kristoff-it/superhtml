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

pub const li: Element = .{
    .tag = .li,
    .model = .{
        .categories = .none,
        .content = .{ .flow = true },
    },
    .meta = .{ .categories_superset = .none },
    .attributes = .{ .dynamic = validate },
    .content = .model,
    .desc =
    \\The `<li>` HTML element is used to represent an item in a list. It
    \\must be contained in a parent element: an ordered list (`<ol>`),
    \\an unordered list (`<ul>`), or a menu (`<menu>`). In menus and
    \\unordered lists, list items are usually displayed using bullet
    \\points. In ordered lists, they are usually displayed with an
    \\ascending counter on the left, such as a number or letter.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/li)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-li-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "value",
        .model = .{
            .rule = .manual,
            .desc = "This integer attribute indicates the current ordinal value of the list item as defined by the `<ol>` element. The only allowed value for this attribute is a number, even if the list is displayed with Roman numerals or letters. List items that follow this one continue numbering from the value set. This attribute has no meaning for unordered lists (`<ul>`) or for menus (`<menu>`).",
        },
    },
});

fn validate(
    gpa: Allocator,
    errors: *std.ArrayListUnmanaged(Ast.Error),
    src: []const u8,
    nodes: []const Ast.Node,
    parent_idx: u32,
    node_idx: u32,
    vait: *Attribute.ValidatingIterator,
) error{OutOfMemory}!Model {
    // If the element is not a child of an ul or menu element: value — Ordinal value of the list item

    const under_ol = nodes[parent_idx].kind == .ol;
    while (try vait.next(gpa, src)) |attr| {
        const name = attr.name.slice(src);
        const model = if (attributes.has(name)) {
            if (under_ol) {
                const value = attr.value orelse {
                    try errors.append(gpa, .{
                        .tag = .missing_attr_value,
                        .main_location = attr.name,
                        .node_idx = node_idx,
                    });
                    continue;
                };

                const value_span = std.mem.trim(
                    u8,
                    value.span.slice(src),
                    &std.ascii.whitespace,
                );

                _ = std.fmt.parseInt(i64, value_span, 10) catch {
                    try errors.append(gpa, .{
                        .tag = .{
                            .invalid_attr_value = .{
                                .reason = "not a valid integer",
                            },
                        },
                        .main_location = attr.name,
                        .node_idx = node_idx,
                    });
                };
                continue;
            } else try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_combination = "only available when a child of <ol>",
                },
                .main_location = attr.name,
                .node_idx = node_idx,
            });
            continue;
        } else Attribute.global.get(name) orelse {
            if (Attribute.isData(name)) continue;
            try errors.append(gpa, .{
                .tag = .invalid_attr,
                .main_location = attr.name,
                .node_idx = node_idx,
            });
            continue;
        };

        try model.rule.validate(gpa, errors, src, node_idx, attr);
    }

    return li.model;
}
