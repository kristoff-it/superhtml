const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const root = @import("../../root.zig");
const Span = root.Span;
const Ast = @import("../Ast.zig");
const Element = @import("../Element.zig");

pub const table: Element = .{
    .tag = .table,
    .model = .{
        .categories = .{ .flow = true },
        .content = .none,
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
    \\The `<table>` HTML element represents tabular data—that is,
    \\information presented in a two-dimensional table comprised of rows
    \\and columns of cells containing data.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/table)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/grouping-content.html#the-table-element)
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

    // In this order: optionally a caption element, followed by zero or more
    // colgroup elements, followed optionally by a thead element, followed by
    // either zero or more tbody elements or one or more tr elements, followed
    // optionally by a tfoot element, optionally intermixed with one or more
    // script-supporting elements.

    const parent = nodes[parent_idx];
    const parent_span = parent.span(src);

    var state: enum {
        caption,
        colgroup,
        thead,
        tbody_tr,
        tbody,
        tr,
        tfoot,
        done,
    } = .caption;
    var has_caption: u32 = 0;
    var has_thead: u32 = 0;
    var has_tfoot: u32 = 0;
    var child_idx = parent.first_child_idx;
    while (child_idx != 0) {
        const child = nodes[child_idx];
        defer child_idx = child.next_idx;
        switch (child.kind) {
            .comment, .script, .template => continue,
            else => {},
        }

        state: switch (state) {
            .caption => switch (child.kind) {
                .caption => {
                    state = .colgroup;
                    has_caption = child_idx;
                },
                .colgroup => {
                    state = .colgroup;
                },
                .thead => {
                    state = .thead;
                    continue :state .thead;
                },
                .tbody => {
                    state = .tbody;
                    continue :state .tbody;
                },
                .tr => {
                    state = .tr;
                    continue :state .tr;
                },
                .tfoot => {
                    state = .tfoot;
                    continue :state .tfoot;
                },
                else => try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = parent_span,
                            .reason = "only <caption>, <colgroup>, <thead>, <tbody>, <tr>, <tfoot>, <script>, and <template> are allowed",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
            },
            .colgroup => switch (child.kind) {
                .caption => if (has_caption == 0) try errors.append(gpa, .{
                    .tag = .{ .wrong_position = .first },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }) else try errors.append(gpa, .{
                    .tag = .{
                        .duplicate_child = .{
                            .span = nodes[has_caption].span(src),
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
                .colgroup => {},
                .thead => {
                    state = .thead;
                    continue :state .thead;
                },
                .tbody => {
                    state = .tbody;
                    continue :state .tbody;
                },
                .tr => {
                    state = .tr;
                    continue :state .tr;
                },
                .tfoot => {
                    state = .tfoot;
                    continue :state .tfoot;
                },
                else => try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = parent_span,
                            .reason = "only <colgroup>, <thead>, <tbody>, <tr>, <tfoot>, <script>, and <template> are allowed",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
            },
            .thead => switch (child.kind) {
                .caption => if (has_caption == 0) try errors.append(gpa, .{
                    .tag = .{ .wrong_position = .first },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }) else try errors.append(gpa, .{
                    .tag = .{
                        .duplicate_child = .{
                            .span = nodes[has_caption].span(src),
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
                .colgroup => try errors.append(gpa, .{
                    .tag = .{
                        .wrong_sibling_sequence = .{
                            .reason = "must be above <thead>",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
                .thead => {
                    state = .tbody_tr;
                    has_thead = child_idx;
                },
                .tbody => {
                    state = .tbody;
                    continue :state .tbody;
                },
                .tr => {
                    state = .tr;
                    continue :state .tr;
                },
                .tfoot => {
                    state = .tfoot;
                    continue :state .tfoot;
                },
                else => try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = parent_span,
                            .reason = "only <thead>, <tbody>, <tr>, <tfoot>, <script>, and <template> are allowed",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
            },
            .tbody_tr => switch (child.kind) {
                .caption => if (has_caption == 0) try errors.append(gpa, .{
                    .tag = .{ .wrong_position = .first },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }) else try errors.append(gpa, .{
                    .tag = .{
                        .duplicate_child = .{
                            .span = nodes[has_caption].span(src),
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
                .colgroup => try errors.append(gpa, .{
                    .tag = .{
                        .wrong_sibling_sequence = .{
                            .reason = "must be above <thead> (and below <caption>, if present)",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
                .thead => {
                    assert(has_thead != 0);
                    try errors.append(gpa, .{
                        .tag = .{
                            .duplicate_child = .{
                                .span = nodes[has_thead].span(src),
                            },
                        },
                        .main_location = child.span(src),
                        .node_idx = child_idx,
                    });
                },
                .tbody => {
                    state = .tbody;
                    continue :state .tbody;
                },
                .tr => {
                    state = .tr;
                    continue :state .tr;
                },
                .tfoot => {
                    state = .tfoot;
                    continue :state .tfoot;
                },
                else => try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = parent_span,
                            .reason = "only <tbody>, <tr>, <tfoot>, <script>, and <template> are allowed",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
            },
            .tbody => switch (child.kind) {
                .caption => if (has_caption == 0) try errors.append(gpa, .{
                    .tag = .{ .wrong_position = .first },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }) else try errors.append(gpa, .{
                    .tag = .{
                        .duplicate_child = .{
                            .span = nodes[has_caption].span(src),
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
                .colgroup => try errors.append(gpa, .{
                    .tag = .{
                        .wrong_sibling_sequence = .{
                            .reason = "must be above <tbody> (and <thead>, and below <caption>, if present)",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
                .thead => if (has_thead == 0) try errors.append(gpa, .{
                    .tag = .{
                        .wrong_sibling_sequence = .{
                            .reason = "must be above <tbody> (and below <colgroup> and <caption>, if present)",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }) else try errors.append(gpa, .{
                    .tag = .{
                        .duplicate_child = .{
                            .span = nodes[has_thead].span(src),
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
                .tbody => {},
                .tr => try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = parent_span,
                            .reason = "cannot mix <tbody> and <tr>",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
                .tfoot => {
                    state = .tfoot;
                    continue :state .tfoot;
                },
                else => try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = parent_span,
                            .reason = "only  <tbody>, <tfoot>, <script>, and <template> are allowed",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
            },
            .tr => switch (child.kind) {
                .caption => if (has_caption == 0) try errors.append(gpa, .{
                    .tag = .{ .wrong_position = .first },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }) else try errors.append(gpa, .{
                    .tag = .{
                        .duplicate_child = .{
                            .span = nodes[has_caption].span(src),
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
                .colgroup => try errors.append(gpa, .{
                    .tag = .{
                        .wrong_sibling_sequence = .{
                            .reason = "must be above <tr> (and <thead>, and below <caption>, if present)",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
                .thead => if (has_thead == 0) try errors.append(gpa, .{
                    .tag = .{
                        .wrong_sibling_sequence = .{
                            .reason = "must be above <tr> (and below <colgroup> and <caption>, if present)",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }) else try errors.append(gpa, .{
                    .tag = .{
                        .duplicate_child = .{
                            .span = nodes[has_thead].span(src),
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
                .tbody => try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = parent_span,
                            .reason = "cannot mix <tbody> and <tr>",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
                .tr => {},
                .tfoot => {
                    state = .tfoot;
                    continue :state .tfoot;
                },
                else => try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = parent_span,
                            .reason = "only <tr>, <tfoot>, <script>, and <template> are allowed",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
            },
            .tfoot => switch (child.kind) {
                .caption => if (has_caption == 0) try errors.append(gpa, .{
                    .tag = .{ .wrong_position = .first },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }) else try errors.append(gpa, .{
                    .tag = .{
                        .duplicate_child = .{
                            .span = nodes[has_caption].span(src),
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
                .colgroup => try errors.append(gpa, .{
                    .tag = .{
                        .wrong_sibling_sequence = .{
                            .reason = "must be above <tfoot> (and <tbody>, <tr>, and <thead>, and below <caption>, if present)",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
                .thead => if (has_thead == 0) try errors.append(gpa, .{
                    .tag = .{
                        .wrong_sibling_sequence = .{
                            .reason = "must be above <tfoot> (and <tbody>, <tr>, and below <colgroup> and <caption> if present)",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }) else try errors.append(gpa, .{
                    .tag = .{
                        .duplicate_child = .{
                            .span = nodes[has_thead].span(src),
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
                .tbody, .tr => try errors.append(gpa, .{
                    .tag = .{
                        .wrong_sibling_sequence = .{
                            .reason = "must be above <tfoot> (and below <thead>, <colgroup>, and <caption>, if present)",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
                .tfoot => {
                    state = .done;
                    has_tfoot = child_idx;
                },
                else => try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = parent_span,
                            .reason = "only <tfoot>, <script>, and <template> are allowed",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
            },
            .done => switch (child.kind) {
                .caption => if (has_caption == 0) try errors.append(gpa, .{
                    .tag = .{ .wrong_position = .first },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }) else try errors.append(gpa, .{
                    .tag = .{
                        .duplicate_child = .{
                            .span = nodes[has_caption].span(src),
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
                .colgroup => try errors.append(gpa, .{
                    .tag = .{
                        .wrong_sibling_sequence = .{
                            .reason = "must be above <tfoot> (and <tbody>, <tr>, <thead>, and below <caption>, if present)",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
                .thead => if (has_thead == 0) try errors.append(gpa, .{
                    .tag = .{
                        .wrong_sibling_sequence = .{
                            .reason = "must be above <tfoot> (and <tbody>, <tr>, and below <colgroup> and <caption>, if present)",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }) else try errors.append(gpa, .{
                    .tag = .{
                        .duplicate_child = .{
                            .span = nodes[has_thead].span(src),
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
                .tbody, .tr => try errors.append(gpa, .{
                    .tag = .{
                        .wrong_sibling_sequence = .{
                            .reason = "must be above <tfoot> (and below <thead>, <colgroup>, and <caption>, if present)",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
                .tfoot => {
                    assert(has_tfoot != 0);
                    try errors.append(gpa, .{
                        .tag = .{
                            .duplicate_child = .{
                                .span = nodes[has_tfoot].span(src),
                            },
                        },
                        .main_location = child.span(src),
                        .node_idx = child_idx,
                    });
                },
                else => try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = parent_span,
                            .reason = "only <script> and <template> are allowed",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
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
    _ = arena;
    _ = src;
    const parent = ast.nodes[parent_idx];
    var state: enum {
        caption,
        colgroup,
        thead,
        tbody_tr,
        tbody,
        tr,
        tfoot,
        done,
    } = .caption;
    var kind_after_cursor: Ast.Kind = .root;
    var child_idx = parent.first_child_idx;
    while (child_idx != 0) {
        const child = ast.nodes[child_idx];
        defer child_idx = child.next_idx;
        switch (child.kind) {
            .comment, .script, .template => continue,
            else => {},
        }

        if (child.open.start > offset) {
            kind_after_cursor = child.kind;
            break;
        }

        state: switch (state) {
            .caption => switch (child.kind) {
                .caption => {
                    state = .colgroup;
                },
                .colgroup => {
                    state = .colgroup;
                },
                .thead => {
                    state = .thead;
                    continue :state .thead;
                },
                .tbody => {
                    state = .tbody;
                    continue :state .tbody;
                },
                .tr => {
                    state = .tr;
                    continue :state .tr;
                },
                .tfoot => {
                    state = .tfoot;
                    continue :state .tfoot;
                },
                else => {},
            },
            .colgroup => switch (child.kind) {
                .thead => {
                    state = .thead;
                    continue :state .thead;
                },
                .tbody => {
                    state = .tbody;
                    continue :state .tbody;
                },
                .tr => {
                    state = .tr;
                    continue :state .tr;
                },
                .tfoot => {
                    state = .tfoot;
                    continue :state .tfoot;
                },
                else => {},
            },
            .thead => switch (child.kind) {
                .thead => {
                    state = .tbody_tr;
                },
                .tbody => {
                    state = .tbody;
                    continue :state .tbody;
                },
                .tr => {
                    state = .tr;
                    continue :state .tr;
                },
                .tfoot => {
                    state = .tfoot;
                    continue :state .tfoot;
                },
                else => {},
            },
            .tbody_tr => switch (child.kind) {
                .tbody => {
                    state = .tbody;
                    continue :state .tbody;
                },
                .tr => {
                    state = .tr;
                    continue :state .tr;
                },
                .tfoot => {
                    state = .tfoot;
                    continue :state .tfoot;
                },
                else => {},
            },
            .tbody => switch (child.kind) {
                .tfoot => {
                    state = .tfoot;
                    continue :state .tfoot;
                },
                else => {},
            },
            .tr => switch (child.kind) {
                .tfoot => {
                    state = .tfoot;
                    continue :state .tfoot;
                },
                else => {},
            },
            .tfoot => switch (child.kind) {
                .tfoot => {
                    state = .done;
                },
                else => {},
            },
            .done => break,
        }
    }

    const prefix: []const Ast.Completion = &.{
        .{ .label = "caption", .desc = comptime Element.all.get(.caption).desc },
        .{ .label = "colgroup", .desc = comptime Element.all.get(.colgroup).desc },
        .{ .label = "thead", .desc = comptime Element.all.get(.thead).desc },
        .{ .label = "tbody", .desc = comptime Element.all.get(.tbody).desc },
        .{ .label = "tr", .desc = comptime Element.all.get(.tr).desc },
        .{ .label = "tfoot", .desc = comptime Element.all.get(.tfoot).desc },
        .{ .label = "script", .desc = comptime Element.all.get(.script).desc },
        .{ .label = "template", .desc = comptime Element.all.get(.template).desc },
    };

    return switch (state) {
        .caption => switch (kind_after_cursor) {
            .caption => prefix[6..],
            .colgroup => prefix[0..2] ++ prefix[6..],
            .thead => prefix[0..2] ++ prefix[6..],
            .tbody => prefix[0..4] ++ prefix[6..],
            .tr => prefix[0..3] ++ prefix[4..5] ++ prefix[6..],
            .tfoot => prefix[0..5] ++ prefix[6..],
            else => prefix,
        },
        .colgroup => switch (kind_after_cursor) {
            .colgroup, .thead => prefix[1..2] ++ prefix[6..],
            .tbody => prefix[1..4] ++ prefix[6..],
            .tr => prefix[1..3] ++ prefix[4..5] ++ prefix[6..],
            .tfoot => prefix[1..5] ++ prefix[6..],
            else => prefix[1..],
        },
        .thead => unreachable,
        .tbody_tr => switch (kind_after_cursor) {
            .tbody => prefix[3..4] ++ prefix[6..],
            .tr => prefix[4..5] ++ prefix[6..],
            .tfoot => prefix[3..5] ++ prefix[6..],
            else => prefix[3..],
        },
        .tbody => switch (kind_after_cursor) {
            .tbody, .tfoot => prefix[3..4] ++ prefix[6..],
            else => prefix[3..4] ++ prefix[5..],
        },
        .tr => switch (kind_after_cursor) {
            .tr, .tfoot => prefix[4..5] ++ prefix[6..],
            else => prefix[4..],
        },
        .tfoot => unreachable,
        .done => prefix[6..],
    };
}
