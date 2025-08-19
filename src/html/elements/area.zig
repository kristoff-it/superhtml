const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Tokenizer = @import("../Tokenizer.zig");
const Ast = @import("../Ast.zig");
const root = @import("../../root.zig");
const Span = root.Span;
const Language = root.Language;
const Element = @import("../Element.zig");
const Categories = Element.Categories;
const Model = Element.Model;
const CompletionMode = Element.CompletionMode;
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;
const log = std.log.scoped(.area);

pub const area: Element = .{
    .tag = .area,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
        },
        .content = .none, // void
    },

    .meta = .{
        .categories_superset = .{
            .flow = true,
            .phrasing = true,
        },
    },

    .attributes = .{ .dynamic = validateAttrs },
    .content = .model,
    .desc =
    \\The <area> HTML element defines an area inside an image map that
    \\has predefined clickable areas. An image map allows geometric
    \\areas on an image to be associated with hypertext links.
    \\
    \\This element is used only within a <map> element.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/area)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-area-element)
    ,
};

// coords
// shape
// href
pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "coords",
        .model = .{
            .rule = .manual,
            .desc =
            \\The coords attribute details the coordinates of the shape
            \\attribute in size, shape, and placement of an `<area>`. This
            \\attribute must not be used if shape is set to default.
            \\
            \\- `rect`: the value is `x1,y1,x2,y2`. The value specifies the
            \\coordinates of the top-left and bottom-right corner of the
            \\rectangle.
            \\
            \\- `circle`: the value is `x,y,radius`. Value specifies the
            \\coordinates of the circle center and the radius.
            \\
            \\- `poly`: the value is `x1,y1,x2,y2,..,xn,yn`. Value specifies
            \\the coordinates of the edges of the polygon. If the first
            \\and last coordinate pairs are not the same, the browser will
            \\add the last coordinate pair to close the polygon
            ,
        },
    },
    .{
        .name = "shape",
        .model = .{
            .rule = .{
                // validated manually
                .list = .init(.missing, .one, &.{
                    .{
                        .label = "default",
                        .desc = "This area is the whole image.",
                    },
                    .{
                        .label = "rect",
                        .desc = "Designates a rectangle, using exactly four integers in the coords attribute.",
                    },
                    .{
                        .label = "poly",
                        .desc = "Designates a polygon, using at-least six integers in the coords attribute.",
                    },
                    .{
                        .label = "circle",
                        .desc = "Designates a circle, using exactly three integers in the coords attribute.",
                    },
                }),
            },
            .desc = "The kind of shape to be created in an image map.",
        },
    },

    .{
        .name = "href",
        .model = .{
            .rule = .{ .url = .empty },
            .desc =
            \\The URL that the hyperlink points to. Links are not
            \\restricted to HTTP-based URLs — they can use any URL scheme
            \\supported by browsers.
            \\
            \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/a#href)
            \\- [HTML Spec](https://html.spec.whatwg.org/multipage/links.html#attr-hyperlink-href)
            ,
        },
    },
    .{
        .name = "alt",
        .model = Attribute.common.alt,
    },

    .{
        .name = "target",
        .model = Attribute.common.target,
    },
    .{
        .name = "download",
        .model = Attribute.common.download,
    },
    .{
        .name = "ping",
        .model = Attribute.common.ping,
    },
    .{
        .name = "rel",
        .model = Attribute.common.rel,
    },
    .{
        .name = "referrerpolicy",
        .model = Attribute.common.referrerpolicy,
    },
});

