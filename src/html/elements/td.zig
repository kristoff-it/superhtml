const std = @import("std");
const Allocator = std.mem.Allocator;
const Element = @import("../Element.zig");
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;

pub const td: Element = .{
    .tag = .td,
    .model = .{
        .categories = .none,
        .content = .{ .flow = true },
    },
    .meta = .{
        .categories_superset = .none,
    },
    .attributes = .manual,
    .content = .model,
    .desc =
    \\The `<td>` HTML element defines a cell of a table that contains
    \\data and may be used as a child of the `<tr>` element.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/td)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-td-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "colspan",
        .model = .{
            .rule = .{ .non_neg_int = .{ .min = 1, .max = 1000 } },
            .desc = "Contains a non-negative integer value that indicates how many columns the data cell spans or extends. The default value is 1. User agents dismiss values higher than 1000 as incorrect, setting to the default value (1).",
        },
    },
    .{
        .name = "rowspan",
        .model = .{
            .rule = .{ .non_neg_int = .{ .min = 1, .max = 65534 } },
            .desc = "Contains a non-negative integer value that indicates for how many rows the data cell spans or extends. The default value is 1; if its value is set to 0, it extends until the end of the table grouping section (`<thead>`, `<tbody>`, `<tfoot>`, even if implicitly defined), that the cell belongs to. Values higher than 65534 are clipped to 65534.",
        },
    },
    .{
        .name = "headers",
        .model = .{
            .desc = "Contains a list of space-separated strings, each corresponding to the id attribute of the `<th>` elements that provide headings for this table cell.",
            .rule = .{
                .list = .init(.{ .custom = validateHeaders }, .many_unique, &.{
                    .{
                        .label = "ID",
                        .value = "myTh",
                        .desc = "ID of a <th> element",
                    },
                }),
            },
        },
    },
});

fn validateHeaders(value: []const u8) ?Attribute.Rule.ValueRejection {
    _ = value;
    return null;
}
