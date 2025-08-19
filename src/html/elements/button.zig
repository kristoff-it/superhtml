const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../../root.zig");
const Span = root.Span;
const Ast = @import("../Ast.zig");
const Content = Ast.Node.Categories;
const Element = @import("../Element.zig");
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;

pub const button: Element = .{
    .tag = .button,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
            .interactive = true,
        },
        .content = .{
            .phrasing = true,
        },
    },
    .meta = .{
        .categories_superset = .{
            .flow = true,
            .phrasing = true,
            .interactive = true,
        },
        .content_reject = .{
            .interactive = true,
        },
        .extra_reject = .{
            .tabindex = true,
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
    \\The `<button>` HTML element is an interactive element activated by a user with
    \\a mouse, keyboard, finger, voice command, or other assistive
    \\technology. Once activated, it then performs an action, such as
    \\submitting a form or opening a dialog. By default, HTML buttons are
    \\presented in a style resembling the platform the user agent runs on,
    \\but you can change buttons' appearance with CSS.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/button)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-button-element)
    ,
};

const temp: Attribute = .{
    .rule = .any,
    .desc = "#temp a attribute#",
};

pub const attributes: AttributeSet = .init(&.{
    .{ .name = "command", .model = temp },
    .{ .name = "commandfor", .model = temp },
    .{ .name = "disabled", .model = temp },
    .{ .name = "form", .model = temp },
    .{ .name = "formaction", .model = temp },
    .{ .name = "formenctype", .model = temp },
    .{ .name = "formmethod", .model = temp },
    .{ .name = "formnovalidate", .model = temp },
    .{ .name = "formtarget", .model = temp },
    .{ .name = "name", .model = temp },
    .{ .name = "popovertarget", .model = temp },
    .{ .name = "popovertargetaction", .model = temp },
    .{ .name = "type", .model = temp },
    .{ .name = "value", .model = temp },
});

pub fn validateContent(
    gpa: Allocator,
    nodes: []const Ast.Node,
    errors: *std.ArrayListUnmanaged(Ast.Error),
    src: []const u8,
    parent_idx: u32,
) error{OutOfMemory}!void {
    const parent = nodes[parent_idx];
    const parent_span = parent.startTagIterator(src, .html).name_span;
    const first_child_idx = parent.first_child_idx;
    if (first_child_idx == 0) return;
    const stop_idx = parent.stop(nodes);

    // If the element is the first child of a select element, then it may also
    // have zero or one descendant selectedcontent element.
    const can_have_selectedcontent = blk: {
        if (parent.parent_idx == 0) break :blk false;
        const granpa = nodes[parent.parent_idx];
        break :blk granpa.kind == .select and
            granpa.first_child_idx == parent_idx;
    };

    var seen_selectedcontent: ?Span = null;
    var next_idx = first_child_idx;
    while (next_idx < stop_idx) {
        const node_idx = next_idx;
        const node = nodes[next_idx];

        if (node.kind == .___) {
            next_idx = node.stop(nodes);
            continue;
        } else if (node.kind == .svg or node.kind == .math) {
            next_idx = node.stop(nodes);
        } else {
            next_idx += 1;
            if (!node.kind.isElement()) continue;
        }

        const node_span = node.startTagIterator(src, .html).name_span;

        if (node.kind == .selectedcontent) {
            if (!can_have_selectedcontent) {
                try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = parent_span,
                            .reason = "only allowed when button is the first child of a select",
                        },
                    },
                    .main_location = node_span,
                    .node_idx = node_idx,
                });
                continue;
            }

            if (seen_selectedcontent) |sc| {
                try errors.append(gpa, .{
                    .tag = .{
                        .duplicate_child = .{
                            .span = sc,
                            .reason = "button can only have one selectedcontent descendant",
                        },
                    },
                    .main_location = node_span,
                    .node_idx = node_idx,
                });
                continue;
            }

            seen_selectedcontent = node_span;
            // continue validation of extra

        }

        if (button.modelRejects(
            nodes,
            src,
            parent,
            parent_span,
            &Element.all.get(node.kind),
            node.model,
        )) |rejection| {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_nesting = .{
                        .span = rejection.span,
                        .reason = rejection.reason,
                    },
                },
                .main_location = node_span,
                .node_idx = node_idx,
            });
            continue;
        }
    }
}
fn completionsContent(
    arena: Allocator,
    ast: Ast,
    src: []const u8,
    node_idx: u32,
    offset: u32,
) error{OutOfMemory}![]const Ast.Completion {
    _ = arena;
    _ = ast;
    _ = src;
    _ = node_idx;
    _ = offset;
    return &.{};
}