fn validateAttrs(
    gpa: Allocator,
    errors: *std.ArrayListUnmanaged(Ast.Error),
    src: []const u8,
    nodes: []const Ast.Node,
    parent_idx: u32,
    node_idx: u32,
    vait: *Attribute.ValidatingIterator,
) error{OutOfMemory}!Model {

    // An area element with a parent node must have a map element ancestor.
    blk: {
        var ancestor_idx = parent_idx;
        while (ancestor_idx != 0) {
            const ancestor = nodes[ancestor_idx];
            ancestor_idx = ancestor.parent_idx;
            if (ancestor.kind == .map) break :blk;
        }

        try errors.append(gpa, .{
            .tag = .{ .missing_ancestor = .map },
            .main_location = vait.name,
            .node_idx = node_idx,
        });
    }

    var seen_attrs: [attributes.list.len]?Span = undefined;
    @memset(&seen_attrs, null);

    // If the itemprop attribute is specified on an area element, then the href
    // attribute must also be specified.
    var has_itemprop: ?Span = null;
    var shape: ?usize = null;
    var coords_attr: ?Tokenizer.Attr = null;
    while (try vait.next(gpa, src)) |attr| {
        const name = attr.name.slice(src);
        const attr_model = blk: {
            if (attributes.index(name)) |idx| {
                seen_attrs[idx] = attr.name;
                switch (idx) {
                    else => {},
                    attributes.comptimeIndex("shape") => {
                        const model = attributes.list[idx].model;
                        const value = attr.value orelse {
                            try errors.append(gpa, .{
                                .tag = .missing_attr_value,
                                .main_location = attr.name,
                                .node_idx = node_idx,
                            });
                            continue;
                        };
                        switch (try model.rule.list.match(
                            gpa,
                            errors,
                            node_idx,
                            value.span.start,
                            value.span.slice(src),
                        )) {
                            .list => |list_idx| shape = list_idx,
                            .none => {},
                            else => unreachable,
                        }
                        continue;
                    },
                    attributes.comptimeIndex("coords") => {
                        coords_attr = attr;
                        continue;
                    },
                }
                break :blk attributes.list[idx].model;
            }

            const gidx = Attribute.global.index(name) orelse {
                if (Attribute.isData(name)) continue;
                try errors.append(gpa, .{
                    .tag = .invalid_attr,
                    .main_location = attr.name,
                    .node_idx = node_idx,
                });

                continue;
            };

            if (Attribute.global.comptimeIndex("itemprop") == gidx) {
                has_itemprop = attr.name;
            }

            break :blk Attribute.global.list[gidx].model;
        };

        try attr_model.rule.validate(gpa, errors, src, node_idx, attr);
    }

    const shape_model = comptime attributes.get("shape").?;
    if (shape) |sh_idx| blk: {
        if (sh_idx == comptime shape_model.rule.list.set.getIndex("default").?) {
            if (coords_attr) |attr| try errors.append(gpa, .{
                // In the default state, area elements must not have a coords
                //attribute. (The area is the whole image.)
                .tag = .{
                    .invalid_attr_combination = "not allowed when [shape] is 'default'",
                },
                .main_location = attr.name,
                .node_idx = node_idx,
            });
            break :blk;
        }

        const ca = coords_attr orelse {
            try errors.append(gpa, .{
                .tag = .{ .missing_required_attr = "coords" },
                .main_location = vait.name,
                .node_idx = node_idx,
            });
            break :blk;
        };

        const value = ca.value orelse {
            try errors.append(gpa, .{
                .tag = .missing_attr_value,
                .main_location = ca.name,
                .node_idx = node_idx,
            });
            break :blk;
        };
        const value_slice = value.span.slice(src);

        var it = std.mem.splitScalar(u8, value_slice, ',');
        switch (sh_idx) {
            else => unreachable,
            // poly
            shape_model.rule.list.set.getIndex("poly").? => {
                // In the polygon state, area elements must have a coords
                // attribute with at least six integers, and the number of
                // integers must be even.

                var idx: usize = 0;
                if (std.mem.trim(u8, value_slice, &std.ascii.whitespace).len > 0) {
                    while (it.next()) |digits| : (idx += 1) {
                        _ = std.fmt.parseInt(i64, digits, 10) catch {
                            try errors.append(gpa, .{
                                .tag = .{
                                    .invalid_attr_value = .{
                                        .reason = "not a valid integer",
                                    },
                                },
                                .main_location = .{
                                    .start = @intCast(
                                        value.span.start + (digits.ptr - value_slice.ptr),
                                    ),
                                    .end = @intCast(
                                        value.span.start + (digits.ptr - value_slice.ptr) + digits.len,
                                    ),
                                },
                                .node_idx = node_idx,
                            });

                            break :blk;
                        };
                    }
                }

                if (idx < 6) {
                    try errors.append(gpa, .{
                        .tag = .{
                            .invalid_attr_value = .{
                                .reason = "should contain at least 6 numbers when [shape] is 'poly'",
                            },
                        },
                        .main_location = value.span,
                        .node_idx = node_idx,
                    });
                } else if (idx % 2 != 0) {
                    try errors.append(gpa, .{
                        .tag = .{
                            .invalid_attr_value = .{
                                .reason = "should contain an even number of entries when [shape] is 'poly'",
                            },
                        },
                        .main_location = value.span,
                        .node_idx = node_idx,
                    });
                }
            },
            // rect
            shape_model.rule.list.set.getIndex("rect").? => {
                // In the rectangle state, area elements must have a coords
                // attribute with exactly four integers, the first of which
                // must be less than the third, and the second of which must
                // be less than the fourth.

                var idx: usize = 0;
                var first: i64 = undefined;
                var third: i64 = undefined;
                if (std.mem.trim(u8, value_slice, &std.ascii.whitespace).len > 0) {
                    while (it.next()) |digits| : (idx += 1) {
                        if (idx == 4) {
                            try errors.append(gpa, .{
                                .tag = .{
                                    .invalid_attr_value = .{
                                        .reason = "should contain 4 numbers when [shape] is 'rect'",
                                    },
                                },
                                .main_location = .{
                                    .start = @intCast(
                                        value.span.start + (digits.ptr - value_slice.ptr),
                                    ),
                                    .end = value.span.end,
                                },
                                .node_idx = node_idx,
                            });
                            break;
                        }

                        const num = std.fmt.parseInt(i64, digits, 10) catch {
                            try errors.append(gpa, .{
                                .tag = .{
                                    .invalid_attr_value = .{
                                        .reason = "not a valid integer",
                                    },
                                },
                                .main_location = .{
                                    .start = @intCast(
                                        value.span.start + (digits.ptr - value_slice.ptr),
                                    ),
                                    .end = @intCast(
                                        value.span.start + (digits.ptr - value_slice.ptr) + digits.len,
                                    ),
                                },
                                .node_idx = node_idx,
                            });

                            break :blk;
                        };

                        switch (idx) {
                            else => unreachable,
                            0 => {
                                first = num;
                            },
                            1 => {
                                if (num <= first) {
                                    try errors.append(gpa, .{
                                        .tag = .{
                                            .invalid_attr_value = .{
                                                .reason = "first number must be lower than the second number",
                                            },
                                        },
                                        .main_location = .{
                                            .start = @intCast(
                                                value.span.start + (digits.ptr - value_slice.ptr),
                                            ),
                                            .end = @intCast(
                                                value.span.start + (digits.ptr - value_slice.ptr) + digits.len,
                                            ),
                                        },
                                        .node_idx = node_idx,
                                    });
                                }
                            },
                            2 => {
                                third = num;
                            },
                            3 => {
                                if (num <= third) {
                                    try errors.append(gpa, .{
                                        .tag = .{
                                            .invalid_attr_value = .{
                                                .reason = "third number must be lower than the fourth number",
                                            },
                                        },
                                        .main_location = .{
                                            .start = @intCast(
                                                value.span.start + (digits.ptr - value_slice.ptr),
                                            ),
                                            .end = @intCast(
                                                value.span.start + (digits.ptr - value_slice.ptr) + digits.len,
                                            ),
                                        },
                                        .node_idx = node_idx,
                                    });
                                }
                            },
                        }
                    }
                }

                if (idx < 4) {
                    try errors.append(gpa, .{
                        .tag = .{
                            .invalid_attr_value = .{
                                .reason = "should contain 4 numbers when [shape] is 'rect'",
                            },
                        },
                        .main_location = value.span,
                        .node_idx = node_idx,
                    });
                }
            },
            // circle
            shape_model.rule.list.set.getIndex("circle").? => {
                // In the circle state, area elements must have a coords attribute
                // present, with three integers, the last of which must be
                // non-negative.
                var idx: usize = 0;
                if (std.mem.trim(u8, value_slice, &std.ascii.whitespace).len > 0) {
                    while (it.next()) |digits| : (idx += 1) {
                        if (idx == 3) {
                            try errors.append(gpa, .{
                                .tag = .{
                                    .invalid_attr_value = .{
                                        .reason = "should contain 3 numbers when [shape] is 'circle'",
                                    },
                                },
                                .main_location = .{
                                    .start = @intCast(
                                        value.span.start + (digits.ptr - value_slice.ptr),
                                    ),
                                    .end = value.span.end,
                                },
                                .node_idx = node_idx,
                            });
                            break;
                        }
                        const num = std.fmt.parseInt(i64, digits, 10) catch {
                            try errors.append(gpa, .{
                                .tag = .{
                                    .invalid_attr_value = .{
                                        .reason = "not a valid integer number",
                                    },
                                },
                                .main_location = .{
                                    .start = @intCast(
                                        value.span.start + (digits.ptr - value_slice.ptr),
                                    ),
                                    .end = @intCast(
                                        value.span.start + (digits.ptr - value_slice.ptr) + digits.len,
                                    ),
                                },
                                .node_idx = node_idx,
                            });
                            continue;
                        };

                        if (idx == 2) {
                            if (num < 0) try errors.append(gpa, .{
                                .tag = .{
                                    .invalid_attr_value = .{
                                        .reason = "must be a non-negative integer",
                                    },
                                },
                                .main_location = .{
                                    .start = @intCast(
                                        value.span.start + (digits.ptr - value_slice.ptr),
                                    ),
                                    .end = @intCast(
                                        value.span.start + (digits.ptr - value_slice.ptr) + digits.len,
                                    ),
                                },
                                .node_idx = node_idx,
                            });
                        }
                    }
                }

                if (idx < 3) {
                    try errors.append(gpa, .{
                        .tag = .{
                            .invalid_attr_value = .{
                                .reason = "should contain 3 numbers when [shape] is 'circle'",
                            },
                        },
                        .main_location = value.span,
                        .node_idx = node_idx,
                    });
                }
            },
        }
    }

    const has_href = seen_attrs[attributes.comptimeIndex("href")] != null;
    if (!has_href) {
        for (seen_attrs[attributes.comptimeIndex("href") + 1 ..]) |maybe_span| if (maybe_span) |span| {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_combination = "missing [href]",
                },
                .main_location = span,
                .node_idx = node_idx,
            });
        };

        if (has_itemprop) |span| {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_combination = "missing [href]",
                },
                .main_location = span,
                .node_idx = node_idx,
            });
        }
    }

    // If the area element has no href attribute, then the area represented by
    //the element cannot be selected, and the alt attribute must be omitted.
    if (seen_attrs[attributes.comptimeIndex("alt")] == null and has_href) {
        try errors.append(gpa, .{
            .tag = .{
                .missing_required_attr = "alt",
            },
            .main_location = vait.name,
            .node_idx = node_idx,
        });
    }

    return area.model;
}
