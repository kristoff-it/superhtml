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

pub const datalist: Element = .{
    .tag = .datalist,
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
    .content = .{
        .custom = .{
            .validate = validateContent,
            .completions = completionsContent,
        },
    },
    .desc =
    \\The `<datalist>` HTML element contains a set of `<option>` elements
    \\that represent the permissible or recommended options available to
    \\choose from within other controls.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/datalist)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-datalist-element)
    ,
};

pub fn validateContent(
    gpa: Allocator,
    nodes: []const Ast.Node,
    errors: *std.ArrayListUnmanaged(Ast.Error),
    src: []const u8,
    parent_idx: u32,
) error{OutOfMemory}!void {
    // Either: phrasing content.
    // Or: Zero or more option and script-supporting elements.

    const parent = nodes[parent_idx];
    const parent_span = parent.span(src);
    var state: enum { searching, phrasing, option } = .searching;

    var child_idx = parent.first_child_idx;
    while (child_idx != 0) {
        const child = nodes[child_idx];
        defer child_idx = child.next_idx;
        switch (child.kind) {
            .comment, .script, .template => continue,
            else => {},
        }

        switch (state) {
            .searching => if (child.kind == .option) {
                state = .option;
            },
            .option => if (child.kind != .option) try errors.append(gpa, .{
                .tag = .{
                    .invalid_nesting = .{
                        .span = parent_span,
                        .reason = "when an <option> child is present, only <option>, <script> and <template> are allowed",
                    },
                },
                .main_location = child.span(src),
                .node_idx = child_idx,
            }),
            .phrasing => {
                if (child.kind == .option) try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = parent_span,
                            .reason = "only allowed when the only children are <option>, <script> or <template>",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }) else if (!child.model.categories.phrasing) try errors.append(gpa, .{
                    .tag = .{ .invalid_nesting = .{ .span = parent_span } },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                });
            },
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

    const state: enum { searching, phrasing, option } = while (child_idx != 0) {
        const child = ast.nodes[child_idx];
        defer child_idx = child.first_child_idx;
        switch (child.kind) {
            .comment, .script, .template => continue,
            else => {},
        }

        if (child.kind == .option) {
            break .option;
        } else if (child.model.categories.phrasing) {
            break .phrasing;
        }
    } else .searching;

    return switch (state) {
        .searching => Element.simpleCompletions(
            arena,
            &.{.option},
            datalist.model.content,
            .none,
            .{},
        ),
        .option => &.{
            .{ .label = "option", .desc = comptime Element.all.get(.option).desc },
            .{ .label = "script", .desc = comptime Element.all.get(.script).desc },
            .{ .label = "template", .desc = comptime Element.all.get(.template).desc },
        },
        .phrasing => Element.simpleCompletions(
            arena,
            &.{},
            datalist.model.content,
            .none,
            .{},
        ),
    };
}
