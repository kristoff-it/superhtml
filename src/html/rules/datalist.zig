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

    var state: enum { either, phrasing, options } = .either;
    var child_idx = nodes[parent_idx].first_child_idx;
    while (child_idx != 0) {
        const ch = nodes[child_idx];
        defer child_idx = ch.next_idx;

        switch (state) {
            .phrasing, .options => unreachable,
            .either => switch (ch.kind) {
                .root, .element_self_closing => unreachable,
                .doctype, .comment => continue,
                .text => {
                    state = .phrasing;
                    break;
                },
                .element, .element_void => {
                    var tt: Tokenizer = .{
                        .idx = ch.open.start,
                        .return_attrs = true,
                        .language = language,
                    };

                    const span = tt.next(src[0..ch.open.end]).?.tag_name;
                    const name = span.slice(src);

                    if (std.ascii.eqlIgnoreCase(name, "option")) {
                        state = .options;
                        break;
                    } else if (tags.phrasing_tags_map.getIndex(
                        name,
                    )) |idx| {
                        const key = tags.phrasing_tags_map.keys()[idx];
                        if (key.ptr != "script".ptr and
                            key.ptr != "template".ptr)
                        {
                            state = .phrasing;
                            break;
                        }
                    }

                    continue;
                },
            },
        }
    }

    switch (state) {
        .options => return &.{ "option", "script", "template" },
        .phrasing => return tags.phrasing_tags,
        .either => {
            const all = try arena.alloc(
                []const u8,
                tags.phrasing_tags.len + 1,
            );

            all[0] = "option";
            @memcpy(all[1..], tags.phrasing_tags);
            return all;
        },
    }
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

    var state: enum { either, phrasing, options } = .either;
    var child_idx = first_child_idx;
    while (child_idx != 0) {
        const ch = nodes[child_idx];
        defer child_idx = ch.next_idx;

        switch (state) {
            .either => switch (ch.kind) {
                .comment => continue,
                .root, .element_self_closing => unreachable,
                .text => {
                    state = .phrasing;
                    continue;
                },
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
                .element, .element_void => {
                    var tt: Tokenizer = .{
                        .idx = ch.open.start,
                        .return_attrs = true,
                        .language = language,
                    };

                    const span = tt.next(src[0..ch.open.end]).?.tag_name;
                    const name = span.slice(src);

                    if (std.ascii.eqlIgnoreCase(name, "option")) {
                        state = .options;
                    } else if (tags.phrasing_tags_map.getIndex(
                        name,
                    )) |idx| {
                        const key = tags.phrasing_tags_map.keys()[idx];
                        if (key.ptr != "script".ptr and
                            key.ptr != "template".ptr)
                        {
                            state = .phrasing;
                        }
                    } else {
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

                    continue;
                },
            },
            .phrasing => switch (ch.kind) {
                .root, .element_self_closing => unreachable,
                .text, .comment => continue,
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
                .element, .element_void => {
                    var tt: Tokenizer = .{
                        .idx = ch.open.start,
                        .return_attrs = true,
                        .language = language,
                    };

                    const span = tt.next(src[0..ch.open.end]).?.tag_name;
                    const name = span.slice(src);

                    if (std.ascii.eqlIgnoreCase(name, "option")) {
                        try errors.append(.{
                            .tag = .{
                                .invalid_nesting = .{
                                    .span = parent_span,
                                    .reason = "datalist is in phrasing mode",
                                },
                            },
                            .main_location = span,
                            .node_idx = child_idx,
                        });
                    } else if (!tags.phrasing_tags_map.has(name)) {
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
                    continue;
                },
            },
            .options => switch (ch.kind) {
                .comment => continue,
                .root, .element_self_closing => unreachable,
                .text => {
                    try errors.append(.{
                        .tag = .{
                            .invalid_nesting = .{
                                .span = parent_span,
                                .reason = "datalist is in options mode",
                            },
                        },
                        .main_location = ch.open,
                        .node_idx = child_idx,
                    });
                    continue;
                },
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
                .element, .element_void => {
                    var tt: Tokenizer = .{
                        .idx = ch.open.start,
                        .return_attrs = true,
                        .language = language,
                    };

                    const span = tt.next(src[0..ch.open.end]).?.tag_name;
                    const name = span.slice(src);

                    if (!std.ascii.eqlIgnoreCase(name, "option") and
                        !std.ascii.eqlIgnoreCase(name, "script") and
                        !std.ascii.eqlIgnoreCase(name, "template"))
                    {
                        try errors.append(.{
                            .tag = .{
                                .invalid_nesting = .{
                                    .span = parent_span,
                                    .reason = "datalist is in option mode",
                                },
                            },
                            .main_location = span,
                            .node_idx = child_idx,
                        });
                    }
                    continue;
                },
            },
        }

        comptime unreachable;
    }
}
