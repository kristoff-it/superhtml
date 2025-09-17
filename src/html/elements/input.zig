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

pub const input: Element = .{
    .tag = .input,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
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
    .attributes = .{ .dynamic = validate },
    .content = .model,
    .desc =
    \\The `<input>` HTML element is used to create interactive
    \\controls for web-based forms in order to accept data from the
    \\user; a wide variety of types of input data and control widgets
    \\are available, depending on the device and user agent. The
    \\`<input>` element is one of the most powerful and complex in all
    \\of HTML due to the sheer number of combinations of input types
    \\and attributes.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/input)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-input-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "type",
        .model = .{
            .desc = "How an `<input>` works varies considerably depending on the value of this attribute. If this attribute is not specified, the default type adopted is `text`.",
            .rule = .{
                .list = .init(.none, .one, &.{
                    .{
                        .label = "button",
                        .desc = "A push button with no default behavior displaying the value of the `value` attribute, empty by default.",
                    },
                    .{
                        .label = "checkbox",
                        .desc = "A check box allowing single values to be selected/deselected.",
                    },
                    .{
                        .label = "color",
                        .desc = "A control for specifying a color; opening a color picker when active in supporting browsers.",
                    },
                    .{
                        .label = "date",
                        .desc = "A control for entering a date (year, month, and day, with no time). Opens a date picker or numeric wheels for year, month, day when active in supporting browsers.",
                    },
                    .{
                        .label = "datetime-local",
                        .desc = "A control for entering a date and time, with no time zone. Opens a date picker or numeric wheels for date- and time-components when active in supporting browsers.",
                    },
                    .{
                        .label = "email",
                        .desc = "A field for editing an email address. Looks like a `text` input, but has validation parameters and relevant keyboard in supporting browsers and devices with dynamic keyboards.",
                    },
                    .{
                        .label = "file",
                        .desc = "A control that lets the user select a file. Use the `accept` attribute to define the types of files that the control can select.",
                    },
                    .{
                        .label = "hidden",
                        .desc = "A control that is not displayed but whose value is submitted to the server.",
                    },
                    .{
                        .label = "image",
                        .desc = "A graphical submit button. Displays an image defined by the `src` attribute. The `alt` attribute displays if the image `src` is missing.",
                    },
                    .{
                        .label = "month",
                        .desc = "A control for entering a month and year, with no time zone.",
                    },
                    .{
                        .label = "number",
                        .desc = "A control for entering a number. Displays a spinner and adds default validation. Displays a numeric keypad in some devices with dynamic keypads.",
                    },
                    .{
                        .label = "password",
                        .desc = "A single-line text field whose value is obscured. Will alert user if site is not secure.",
                    },
                    .{
                        .label = "radio",
                        .desc = "A radio button, allowing a single value to be selected out of multiple choices with the same `name` value.",
                    },
                    .{
                        .label = "range",
                        .desc = "A control for entering a number whose exact value is not important. Displays as a range widget defaulting to the middle value. Used in conjunction `min` and `max` to define the range of acceptable values.",
                    },
                    .{
                        .label = "reset",
                        .desc = "A button that resets the contents of the form to default values. Good for pranking users.",
                    },
                    .{
                        .label = "search",
                        .desc = "A single-line text field for entering search strings. Line-breaks are automatically removed from the input value. May include a delete icon in supporting browsers that can be used to clear the field. Displays a search icon instead of enter key on some devices with dynamic keypads.",
                    },
                    .{
                        .label = "submit",
                        .desc = "A button that submits the form.",
                    },
                    .{
                        .label = "tel",
                        .desc = "A control for entering a telephone number. Displays a telephone keypad in some devices with dynamic keypads.",
                    },
                    .{
                        .label = "text",
                        .desc = "The default value. A single-line text field. Line-breaks are automatically removed from the input value.",
                    },
                    .{
                        .label = "time",
                        .desc = "A control for entering a time value with no time zone.",
                    },
                    .{
                        .label = "url",
                        .desc = "A field for entering a URL. Looks like a `text` input, but has validation parameters and relevant keyboard in supporting browsers and devices with dynamic keyboards.",
                    },
                    .{
                        .label = "week",
                        .desc = "A control for entering a date consisting of a week-year number and a week number with no time zone.",
                    },
                }),
            },
        },
    },
    .{
        .name = "name",
        .model = .{
            .rule = .not_empty,
            .desc = "Name of the form control. Submitted with the form as part of a name/value pair.",
        },
    },
    .{
        .name = "value",
        .model = .{
            .rule = .any,
            .desc = "The value of the control. When specified in the HTML, corresponds to the initial value.",
        },
    },
    .{
        .name = "placeholder",
        .model = .{
            .rule = .{ .custom = validatePlaceholder },
            .desc = "Text that appears in the form control when it has no value set.",
        },
    },
    .{
        .name = "checked",
        .model = .{
            .rule = .bool,
            .desc = "Whether the command or control is checked.",
        },
    },
    .{
        .name = "required",
        .model = .{
            .rule = .bool,
            .desc = "A value is required or must be checked for the form to be submittable.",
        },
    },
    .{
        .name = "disabled",
        .model = .{
            .rule = .bool,
            .desc = "The Boolean `disabled` attribute, when present, makes the element not mutable, focusable, or even submitted with the form. The user can neither edit nor focus on the control, nor its form control descendants.",
        },
    },
    .{
        .name = "readonly",
        .model = .{
            .rule = .bool,
            .desc = "The value is not editable.",
        },
    },
    .{
        .name = "maxlength",
        .model = .{
            .rule = .{ .non_neg_int = .{} },
            .desc = "Maximum length (number of characters) of `value`.",
        },
    },
    .{
        .name = "minlength",
        .model = .{
            .rule = .{ .non_neg_int = .{} },
            .desc = "Minimum length (number of characters) of `value`.",
        },
    },
    .{
        .name = "min",
        .model = .{
            .rule = .manual,
            .desc = "Minimum value",
        },
    },
    .{
        .name = "max",
        .model = .{
            .rule = .manual,
            .desc = "Maximum value",
        },
    },
    .{
        .name = "step",
        .model = .{
            .rule = .any, // TODO: .manual
            .desc = "Incremental values that are valid.",
        },
    },
    .{
        .name = "autocomplete",
        .model = .{
            .desc = "",
            .rule = .any, // TODO: implement the full official bonkers validation
        },
    },
    .{
        .name = "pattern",
        .model = .{
            .rule = .any,
            .desc = "Pattern the value must match to be valid.",
        },
    },
    .{
        .name = "multiple",
        .model = .{
            .rule = .bool,
            .desc = "Whether to allow multiple values.",
        },
    },
    .{
        .name = "list",
        .model = .{
            .rule = .not_empty,
            .desc = "Value of the `id` attribute of the `<datalist>` of autocomplete options.",
        },
    },
    .{
        .name = "size",
        .model = .{
            .rule = .{ .non_neg_int = .{} },
            .desc = "The number of characters that, in a visual rendering, the user agent is to allow the user to see while editing the element's value.",
        },
    },
    .{
        .name = "form",
        .model = .{
            .rule = .not_empty,
            .desc =
            \\A string specifying the `<form>` element with which the
            \\input is associated (that is, its form owner). This string's
            \\value, if present, must match the id of a `<form>` element
            \\in the same document. If this attribute isn't specified, the
            \\`<input>` element is associated with the nearest containing
            \\form, if any.
            \\
            \\The `form` attribute lets you place an input anywhere in the
            \\document but have it included with a form elsewhere in the
            \\document.
            ,
        },
    },
    .{
        .name = "formaction",
        .model = .{
            .rule = .{ .url = .not_empty },
            .desc = "Valid for the `image` and `submit` input types only. The URL that processes the information submitted by the button. Overrides the `action` attribute of the button's form owner. Does nothing if there is no form owner.",
        },
    },
    .{
        .name = "formenctype",
        .model = .{
            .rule = @import("button.zig").attributes.get("formenctype").?.rule,
            .desc = "Valid for the `image` and `submit` input types only. Specifies how to encode the form data that is submitted.",
        },
    },
    .{
        .name = "formmethod",
        .model = .{
            .rule = @import("button.zig").attributes.get("formmethod").?.rule,
            .desc = "Valid for the `image` and `submit` input types only. This attribute specifies the HTTP method used to submit the form.",
        },
    },
    .{
        .name = "formnovalidate",
        .model = .{
            .rule = .bool,
            .desc =
            \\Valid for the image and submit input types only.
            \\This Boolean attribute specifies that the form is not to be
            \\validated when it is submitted. If this attribute is specified, it
            \\overrides the `novalidate` attribute of the button's form owner.
            ,
        },
    },
    .{
        .name = "formtarget",
        .model = .{
            .desc =
            \\Valid for the `image` and `submit` input types only. This attribute
            \\is an author-defined name or standardized, underscore-prefixed
            \\keyword indicating where to display the response from submitting
            \\the form.
            ,
            .rule = .{
                .list = blk: {
                    const target = Attribute.common.target.rule.list;
                    break :blk .init(
                        target.extra,
                        .one,
                        target.completions[0 .. target.completions.len - 1],
                    );
                },
            },
        },
    },
    .{
        .name = "src",
        .model = .{
            .rule = .{ .url = .not_empty },
            .desc = "Same as `src` attribute for `<img>`; address of image resource.",
        },
    },
    .{
        .name = "alt",
        .model = .{
            .rule = .not_empty,
            .desc = "alt attribute for the image type. Required for accessibility",
        },
    },
    .{
        .name = "height",
        .model = .{
            .rule = .{ .non_neg_int = .{} },
            .desc = "Same as height attribute for `<img>`.",
        },
    },
    .{
        .name = "width",
        .model = .{
            .rule = .{ .non_neg_int = .{} },
            .desc = "Same as width attribute for `<img>`.",
        },
    },
    .{
        .name = "accept",
        .model = .{
            .desc = "Hint for expected file type in file upload controls.",
            .rule = .{
                .list = .init(.{ .custom = validateAccept }, .many_unique_comma, &.{
                    .{
                        .label = "audio/*",
                        .desc = "Indicates that sound files are accepted.",
                    },
                    .{
                        .label = "video/*",
                        .desc = "Indicates that video files are accepted.",
                    },
                    .{
                        .label = "image/*",
                        .desc = "Indicates that image files are accepted.",
                    },
                    .{
                        .label = "MIME value",
                        .value = "type/subtype",
                        .desc = "A MIME value without parameters.",
                    },
                    .{
                        .label = "File Extension",
                        .value = ".foo",
                        .desc = "A file extension.",
                    },
                }),
            },
        },
    },
    .{
        .name = "dirname",
        .model = .{
            .desc = "Valid for `hidden`, `text`, `search`, `url`, `tel`, and `email` input types, the `dirname` attribute enables the submission of the directionality of the element. When included, the form control will submit with two name/value pairs: the first being the name and value, and the second being the value of the `dirname` attribute as the name, with a value of `ltr` or `rtl` as set by the browser.",
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
    .{
        .name = "colorspace",
        .model = .{
            .desc = "",
            .rule = .{
                .list = .init(.none, .one, &.{
                    .{
                        .label = "limited-srgb",
                        .desc = "The CSS color is converted to the 'srgb' color space and limited to 8-bits per component.",
                    },
                    .{
                        .label = "display-p3",
                        .desc = "The CSS color is converted to the 'display-p3' color space.",
                    },
                }),
            },
        },
    },
    .{
        .name = "alpha",
        .model = .{
            .rule = .bool,
            .desc = "If present, it indicates the CSS color's alpha component can be manipulated by the end user and does not have to be fully opaque.",
        },
    },
    .{
        .name = "popovertarget",
        .model = .{
            .rule = .not_empty,
            .desc = "Designates an `<input type=\"button\">` as a control for a popover element.",
        },
    },
    .{
        .name = "popovertargetaction",
        .model = .{
            .rule = .not_empty,
            .desc = "Specifies the action that a popover control should perform.",
        },
    },
});

