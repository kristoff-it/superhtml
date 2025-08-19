const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Tokenizer = @import("../Tokenizer.zig");
const Ast = @import("../Ast.zig");
const Node = Ast.Node;
const root = @import("../../root.zig");
const Span = root.Span;
const Language = root.Language;
const Error = Ast.Error;
const Rule = Ast.Rule;
const rules = @import("../rules.zig");
const flow = rules.flow;
const tags = @import("../tags.zig");
const TagSet = tags.Set;

pub const rule: Rule = .{
    .custom = .{
        .validate = validate,
        .completions = completions,
    },
};

fn completions(
    arena: Allocator,
    nodes: []const Node,
    src: []const u8,
    language: Language,
    rule_idx: u32,
    parent_idx: u32,
) ![]const []const u8 {
    _ = arena;
    _ = rule_idx;

    var has_head = false;
    var has_body = false;

    var child_idx: u32 = nodes[parent_idx].first_child_idx;
    while (child_idx != 0) {
        const ch = nodes[child_idx];
        defer child_idx = ch.next_idx;

        if (ch.kind != .element) continue;

        const child_name = ch_blk: {
            var ch_tt: Tokenizer = .{
                .idx = ch.open.start,
                .return_attrs = true,
                .language = language,
            };
            const child_name = ch_tt.next(
                src[0..ch.open.end],
            ).?.tag_name.slice(src);

            break :ch_blk child_name;
        };

        if (std.ascii.eqlIgnoreCase(child_name, "head")) {
            has_head = true;
        } else if (std.ascii.eqlIgnoreCase(child_name, "body")) {
            has_body = true;
        }

        if (has_head and has_body) break;
    }

    const all: []const []const u8 = &.{ "head", "body" };
    const start: usize = if (has_head) 1 else 0;
    const end: usize = if (has_body) 1 else 2;
    return all[start..end];
}

fn validate(
    nodes: []const Node,
    errors: *std.ArrayList(Error),
    src: []const u8,
    language: Language,
    rule_idx: u32,
    parent_span: Span,
    parent_idx: u32,
    first_child_idx: u32,
) !void {
    _ = rule_idx;

    var has_head: ?Span = null;
    var has_body: ?Span = null;

    var child_idx = first_child_idx;
    while (child_idx != 0) {
        const ch = nodes[child_idx];
        defer child_idx = ch.next_idx;

        switch (ch.kind) {
            .root, .element_self_closing => unreachable,
            .doctype => {
                try errors.append(.{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = parent_span,
                        },
                    },
                    .main_location = ch.open,
                    .node_idx = child_idx,
                });
                continue;
            },
            .comment => continue,
            .text => {
                try errors.append(.{
                    .tag = .{
                        .invalid_nesting = .{ .span = parent_span },
                    },
                    .main_location = ch.open,
                    .node_idx = child_idx,
                });
                continue;
            },
            .element, .element_void => {},
        }

        const child_span: Span = ch_blk: {
            var ch_tt: Tokenizer = .{
                .idx = ch.open.start,
                .return_attrs = true,
                .language = language,
            };
            break :ch_blk ch_tt.next(src[0..ch.open.end]).?.tag_name;
        };
        const child_name = child_span.slice(src);

        if (std.ascii.eqlIgnoreCase(child_name, "head")) {
            if (has_head) |h| {
                try errors.append(.{
                    .tag = .{
                        .duplicate_child = h,
                    },
                    .main_location = child_span,
                    .node_idx = child_idx,
                });
            } else {
                has_head = child_span;
                if (has_body != null) {
                    try errors.append(.{
                        .tag = .{
                            .wrong_position = .first,
                        },
                        .main_location = child_span,
                        .node_idx = child_idx,
                    });
                }
            }
        } else if (std.ascii.eqlIgnoreCase(child_name, "body")) {
            if (has_body) |b| {
                try errors.append(.{
                    .tag = .{
                        .duplicate_child = b,
                    },
                    .main_location = child_span,
                    .node_idx = child_idx,
                });
            } else {
                has_body = child_span;
                if (has_head == null) {
                    try errors.append(.{
                        .tag = .{
                            .wrong_position = .second,
                        },
                        .main_location = child_span,
                        .node_idx = child_idx,
                    });
                }
            }
        } else if (tags.all.has(child_name)) try errors.append(.{
            .tag = .{
                .invalid_nesting = .{ .span = parent_span },
            },
            .main_location = child_span,
            .node_idx = child_idx,
        });
    }

    if (has_head == null) try errors.append(.{
        .tag = .{
            .missing_child = .head,
        },
        .main_location = parent_span,
        .node_idx = parent_idx,
    });

    if (has_body == null) try errors.append(.{
        .tag = .{
            .missing_child = .body,
        },
        .main_location = parent_span,
        .node_idx = parent_idx,
    });
}
