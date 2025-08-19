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
    const nesting: enum { dl, option, optgroup, select, none } = blk: {
        var ancestor_idx = parent_idx;
        while (ancestor_idx != 0) {
            const ancestor = nodes[ancestor_idx];
            defer ancestor_idx = ancestor.parent_idx;

            var tt: Tokenizer = .{
                .idx = ancestor.open.start,
                .return_attrs = true,
                .language = language,
            };

            const span = tt.next(src[0..ancestor.open.end]).?.tag_name;
            const name = span.slice(src);

            if (std.ascii.eqlIgnoreCase(name, "dl")) {
                break :blk .dl;
            }
            if (std.ascii.eqlIgnoreCase(name, "option")) {
                break :blk .option;
            }
            if (std.ascii.eqlIgnoreCase(name, "optgroup")) {
                break :blk .optgroup;
            }
            if (std.ascii.eqlIgnoreCase(name, "select")) {
                break :blk .select;
            }
            continue;
        }
        break :blk .none;
    };

    const r = switch (nesting) {
        inline else => |tag| try @field(rules, @tagName(tag)),
        .none => flow,
    };

    return switch (r) {
        .simple => |simple| simple.completions(arena),
        .custom => |custom| custom.completions(
            arena,
            nodes,
            src,
            language,
            rule_idx,
            parent_idx,
        ),
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
    assert(parent_idx != 0);
    // If the element is a child of a dl element: One or more dt
    // elements followed by one or more dd elements, optionally
    // intermixed with script-supporting elements.
    //
    // Otherwise, if the element is a descendant of an option
    // element: Zero or more option element inner content
    // elements.
    //
    // Otherwise, if the element is a descendant of an optgroup
    // element: Zero or more optgroup element inner content
    // elements.
    //
    // Otherwise, if the element is a descendant of a select
    // element: Zero or more select element inner content
    // elements.
    //
    // Otherwise: flow content.

    const nesting: enum { dl, option, optgroup, select, none } = blk: {
        var ancestor_idx = parent_idx;
        while (ancestor_idx != 0) {
            const ancestor = nodes[ancestor_idx];
            defer ancestor_idx = ancestor.parent_idx;

            var tt: Tokenizer = .{
                .idx = ancestor.open.start,
                .return_attrs = true,
                .language = language,
            };

            const span = tt.next(src[0..ancestor.open.end]).?.tag_name;
            const name = span.slice(src);

            if (std.ascii.eqlIgnoreCase(name, "dl")) {
                break :blk .dl;
            }
            if (std.ascii.eqlIgnoreCase(name, "option")) {
                break :blk .option;
            }
            if (std.ascii.eqlIgnoreCase(name, "optgroup")) {
                break :blk .optgroup;
            }
            if (std.ascii.eqlIgnoreCase(name, "select")) {
                break :blk .select;
            }

            continue;
        }
        break :blk .none;
    };

    const r = switch (nesting) {
        inline else => |tag| try @field(rules, @tagName(tag)),
        .none => flow,
    };

    return switch (r) {
        .simple => |simple| simple.validate(
            nodes,
            errors,
            src,
            language,
            parent_span,
            parent_idx,
            first_child_idx,
        ),
        .custom => |custom| custom.validate(
            nodes,
            errors,
            src,
            language,
            ancestor_rule_idx,
            parent_span,
            parent_idx,
            first_child_idx,
        ),
    };
}
