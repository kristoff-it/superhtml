const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const root = @import("../../root.zig");
const Span = root.Span;
const Ast = @import("../Ast.zig");
const Element = @import("../Element.zig");
const Model = Element.Model;
const Categories = Element.Categories;
const Attribute = @import("../Attribute.zig");
const ValidatingIterator = Attribute.ValidatingIterator;
const AttributeSet = Attribute.AttributeSet;

pub const select: Element = .{
    .tag = .select,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
            .interactive = true,
        },
        .content = .none,
    },
    .meta = .{
        .categories_superset = .{
            .flow = true,
            .phrasing = true,
            .interactive = true,
        },
    },
    .attributes = .manual, // in validateContent
    .content = .{
        .custom = .{
            .validate = validateContent,
            .completions = completionsContent,
        },
    },
    .desc =
    \\The `<select>` HTML element represents a control that provides a
    \\menu of options.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/select)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-select-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "name",
        .model = .{
            .rule = .not_empty,
            .desc = "This attribute is used to specify the name of the control.",
        },
    },
    .{
        .name = "required",
        .model = .{
            .rule = .bool,
            .desc = "A Boolean attribute indicating that an option with a non-empty string value must be selected.",
        },
    },
    .{
        .name = "multiple",
        .model = .{
            .rule = .bool,
            .desc = "This Boolean attribute indicates that multiple options can be selected in the list. If it is not specified, then only one option can be selected at a time. When multiple is specified, most browsers will show a scrolling list box instead of a single line dropdown. Multiple selected options are submitted using the `URLSearchParams` array convention, i.e., `name=value1&name=value2`.",
        },
    },
    .{
        .name = "size",
        .model = .{
            .rule = .manual, // validateContent
            .desc = "If the control is presented as a scrolling list box (e.g., when `multiple` is specified), this attribute represents the number of rows in the list that should be visible at one time. Browsers are not required to present a select element as a scrolled list box. The default value is 1 according to the HTML spec although browser behavior might not align.",
        },
    },
    .{
        .name = "form",
        .model = .{
            .rule = .not_empty,
            .desc =
            \\The `<form>` element to associate the <select> with (its
            \\form owner). The value of this attribute must be the id of a
            \\`<form>` in the same document. (If this attribute is not set,
            \\the `<select>` is associated with its ancestor `<form>` element,
            \\if any.)
            \\
            \\This attribute lets you associate <select> elements to `<form>`s
            \\anywhere in the document, not just inside a `<form>`. It can
            \\also override an ancestor `<form>` element.
            ,
        },
    },
    .{
        .name = "autocomplete",
        .model = .{
            .desc = "A string providing a hint for a user agent's autocomplete feature. See The HTML autocomplete attribute for a complete list of values and details on how to use autocomplete.",
            .rule = .{
                .list = .init(.none, .one, &.{
                    .{
                        .label = "off",
                        .desc = "The browser may not automatically complete entries.",
                    },
                    .{
                        .label = "on",
                        .desc = "The browser may automatically complete entries.",
                    },
                }),
            },
        },
    },
    .{
        .name = "disabled",
        .model = .{
            .rule = .bool,
            .desc = "This Boolean attribute indicates that the user cannot interact with the control. If this attribute is not specified, the control inherits its setting from the containing element, for example `<fieldset>`; if there is no containing element with the disabled attribute set, then the control is enabled.",
        },
    },
});

