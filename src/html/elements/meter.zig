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
const log = std.log.scoped(.button);

pub const meter: Element = .{
    .tag = .meter,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
        },
        .content = .{ .phrasing = true },
    },
    .meta = .{
        .categories_superset = .{
            .flow = true,
            .phrasing = true,
        },
    },
    .attributes = .{
        .dynamic = validate,
    },
    .content = .{
        .simple = .{
            .forbidden_descendants = .init(.{ .meter = true }),
        },
    },
    .desc =
    \\The `<meter>` HTML element represents either a scalar value
    \\within a known range or a fractional value.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/meter)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-meter-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "min",
        .model = .{
            .rule = .manual,
            .desc = "The lower numeric bound of the measured range. This must be less than the maximum value (`max` attribute), if specified. If unspecified, the minimum value is 0.",
        },
    },
    .{
        .name = "max",
        .model = .{
            .rule = .manual,
            .desc = "The upper numeric bound of the measured range. This must be greater than the minimum value (`min` attribute), if specified. If unspecified, the maximum value is 1.",
        },
    },
    .{
        .name = "value",
        .model = .{
            .rule = .manual,
            .desc = "The current numeric value. This must be between the minimum and maximum values (`min` attribute and `max` attribute) if they are specified. If unspecified or malformed, the value is 0. If specified, but not within the range given by the `min` attribute and `max` attribute, the value is equal to the nearest end of the range.",
        },
    },
    .{
        .name = "optimum",
        .model = .{
            .rule = .manual,
            .desc = "This attribute indicates the optimal numeric value. It must be within the range (as defined by the `min` attribute and `max` attribute). When used with the `low` attribute and `high` attribute, it gives an indication where along the range is considered preferable. For example, if it is between the `min` attribute and the `low` attribute, then the lower range is considered preferred. The browser may color the meter's bar differently depending on whether the value is less than or equal to the optimum value.",
        },
    },
    .{
        .name = "low",
        .model = .{
            .rule = .manual,
            .desc = "The upper numeric bound of the low end of the measured range. This must be greater than the minimum value (`min` attribute), and it also must be less than the high value and maximum value (`high` attribute and `max` attribute, respectively), if any are specified. If unspecified, or if less than the minimum value, the low value is equal to the minimum value.",
        },
    },
    .{
        .name = "high",
        .model = .{
            .rule = .manual,
            .desc = "The lower numeric bound of the high end of the measured range. This must be less than the maximum value (`max` attribute), and it also must be greater than the low value and minimum value (`low` attribute and `min` attribute, respectively), if any are specified. If unspecified, or if greater than the maximum value, the high value is equal to the maximum value.",
        },
    },
});

