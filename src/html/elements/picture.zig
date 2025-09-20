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
            // .embedded = true,
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
    \\The `<picture>` HTML element contains zero or more `<source>` elements
    \\and one `<img>` element to offer alternative versions of an image for
    \\different display/device scenarios.
    \\
    \\The browser will consider each child `<source>` element and choose
    \\the best match among them. If no matches are found—or the browser
    \\doesn't support the `<picture>` element—the URL of the `<img>` element's
    \\src attribute is selected. The selected image is then presented in
    \\the space occupied by the `<img>` element.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/picture)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/grouping-content.html#the-picture-element)
    ,
};

fn validate(
    gpa: Allocator,
    nodes: []const Ast.Node,
    seen_attrs: *std.StringHashMapUnmanaged(Span),
    seen_ids: *std.StringHashMapUnmanaged(Span),
    errors: *std.ArrayListUnmanaged(Ast.Error),
    src: []const u8,
    parent_idx: u32,
) error{OutOfMemory}!void {
    const parent = nodes[parent_idx];
    const parent_span = parent.span(src);
    const first_child_idx = parent.first_child_idx;

    const source_attrs = comptime Attribute.element_attrs.get(.source);

    // Used to catch duplicate descriptors in image candidate strings
    var seen_descriptors: std.StringArrayHashMapUnmanaged(Span) = .empty;
    defer seen_descriptors.deinit(gpa);

    var state: enum { source, img, done } = .source;
    var child_idx = first_child_idx;

    const img_allow_autosizes = while (child_idx != 0) {
        const child = nodes[child_idx];
        child_idx = child.next_idx;
        if (child.kind == .img) break child.model.extra.autosizes_allowed;
    } else blk: {
        try errors.append(gpa, .{
            .tag = .{ .missing_child = .img },
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
                        seen_attrs,
                        seen_ids,
                        .html,
                        child.open,
                        src,
                        child_idx,
                    );

                    var sizes: ?Span = null;
                    var srcset: ?Span = null;
                    var seen_any_w = false;
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
                                        &seen_descriptors,
                                        attr,
                                        src,
                                        child_idx,
                                        &seen_any_w,
                                    );
                                    continue;
                                },
                                source_attrs.comptimeIndex("src") => {
                                    try errors.append(gpa, .{
                                        .tag = .{
                                            .invalid_attr_nesting = .{
                                                .kind = .picture,
                                            },
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
                            if (Attribute.isData(name)) continue;
                            try errors.append(gpa, .{
                                .tag = .invalid_attr,
                                .main_location = attr.name,
                                .node_idx = child_idx,
                            });
                            continue;
                        };

                        try model.rule.validate(gpa, errors, src, child_idx, attr);
                    }

                    if (srcset == null) {
                        try errors.append(gpa, .{
                            // missing mandatory attr
                            .tag = .{
                                .missing_required_attr = "srcset is mandatory for this element",
                            },
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

                    if (sizes != null) {
                        if (!seen_any_w) try errors.append(gpa, .{
                            .tag = .{
                                .invalid_attr_combination =
                                \\presence of 'sizes' requires image string candidates to specify width descriptors
                                ,
                            },
                            .main_location = srcset.?,
                            .node_idx = child_idx,
                        });

                        continue;
                    }

                    if (!img_allow_autosizes) try errors.append(gpa, .{
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

const DescriptorKinds = struct { w: bool, x: bool, h: bool };

pub fn validateSrcset(
    gpa: Allocator,
    errors: *std.ArrayListUnmanaged(Ast.Error),
    seen_descriptors: *std.StringArrayHashMapUnmanaged(Span),
    attr: Tokenizer.Attr,
    src: []const u8,
    node_idx: u32,
    seen_any_w: *bool,
) !void {
    // https://html.spec.whatwg.org/multipage/images.html#parsing-a-srcset-attribute

    seen_descriptors.clearRetainingCapacity();
    const value = attr.value orelse return errors.append(gpa, .{
        .tag = .missing_attr_value,
        .main_location = attr.name,
        .node_idx = node_idx,
    });

    // 1. Let input be the value passed to this algorithm.
    const input = value.span.slice(src);

    // 2. Let position be a pointer into input, initially pointing at the start of the string.
    var position: u32 = 0;

    while (true) {
        // 4. Splitting loop: Collect a sequence of code points that are ASCII whitespace or U+002C COMMA characters from input given position. If any U+002C COMMA characters were collected, that is a parse error.
        while (position < input.len) : (position += 1) {
            if (std.ascii.isWhitespace(input[position])) continue;
            if (input[position] == ',') return errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{ .reason = "invalid comma" },
                },
                .main_location = .{
                    .start = value.span.start + position - 1,
                    .end = value.span.start + position,
                },
                .node_idx = node_idx,
            });
            break;
            // 5. If position is past the end of input, return candidates.
        } else break;

        // 6. Collect a sequence of code points that are not ASCII whitespace from input given position, and let url be the result.
        const url_start = position;
        while (position < input.len) : (position += 1) {
            if (std.ascii.isWhitespace(input[position])) break;
        }

        // 8. If url ends with U+002C (,), then:
        if (input[position - 1] == ',') {
            // 1. Remove all trailing U+002C COMMA characters from url. If this removed more than one character, that is a parse error.
            if (position >= 2 and input[position - 2] == ',') return errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{ .reason = "invalid comma" },
                },
                .main_location = .{
                    .start = value.span.start + position,
                    .end = value.span.start + position + 1,
                },
                .node_idx = node_idx,
            });

            const url = input[url_start .. position - 1];
            log.debug("url-with-comma: '{s}'", .{url});
            if (validateUrl(
                node_idx,
                value.span.start + url_start,
                url,
            )) |err| try errors.append(gpa, err);

            // No descriptor implies '1x'
            const gop = try seen_descriptors.getOrPut(gpa, "1x");
            if (gop.found_existing) return errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "duplicate descriptor (no descriptor implies '1x')",
                    },
                },
                .main_location = .{
                    .start = value.span.start + url_start,
                    .end = value.span.start + position,
                },
                .node_idx = node_idx,
            });
            gop.value_ptr.* = .{
                .start = value.span.start + url_start,
                .end = value.span.start + position,
            };
            continue;
        }

        const url = input[url_start..position];
        log.debug("url-no-comma: '{s}'", .{url});
        if (validateUrl(
            node_idx,
            value.span.start + url_start,
            url,
        )) |err| try errors.append(gpa, err);

        // Otherwise:

        // 10. Let width be absent.
        // 11. Let density be absent.
        // 12. Let future-compat-h be absent.
        var present: DescriptorKinds = .{
            .w = false,
            .x = false,
            .h = false,
        };
        defer seen_any_w.* |= present.w;

        // 1. Descriptor tokenizer: Skip ASCII whitespace within input given position.
        while (position < input.len) : (position += 1) {
            if (!std.ascii.isWhitespace(input[position])) break;
        }

        // 3. Let state be in descriptor.
        var state: enum { descriptor, parens, after } = .descriptor;

        // 4. Let c be the character at position. Do the following depending on the value of state. For the purpose of this step, "EOF" is a special character representing that position is past the end of input.
        var any_descriptors = false;
        var descriptor_start: u32 = position;
        while (true) : (position += 1) {
            const c = if (position == input.len) 0 else input[position];
            state: switch (state) {
                .descriptor => switch (c) {
                    ' ', '\t'...'\r' => {
                        // ASCII whitespace
                        // If current descriptor is not empty, append current descriptor to descriptors and let current descriptor be the empty string. Set state to after descriptor.
                        const descriptor = input[descriptor_start..position];
                        if (descriptor.len != 0) {
                            any_descriptors = true;
                            if (try validateDescriptor(
                                gpa,
                                seen_descriptors,
                                &present,
                                node_idx,
                                value.span.start + descriptor_start,
                                descriptor,
                            )) |err| return errors.append(gpa, err);

                            descriptor_start = position;
                            state = .after;
                        }
                    },
                    ',' => {
                        // U+002C COMMA (,)
                        // Advance position to the next character in input. If current descriptor is not empty, append current descriptor to descriptors. Jump to the step labeled descriptor parser.
                        const descriptor = input[descriptor_start..position];
                        if (descriptor.len != 0) {
                            any_descriptors = true;
                            if (try validateDescriptor(
                                gpa,
                                seen_descriptors,
                                &present,
                                node_idx,
                                value.span.start + descriptor_start,
                                descriptor,
                            )) |err| return errors.append(gpa, err);
                        }
                        position += 1;
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
                        const descriptor = input[descriptor_start..position];
                        if (descriptor.len != 0) {
                            any_descriptors = true;
                            if (try validateDescriptor(
                                gpa,
                                seen_descriptors,
                                &present,
                                node_idx,
                                value.span.start + descriptor_start,
                                descriptor,
                            )) |err| return errors.append(gpa, err);
                        }
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
                        descriptor_start = position;
                        state = .descriptor;
                        continue :state .descriptor;
                    },
                },
            }
            // Advance position to the next character in input. Repeat this step.
        }

        if (any_descriptors) continue;
        // No descriptors implies '1x'
        const gop = try seen_descriptors.getOrPut(gpa, "1x");
        if (gop.found_existing) return errors.append(gpa, .{
            .tag = .{
                .invalid_attr_value = .{
                    .reason = "duplicate descriptor (no descriptor implies '1x')",
                },
            },
            .main_location = .{
                .start = value.span.start + url_start,
                .end = value.span.start + position,
            },
            .node_idx = node_idx,
        });
        gop.value_ptr.* = .{
            .start = value.span.start + url_start,
            .end = value.span.start + position,
        };
        // Return to the step labeled splitting loop.
    }

    // There must not be an image candidate string for an element that has the same width descriptor value as another image candidate string's width descriptor value for the same element.

    // There must not be an image candidate string for an element that has the same pixel density descriptor value as another image candidate string's pixel density descriptor value for the same element. For the purpose of this requirement, an image candidate string with no descriptors is equivalent to an image candidate string with a 1x descriptor.

    // If an image candidate string for an element has the width descriptor specified, all other image candidate strings for that element must also have the width descriptor specified.

    if (seen_any_w.*) {
        for (seen_descriptors.keys(), seen_descriptors.values()) |k, v| {
            const unit = k[k.len - 1];
            if (unit != 'w' and unit != 'h') try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "presence of a width descriptor requires all descriptors to be width",
                    },
                },
                .main_location = v,
                .node_idx = node_idx,
            });
        }
    }

    // The specified width in an image candidate string's width descriptor must match the natural width in the resource given by the image candidate string's URL, if it has a natural width.

    // If an element has a sizes attribute present, all image candidate strings for that element must have the width descriptor specified.

}