pub fn validateContent(
    gpa: Allocator,
    nodes: []const Ast.Node,
    seen_attrs: *std.StringHashMapUnmanaged(Span),
    seen_ids: *std.StringHashMapUnmanaged(Span),
    errors: *std.ArrayListUnmanaged(Ast.Error),
    src: []const u8,
    parent_idx: u32,
) !void {

    // A select element whose multiple attribute is absent, and whose display
    // size is 1, is expected to render as an 'inline-block' one-line drop-down
    // box.
    //
    // The display size of a select element is the result of applying the
    // rules for parsing non-negative integers to the value of the element's
    // size attribute, if it has one and parsing it is successful. If applying
    // those rules to the attribute's value is not successful, or if the
    // size attribute is absent, then the element's display size is 4 if the
    // element's multiple content attribute is present, and 1 otherwise.

    const parent = nodes[parent_idx];
    const parent_span = parent.span(src);
    var vait: ValidatingIterator = .init(
        errors,
        seen_attrs,
        seen_ids,
        .html,
        parent.open,
        src,
        parent_idx,
    );

    var has_multiple = false;
    var size: u32 = 1;
    while (try vait.next(gpa, src)) |attr| {
        const name = attr.name.slice(src);
        const attr_model = blk: {
            if (attributes.index(name)) |idx| {
                if (attributes.comptimeIndex("multiple") == idx) {
                    has_multiple = true;
                    continue;
                }
                if (attributes.comptimeIndex("size") == idx) {
                    const value = attr.value orelse {
                        try errors.append(gpa, .{
                            .tag = .missing_attr_value,
                            .main_location = attr.name,
                            .node_idx = parent_idx,
                        });
                        continue;
                    };

                    const value_string = std.mem.trim(
                        u8,
                        value.span.slice(src),
                        &std.ascii.whitespace,
                    );

                    if (std.fmt.parseInt(u32, value_string, 10)) |number| {
                        if (number > 0) {
                            size = number;
                            continue;
                        }
                    } else |_| {}
                    try errors.append(gpa, .{
                        .tag = .{
                            .invalid_attr_value = .{
                                .reason = "not a valid positive integer",
                            },
                        },
                        .main_location = attr.name,
                        .node_idx = parent_idx,
                    });
                    continue;
                }

                break :blk attributes.list[idx].model;
            }

            break :blk Attribute.global.get(name) orelse {
                if (Attribute.isData(name)) continue;
                try errors.append(gpa, .{
                    .tag = .invalid_attr,
                    .main_location = attr.name,
                    .node_idx = parent_idx,
                });

                continue;
            };
        };

        try attr_model.rule.validate(gpa, errors, src, parent_idx, attr);
    }

    // Zero or one button elements if the select is a drop-down box, followed by
    // zero or more select element inner content elements.
    const can_have_button = !has_multiple and size == 1;
    var state: union(enum) { button, rest: ?u32 } = if (can_have_button) .button else .{
        .rest = null,
    };
    var child_idx = parent.first_child_idx;
    while (child_idx != 0) {
        const child = nodes[child_idx];
        defer child_idx = child.next_idx;

        if (child.kind == .comment) continue;

        const child_span = child.span(src);

        state: switch (state) {
            .button => switch (child.kind) {
                .button => state = .{ .rest = child_idx },
                else => {
                    state = .{ .rest = null };
                    continue :state .{ .rest = null };
                },
            },
            .rest => |maybe_btn| switch (child.kind) {
                else => try errors.append(gpa, .{
                    .tag = .{ .invalid_nesting = .{ .span = parent_span } },
                    .main_location = child_span,
                    .node_idx = child_idx,
                }),
                .option,
                .optgroup,
                .hr,
                .script,
                .template,
                .noscript,
                .div,
                => {},
                .button => if (maybe_btn) |first_idx| try errors.append(gpa, .{
                    .tag = .{
                        .duplicate_child = .{
                            .span = nodes[first_idx].span(src),
                        },
                    },
                    .main_location = child_span,
                    .node_idx = child_idx,
                }) else if (can_have_button) try errors.append(gpa, .{
                    .tag = .{ .wrong_position = .first },
                    .main_location = child_span,
                    .node_idx = child_idx,
                }) else try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = parent_span,
                            .reason = "requires <select> to have [size] set to 1 and to not define [multiple]",
                        },
                    },
                    .main_location = child_span,
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
    const parent = ast.nodes[parent_idx];

    var has_multiple = false;
    var size: u32 = 1;
    var it = parent.startTagIterator(src, .html);
    while (it.next(src)) |attr| {
        const name = attr.name.slice(src);
        const idx = attributes.index(name) orelse continue;
        if (attributes.comptimeIndex("multiple") == idx) {
            has_multiple = true;
            continue;
        }

        if (attributes.comptimeIndex("size") == idx) {
            const value = attr.value orelse continue;
            const value_string = std.mem.trim(
                u8,
                value.span.slice(src),
                &std.ascii.whitespace,
            );

            const number = std.fmt.parseInt(u32, value_string, 10) catch continue;
            if (number > 0) size = number;
        }
    }

    const can_have_button = !has_multiple and size == 1;

    var child_idx = parent.first_child_idx;
    const dont_suggest_button = !can_have_button or while (child_idx != 0) {
        const child = ast.nodes[child_idx];
        defer child_idx = child.next_idx;
        if (child.kind == .comment) continue;

        if (child.kind == .button) {
            break true;
        }

        if (child.open.start < offset) break true;
        break false;
    } else false;

    return Element.simpleCompletions(
        arena,
        if (dont_suggest_button) &.{ .option, .optgroup } else &.{
            .button,
            .option,
            .optgroup,
        },
        .none,
        .none,
        .{
            .extra_children = &.{
                .hr,
                .script,
                .template,
                .noscript,
                .div,
            },
        },
    );
}
