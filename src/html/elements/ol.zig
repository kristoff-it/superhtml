const std = @import("std");
const Allocator = std.mem.Allocator;
const Tokenizer = @import("../Tokenizer.zig");
const Ast = @import("../Ast.zig");
const Element = @import("../Element.zig");
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;

pub const ol: Element = .{
    .tag = .ol,
    .model = .{
        .categories = .{ .flow = true },
        .content = .none,
    },
    .meta = .{
        .categories_superset = .{ .flow = true },
    },
    .attributes = .static,
    .content = .{
        .simple = .{
            .extra_children = &.{ .li, .script, .template },
        },
    },
    .desc =
    \\The `<ol>` HTML element represents an ordered list of items —
    \\typically rendered as a numbered list.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/ol)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-ol-element)
    ,
};
pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "reversed",
        .model = .{
            .rule = .bool,
            .desc = "This Boolean attribute specifies that the list's items are in reverse order. Items will be numbered from high to low.",
        },
    },
    .{
        .name = "start",
        .model = .{
            .rule = .{ .custom = validateStart },
            .desc = "An integer to start counting from for the list items. Always an Arabic numeral (1, 2, 3, etc.), even when the numbering type is letters or Roman numerals. For example, to start numbering elements from the letter `\"d\"` or the Roman numeral `\"iv,\"` use `start=\"4\"`.",
        },
    },
    .{
        .name = "type",
        .model = .{
            .desc = "Sets the numbering type",
            .rule = .{
                .list = .init(.none, .one, &.{
                    .{ .label = "a", .desc = "lowercase letters" },
                    .{ .label = "A", .desc = "uppercase letters" },
                    .{ .label = "i", .desc = "lowercase Roman numerals" },
                    .{ .label = "I", .desc = "uppercase Roman numerals" },
                    .{ .label = "1", .desc = "numbers (default)" },
                }),
            },
        },
    },
});

fn validateStart(
    gpa: Allocator,
    errors: *std.ArrayListUnmanaged(Ast.Error),
    src: []const u8,
    node_idx: u32,
    attr: Tokenizer.Attr,
) error{OutOfMemory}!void {
    const value = attr.value orelse return errors.append(gpa, .{
        .tag = .missing_attr_value,
        .main_location = attr.name,
        .node_idx = node_idx,
    });

    const digits = std.mem.trim(u8, value.span.slice(src), &std.ascii.whitespace);
    _ = std.fmt.parseInt(i64, digits, 10) catch return errors.append(gpa, .{
        .tag = .{ .invalid_attr_value = .{ .reason = "invalid integer" } },
        .main_location = value.span,
        .node_idx = node_idx,
    });
}
