const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Tokenizer = @import("../Tokenizer.zig");
const Ast = @import("../Ast.zig");
const Element = @import("../Element.zig");
const Attribute = @import("../Attribute.zig");
const ValidatingIterator = Attribute.ValidatingIterator;
const root = @import("../../root.zig");
const Span = root.Span;
const log = std.log.scoped(.srcset);

pub const picture: Element = .{
    .tag = .picture,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
            .embedded = true,
            // .palpable = true,
        },
        .content = .none,
    },
    .meta = .{ .categories_superset = .none },
    .attributes = .static,
    .content = .{
        .custom = .{
            .validate = validate,
            .completions = completions,
        },
    },
    .desc =
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/p)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/grouping-content.html#the-p-element)
    ,
};

fn validate(
    gpa: Allocator,
    nodes: []const Ast.Node,
    errors: *std.ArrayListUnmanaged(Ast.Error),
    src: []const u8,
    parent_idx: u32,
) error{OutOfMemory}!void {
    const parent = nodes[parent_idx];
    const parent_span = parent.span(src);
    const first_child_idx = parent.first_child_idx;

    const source_attrs = comptime Attribute.element_attrs.get(.source);
    var seen_attrs: std.StringHashMapUnmanaged(Span) = .empty;
    defer seen_attrs.deinit(gpa);

    var state: enum { source, img, done } = .source;
    var child_idx = first_child_idx;

    const img_autosizes = while (child_idx != 0) {
        const child = nodes[child_idx];
        defer child_idx = child.next_idx;

        if (child.kind == .img) break child.model.extra.autosizes_allowed;
    } else blk: {
        try errors.append(gpa, .{
            .tag = .{
                .missing_child = .img,
            },
            .main_location = parent_span,
            .node_idx = parent_idx,
        });
        break :blk true;
    };

    child_idx = first_child_idx;
    while (child_idx != 0) {
        const child = nodes[child_idx];
        defer child_idx = child.next_idx;

        switch (child.kind) {
            .source, .img => {},
            .script, .template => continue,
            else => {
                try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = parent_span,
                            .reason = "only 'source', 'img', 'script', and 'template' are allowed",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                });
                continue;
            },
        }

        var img_span: Span = undefined;
        state: switch (state) {
            .source => switch (child.kind) {
                else => unreachable,
                .source => {
                    var vait: ValidatingIterator = .init(
                        errors,
                        &seen_attrs,
                        .html,
                        child.open,
                        src,
                        child_idx,
                    );

                    var sizes: ?Span = null;
                    var srcset: ?Span = null;
                    var srcset_width_desc = true;
                    while (try vait.next(gpa, src)) |attr| {
                        const name = attr.name.slice(src);
                        const model = if (source_attrs.index(name)) |idx| blk: {
                            switch (idx) {
                                else => {},
                                source_attrs.comptimeIndex("srcset") => {
                                    srcset = attr.name;
                                    // validate the value
                                    try validateSrcset(
                                        gpa,
                                        errors,
                                        attr,
                                        src,
                                        child_idx,
                                        &srcset_width_desc,
                                    );
                                    continue;
                                },
                                source_attrs.comptimeIndex("src") => {
                                    try errors.append(gpa, .{
                                        .tag = .{
                                            .invalid_attr_nesting = .picture,
                                        },
                                        .main_location = attr.name,
                                        .node_idx = child_idx,
                                    });
                                    continue;
                                },
                                source_attrs.comptimeIndex("sizes") => {
                                    sizes = attr.name;
                                },
                            }
                            break :blk source_attrs.list[idx].model;
                        } else Attribute.global.get(name) orelse {
                            try errors.append(gpa, .{
                                .tag = .invalid_attr,
                                .main_location = attr.name,
                                .node_idx = child_idx,
                            });
                            continue;
                        };

                        // try model.validate();
                        _ = model;
                    }

                    if (srcset == null) {
                        try errors.append(gpa, .{
                            // missing mandatory attr
                            .tag = .{ .missing_required_attr = "srcset is mandatory" },
                            .main_location = child.span(src),
                            .node_idx = child_idx,
                        });
                        continue;
                    }

                    // If the srcset attribute has any image candidate strings
                    //using a width descriptor, the sizes attribute may also
                    //be present. If, additionally, the following sibling img
                    //element does not allow auto-sizes, the sizes attribute
                    //must be present. The sizes attribute is a sizes attribute,
                    //which contributes the source size to the source set, if
                    //the source element is selected.

                    if (sizes) |sz| {
                        if (!srcset_width_desc) try errors.append(gpa, .{
                            .tag = .{
                                .invalid_attr_combination =
                                \\requires 'srcset' to specify at least one image with a width descriptor
                                ,
                            },
                            .main_location = sz,
                            .node_idx = child_idx,
                        });

                        continue;
                    }

                    if (img_autosizes) try errors.append(gpa, .{
                        .tag = .{ .missing_required_attr = "sizes" },
                        .main_location = vait.name,
                        .node_idx = child_idx,
                    });
                },
                .img => {
                    state = .img;
                    continue :state .img;
                },
            },
            .img => switch (child.kind) {
                else => unreachable,
                .source => continue :state .done,
                .img => {
                    img_span = child.span(src);
                    state = .done;
                },
            },
            .done => switch (child.kind) {
                else => unreachable,
                .source => try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = parent_span,
                            .reason = "source elements must go above the img element",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
                .img => try errors.append(gpa, .{
                    .tag = .{
                        .duplicate_child = .{
                            .span = img_span,
                            .reason = "source elements must go above the img element",
                        },
                    },
                    .main_location = child.span(src),
                    .node_idx = child_idx,
                }),
            },
        }
    }
}