const Type = blk: {
    const labels = attributes.get("type").?.rule.list.set.keys();
    var cases: [labels.len]std.builtin.Type.EnumField = undefined;
    for (labels, &cases, 0..) |l, *case, idx| case.* = .{
        .name = @ptrCast(l),
        .value = idx,
    };

    break :blk @Type(.{
        .@"enum" = .{
            .tag_type = u8,
            .fields = &cases,
            .decls = &.{},
            .is_exhaustive = true,
        },
    });
};

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
        const model = if (attributes.index(name)) |idx| {
            attrs[idx] = attr;
            continue;
        } else Attribute.global.get(name) orelse {
            if (Attribute.isData(name)) continue;
            try errors.append(gpa, .{
                .tag = .invalid_attr,
                .main_location = attr.name,
                .node_idx = node_idx,
            });
            continue;
        };

        try model.rule.validate(gpa, errors, src, node_idx, attr);
    }

    const type_idx = attributes.comptimeIndex("type");
    const type_value: Type = if (attrs[type_idx]) |attr| blk: {
        const value = attr.value orelse {
            try errors.append(gpa, .{
                .tag = .missing_attr_value,
                .main_location = attr.name,
                .node_idx = node_idx,
            });
            break :blk .text;
        };

        const value_slice = value.span.slice(src);
        const match = try attributes.list[type_idx].model.rule.list.match(
            gpa,
            errors,
            node_idx,
            value.span.start,
            value_slice,
        );

        switch (match) {
            .none => return input.model, // error has already been reported
            .list => |list_idx| break :blk @enumFromInt(list_idx),
            else => unreachable,
        }
    } else .text;

    var active_attrs: [attrs.len]bool = @splat(false);
    active_attrs[attributes.comptimeIndex("disabled")] = true;
    active_attrs[attributes.comptimeIndex("form")] = true;
    active_attrs[attributes.comptimeIndex("name")] = true;
    active_attrs[attributes.comptimeIndex("type")] = true;
    active_attrs[attributes.comptimeIndex("value")] = true;
    active_attrs[attributes.comptimeIndex("width")] = true;

    switch (type_value) {
        .hidden => {
            active_attrs[attributes.comptimeIndex("autocomplete")] = true;
            active_attrs[attributes.comptimeIndex("dirname")] = true;
        },
        .text,
        .search,
        .tel,
        .url,
        .email,
        .password,
        => {
            active_attrs[attributes.comptimeIndex("autocomplete")] = true;
            active_attrs[attributes.comptimeIndex("dirname")] = true;
            active_attrs[attributes.comptimeIndex("list")] = type_value != .password;
            active_attrs[attributes.comptimeIndex("maxlength")] = true;
            active_attrs[attributes.comptimeIndex("minlength")] = true;
            active_attrs[attributes.comptimeIndex("pattern")] = true;
            active_attrs[attributes.comptimeIndex("placeholder")] = true;
            active_attrs[attributes.comptimeIndex("readonly")] = true;
            active_attrs[attributes.comptimeIndex("required")] = true;
            active_attrs[attributes.comptimeIndex("size")] = true;
            active_attrs[attributes.comptimeIndex("multiple")] = type_value == .email;
        },
        .date,
        .month,
        .week,
        .time,
        .@"datetime-local",
        .number,
        .range,
        => {
            active_attrs[attributes.comptimeIndex("autocomplete")] = true;
            active_attrs[attributes.comptimeIndex("list")] = true;
            active_attrs[attributes.comptimeIndex("max")] = true;
            active_attrs[attributes.comptimeIndex("min")] = true;
            active_attrs[attributes.comptimeIndex("placeholder")] = type_value == .number;
            active_attrs[attributes.comptimeIndex("readonly")] = type_value != .range;
            active_attrs[attributes.comptimeIndex("required")] = type_value != .range;
            active_attrs[attributes.comptimeIndex("step")] = true;
        },
        .color => {
            active_attrs[attributes.comptimeIndex("alpha")] = true;
            active_attrs[attributes.comptimeIndex("autocomplete")] = true;
            active_attrs[attributes.comptimeIndex("colorspace")] = true;
            active_attrs[attributes.comptimeIndex("list")] = true;
        },
        .checkbox, .radio => {
            active_attrs[attributes.comptimeIndex("checked")] = true;
            active_attrs[attributes.comptimeIndex("required")] = true;
        },
        .file => {
            active_attrs[attributes.comptimeIndex("accept")] = true;
            active_attrs[attributes.comptimeIndex("multiple")] = true;
            active_attrs[attributes.comptimeIndex("required")] = true;
        },
        .submit => {
            active_attrs[attributes.comptimeIndex("dirname")] = true;
            active_attrs[attributes.comptimeIndex("formaction")] = true;
            active_attrs[attributes.comptimeIndex("formenctype")] = true;
            active_attrs[attributes.comptimeIndex("formmethod")] = true;
            active_attrs[attributes.comptimeIndex("formnovalidate")] = true;
            active_attrs[attributes.comptimeIndex("formtarget")] = true;
            active_attrs[attributes.comptimeIndex("popovertarget")] = true;
            active_attrs[attributes.comptimeIndex("popovertargetaction")] = true;
        },
        .image => {
            active_attrs[attributes.comptimeIndex("alt")] = true;
            active_attrs[attributes.comptimeIndex("formaction")] = true;
            active_attrs[attributes.comptimeIndex("formenctype")] = true;
            active_attrs[attributes.comptimeIndex("formmethod")] = true;
            active_attrs[attributes.comptimeIndex("formnovalidate")] = true;
            active_attrs[attributes.comptimeIndex("formtarget")] = true;
            active_attrs[attributes.comptimeIndex("height")] = true;
            active_attrs[attributes.comptimeIndex("popovertarget")] = true;
            active_attrs[attributes.comptimeIndex("popovertargetaction")] = true;
            active_attrs[attributes.comptimeIndex("src")] = true;
            active_attrs[attributes.comptimeIndex("width")] = true;
        },
        .reset, .button => {
            active_attrs[attributes.comptimeIndex("popovertarget")] = true;
            active_attrs[attributes.comptimeIndex("popovertargetaction")] = true;
        },
    }

    assert(type_idx == 0);
    for (attrs[1..], active_attrs[1..], 1..) |maybe_attr, active, idx| {
        @setEvalBranchQuota(3000);
        const attr = maybe_attr orelse continue;

        if (!active) {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_combination = switch (type_value) {
                        inline else => |tag| "not valid when [type] is '" ++ @tagName(tag) ++ "'",
                    },
                },
                .main_location = attr.name,
                .node_idx = node_idx,
            });
            continue;
        }

        const rule: Attribute.Rule = switch (idx) {
            attributes.comptimeIndex("min"),
            attributes.comptimeIndex("max"),
            => switch (type_value) {
                .date => .any,
                .month => .any,
                .week => .any,
                .time => .any,
                .@"datetime-local" => .any,
                .number => .float,
                .range => .any,
                else => unreachable,
            },
            else => attributes.list[idx].model.rule,
        };
        try rule.validate(gpa, errors, src, node_idx, attr);
    }

    switch (type_value) {
        else => {},
        .text, .tel => {
            // The value attribute, if specified, must have a value that contains no U+000A LINE FEED (LF) or U+000D CARRIAGE RETURN (CR) characters.
        },
        .url => {
            // The value attribute, if specified and not empty, must have a value that is a valid URL potentially surrounded by spaces that is also an absolute URL.
            //
            //
            // An absolute-URL string must be one of the following:

            // a URL-scheme string that is an ASCII case-insensitive match for a special scheme and not an ASCII case-insensitive match for "file", followed by U+003A (:) and a scheme-relative-special-URL string

            // a URL-scheme string that is not an ASCII case-insensitive match for a special scheme, followed by U+003A (:) and a relative-URL string

            // a URL-scheme string that is an ASCII case-insensitive match for "file", followed by U+003A (:) and a scheme-relative-file-URL string
        },
        .email => {

            // When the multiple attribute is not specified on the element
            // The value attribute, if specified and not empty, must have a value that is a single valid email address.
            //
            //
            // When the multiple attribute is specified on the element
            // The value attribute, if specified, must have a value that is a valid email address list.

        },
        .password => {
            // The value attribute, if specified, must have a value that contains no U+000A LINE FEED (LF) or U+000D CARRIAGE RETURN (CR) characters.
        },
        .date => {

            // The value attribute, if specified and not empty, must have a value that is a valid date string.

            // The value sanitization algorithm is as follows: If the value of the element is not a valid date string, then set it to the empty string instead.

            // The min attribute, if specified, must have a value that is a valid date string. The max attribute, if specified, must have a value that is a valid date string.

            // The step attribute is expressed in days. The step scale factor is 86,400,000 (which converts the days to milliseconds, as used in the other algorithms). The default step is 1 day.
        },
        .month => {

            // The value attribute, if specified and not empty, must have a value that is a valid month string.

            // The value sanitization algorithm is as follows: If the value of the element is not a valid month string, then set it to the empty string instead.

            // The min attribute, if specified, must have a value that is a valid month string. The max attribute, if specified, must have a value that is a valid month string.

            // The step attribute is expressed in months. The step scale factor is 1 (there is no conversion needed as the algorithms use months). The default step is 1 month.

        },
        .week => {

            // The value attribute, if specified and not empty, must have a value that is a valid week string.

            // The value sanitization algorithm is as follows: If the value of the element is not a valid week string, then set it to the empty string instead.

            // The min attribute, if specified, must have a value that is a valid week string. The max attribute, if specified, must have a value that is a valid week string.

            // The step attribute is expressed in weeks. The step scale factor is 604,800,000 (which converts the weeks to milliseconds, as used in the other algorithms). The default step is 1 week. The default step base is −259,200,000 (the start of week 1970-W01).
        },
        .time => {

            // The value attribute, if specified and not empty, must have a value that is a valid time string.

            // The value sanitization algorithm is as follows: If the value of the element is not a valid time string, then set it to the empty string instead.

            // The form control has a periodic domain.

            // The min attribute, if specified, must have a value that is a valid time string. The max attribute, if specified, must have a value that is a valid time string.

            // The step attribute is expressed in seconds. The step scale factor is 1000 (which converts the seconds to milliseconds, as used in the other algorithms). The default step is 60 seconds.

        },

        .@"datetime-local" => {

            // The value attribute, if specified and not empty, must have a value that is a valid local date and time string.

            // The value sanitization algorithm is as follows: If the value of the element is a valid local date and time string, then set it to a valid normalized local date and time string representing the same date and time; otherwise, set it to the empty string instead.

            // The min attribute, if specified, must have a value that is a valid local date and time string. The max attribute, if specified, must have a value that is a valid local date and time string.

            // The step attribute is expressed in seconds. The step scale factor is 1000 (which converts the seconds to milliseconds, as used in the other algorithms). The default step is 60 seconds.

        },

        .number => {

            // The value attribute, if specified and not empty, must have a value that is a valid floating-point number.

            // The value sanitization algorithm is as follows: If the value of the element is not a valid floating-point number, then set it to the empty string instead.

            // The min attribute, if specified, must have a value that is a valid floating-point number. The max attribute, if specified, must have a value that is a valid floating-point number.

            // The step scale factor is 1. The default step is 1 (allowing only integers to be selected by the user, unless the step base has a non-integer value).

        },
        .range => {

            // The value attribute, if specified, must have a value that is a valid floating-point number.
            //
            // The min attribute, if specified, must have a value that is a valid floating-point number. The default minimum is 0. The max attribute, if specified, must have a value that is a valid floating-point number. The default maximum is 100.

        },

        .color => {

            // The value attribute, if specified and not the empty string, must have a value that is a CSS color.

        },
        .image => {

            // The image is given by the src attribute. The src attribute must be present, and must contain a valid non-empty URL potentially surrounded by spaces referencing a non-interactive, optionally animated, image resource that is neither paged nor scripted.
            //
            // The alt attribute must be present, and must contain a non-empty string giving the label that would be appropriate for an equivalent button if the image was unavailable.
        },
        .button => {

            // A label for the button must be provided in the value attribute, though it may be the empty string.
        },
    }

    return input.model;
}

