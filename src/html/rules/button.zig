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

    const button_node = nodes[parent_idx];
    assert(parent_idx != 0);

    var allows_sc = blk: {
        if (button_node.parent_idx == 0) break :blk false;

        const n = nodes[button_node.parent_idx];
        if (n.first_child_idx != parent_idx) break :blk false;

        var tt: Tokenizer = .{
            .idx = n.open.start,
            .return_attrs = true,
            .language = language,
        };

        const span = tt.next(src[0..n.open.end]).?.tag_name;
        const name = span.slice(src);
        break :blk std.ascii.eqlIgnoreCase(name, "select");
    };

    const first_child_idx = button_node.first_child_idx;
    if (first_child_idx != 0) sc: {
        const stop_idx = blk: {
            var cur = button_node;
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

            if (std.ascii.eqlIgnoreCase(name, "selectedcontent")) {
                allows_sc = false;
                break :sc;
            }
        }
    }

    const all: []const []const u8 = &.{
        "selectedcontent", "abbr",   "area",    "audio",
        "b",               "bdi",    "bdo",     "br",
        "canvas",          "cite",   "code",    "data",
        "datalist",        "del",    "dfn",     "em",
        "i",               "img",    "input",   "ins",
        "kbd",             "link",   "map",     "mark",
        "math",            "meta",   "meter",   "noscript",
        "object",          "output", "picture", "progress",
        "q",               "ruby",   "s",       "samp",
        "script",          "slot",   "small",   "span",
        "strong",          "sub",    "sup",     "svg",
        "template",        "time",   "u",       "var",
        "video",           "wbr",
    };

    if (allows_sc) return all;
    return all[1..];
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
    // Phrasing content, but there must be no interactive content descendant and no descendant with the tabindex attribute specified. If the element is the first child of a select element, then it may also have zero or one descendant selectedcontent element.

    _ = ancestor_rule_idx;
    assert(parent_idx != 0);
    try rules.phrasing.simple.validate(
        nodes,
        errors,
        src,
        language,
        parent_span,
        parent_idx,
        first_child_idx,
    );

    const button_node = nodes[parent_idx];
    assert(parent_idx != 0);

    if (first_child_idx != 0) {
        const stop_idx = blk: {
            var cur = button_node;
            while (true) {
                if (cur.next_idx != 0) break :blk cur.next_idx;
                if (cur.parent_idx == 0) break :blk nodes.len;
                cur = nodes[cur.parent_idx];
            }
        };
        assert(stop_idx > first_child_idx);

        var allows_sc = blk: {
            if (button_node.parent_idx == 0) break :blk false;

            const n = nodes[button_node.parent_idx];
            if (n.first_child_idx != parent_idx) break :blk false;

            var tt: Tokenizer = .{
                .idx = n.open.start,
                .return_attrs = true,
                .language = language,
            };

            const span = tt.next(src[0..n.open.end]).?.tag_name;
            const name = span.slice(src);
            break :blk std.ascii.eqlIgnoreCase(name, "select");
        };

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

            if (std.ascii.eqlIgnoreCase(name, "selectedcontent")) {
                if (allows_sc) {
                    allows_sc = false;
                } else {
                    try errors.append(.{
                        .tag = .{
                            .invalid_nesting = .{ .span = parent_span },
                        },
                        .main_location = span,
                        .node_idx = cur_idx,
                    });
                }
            }

            if (tags.interactive_content_map.has(name)) try errors.append(.{
                .tag = .{
                    .invalid_nesting = .{ .span = parent_span },
                },
                .main_location = span,
                .node_idx = cur_idx,
            });
        }
    }
}
