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

pub const colgroup: Element = .{
    .tag = .colgroup,
    .model = .{
        .categories = .none,
        .content = .none,
    },
    .meta = .{ .categories_superset = .none },
    .attributes = .static,
    .content = .{
        .custom = .{
            .validate = validateContent,
            .completions = completionsContent,
        },
    },
    .desc =
    \\The `<colgroup>` HTML element defines a group of columns within a table.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/colgroup)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-colgroup-element)
    ,
};
pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "span",
        .model = .{
            .rule = .{ .custom = @import("col.zig").validateSpan },
            .desc = "Specifies the number of consecutive columns the `<colgroup>` element spans. The value must be a positive integer greater than zero and lower than 1001. If not present, its default value is 1.",
        },
    },
});

pub fn validateContent(
    gpa: Allocator,
    nodes: []const Ast.Node,
    errors: *std.ArrayListUnmanaged(Ast.Error),
    src: []const u8,
    parent_idx: u32,
) error{OutOfMemory}!void {
    // If the span attribute is present: Nothing.
    // If the span attribute is absent: Zero or more col and template elements.

    const parent = nodes[parent_idx];
    const parent_span = parent.span(src);
    const has_span = blk: {
        var it = parent.startTagIterator(src, .html);
        break :blk while (it.next(src)) |attr| {
            const name = attr.name.slice(src);
            if (std.ascii.eqlIgnoreCase(name, "span")) break true;
        } else false;
    };

    var child_idx = parent.first_child_idx;
    while (child_idx != 0) {
        const child = nodes[child_idx];
        defer child_idx = child.next_idx;
        if (child.kind == .comment) continue;

        if (has_span or (child.kind != .col and child.kind != .template)) {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_nesting = .{
                        .span = parent_span,
                        .reason = if (has_span)
                            "when [span] is defined, no children are allowed"
                        else
                            "only <col> and <template> children are allowed",
                    },
                },
                .main_location = child.span(src),
                .node_idx = child_idx,
            });
        }
    }
}

fn completionsContent(
    arena: Allocator,
    ast: Ast,
    src: []const u8,
    parent_idx: u32,
    offset: u32,
) error{OutOfMemory}![]const Ast.Completion {
    _ = arena;
    _ = offset;
    const parent = ast.nodes[parent_idx];
    const has_span = blk: {
        var it = parent.startTagIterator(src, .html);
        break :blk while (it.next(src)) |attr| {
            const name = attr.name.slice(src);
            if (std.ascii.eqlIgnoreCase(name, "span")) break true;
        } else false;
    };

    if (has_span) return &.{};

    return &.{
        .{ .label = "col", .desc = comptime Element.all.get(.col).desc },
        .{ .label = "template", .desc = comptime Element.all.get(.template).desc },
    };
}
