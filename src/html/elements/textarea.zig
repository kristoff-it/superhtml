const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../../root.zig");
const Span = root.Span;
const Ast = @import("../Ast.zig");
const Element = @import("../Element.zig");
const Model = Element.Model;
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;

pub const textarea: Element = .{
    .tag = .textarea,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
            .interactive = true,
        },
        .content = .{ .text = true },
    },
    .meta = .{
        .categories_superset = .{
            .metadata = true,
            .flow = true,
            .phrasing = true,
            .interactive = true,
        },
    },
    .attributes = .{ .dynamic = validateAttrs },
    // .content = .{
    //     .custom = .{
    //         .validate = validateContent,
    //         .completions = completionsContent,
    //     },
    // },
    .content = .model,
    .desc =
    \\The `<textarea>` HTML element represents a multi-line plain-text
    \\editing control, useful when you want to allow users to enter a
    \\sizeable amount of free-form text, for example a comment on a review
    \\or feedback form.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/textarea)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-textarea-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "name",
        .model = .{
            .rule = .not_empty,
            .desc = "The name of the control.",
        },
    },
    .{
        .name = "placeholder",
        .model = .{
            .rule = .not_empty,
            .desc = "A hint to the user of what can be entered in the control. Carriage returns or line-feeds within the placeholder text will be treated as line breaks when rendering the hint.",
        },
    },
    .{
        .name = "rows",
        .model = .{
            .rule = .{ .non_neg_int = .{ .min = 1 } },
            .desc = "The number of visible text lines for the control. If it is specified, it must be a positive integer. If it is not specified, the default value is 2.",
        },
    },
    .{
        .name = "cols",
        .model = .{
            .rule = .{ .non_neg_int = .{ .min = 1 } },
            .desc = "The visible width of the text control, in average character widths. If it is specified, it must be a positive integer. If it is not specified, the default value is 20.",
        },
    },
    .{
        .name = "required",
        .model = .{
            .rule = .bool,
            .desc = "This attribute specifies that the user must fill in a value before submitting a form.",
        },
    },
    .{
        .name = "maxlength",
        .model = .{
            .rule = .{ .non_neg_int = .{} },
            .desc = "The maximum string length (measured in UTF-16 code units) that the user can enter. If this value isn't specified, the user can enter an unlimited number of characters.",
        },
    },
    .{
        .name = "minlength",
        .model = .{
            .rule = .{ .non_neg_int = .{} },
            .desc = "The minimum string length (measured in UTF-16 code units) required that the user should enter.",
        },
    },
    .{
        .name = "readonly",
        .model = .{
            .rule = .bool,
            .desc = "This Boolean attribute indicates that the user cannot modify the value of the control. Unlike the `disabled` attribute, the readonly attribute does not prevent the user from clicking or selecting in the control. The value of a read-only control is still submitted with the form.",
        },
    },
    .{
        .name = "disabled",
        .model = .{
            .rule = .bool,
            .desc = "This Boolean attribute indicates that the user cannot interact with the control. If this attribute is not specified, the control inherits its setting from the containing element, for example `<fieldset>`; if there is no containing element when the disabled attribute is set, the control is enabled.",
        },
    },
    .{
        .name = "autocomplete",
        .model = .{
            .desc = "Controls whether entered text can be automatically completed by the browser.",
            .rule = .{
                .list = .init(.none, .one, &.{
                    .{
                        .label = "off",
                        .desc = "The browser may not automatically complete entries (browsers tend to ignore this for suspected login forms).",
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
        .name = "wrap",
        .model = .{
            .desc = "Indicates how the control should wrap the value for form submission. If this attribute is not specified, `soft` is its default value.",
            .rule = .{
                .list = .init(.none, .one, &.{
                    .{
                        .label = "hard",
                        .desc = "The browser automatically inserts line breaks (`CR+LF`) so that each line is no longer than the width of the control; the `cols` attribute must be specified for this to take effect.",
                    },
                    .{
                        .label = "soft",
                        .desc = "The browser ensures that all line breaks in the entered value are a `CR+LF` pair, but no additional line breaks are added to the value.",
                    },
                }),
            },
        },
    },
    .{
        .name = "form",
        .model = .{
            .rule = .not_empty,
            .desc = "The form element that the <textarea> element is associated with (its \"form owner\"). The value of the attribute must be the id of a form element in the same document. This attribute enables you to place `<textarea>` elements anywhere within a document, not just as descendants of form elements.",
        },
    },
    .{
        .name = "dirname",
        .model = .{
            .desc = "This attribute is used to indicate the text directionality of the element contents.",
            .rule = .{
                .list = .init(.none, .one, &.{
                    .{
                        .label = "rtl",
                        .desc = "The text entered by the user is in a right-to-left writing direction.",
                    },
                    .{
                        .label = "ltr",
                        .desc = "The text entered by the user is in a left-to-right writing direction.",
                    },
                }),
            },
        },
    },
});

pub fn validateAttrs(
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
    // If the element's wrap attribute is in the Hard state, the cols attribute must be specified.

    // If an element has both a maximum allowed value length and a minimum allowed value length, the minimum allowed value length must be smaller than or equal to the maximum allowed value length.
    var has_minlength: ?struct { Span, usize } = null;
    var has_maxlength: ?usize = null;
    while (try vait.next(gpa, src)) |attr| {
        const name = attr.name.slice(src);
        const attr_model = blk: {
            if (attributes.index(name)) |idx| {
                switch (idx) {
                    attributes.comptimeIndex("minlength"),
                    attributes.comptimeIndex("maxlength"),
                    => {
                        const value = attr.value orelse {
                            try errors.append(gpa, .{
                                .tag = .missing_attr_value,
                                .main_location = attr.name,
                                .node_idx = node_idx,
                            });
                            continue;
                        };

                        const value_slice = std.mem.trim(
                            u8,
                            value.span.slice(src),
                            &std.ascii.whitespace,
                        );

                        const number = std.fmt.parseInt(usize, value_slice, 10) catch {
                            try errors.append(gpa, .{
                                .tag = .{
                                    .invalid_attr_value = .{
                                        .reason = "not a valid non-negative integer",
                                    },
                                },
                                .main_location = value.span,
                                .node_idx = node_idx,
                            });
                            continue;
                        };

                        if (idx == attributes.comptimeIndex("minlength"))
                            has_minlength = .{ value.span, number }
                        else
                            has_maxlength = number;

                        continue;
                    },
                    else => break :blk attributes.list[idx].model,
                }
            }

            break :blk Attribute.global.get(name) orelse {
                if (Attribute.isData(name)) continue;
                try errors.append(gpa, .{
                    .tag = .invalid_attr,
                    .main_location = attr.name,
                    .node_idx = node_idx,
                });
                continue;
            };
        };

        try attr_model.rule.validate(gpa, errors, src, node_idx, attr);
    }

    if (has_minlength) |min| if (has_maxlength) |max| {
        if (min[1] > max) try errors.append(gpa, .{
            .tag = .{
                .invalid_attr_combination = "[minlength] must not be greater than [maxlength]",
            },
            .main_location = min[0],
            .node_idx = node_idx,
        });
    };

    return textarea.model;
}

// pub fn validateContent(
//     gpa: Allocator,
//     nodes: []const Ast.Node,
//     errors: *std.ArrayListUnmanaged(Ast.Error),
//     src: []const u8,
//     parent_idx: u32,
// ) error{OutOfMemory}!void {
//     const parent = nodes[parent_idx];
//     const parent_span = parent.span(src);
//     var child_idx = parent.first_child_idx;
//     while (child_idx != 0) {
//         const child = nodes[child_idx];
//         defer child_idx = child.next_idx;

//         if (child.kind != .text) try errors.append(gpa, .{
//             .tag = .{
//                 .invalid_nesting = .{
//                     .span = parent_span,
//                     .reason = "only text allowed",
//                 },
//             },
//             .main_location = child.span(src),
//             .node_idx = child_idx,
//         });
//     }
// }

// fn completionsContent(
//     arena: Allocator,
//     ast: Ast,
//     src: []const u8,
//     parent_idx: u32,
//     offset: u32,
// ) error{OutOfMemory}![]const Ast.Completion {
//     _ = arena;
//     _ = ast;
//     _ = src;
//     _ = parent_idx;
//     _ = offset;
//     return &.{};
// }
