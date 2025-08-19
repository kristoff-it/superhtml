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
    // Flow content, but with no heading content descendants, no sectioning content descendants, and no header, footer, or address element descendants.
    _ = ancestor_rule_idx;
    assert(parent_idx != 0);
    try flow.simple.validate(
        nodes,
        errors,
        src,
        language,
        parent_span,
        parent_idx,
        first_child_idx,
    );

    const bad_descendants: []const []const u8 = &.{
        "address",
        "article",
        "aside",
        "footer",
        "h1",
        "h2",
        "h3",
        "h4",
        "h5",
        "h6",
        "header",
        "hgroup",
        "nav",
        "section",
    };
    const bad_descendants_map: TagSet = comptime blk: {
        var keys: []const struct { []const u8 } = &.{};
        for (bad_descendants) |i| keys = keys ++ .{.{i}};
        break :blk TagSet.initComptime(keys);
    };

    const address_node = nodes[parent_idx];
    assert(parent_idx != 0);

    if (first_child_idx != 0) {
        const stop_idx = blk: {
            var cur = address_node;
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

            if (bad_descendants_map.has(name)) try errors.append(.{
                .tag = .{
                    .invalid_nesting = .{
                        .span = parent_span,
                        .reason = "no interactive elements",
                    },
                },
                .main_location = span,
                .node_idx = cur_idx,
            });
        }
    }
}

fn completions(
    arena: Allocator,
    nodes: []const Node,
    src: []const u8,
    language: Language,
    rule_idx: u32,
    parent_idx: u32,
) ![]const []const u8 {
    _ = arena;
    _ = nodes;
    _ = src;
    _ = language;
    _ = rule_idx;
    _ = parent_idx;
    return &.{
        "a",       "abbr",     "area",     "audio",
        "b",       "bdi",      "bdo",      "blockquote",
        "br",      "button",   "canvas",   "cite",
        "code",    "data",     "datalist", "del",
        "details", "dfn",      "dialog",   "div",
        "dl",      "em",       "embed",    "fieldset",
        "figure",  "form",     "hr",       "i",
        "iframe",  "img",      "input",    "ins",
        "kbd",     "label",    "link",     "main",
        "map",     "mark",     "math",     "menu",
        "meta",    "meter",    "noscript", "object",
        "ol",      "output",   "p",        "picture",
        "pre",     "progress", "q",        "ruby",
        "s",       "samp",     "script",   "search",
        "select",  "slot",     "small",    "span",
        "strong",  "sub",      "sup",      "svg",
        "table",   "template", "textarea", "time",
        "u",       "ul",       "var",      "video",
        "wbr",
    };
}