fn validate(
    gpa: Allocator,
    errors: *std.ArrayListUnmanaged(Ast.Error),
    src: []const u8,
    nodes: []const Ast.Node,
    parent_idx: u32,
    node_idx: u32,
    vait: *Attribute.ValidatingIterator,
) error{OutOfMemory}!Model {
    _ = nodes;
    _ = parent_idx;

    var attrs: [attributes.list.len]?Tokenizer.Attr = @splat(null);
    while (try vait.next(gpa, src)) |attr| {
        const name = attr.name.slice(src);
        if (attributes.index(name)) |idx| {
            attrs[idx] = attr;
        } else if (Attribute.global.get(name)) |model| {
            try model.rule.validate(gpa, errors, src, node_idx, attr);
        } else {
            if (Attribute.isData(name)) continue;
            try errors.append(gpa, .{
                .tag = .invalid_attr,
                .main_location = attr.name,
                .node_idx = node_idx,
            });
            continue;
        }
    }

    const min: f64 = if (attrs[attributes.comptimeIndex("min")]) |attr| blk: {
        const value = attr.value orelse {
            try errors.append(gpa, .{
                .tag = .missing_attr_value,
                .main_location = attr.name,
                .node_idx = node_idx,
            });
            return meter.model;
        };

        const digits = value.span.slice(src);
        break :blk std.fmt.parseFloat(f64, digits) catch {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "not a valid floating point number",
                    },
                },
                .main_location = attr.name,
                .node_idx = node_idx,
            });
            return meter.model;
        };
    } else 0;

    const max: f64 = if (attrs[attributes.comptimeIndex("max")]) |attr| blk: {
        const value = attr.value orelse {
            try errors.append(gpa, .{
                .tag = .missing_attr_value,
                .main_location = attr.name,
                .node_idx = node_idx,
            });
            return meter.model;
        };

        const digits = value.span.slice(src);
        break :blk std.fmt.parseFloat(f64, digits) catch {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "not a valid floating point number",
                    },
                },
                .main_location = attr.name,
                .node_idx = node_idx,
            });
            return meter.model;
        };
    } else 1.0;

    if (min > max) {
        try errors.append(gpa, .{
            .tag = .{ .invalid_attr_combination = "[max] (defaults to 1.0) must be greater than [min] (defaults to 0.0)" },
            .main_location = vait.name,
            .node_idx = node_idx,
        });
        return meter.model;
    }

    const low: ?f64 = if (attrs[attributes.comptimeIndex("low")]) |attr| blk: {
        const value = attr.value orelse break :blk null;
        const digits = value.span.slice(src);
        break :blk std.fmt.parseFloat(f64, digits) catch {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "not a valid floating point number",
                    },
                },
                .main_location = attr.name,
                .node_idx = node_idx,
            });
            return meter.model;
        };
    } else null;

    const high: ?f64 = if (attrs[attributes.comptimeIndex("high")]) |attr| blk: {
        const value = attr.value orelse break :blk null;
        const digits = value.span.slice(src);
        break :blk std.fmt.parseFloat(f64, digits) catch {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "not a valid floating point number",
                    },
                },
                .main_location = attr.name,
                .node_idx = node_idx,
            });
            return meter.model;
        };
    } else null;

    if (low) |l| if (l < min) {
        try errors.append(gpa, .{
            .tag = .{
                .invalid_attr_combination = "[min] must be lower or equal than [low]",
            },
            .main_location = vait.name,
            .node_idx = node_idx,
        });
    } else if (high) |h| {
        if (l > h) {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_combination = " [low] must be lower or equal than [high]",
                },
                .main_location = vait.name,
                .node_idx = node_idx,
            });
        }
    } else if (l > max) {
        try errors.append(gpa, .{
            .tag = .{
                .invalid_attr_combination = "[low] must be lower or equal than [max]",
            },
            .main_location = vait.name,
            .node_idx = node_idx,
        });
    };

    if (high) |h| if (h < min) {
        try errors.append(gpa, .{
            .tag = .{
                .invalid_attr_combination = "[min] must be lower or equal than [high]",
            },
            .main_location = vait.name,
            .node_idx = node_idx,
        });
    } else if (h > max) {
        try errors.append(gpa, .{
            .tag = .{
                .invalid_attr_combination = "[high] must be lower or equal than [max]",
            },
            .main_location = vait.name,
            .node_idx = node_idx,
        });
    };

    if (attrs[attributes.comptimeIndex("value")]) |attr| blk: {
        const value = attr.value orelse {
            try errors.append(gpa, .{
                .tag = .{ .missing_required_attr = "value" },
                .main_location = vait.name,
                .node_idx = node_idx,
            });
            break :blk;
        };

        const digits = value.span.slice(src);
        const number = std.fmt.parseFloat(f64, digits) catch {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "not a valid floating point number",
                    },
                },
                .main_location = attr.name,
                .node_idx = node_idx,
            });
            return meter.model;
        };

        if (number < min) try errors.append(gpa, .{
            .tag = .{
                .invalid_attr_combination = "[min] (defaults to 0.0) must be lower or equal than [value]",
            },
            .main_location = vait.name,
            .node_idx = node_idx,
        });

        if (number > max) try errors.append(gpa, .{
            .tag = .{
                .invalid_attr_combination = "[value] must be lower or equal than [max] (defaults to 1.0)",
            },
            .main_location = vait.name,
            .node_idx = node_idx,
        });
    } else try errors.append(gpa, .{
        .tag = .{ .missing_required_attr = "value" },
        .main_location = vait.name,
        .node_idx = node_idx,
    });

    if (attrs[attributes.comptimeIndex("optimum")]) |attr| blk: {
        const value = attr.value orelse break :blk;
        const digits = value.span.slice(src);
        const number = std.fmt.parseFloat(f64, digits) catch {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "not a valid floating point number",
                    },
                },
                .main_location = attr.name,
                .node_idx = node_idx,
            });
            return meter.model;
        };

        if (number < min) try errors.append(gpa, .{
            .tag = .{
                .invalid_attr_combination = "[min] (defaults to 0.0) must be lower or equal than [optimum]",
            },
            .main_location = vait.name,
            .node_idx = node_idx,
        });

        if (number > max) try errors.append(gpa, .{
            .tag = .{
                .invalid_attr_combination = "[optimum] must be lower or equal than [max] (defaults to 1.0)",
            },
            .main_location = vait.name,
            .node_idx = node_idx,
        });
    }

    return meter.model;
}
