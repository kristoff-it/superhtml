const std = @import("std");
const Allocator = std.mem.Allocator;
const Element = @import("../Element.zig");
const Tokenizer = @import("../Tokenizer.zig");
const Ast = @import("../Ast.zig");
const root = @import("../../root.zig");
const Language = root.Language;
const Span = root.Span;

pub const html: Element = .{
    .tag = .html,
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
    \\The `<html>` HTML element represents the root (top-level element) of an HTML
    \\document, so it is also referred to as the root element. All other
    \\elements must be descendants of this element. There can be only one
    \\<html> element in a document.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/html)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/semantics.html#the-html-element)
    ,
};

pub fn validateContent(
    gpa: Allocator,
    nodes: []const Ast.Node,
    seen_attrs: *std.StringHashMapUnmanaged(Span),
    seen_ids: *std.StringHashMapUnmanaged(Span),
    errors: *std.ArrayListUnmanaged(Ast.Error),
    src: []const u8,
    parent_idx: u32,
) !void {
    _ = seen_attrs;
    _ = seen_ids;
    var has_head: ?Span = null;
    var has_body: ?Span = null;

    const parent = nodes[parent_idx];
    const parent_span = parent.span(src);

    var child_idx = parent.first_child_idx;
    while (child_idx != 0) {
        const child = nodes[child_idx];
        defer child_idx = child.next_idx;
        if (child.kind == .comment) continue;

        const child_span = child.span(src);

        if (child.kind != .head and child.kind != .body) {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_nesting = .{ .span = parent_span },
                },
                .main_location = child_span,
                .node_idx = child_idx,
            });
            continue;
        }

        if (child.kind == .head) {
            if (has_head) |h| {
                try errors.append(gpa, .{
                    .tag = .{
                        .duplicate_child = .{ .span = h },
                    },
                    .main_location = child_span,
                    .node_idx = child_idx,
                });
            } else {
                has_head = child_span;
                if (has_body != null) {
                    try errors.append(gpa, .{
                        .tag = .{
                            .wrong_position = .first,
                        },
                        .main_location = child_span,
                        .node_idx = child_idx,
                    });
                }
            }
        } else if (child.kind == .body) {
            if (has_body) |b| {
                try errors.append(gpa, .{
                    .tag = .{
                        .duplicate_child = .{ .span = b },
                    },
                    .main_location = child_span,
                    .node_idx = child_idx,
                });
            } else {
                has_body = child_span;
                if (has_head == null) {
                    try errors.append(gpa, .{
                        .tag = .{
                            .wrong_position = .second,
                        },
                        .main_location = child_span,
                        .node_idx = child_idx,
                    });
                }
            }
        }
    }

    if (has_head == null) try errors.append(gpa, .{
        .tag = .{
            .missing_child = .head,
        },
        .main_location = parent_span,
        .node_idx = parent_idx,
    });

    if (has_body == null) try errors.append(gpa, .{
        .tag = .{
            .missing_child = .body,
        },
        .main_location = parent_span,
        .node_idx = parent_idx,
    });
}
fn completionsContent(
    arena: Allocator,
    ast: Ast,
    src: []const u8,
    node_idx: u32,
    offset: u32,
) error{OutOfMemory}![]const Ast.Completion {
    _ = arena;
    _ = src;
    _ = offset;

    var has_head = false;
    var has_body = false;

    const parent = ast.nodes[node_idx];
    var child_idx = parent.first_child_idx;
    while (child_idx != 0) {
        const child = ast.nodes[child_idx];
        defer child_idx = child.next_idx;

        switch (child.kind) {
            .head => has_head = true,
            .body => has_body = true,
            else => if (has_head and has_body) break,
        }
    }

    const all: []const Ast.Completion = &.{
        comptime Element.all_completions.get(.head),
        comptime Element.all_completions.get(.body),
    };

    if (has_head) {
        if (has_body) return &.{};
        return all[1..];
    } else {
        if (has_body) return all[0..1];
        return all;
    }
}