fn validateSrcset(
    gpa: Allocator,
    errors: *std.ArrayListUnmanaged(Ast.Error),
    attr: Tokenizer.Attr,
    src: []const u8,
    node_idx: u32,
    width_desc: *bool,
) !void {
    // https://html.spec.whatwg.org/multipage/images.html#parsing-a-srcset-attribute

    const value = attr.value orelse return errors.append(gpa, .{
        .tag = .missing_attr_value,
        .main_location = attr.name,
        .node_idx = node_idx,
    });

    // 1. Let input be the value passed to this algorithm.
    const input = value.span.slice(src);

    // 2. Let position be a pointer into input, initially pointing at the start of the string.
    var position: u32 = 0;

    // 10. Let width be absent.
    // var width = false;

    // 11. Let density be absent.
    // var density = false;

    // Let future-compat-h be absent.
    // var future_h = false;
    _ = width_desc;

    outer: while (position < input.len) {
        // 4. Splitting loop: Collect a sequence of code points that are ASCII whitespace or U+002C COMMA characters from input given position. If any U+002C COMMA characters were collected, that is a parse error.
        const start = position;
        while (position < input.len) : (position += 1) {
            if (std.ascii.isWhitespace(input[position])) continue;
            if (input[position] == ',') return errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{ .reason = "missing URL" },
                },
                .main_location = .{
                    .start = value.span.start + start,
                    .end = value.span.start + position,
                },
                .node_idx = node_idx,
            });
            break;
            // 5. If position is past the end of input, return candidates.
        } else return;

        // 6. Collect a sequence of code points that are not ASCII whitespace from input given position, and let url be the result.
        while (position < input.len) : (position += 1) {
            if (std.ascii.isWhitespace(input[position])) break;
        }

        // 8. If url ends with U+002C (,), then:
        if (position < input.len and input[position] == ',') {
            // 1. Remove all trailing U+002C COMMA characters from url. If this removed more than one character, that is a parse error.
            if (position >= 1 and input[position - 1] == ',') return errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{ .reason = "invalid character" },
                },
                .main_location = .{
                    .start = value.span.start + position,
                    .end = value.span.start + position + 1,
                },
                .node_idx = node_idx,
            });
        } else { // Otherwise:
            // 1. Descriptor tokenizer: Skip ASCII whitespace within input given position.
            while (position < input.len) : (position += 1) {
                if (!std.ascii.isWhitespace(input[position])) break;
            }

            // 3. Let state be in descriptor.
            var state: enum { descriptor, parens, after } = .descriptor;

            // 4. Let c be the character at position. Do the following depending on the value of state. For the purpose of this step, "EOF" is a special character representing that position is past the end of input.
            const descriptor_start: u32 = position;
            while (true) : (position += 1) {
                const c = if (position == input.len) 0 else input[position];
                state: switch (state) {
                    .descriptor => switch (c) {
                        ' ', '\t'...'\r' => {
                            // ASCII whitespace
                            // If current descriptor is not empty, append current descriptor to descriptors and let current descriptor be the empty string. Set state to after descriptor.
                            if (position - descriptor_start != 0) {
                                state = .after;
                            }
                        },
                        ',' => {
                            // U+002C COMMA (,)
                            // Advance position to the next character in input. If current descriptor is not empty, append current descriptor to descriptors. Jump to the step labeled descriptor parser.
                            if (position - descriptor_start == 0) continue :outer;
                            break;
                        },
                        '(' => {
                            // U+0028 LEFT PARENTHESIS (()
                            // Append c to current descriptor. Set state to in parens.
                            state = .parens;
                        },

                        0 => {
                            // EOF
                            // If current descriptor is not empty, append current descriptor to descriptors. Jump to the step labeled descriptor parser.
                            if (position - descriptor_start == 0) continue :outer;
                            break;
                        },

                        else => {
                            // Anything else
                            // Append c to current descriptor.
                        },
                    },
                    .parens => switch (c) {
                        ')' => {
                            // U+0029 RIGHT PARENTHESIS ())
                            // Append c to current descriptor. Set state to in descriptor.
                            state = .descriptor;
                        },

                        0 => {
                            // EOF
                            // Append current descriptor to descriptors. Jump to the step labeled descriptor parser.
                            break;
                        },
                        else => {
                            // Anything else
                            // Append c to current descriptor.
                        },
                    },
                    .after => switch (c) {
                        ' ', '\t'...'\r' => {
                            // ASCII whitespace
                            // Stay in this state.
                        },

                        0 => {
                            // EOF
                            // Jump to the step labeled descriptor parser.
                            break;
                        },

                        else => {
                            // Anything else
                            // Set state to in descriptor. Set position to the previous character in input.
                            state = .descriptor;
                            continue :state .descriptor;
                        },
                    },
                }
                // Advance position to the next character in input. Repeat this step.
            }

            const descriptor = input[descriptor_start..position];
            assert(descriptor.len > 0);

            switch (descriptor[descriptor.len - 1]) {
                'w' => {},
                'x' => {},
                'h' => {},
                else => return errors.append(gpa, .{
                    .tag = .{
                        .invalid_attr_value = .{ .reason = "invalid descriptor" },
                    },
                    .main_location = .{
                        .start = value.span.start + descriptor_start,
                        .end = value.span.start + position,
                    },
                    .node_idx = node_idx,
                }),
            }

            if (position < input.len - 1 and input[position] == ',') {
                position += 1;
            }
        }
    }
}

fn completions(
    arena: Allocator,
    ast: Ast,
    src: []const u8,
    parent_idx: u32,
    offset: u32, // cursor position
) error{OutOfMemory}![]const Ast.Completion {
    _ = arena;
    _ = ast;
    _ = src;
    _ = parent_idx;
    _ = offset;
    return &.{};
}
