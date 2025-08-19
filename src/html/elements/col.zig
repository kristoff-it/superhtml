const std = @import("std");
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

pub const col: Element = .{
    .tag = .col,
    .model = .{
        .categories = .none,
        .content = .none,
    },
    .meta = .{ .categories_superset = .none },
    .attributes = .static,
    .content = .model,
    .desc =
    \\The `<col>` HTML element defines one or more columns in a column
    \\group represented by its parent `<colgroup>` element. The `<col>`
    \\element is only valid as a child of a `<colgroup>` element that has
    \\no `span` attribute defined.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/col)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-col-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "span",
        .model = .{
            .rule = .{ .custom = validateSpan },
            .desc = "Specifies the number of consecutive columns the `<col>` element spans. The value must be a positive integer lower than or equal to 1000. If not present, its default value is 1.",
        },
    },
});

pub fn validateSpan(
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

    const value_slice = value.span.slice(src);
    const digits = std.mem.trim(u8, value_slice, &std.ascii.whitespace);
    if (std.fmt.parseInt(i64, digits, 10)) |num| {
        if (num <= 0) {
            return errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "integer must be positive",
                    },
                },
                .main_location = value.span,
                .node_idx = node_idx,
            });
        } else if (num > 1000) {
            return errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "integer must be <= 1000",
                    },
                },
                .main_location = value.span,
                .node_idx = node_idx,
            });
        }
    } else |_| return errors.append(gpa, .{
        .tag = .{
            .invalid_attr_value = .{
                .reason = "invalid positive integer",
            },
        },
        .main_location = value.span,
        .node_idx = node_idx,
    });
}