fn validatePlaceholder(
    gpa: Allocator,
    errors: *std.ArrayListUnmanaged(Ast.Error),
    src: []const u8,
    node_idx: u32,
    attr: Tokenizer.Attr,
) !void {
    const value = attr.value orelse return errors.append(gpa, .{
        .tag = .missing_attr_value,
        .main_location = attr.name,
        .node_idx = node_idx,
    });
    const value_slice = value.span.slice(src);

    const cr_lf = std.mem.indexOfAny(u8, value_slice, "\r\n") orelse return;
    return errors.append(gpa, .{
        .tag = .{
            .invalid_attr_value = .{
                .reason = "cannot contain CR or LF (newlines)",
            },
        },
        .main_location = .{
            .start = @intCast(value.span.start + cr_lf),
            .end = @intCast(value.span.start + cr_lf + 1),
        },
        .node_idx = node_idx,
    });
}
fn validateAccept(value: []const u8) ?Attribute.Rule.ValueRejection {
    if (value.len == 0) return .{};
    if (value[0] == '.') return null;

    // 3. Let type be the result of collecting a sequence of code points that
    // are not U+002F (/) from input, given position.
    // 5. If position is past the end of input, then return failure.
    const slash_idx = std.mem.indexOfScalar(u8, value, '/') orelse {
        return .{
            .reason = "missing leading '.' for file extension or missing '/' in MIME value",
        };
    };

    const mime_type = value[0..slash_idx];

    // 4. If type is the empty string or does not solely contain HTTP token code
    // points, then return failure.
    if (mime_type.len == 0) return .{
        .reason = "emtpy MIME type",
        .offset = @intCast(slash_idx),
    };

    if (std.mem.trim(u8, value[slash_idx + 1 ..], &std.ascii.whitespace).len == 0) return .{
        .reason = "emtpy MIME subtype",
        .offset = @intCast(slash_idx + 1),
    };

    return Attribute.validateMimeChars(mime_type);
}
