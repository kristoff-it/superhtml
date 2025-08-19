const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../../root.zig");
const Span = root.Span;
const Tokenizer = @import("../Tokenizer.zig");
const Ast = @import("../Ast.zig");
const Content = Ast.Node.Categories;
const Element = @import("../Element.zig");
const Model = Element.Model;
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;
const log = std.log.scoped(.details);

pub const hgroup: Element = .{
    .tag = .hgroup,
    .model = .{
        .categories = .{
            .flow = true,
            .heading = true,
        },
        .content = .none,
    },
    .meta = .{
        .categories_superset = .{
            .flow = true,
            .heading = true,
        },
    },
    .attributes = .static,
    .content = .{
        .custom = .{
            .validate = validateContent,
            .completions = completionsContent,
        },
    },
    .desc =
    \\The `<hgroup>` HTML element represents a heading and related
    \\content. It groups a single `<h1>`–`<h6>` element with one or more
    \\`<p>`.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/hgroup)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-hgroup-element)
    ,
};

pub fn validateContent(
    gpa: Allocator,
    nodes: []const Ast.Node,
    errors: *std.ArrayListUnmanaged(Ast.Error),
    src: []const u8,
    parent_idx: u32,
) error{OutOfMemory}!void {
    // Zero or more p elements, followed by one h1, h2, h3, h4, h5, or h6
    // element, followed by zero or more p elements, optionally intermixed with
    // script-supporting elements.

    const parent = nodes[parent_idx];
    const parent_span = parent.span(src);

    var state: enum { prefix, heading, suffix } = .prefix;
    var heading: ?Span = null;

    var child_idx = parent.first_child_idx;
    while (child_idx != 0) {
        const child = nodes[child_idx];
        defer child_idx = child.next_idx;
        switch (child.kind) {
            .comment => continue,
            else => {},
        }

        state: switch (state) {
            .prefix => switch (child.kind) {
                .p => {},
                .h1, .h2, .h3, .h4, .h5, .h6 => continue :state .heading,
                else => try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = parent_span,
                            .reason = "only <p> and headings allowed",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
            },
            .heading => switch (child.kind) {
                .h1, .h2, .h3, .h4, .h5, .h6 => {
                    state = .heading;
                    if (heading) |h| {
                        try errors.append(gpa, .{
                            .tag = .{
                                .duplicate_child = .{
                                    .span = h,
                                    .reason = "only one heading element allowed",
                                },
                            },
                            .main_location = child.span(src),
                            .node_idx = child_idx,
                        });
                    } else heading = child.span(src);
                },
                .p => state = .suffix,
                else => try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = parent_span,
                            .reason = "only <p> and headings allowed",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
            },
            .suffix => switch (child.kind) {
                .p => {},
                .h1, .h2, .h3, .h4, .h5, .h6 => try errors.append(gpa, .{
                    .tag = .{
                        .duplicate_child = .{
                            .span = heading.?,
                            .reason = "only one heading element allowed",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
                else => try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = parent_span,
                            .reason = "only <p> and headings allowed",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
            },
        }
    }
}

fn completionsContent(
    arena: Allocator,
    ast: Ast,
    src: []const u8,
    parent_idx: u32,
    offset: u32,
) error{OutOfMemory}![]const Ast.Completion {
    _ = arena;
    _ = src;
    _ = offset;

    const parent = ast.nodes[parent_idx];
    var child_idx = parent.first_child_idx;
    const has_heading = while (child_idx != 0) {
        const child = ast.nodes[child_idx];
        defer child_idx = child.next_idx;
        switch (child.kind) {
            .h1, .h2, .h3, .h4, .h5, .h6 => break true,
            else => {},
        }
    } else false;

    const all: [7]Ast.Completion = comptime blk: {
        const tags = &.{ .p, .h1, .h2, .h3, .h4, .h5, .h6 };

        var all: [7]Ast.Completion = undefined;
        for (&all, tags) |*a, t| a.* = .{
            .label = @tagName(t),
            .desc = Element.all.get(t).desc,
        };
        break :blk all;
    };

    if (has_heading) return all[0..1];
    return &all;
}
