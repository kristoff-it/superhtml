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
    _ = rule_idx;
    assert(parent_idx != 0);

    const needs_summary = blk: {
        const first_child_idx = nodes[parent_idx].first_child_idx;
        if (first_child_idx == 0) break :blk true;
        var child_idx = first_child_idx;
        while (child_idx != 0) {
            const ch = nodes[child_idx];
            defer child_idx = ch.next_idx;

            switch (ch.kind) {
                .root, .element_self_closing => unreachable,
                .comment, .doctype, .text => continue,
                .element, .element_void => {},
            }

            var tt: Tokenizer = .{
                .idx = ch.open.start,
                .return_attrs = true,
                .language = language,
            };

            const span = tt.next(src[0..ch.open.end]).?.tag_name;
            const name = span.slice(src);

            if (std.ascii.eqlIgnoreCase(name, "summary")) {
                break :blk false;
            }
        }

        break :blk true;
    };

    const all = try arena.alloc(
        []const u8,
        tags.flow_tags.keys().len + @intFromBool(needs_summary),
    );

    if (needs_summary) {
        all[0] = "summary";
    }

    @memcpy(all[@intFromBool(needs_summary)..], tags.flow_tags.keys());

    const lt = struct {
        fn lt(_: void, lhs: []const u8, rhs: []const u8) bool {
            return std.mem.lessThan(u8, lhs, rhs);
        }
    }.lt;

    std.mem.sort([]const u8, all[@intFromBool(needs_summary)..], {}, lt);
    return all;
}
fn validate(
    nodes: []const Node,
    errors: *std.ArrayList(Error),
    src: []const u8,
    language: Language,
    ancestor_rule_idx: u32,
    parent_span: Span,
    parent_idx: u32,
    first_child_idx: u32,
) !void {
    _ = ancestor_rule_idx;
    assert(parent_idx != 0);

    if (first_child_idx == 0) return;
    var first = true;
    var has_summary: ?Span = null;
    var child_idx = first_child_idx;
    while (child_idx != 0) {
        const ch = nodes[child_idx];
        defer child_idx = ch.next_idx;

        switch (ch.kind) {
            .root, .element_self_closing => unreachable,
            .comment => continue,
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
            .text => {
                first = false;
                continue;
            },
            .element, .element_void => {},
        }

        defer first = false;

        var tt: Tokenizer = .{
            .idx = ch.open.start,
            .return_attrs = true,
            .language = language,
        };

        const span = tt.next(src[0..ch.open.end]).?.tag_name;
        const name = span.slice(src);

        if (std.mem.indexOfScalar(u8, name, '-') != null) {
            continue;
        }

        if (std.ascii.eqlIgnoreCase(name, "summary")) {
            if (has_summary) |s| {
                try errors.append(.{
                    .tag = .{
                        .duplicate_child = s,
                    },
                    .main_location = span,
                    .node_idx = child_idx,
                });
            } else {
                has_summary = span;
                if (!first) {
                    try errors.append(.{
                        .tag = .{
                            .wrong_position = .first,
                        },
                        .main_location = span,
                        .node_idx = child_idx,
                    });
                }
            }
        } else if (!tags.flow_tags.has(name)) {
            if (tags.all.has(name)) {
                try errors.append(.{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = parent_span,
                        },
                    },
                    .main_location = span,
                    .node_idx = child_idx,
                });
            }
        }
    }

    if (has_summary == null) {
        try errors.append(.{
            .tag = .{
                .missing_child = .summary,
            },
            .main_location = parent_span,
            .node_idx = parent_idx,
        });
    }
}
