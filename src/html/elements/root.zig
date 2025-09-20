const std = @import("std");
const Allocator = std.mem.Allocator;
const Element = @import("../Element.zig");
const Tokenizer = @import("../Tokenizer.zig");
const Ast = @import("../Ast.zig");
const Language = root.Language;
const Span = @import("../../root.zig").Span;
const log = std.log.scoped(.root);

pub const root: Element = .{
    .tag = .root,
    .model = .{
        .categories = .none,
        .content = .all,
    },
    .meta = .{ .categories_superset = .all },
    .attributes = .static,
    .content = .{
        .custom = .{
            .validate = validateContent,
            .completions = completionsContent,
        },
    },

    .desc =
    \\The top level of your HTML document.
    \\
    \\If you have a `<html>` element at the top level, SuperHTML will enforce
    \\an overall correct structure for the document (only comments, `<!doctype>`
    \\and `<html>` allowed at the top level).
    \\
    \\If no `<html>` element is present at the top level, then SuperHTML will
    \\assume that the document contains an html fragment and will allow any
    \\element to be placed at the top level.
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
    const parent = nodes[parent_idx];

    // first pass, find html
    var has_html: ?Span = null;
    var html_idx: u32 = 0;
    var child_idx = parent.first_child_idx;
    while (child_idx != 0) {
        const child = nodes[child_idx];
        defer child_idx = child.next_idx;
        if (child.kind == .html) {
            has_html = child.span(src);
            html_idx = child_idx;
            break;
        }
    }

    // second pass, report errors
    var has_doctype: ?Span = null;
    child_idx = parent.first_child_idx;
    while (child_idx != 0) {
        const child = nodes[child_idx];
        defer child_idx = child.next_idx;

        switch (child.kind) {
            .comment => continue,
            .doctype => {
                if (has_html == null) {
                    try errors.append(gpa, .{
                        .tag = .{
                            .wrong_sibling_sequence = .{
                                .reason = "only allowed when top level has <html>",
                            },
                        },
                        .main_location = child.span(src),
                        .node_idx = child_idx,
                    });
                    continue;
                }

                const previous = has_doctype orelse {
                    has_doctype = child.span(src);
                    if (child_idx > html_idx) {
                        try errors.append(gpa, .{
                            .tag = .{ .wrong_position = .first },
                            .main_location = child.span(src),
                            .node_idx = child_idx,
                        });
                        continue;
                    }

                    // if no error is shown, validate the contents of doctype
                    const tag = child.open.slice(src);
                    var it = std.mem.tokenizeAny(
                        u8,
                        tag[0 .. tag.len - 1],
                        &std.ascii.whitespace,
                    );
                    _ = it.next().?; // !doctype
                    const rest = it.next().?;
                    if (!std.ascii.eqlIgnoreCase(rest, "html") or it.next() != null) {
                        try errors.append(gpa, .{
                            .tag = .unsupported_doctype,
                            .main_location = child.open,
                            .node_idx = child_idx,
                        });
                    }

                    continue;
                };

                try errors.append(gpa, .{
                    .tag = .{ .duplicate_child = .{ .span = previous } },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                });
            },
            .html => {
                if (child_idx == html_idx) continue;
                try errors.append(gpa, .{
                    .tag = .{ .duplicate_child = .{ .span = has_html.? } },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                });
            },
            else => if (has_html != null) {
                try errors.append(gpa, .{
                    .tag = .{
                        .wrong_sibling_sequence = .{
                            .reason = "when top level has <html>, only comments and <!doctype> are allowed next to it",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                });
            },
        }
    }
}
fn completionsContent(
    arena: Allocator,
    ast: Ast,
    src: []const u8,
    node_idx: u32,
    offset: u32,
) error{OutOfMemory}![]const Ast.Completion {
    _ = src;
    const parent = ast.nodes[node_idx];

    var has_html = false;
    var has_doctype = false;
    var cursor_after_html = false;
    var child_idx = parent.first_child_idx;
    while (child_idx != 0) {
        const child = ast.nodes[child_idx];
        defer child_idx = child.next_idx;
        switch (child.kind) {
            .doctype => has_doctype = true,
            .html => {
                log.debug("offset {} html {}", .{ offset, child.open });
                cursor_after_html = offset > child.open.start;
                has_html = true;
                break;
            },
            else => {},
        }
    }

    log.debug("has doc {} curs {}", .{ has_doctype, cursor_after_html });
    if (has_html) {
        return if (has_doctype or cursor_after_html) &.{} else &.{
            .{
                .label = "DOCTYPE",
                .desc = "The required preamble for all HTML documents.",
                .value = "!DOCTYPE html>",
                .kind = .attribute, // well, not really, but it's ok :^)
            },
        };
    }

    return Element.simpleCompletions(arena, &.{.html}, .all, .none, .{});
}
