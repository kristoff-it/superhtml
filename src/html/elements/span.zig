const std = @import("std");
const Allocator = std.mem.Allocator;
const Ast = @import("../Ast.zig");
const Element = @import("../Element.zig");

pub const span: Element = .{
    .tag = .span,
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
    \\The `<span>` HTML element is a generic inline container for phrasing
    \\content, which does not inherently represent anything. It can be
    \\used to group elements for styling purposes (using the `class`
    \\or `id` attributes), or because they share attribute values, such
    \\as `lang`. It should be used only when no other semantic element
    \\is appropriate. `<span>` is very much like a `<div>` element,
    \\but `<div>` is a block-level element whereas a `<span>` is an
    \\inline-level element.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/span)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/grouping-content.html#the-span-element)
    ,
};

pub fn validateContent(
    gpa: Allocator,
    nodes: []const Ast.Node,
    errors: *std.ArrayListUnmanaged(Ast.Error),
    src: []const u8,
    parent_idx: u32,
) error{OutOfMemory}!void {

    // If the element is a descendant of an option element: Zero or more option
    // element inner content elements, except div elements.
    // Otherwise: Phrasing content.

    const parent = nodes[parent_idx];
    if (parent.first_child_idx == 0) return;

    var ancestor_idx = parent.parent_idx;
    const under_option = while (ancestor_idx != 0) {
        const ancestor = nodes[ancestor_idx];
        defer ancestor_idx = ancestor.parent_idx;
        if (ancestor.kind == .option) break true;
    } else false;

    const model = if (under_option) blk: {
        var model = span;
        model.meta.content_reject.interactive = true;
        model.content = .{
            .simple = .{
                .forbidden_descendants = .init(.{
                    .datalist = true,
                    .object = true,
                }),
                .forbidden_descendants_extra = .{ .tabindex = true },
            },
        };
        break :blk model;
    } else blk: {
        var model = span;
        model.content = .model;
        break :blk model;
    };

    try model.validateContent(gpa, nodes, errors, src, parent_idx);
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

    var ancestor_idx = parent.parent_idx;
    const under_option = while (ancestor_idx != 0) {
        const ancestor = ast.nodes[ancestor_idx];
        defer ancestor_idx = ancestor.parent_idx;
        if (ancestor.kind == .option) break true;
    } else false;

    return Element.simpleCompletions(
        arena,
        &.{},
        span.model.content,
        if (under_option) .{ .interactive = true } else .none,
        if (under_option) .{
            .forbidden_descendants = .init(.{
                .datalist = true,
                .object = true,
            }),
            .forbidden_descendants_extra = .{ .tabindex = true },
        } else .{},
    );
}