fn validateUrl(node_idx: u32, offset: u32, url: []const u8) ?Ast.Error {
    if (url.len == 0) return .{
        .tag = .{
            .invalid_attr_value = .{ .reason = "missing URL" },
        },
        .main_location = .{
            .start = offset - 1,
            .end = offset,
        },
        .node_idx = node_idx,
    };

    _ = Attribute.parseUri(url) catch return .{
        .tag = .{
            .invalid_attr_value = .{ .reason = "invalid URL" },
        },
        .main_location = .{
            .start = offset,
            .end = @intCast(offset + url.len),
        },
        .node_idx = node_idx,
    };

    return null;
}

fn validateDescriptor(
    gpa: Allocator,
    seen_descriptors: *std.StringArrayHashMapUnmanaged(Span),
    present: *DescriptorKinds,
    node_idx: u32,
    offset: u32,
    descriptor: []const u8,
) !?Ast.Error {
    assert(descriptor.len > 0);
    log.debug("validating descriptor: '{s}' at offset {}", .{ descriptor, offset });

    const missing_num: Ast.Error = .{
        .tag = .{
            .invalid_attr_value = .{
                .reason = "missing numeric component from descriptor",
            },
        },
        .main_location = .{
            .start = offset,
            .end = @intCast(offset + descriptor.len - 1),
        },
        .node_idx = node_idx,
    };

    success: switch (descriptor[descriptor.len - 1]) {
        'w' => if (descriptor.len > 1) {
            // If the descriptor consists of a valid non-negative integer
            // followed by a U+0077 LATIN SMALL LETTER W character

            const digits = descriptor[0 .. descriptor.len - 1];
            if (std.fmt.parseInt(i64, digits, 10)) |n| {
                // If width and density are not both absent, then let error be yes.
                if (present.w or present.x) return .{
                    .tag = .{
                        .invalid_attr_value = .{
                            .reason = "invalid descriptor combination for this URL",
                        },
                    },
                    .main_location = .{
                        .start = offset,
                        .end = @intCast(offset + descriptor.len),
                    },
                    .node_idx = node_idx,
                };

                present.w = true;

                // Apply the rules for parsing non-negative integers to the
                // descriptor. If the result is 0, let error be yes. Otherwise,
                // let width be the result.
                if (n > 0) break :success;
            } else |_| {}
            return .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "invalid numeric component for width descriptor",
                    },
                },
                .main_location = .{
                    .start = offset,
                    .end = @intCast(offset + descriptor.len),
                },
                .node_idx = node_idx,
            };
        } else return missing_num,
        'x' => if (descriptor.len > 1) {
            // If the descriptor consists of a valid floating-point number
            // followed by a U+0078 LATIN SMALL LETTER X character

            const digits = descriptor[0 .. descriptor.len - 1];
            if (std.fmt.parseFloat(f32, digits)) |n| {
                // If width, density and future-compat-h are not all absent,
                // then let error be yes.
                if (present.w or present.x or present.h) return .{
                    .tag = .{
                        .invalid_attr_value = .{
                            .reason = "invalid descriptor combination for this URL",
                        },
                    },
                    .main_location = .{
                        .start = offset,
                        .end = @intCast(offset + descriptor.len),
                    },
                    .node_idx = node_idx,
                };

                present.x = true;

                // Apply the rules for parsing floating-point number values to
                // the descriptor. If the result is less than 0, let error be
                // yes. Otherwise, let density be the result.
                if (n >= 0) break :success;
            } else |_| {}

            return .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "invalid numeric component for density descriptor",
                    },
                },
                .main_location = .{
                    .start = offset,
                    .end = @intCast(offset + descriptor.len),
                },
                .node_idx = node_idx,
            };
        } else return missing_num,
        'h' => if (descriptor.len > 1) {
            // If the descriptor consists of a valid non-negative integer
            // followed by a U+0068 LATIN SMALL LETTER H character

            const digits = descriptor[0 .. descriptor.len - 1];
            if (std.fmt.parseInt(i64, digits, 10)) |n| {
                // If future-compat-h and density are not both absent, then let
                // error be yes.
                if (present.h or present.x) return .{
                    .tag = .{
                        .invalid_attr_value = .{
                            .reason = "invalid descriptor combination for this URL",
                        },
                    },
                    .main_location = .{
                        .start = offset,
                        .end = @intCast(offset + descriptor.len),
                    },
                    .node_idx = node_idx,
                };

                present.h = true;

                // Apply the rules for parsing non-negative integers to the
                // descriptor. If the result is 0, let error be yes. Otherwise, let
                // future-compat-h be the result.
                if (n > 0) break :success;
            } else |_| {}
            return .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "invalid numeric component for h descriptor",
                    },
                },
                .main_location = .{
                    .start = offset,
                    .end = @intCast(offset + descriptor.len),
                },
                .node_idx = node_idx,
            };
        } else return missing_num,
        else => return .{
            .tag = .{
                .invalid_attr_value = .{ .reason = "invalid descriptor" },
            },
            .main_location = .{
                .start = offset,
                .end = @intCast(offset + descriptor.len),
            },
            .node_idx = node_idx,
        },
    }

    const gop = try seen_descriptors.getOrPut(gpa, descriptor);
    if (gop.found_existing) return .{
        .tag = .{
            .invalid_attr_value = .{
                .reason = "duplicate descriptor",
            },
        },
        .main_location = .{
            .start = offset,
            .end = @intCast(offset + descriptor.len),
        },
        .node_idx = node_idx,
    };

    gop.value_ptr.* = .{
        .start = @intCast(offset + descriptor.len - 1),
        .end = @intCast(offset + descriptor.len),
    };

    return null;
}

fn completions(
    arena: Allocator,
    ast: Ast,
    src: []const u8,
    parent_idx: u32,
    offset: u32, // cursor position
) error{OutOfMemory}![]const Ast.Completion {
    _ = arena;
    _ = src;

    const parent = ast.nodes[parent_idx];

    var state: enum { source, img } = .source;
    var kind_after_cursor: Ast.Kind = .root;
    var child_idx = parent.first_child_idx;
    while (child_idx != 0) {
        const child = ast.nodes[child_idx];
        defer child_idx = child.next_idx;

        if (child.open.start > offset) {
            kind_after_cursor = child.kind;
            break;
        }

        switch (state) {
            .source => if (child.kind == .img) {
                state = .img;
            },
            .img => {},
        }
    }

    const source = comptime Element.all_completions.get(.source);
    const img = comptime Element.all_completions.get(.img);
    const script = comptime Element.all_completions.get(.script);
    const template = comptime Element.all_completions.get(.template);

    return switch (state) {
        .source => switch (kind_after_cursor) {
            .source, .img => &.{ source, script, template },
            else => &.{ source, img, script, template },
        },
        .img => &.{ script, template },
    };
}
