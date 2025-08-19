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
    const all_suggestions = if (Ast.transparentAncestorRule(
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
            .simple => |*simple| try simple.completions(arena),
            .custom => |*custom| try custom.completions(
                arena,
                nodes,
                src,
                language,
                ancestor.idx,
                parent_idx,
            ),
        };
    } else return &.{};

    const lt = struct {
        fn lt(_: void, lhs: []const u8, rhs: []const u8) bool {
            return std.mem.lessThan(u8, lhs, rhs);
        }
    }.lt;

    var copy = std.ArrayListUnmanaged([]const u8).fromOwnedSlice(
        try arena.dupe([]const u8, all_suggestions),
    );

    std.mem.sort([]const u8, copy.items, {}, lt);

    var items_idx: usize = 0;
    outer: for (tags.canvas_interactive_content) |ie| {
        if (items_idx == copy.items.len) break;

        var item = copy.items[items_idx];
        while (lt({}, item, ie)) {
            items_idx += 1;
            if (items_idx == copy.items.len) break :outer;
            item = copy.items[items_idx];
        }

        if (ie.ptr == item.ptr) {
            _ = copy.orderedRemove(items_idx);
        } else {
            items_idx += 1;
        }
    }

    return copy.items;
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
    assert(parent_idx != 0);

    // Transparent, but with no interactive content descendants
    // except for a elements, img elements with usemap
    // attributes, button elements, input elements whose type
    // attribute are in the Checkbox or Radio Button states,
    // input elements that are buttons, and select elements with
    // a multiple attribute or a display size greater than 1.

    if (Ast.transparentAncestorRule(
        nodes,
        src,
        language,
        nodes[ancestor_rule_idx].parent_idx,
    )) |ancestor| {
        const r: *const Rule = switch (ancestor.tag) {
            .transparent => unreachable,
            inline else => |tag| &@field(rules, @tagName(tag)),
        };
        switch (r.*) {
            .simple => |simple| try simple.validate(
                nodes,
                errors,
                src,
                language,
                ancestor.span,
                parent_idx,
                first_child_idx,
            ),
            .custom => |custom| try custom.validate(
                nodes,
                errors,
                src,
                language,
                ancestor.idx,
                ancestor.span,
                parent_idx,
                first_child_idx,
            ),
        }
    }

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

            if (tags.canvas_interactive_content_map.has(
                name,
            )) try errors.append(.{
                .tag = .{
                    .invalid_nesting = .{ .span = parent_span },
                },
                .main_location = span,
                .node_idx = cur_idx,
            });
        }
    }
}
