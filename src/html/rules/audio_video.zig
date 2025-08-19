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
    ancestor_rule_idx: u32,
    parent_idx: u32,
) ![]const []const u8 {
    var state: enum { source, track, rest } = .source;

    const first_child_idx = nodes[parent_idx].first_child_idx;
    if (first_child_idx != 0) {
        const stop_idx = blk: {
            var cur = nodes[parent_idx];
            while (true) {
                if (cur.next_idx != 0) break :blk cur.next_idx;
                if (cur.parent_idx == 0) break :blk nodes.len;
                cur = nodes[cur.parent_idx];
            }
        };
        assert(stop_idx > first_child_idx);
        var cur_idx = first_child_idx;
        while (cur_idx != stop_idx) : (cur_idx += 1) {
            const n = nodes[cur_idx];

            switch (n.kind) {
                .element, .element_void => {},
                else => continue,
            }

            var tt: Tokenizer = .{
                .idx = n.open.start,
                .return_attrs = true,
                .language = language,
            };

            const span = tt.next(src[0..n.open.end]).?.tag_name;
            const name = span.slice(src);

            state: switch (state) {
                .source => {
                    if (!std.ascii.eqlIgnoreCase(name, "source")) {
                        state = .track;
                        continue :state .track;
                    }
                },
                .track => {
                    if (!std.ascii.eqlIgnoreCase(name, "track")) {
                        state = .rest;
                        break;
                    }
                },
                .rest => unreachable,
            }
        }
    }
    // Assumes that the parent cannot suggest 'source' and
    // 'track', since media elements cannot be nested.
    const suggestions = if (Ast.transparentAncestorRule(
        nodes,
        src,
        language,
        nodes[ancestor_rule_idx].parent_idx,
    )) |ancestor| blk: {
        const r: *const Rule = switch (ancestor.tag) {
            .transparent => unreachable,
            inline else => |tag| &@field(rules, @tagName(tag)),
        };
        break :blk switch (r.*) {
            .simple => |simple| try simple.completions(arena),
            .custom => |custom| try custom.completions(
                arena,
                nodes,
                src,
                language,
                ancestor.idx,
                parent_idx,
            ),
        };
    } else &.{};

    const lt = struct {
        fn lt(_: void, lhs: []const u8, rhs: []const u8) bool {
            return std.mem.lessThan(u8, lhs, rhs);
        }
    }.lt;

    const all_suggestions = switch (state) {
        .source => blk: {
            const all = try arena.alloc([]const u8, suggestions.len + 2);
            @memcpy(all[2..], suggestions);
            all[0] = "source";
            all[1] = "track";
            break :blk all;
        },
        .track => blk: {
            const all = try arena.alloc([]const u8, suggestions.len + 1);
            @memcpy(all[1..], suggestions);
            all[0] = "track";
            break :blk all;
        },
        .rest => try arena.dupe([]const u8, suggestions),
    };

    const offset: usize = switch (state) {
        .source => 2,
        .track => 1,
        .rest => 0,
    };

    std.mem.sort([]const u8, all_suggestions[offset..], {}, lt);

    return all_suggestions;
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
) error{OutOfMemory}!void {
    // If the element has a src attribute: zero or more track elements, then transparent, but with no media element descendants.
    // If the element does not have a src attribute: zero or more source elements, then zero or more track elements, then transparent, but with no media element descendants.
    assert(parent_idx != 0);

    if (first_child_idx != 0) {
        const stop_idx = blk: {
            var cur = nodes[parent_idx];
            while (true) {
                if (cur.next_idx != 0) break :blk cur.next_idx;
                if (cur.parent_idx == 0) break :blk nodes.len;
                cur = nodes[cur.parent_idx];
            }
        };
        assert(stop_idx > first_child_idx);

        var state: enum { source, track, rest } = .source;
        var cur_idx = first_child_idx;
        while (cur_idx != stop_idx) : (cur_idx += 1) {
            const n = nodes[cur_idx];

            switch (n.kind) {
                .element, .element_void => {},
                else => continue,
            }

            var tt: Tokenizer = .{
                .idx = n.open.start,
                .return_attrs = true,
                .language = language,
            };

            const span = tt.next(src[0..n.open.end]).?.tag_name;
            const name = span.slice(src);

            state: switch (state) {
                .source => {
                    if (!std.ascii.eqlIgnoreCase(name, "source")) {
                        state = .track;
                        continue :state .track;
                    }
                },
                .track => {
                    if (std.ascii.eqlIgnoreCase(name, "source")) {
                        try errors.append(.{
                            .tag = .{
                                .invalid_nesting = .{
                                    .span = parent_span,
                                    .reason = "source elements must be above track elements",
                                },
                            },
                            .main_location = span,
                            .node_idx = cur_idx,
                        });
                        continue;
                    }

                    if (!std.ascii.eqlIgnoreCase(name, "track")) {
                        state = .rest;
                        continue :state .rest;
                    }
                    continue;
                },
                .rest => {
                    if (std.ascii.eqlIgnoreCase(name, "source")) {
                        try errors.append(.{
                            .tag = .{
                                .invalid_nesting = .{
                                    .span = parent_span,
                                    .reason = "source elements must be above track elements",
                                },
                            },
                            .main_location = span,
                            .node_idx = cur_idx,
                        });
                        continue;
                    }

                    if (std.ascii.eqlIgnoreCase(name, "track")) {
                        try errors.append(.{
                            .tag = .{
                                .invalid_nesting = .{
                                    .span = parent_span,
                                    .reason = "track elements must be between source and all other elements",
                                },
                            },
                            .main_location = span,
                            .node_idx = cur_idx,
                        });
                        continue;
                    }

                    if (std.ascii.eqlIgnoreCase(name, "audio") or
                        std.ascii.eqlIgnoreCase(name, "video"))
                    {
                        try errors.append(.{
                            .tag = .{
                                .invalid_nesting = .{
                                    .span = parent_span,
                                },
                            },
                            .main_location = span,
                            .node_idx = cur_idx,
                        });
                        continue;
                    }

                    // TODO: this is wrong, we need to do the
                    //       above test for all children, not
                    //       just the first one that gets us
                    //       into this state.

                    if (Ast.transparentAncestorRule(
                        nodes,
                        src,
                        language,
                        nodes[ancestor_rule_idx].parent_idx,
                    )) |ancestor| {
                        const r: Rule = switch (ancestor.tag) {
                            .transparent => unreachable,
                            inline else => |tag| @field(rules, @tagName(tag)),
                        };
                        switch (r) {
                            .simple => |simple| try simple.validate(
                                nodes,
                                errors,
                                src,
                                language,
                                ancestor.span,
                                parent_idx,
                                cur_idx,
                            ),
                            .custom => |custom| try custom.validate(
                                nodes,
                                errors,
                                src,
                                language,
                                ancestor.idx,
                                ancestor.span,
                                parent_idx,
                                cur_idx,
                            ),
                        }
                    }
                },
            }
        }
    }
}
