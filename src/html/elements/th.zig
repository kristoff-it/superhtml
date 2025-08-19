const std = @import("std");
const Allocator = std.mem.Allocator;
const Element = @import("../Element.zig");
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;

pub const th: Element = .{
    .tag = .th,
    .model = .{
        .categories = .none,
        .content = .{ .flow = true },
    },
    .meta = .{ .categories_superset = .none },
    .attributes = .manual,
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
    \\The `<th>` HTML element defines a cell as the header of a group
    \\of table cells and may be used as a child of the `<tr>` element.
    \\The exact nature of this group is defined by the scope and
    \\headers attributes.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/th)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-th-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "abbr",
        .model = .{
            .rule = .not_empty,
            .desc = "A short, abbreviated description of the header cell's content provided as an alternative label to use for the header cell when referencing the cell in other contexts. Some user-agents, such as screen readers, may present this description before the content itself.",
        },
    },
    .{
        .name = "colspan",
        .model = .{
            .rule = .{ .non_neg_int = .{ .min = 1, .max = 1000 } },
            .desc = "A non-negative integer value indicating how many columns the header cell spans or extends. The default value is 1. User agents dismiss values higher than 1000 as incorrect, defaulting such values to 1.",
        },
    },
    .{
        .name = "rowspan",
        .model = .{
            .rule = .{ .non_neg_int = .{ .min = 1, .max = 65534 } },
            .desc = "A non-negative integer value indicating how many rows the header cell spans or extends. The default value is 1; if its value is set to 0, the header cell will extend to the end of the table grouping section (`<thead>`, `<tbody>`, `<tfoot>`, even if implicitly defined), that the `<th>` belongs to. Values higher than 65534 are clipped at 65534.",
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
    .{
        .name = "scope",
        .model = .{
            .desc = "Defines the cells that the header (defined in the `<th>`) element relates to.",
            .rule = .{
                .list = .init(.{ .custom = validateHeaders }, .many_unique, &.{
                    .{
                        .label = "row",
                        .desc = "",
                    },
                    .{
                        .label = "col",
                        .desc = "",
                    },
                    .{
                        .label = "rowgroup",
                        .desc = "",
                    },
                    .{
                        .label = "colgroup",
                        .desc = "",
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

// A th element's scope attribute must not be in the Row Group state if the element is not anchored in a row group, nor in the Column Group state if the element is not anchored in a column group.

// A row group is a set of rows anchored at a slot (0, groupy) with a particular height such that the row group covers all the slots with coordinates (x, y) where 0 ≤ x < xwidth and groupy ≤ y < groupy+height. Row groups correspond to tbody, thead, and tfoot elements. Not every row is necessarily in a row group.

// A column group is a set of columns anchored at a slot (groupx, 0) with a particular width such that the column group covers all the slots with coordinates (x, y) where groupx ≤ x < groupx+width and 0 ≤ y < yheight. Column groups correspond to colgroup elements. Not every column is necessarily in a column group.
