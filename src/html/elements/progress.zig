const std = @import("std");
const assert = std.debug.assert;
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

pub const progress: Element = .{
    .tag = .progress,
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
    .attributes = .{ .dynamic = validate },
    .content = .{
        .simple = .{ .forbidden_descendants = .init(.{ .progress = true }) },
    },
    .desc =
    \\The `<progress>` HTML element displays an indicator showing the
    \\completion progress of a task, typically displayed as a progress
    \\bar.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/progress)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-progress-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "max",
        .model = .{
            .rule = .manual,
            .desc = "This attribute describes how much work the task indicated by the progress element requires. The `max` attribute, if present, must have a value greater than 0 and be a valid floating point number. The default value is 1.",
        },
    },
    .{
        .name = "value",
        .model = .{
            .rule = .manual,
            .desc = "This attribute specifies how much of the task that has been completed. It must be a valid floating point number between 0 and `max`, or between 0 and 1 if `max` is omitted. If there is no `value` attribute, the progress bar is indeterminate; this indicates that an activity is ongoing with no indication of how long it is expected to take.",
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
            continue;
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

    const max: f64 = if (attrs[attributes.comptimeIndex("max")]) |attr| blk: {
        const value = attr.value orelse {
            try errors.append(gpa, .{
                .tag = .missing_attr_value,
                .main_location = attr.name,
                .node_idx = node_idx,
            });

            return progress.model;
        };

        const number = std.fmt.parseFloat(f64, value.span.slice(src)) catch {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "not a valid floating point number",
                    },
                },
                .main_location = attr.name,
                .node_idx = node_idx,
            });

            return progress.model;
        };

        if (number < 0) {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "must be greater than zero",
                    },
                },
                .main_location = attr.name,
                .node_idx = node_idx,
            });

            return progress.model;
        }
        break :blk number;
    } else 1.0;

    if (attrs[attributes.comptimeIndex("value")]) |attr| {
        const value = attr.value orelse {
            try errors.append(gpa, .{
                .tag = .missing_attr_value,
                .main_location = attr.name,
                .node_idx = node_idx,
            });

            return progress.model;
        };

        const number = std.fmt.parseFloat(f64, value.span.slice(src)) catch {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "not a valid floating point number",
                    },
                },
                .main_location = attr.name,
                .node_idx = node_idx,
            });

            return progress.model;
        };

        if (number <= 0) {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "must be greater than zero",
                    },
                },
                .main_location = attr.name,
                .node_idx = node_idx,
            });
        } else if (number > max) {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "must be lower or equal than [max] (defaults to 1.0)",
                    },
                },
                .main_location = attr.name,
                .node_idx = node_idx,
            });
        }
    }

    return progress.model;
}
