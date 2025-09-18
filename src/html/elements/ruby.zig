const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Ast = @import("../Ast.zig");
const root = @import("../../root.zig");
const Span = root.Span;
const Language = root.Language;
const Element = @import("../Element.zig");
const Categories = Element.Categories;
const Model = Element.Model;
const CompletionMode = Element.CompletionMode;
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;

pub const ruby: Element = .{
    .tag = .ruby,
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
    \\The `<ruby>` HTML element represents small annotations that are
    \\rendered above, below, or next to base text, usually used for
    \\showing the pronunciation of East Asian characters. It can also
    \\be used for annotating other kinds of text, but this usage is
    \\less common.
    \\
    \\The term ruby originated as a unit of measurement used by
    \\typesetters, representing the smallest size that text can be
    \\printed on newsprint while remaining legible.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/ruby)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-ruby-element)
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
) error{OutOfMemory}!void {
    _ = seen_attrs;
    _ = seen_ids;
    const parent = nodes[parent_idx];
    const parent_span = parent.span(src);

    var state: union(enum) { phrasing, rp_start: u32, rp_rt: u32, rp_end } = .phrasing;
    var child_idx = parent.first_child_idx;
    while (child_idx != 0) {
        const child = nodes[child_idx];
        defer child_idx = child.next_idx;
        switch (child.kind) {
            .___, .comment, .text => continue,
            else => {},
        }

        state: switch (state) {
            .phrasing => switch (child.kind) {
                .rt => {},
                .rp => {
                    state = .{ .rp_start = child_idx };
                    continue :state .{ .rp_start = child_idx };
                },
                else => {
                    if (ruby.modelRejects(
                        nodes,
                        src,
                        parent,
                        parent_span,
                        &Element.all.get(child.kind),
                        child.model,
                    )) |rejection| {
                        try errors.append(gpa, .{
                            .tag = .{
                                .invalid_nesting = .{
                                    .span = rejection.span,
                                    .reason = rejection.reason,
                                },
                            },
                            .main_location = child.span(src),
                            .node_idx = child_idx,
                        });
                        continue;
                    }

                    if (child.first_child_idx == 0) continue;
                    const stop = child.stop(nodes);
                    var descendant_idx = child.first_child_idx;
                    while (descendant_idx != stop) : (descendant_idx += 1) {
                        const descendant = nodes[descendant_idx];
                        if (descendant.kind == .ruby) try errors.append(gpa, .{
                            .tag = .{ .invalid_nesting = .{ .span = parent_span } },
                            .main_location = descendant.span(src),
                            .node_idx = descendant_idx,
                        });
                    }
                },
            },
            .rp_start => switch (child.kind) {
                .rp => {},
                .rt => state = .{ .rp_rt = child_idx },
                else => try errors.append(gpa, .{
                    //missing rt
                    .tag = .{
                        .invalid_nesting = .{
                            .span = parent_span,
                            .reason = "the first <rp> of a group must be followed by <rt><rp>",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
            },
            .rp_rt => |rt_idx| switch (child.kind) {
                .rp => state = .rp_end,
                else => try errors.append(gpa, .{
                    // missing rp
                    .tag = .{
                        .wrong_sibling_sequence = .{
                            .span = nodes[rt_idx].span(src),
                            .reason = "<rt> must be followed by one <rp>",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
            },
            .rp_end => switch (child.kind) {
                .rt => state = .{ .rp_rt = child_idx },
                else => {
                    state = .phrasing;
                    continue :state .phrasing;
                },
            },
        }
    }

    switch (state) {
        else => {},
        .rp_start => |rp_idx| {
            const child_span = nodes[rp_idx].span(src);
            try errors.append(gpa, .{
                // missing rt
                .tag = .{
                    .wrong_sibling_sequence = .{
                        .span = child_span,
                        .reason = "the first <rp> of a group must be followed by <rt><rp>",
                    },
                },
                .main_location = child_span,
                .node_idx = child_idx,
            });
        },
        .rp_rt => |rt_idx| {
            const child_span = nodes[rt_idx].span(src);
            try errors.append(gpa, .{
                // missing rt
                .tag = .{
                    .wrong_sibling_sequence = .{
                        .span = child_span,
                        .reason = "<rt> must be followed by one <rp>",
                    },
                },
                .main_location = child_span,
                .node_idx = child_idx,
            });
        },
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

    const parent = ast.nodes[parent_idx];

    var state: union(enum) { phrasing, rp_start, rp_rt, rp_end } = .phrasing;
    var first_kind_after_offset: Ast.Kind = .root;
    var child_idx = parent.first_child_idx;
    while (child_idx != 0) {
        const child = ast.nodes[child_idx];
        defer child_idx = child.next_idx;
        switch (child.kind) {
            .___, .comment, .text => continue,
            else => {},
        }

        if (child.open.start > offset) {
            first_kind_after_offset = child.kind;
            break;
        }

        switch (state) {
            .phrasing => switch (child.kind) {
                .rp => state = .rp_start,
                else => {},
            },
            .rp_start => switch (child.kind) {
                .rt => state = .rp_rt,
                else => {},
            },
            .rp_rt => switch (child.kind) {
                .rp => state = .rp_end,
                else => {},
            },
            .rp_end => switch (child.kind) {
                .rt => state = .rp_rt,
                else => {},
            },
        }
    }

    return switch (state) {
        .phrasing, .rp_end => Element.simpleCompletions(
            arena,
            &.{ .rt, .rp, .ruby },
            ruby.model.content,
            .none,
            .{},
        ),
        .rp_start => &.{
            .{ .label = "rt", .desc = comptime Element.all.get(.rt).desc },
        },
        .rp_rt => &.{
            .{ .label = "rp", .desc = comptime Element.all.get(.rp).desc },
        },
    };
}
