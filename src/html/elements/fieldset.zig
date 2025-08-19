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
const log = std.log.scoped(.details);

pub const fieldset: Element = .{
    .tag = .fieldset,
    .model = .{
        .categories = .{ .flow = true },
        .content = .{ .flow = true },
    },
    .meta = .{
        .categories_superset = .{ .flow = true },
    },
    .attributes = .static,
    .content = .{
        .custom = .{
            .validate = validateContent,
            .completions = completionsContent,
        },
    },
    .desc =
    \\The `<fieldset>` HTML element is used to group several controls as
    \\well as labels (`<label>`) within a web form.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/fieldset)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-fieldset-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "disabled",
        .model = .{
            .rule = .bool,
            .desc = "If this Boolean attribute is set, all form controls that are descendants of the `<fieldset>`, are disabled, meaning they are not editable and won't be submitted along with the `<form>`. They won't receive any browsing events, like mouse clicks or focus-related events. By default browsers display such controls grayed out. Note that form elements inside the `<legend>` element won't be disabled.",
        },
    },
    .{
        .name = "form",
        .model = .{
            .rule = .not_empty,
            .desc = "This attribute takes the value of the id attribute of a `<form>` element you want the `<fieldset>` to be part of, even if it is not inside the form. Please note that usage of this is confusing — if you want the `<input>` elements inside the `<fieldset>` to be associated with the form, you need to use the form attribute directly on those elements. You can check which elements are associated with a form via JavaScript, using `HTMLFormElement.elements`.",
        },
    },
    .{
        .name = "name",
        .model = .{
            .rule = .not_empty,
            .desc = "The name associated with the group.",
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
    // Optionally, a legend element, followed by flow content.
    const parent = nodes[parent_idx];
    const parent_span = parent.span(src);

    var has_legend: ?Span = null;

    var child_idx = parent.first_child_idx;
    while (child_idx != 0) {
        const child = nodes[child_idx];
        defer child_idx = child.next_idx;
        switch (child.kind) {
            .text, .comment => continue,
            else => {},
        }

        if (child.kind == .legend) {
            if (has_legend) |lg| {
                try errors.append(gpa, .{
                    .tag = .{ .duplicate_child = .{ .span = lg } },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                });
            } else {
                has_legend = child.span(src);
                if (child_idx != parent.first_child_idx) {
                    try errors.append(gpa, .{
                        .tag = .{ .wrong_position = .first },
                        .main_location = has_legend.?,
                        .node_idx = child_idx,
                    });
                }
            }
        } else if (!child.model.categories.flow) {
            try errors.append(gpa, .{
                .tag = .{ .invalid_nesting = .{ .span = parent_span } },
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
    _ = src;
    _ = offset;

    const parent = ast.nodes[parent_idx];
    var child_idx = parent.first_child_idx;
    const has_legend = while (child_idx != 0) {
        const child = ast.nodes[child_idx];
        defer child_idx = child.next_idx;
        if (child.kind == .legend) break true;
    } else false;

    const prefix: []const Ast.Kind = if (has_legend) &.{} else &.{.legend};
    return Element.simpleCompletions(
        arena,
        prefix,
        fieldset.model.content,
        .none,
        .{},
    );
}
