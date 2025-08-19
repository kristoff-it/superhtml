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
    var has_heading = false;
    var child_idx = nodes[parent_idx].first_child_idx;
    while (child_idx != 0) {
        const ch = nodes[child_idx];
        defer child_idx = ch.next_idx;

        switch (ch.kind) {
            .element, .element_void => {},
            else => continue,
        }

        var tt: Tokenizer = .{
            .idx = ch.open.start,
            .return_attrs = true,
            .language = language,
        };

        const span = tt.next(src[0..ch.open.end]).?.tag_name;
        const name = span.slice(src);

        if (std.ascii.eqlIgnoreCase(name, "h1") or
            std.ascii.eqlIgnoreCase(name, "h2") or
            std.ascii.eqlIgnoreCase(name, "h3") or
            std.ascii.eqlIgnoreCase(name, "h4") or
            std.ascii.eqlIgnoreCase(name, "h5") or
            std.ascii.eqlIgnoreCase(name, "h6"))
        {
            has_heading = true;
            break;
        }
    }

    if (has_heading) return &.{ "p", "script", "template" };
    return &.{
        "p",  "h1",     "h2",
        "h3", "h4",     "h5",
        "h6", "script", "template",
    };
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
    // Zero or more p elements, followed by one h1, h2, h3, h4,
    // h5, or h6 element, followed by zero or more p elements,
    // optionally intermixed with script-supporting elements.
    _ = ancestor_rule_idx;
    assert(parent_idx != 0);

    var has_heading = false;
    var child_idx = first_child_idx;
    while (child_idx != 0) {
        const ch = nodes[child_idx];
        defer child_idx = ch.next_idx;

        switch (ch.kind) {
            .element, .element_void => {},
            .doctype => {
                try errors.append(.{
                    .tag = .{
                        .invalid_nesting = .{ .span = parent_span },
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
            else => continue,
        }

        var tt: Tokenizer = .{
            .idx = ch.open.start,
            .return_attrs = true,
            .language = language,
        };

        const span = tt.next(src[0..ch.open.end]).?.tag_name;
        const name = span.slice(src);

        if (std.ascii.eqlIgnoreCase(name, "p") or
            std.ascii.eqlIgnoreCase(name, "script") or
            std.ascii.eqlIgnoreCase(name, "template"))
        {
            continue;
        }

        if (std.ascii.eqlIgnoreCase(name, "h1") or
            std.ascii.eqlIgnoreCase(name, "h2") or
            std.ascii.eqlIgnoreCase(name, "h3") or
            std.ascii.eqlIgnoreCase(name, "h4") or
            std.ascii.eqlIgnoreCase(name, "h5") or
            std.ascii.eqlIgnoreCase(name, "h6"))
        {
            if (has_heading) {
                try errors.append(.{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = parent_span,
                        },
                    },
                    .main_location = ch.open,
                    .node_idx = child_idx,
                });
            } else {
                has_heading = true;
            }
        }
    }
}
