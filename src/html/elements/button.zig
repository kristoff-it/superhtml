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

pub const button: Element = .{
    .tag = .button,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
            .interactive = true,
        },
        .content = .{
            .phrasing = true,
        },
    },
    .meta = .{
        .categories_superset = .{
            .flow = true,
            .phrasing = true,
            .interactive = true,
        },
        .content_reject = .{
            .interactive = true,
        },
        .extra_reject = .{
            .tabindex = true,
        },
    },
    .attributes = .{
        .dynamic = validateAttrs,
    },
    .content = .{
        .custom = .{
            .validate = validateContent,
            .completions = completionsContent,
        },
    },
    .desc =
    \\The `<button>` HTML element is an interactive element activated by a user with
    \\a mouse, keyboard, finger, voice command, or other assistive
    \\technology. Once activated, it then performs an action, such as
    \\submitting a form or opening a dialog. By default, HTML buttons are
    \\presented in a style resembling the platform the user agent runs on,
    \\but you can change buttons' appearance with CSS.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/button)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-button-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "command",
        .model = .{
            .desc = "Specifies the action to be performed on an element being controlled by a control `<button>` specified via the `commandfor` attribute.",
            .rule = .{
                .list = .init(.{ .custom = validateCommand }, .one, &.{
                    .{
                        .label = "show-modal",
                        .desc =
                        \\The button will show a `<dialog>` as modal. If
                        \\the dialog is already modal, no action will
                        \\be taken. This is a declarative equivalent of
                        \\calling the `HTMLDialogElement.showModal()` method
                        \\on the `<dialog>` element.
                        ,
                    },
                    .{
                        .label = "close",
                        .desc =
                        \\The button will close a `<dialog>` element. If
                        \\the dialog is already closed, no action will
                        \\be taken. This is a declarative equivalent of
                        \\calling the `HTMLDialogElement.close()` method on
                        \\the `<dialog>` element.
                        ,
                    },
                    .{
                        .label = "request-close",
                        .desc =
                        \\The button will trigger a `cancel` event on a
                        \\`<dialog>` element to request that the browser
                        \\dismiss it, followed by a `close` event. This
                        \\differs from the `close` command in that authors
                        \\can call `Event.preventDefault()` on the `cancel`
                        \\event to prevent the `<dialog>` from closing. If
                        \\the dialog is already closed, no action will
                        \\be taken. This is a declarative equivalent of
                        \\calling the `HTMLDialogElement.requestClose()`
                        \\method on the `<dialog>` element.
                        ,
                    },
                    .{
                        .label = "show-popover",
                        .desc =
                        \\The button will show a hidden popover. If you
                        \\try to show an already showing popover, no
                        \\action will be taken. 
                        \\
                        \\This is equivalent to setting a value
                        \\of show for the `popovertargetaction` attribute,
                        \\and also provides a declarative equivalent to
                        \\calling the `HTMLElement.showPopover()` method on
                        \\the popover element.
                        ,
                    },
                    .{
                        .label = "hide-popover",
                        .desc =
                        \\The button will hide a showing popover. If you
                        \\try to hide an already hidden popover, no action
                        \\will be taken.
                        \\
                        \\This is equivalent to setting a value of `hide`
                        \\for the `popovertargetaction` attribute, and also
                        \\provides a declarative equivalent to calling the
                        \\`HTMLElement.hidePopover()` method on the popover
                        \\element.
                        ,
                    },
                    .{
                        .label = "toggle-popover",
                        .desc =
                        \\The button will toggle a popover between showing
                        \\and hidden. If the popover is hidden, it will
                        \\be shown; if the popover is showing, it will
                        \\be hidden.
                        \\
                        \\This is equivalent to setting a value of `toggle`
                        \\for the `popovertargetaction` attribute, and also
                        \\provides a declarative equivalent to calling the
                        \\`HTMLElement.togglePopover()` method on the popover
                        \\element.
                        ,
                    },
                    .{
                        .label = "Custom Command",
                        .value = "--mycommand",
                        .desc =
                        \\The button will dispatch a `CommandEvent` with the
                        \\`command` field set to the provided value. Must start
                        \\with '--'. 
                        ,
                    },
                }),
            },
        },
    },
    .{
        .name = "commandfor",
        .model = .{
            .rule = .not_empty,
            .desc = "Turns a `<button>` element into a command button, controlling a given interactive element by issuing the command specified in the button's `command` attribute. The `commandfor` attribute takes the ID of the element to control as its value. This is a more general version of `popovertarget`.",
        },
    },
    .{
        .name = "disabled",
        .model = .{
            .rule = .bool,
            .desc = "This Boolean attribute prevents the user from interacting with the button: it cannot be pressed or focused.",
        },
    },
    .{
        .name = "form",
        .model = .{
            .rule = .not_empty,
            .desc =
            \\The `<form>` element to associate the button with (its form
            \\owner). The value of this attribute must be the `id` of a
            \\`<form>` in the same document. (If this attribute is not set,
            \\the `<button>` is associated with its ancestor `<form>` element,
            \\if any.)
            \\
            \\This attribute lets you associate `<button>` elements to
            \\`<form>`s anywhere in the document, not just inside a `<form>`.
            \\It can also override an ancestor `<form>` element.
            ,
        },
    },
    .{
        .name = "formaction",
        .model = .{
            .rule = .{ .url = .not_empty },
            .desc = "The URL that processes the information submitted by the button. Overrides the `action` attribute of the button's form owner. Does nothing if there is no form owner.",
        },
    },
    .{
        .name = "formenctype",
        .model = .{
            .desc = "If the button is a submit button (it's inside/associated with a `<form>` and doesn't have `type=\"button\"`), specifies how to encode the form data that is submitted.",
            .rule = .{
                .list = .init(.none, .one, &.{
                    .{
                        .label = "application/x-www-form-urlencoded",
                        .desc = "The default if the attribute is not used.",
                    },
                    .{
                        .label = "multipart/form-data",
                        .desc = "Used to submit `<input>` elements with their type attributes set to `file`.",
                    },
                    .{
                        .label = "text/plain",
                        .desc = "Specified as a debugging aid; shouldn't be used for real form submission.",
                    },
                }),
            },
        },
    },
    .{
        .name = "formmethod",
        .model = .{
            .desc = "If the button is a submit button (it's inside/associated with a `<form>` and doesn't have `type=\"button\"`), this attribute specifies the HTTP method used to submit the form.",
            .rule = .{
                .list = .init(.none, .one, &.{
                    .{
                        .label = "get",
                        .desc = "The form data are appended to the form's action URL, with a `?` as a separator, and the resulting URL is sent to the server. Use this method when the form has no side effects, like search forms.",
                    },
                    .{
                        .label = "post",
                        .desc = "The data from the form are included in the body of the HTTP request when sent to the server. Use when the form contains information that shouldn't be public, like login credentials.",
                    },
                    .{
                        .label = "dialog",
                        .desc = "This method is used to indicate that the button closes the dialog with which it is associated, and does not transmit the form data at all.",
                    },
                }),
            },
        },
    },
    .{
        .name = "formnovalidate",
        .model = .{
            .rule = .bool,
            .desc =
            \\If the button is a submit button, this Boolean attribute
            \\specifies that the form is not to be validated when it is
            \\submitted. If this attribute is specified, it overrides the
            \\`novalidate` attribute of the button's form owner.
            \\
            \\This attribute is also available on `<input type="image">` and
            \\`<input type="submit">` elements.
            ,
        },
    },
    .{
        .name = "formtarget",
        .model = .{
            .desc =
            \\If the button is a submit button, this attribute is an
            \\author-defined name or standardized, underscore-prefixed
            \\keyword indicating where to display the response from
            \\submitting the form. This is the name of, or keyword for,
            \\a browsing context (a tab, window, or `<iframe>`). If this
            \\attribute is specified, it overrides the `target` attribute of
            \\the button's form owner.
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
        .name = "name",
        .model = .{
            .rule = .{ .custom = validateName },
            .desc = "The name of the button, submitted as a pair with the button's `value` as part of the form data, when that button is used to submit the form.",
        },
    },
    .{
        .name = "popovertarget",
        .model = .{
            .rule = .not_empty,
            .desc =
            \\Turns a <button> element into a popover control button;
            \\takes the ID of the popover element to control as its
            \\value. Establishing a relationship between a popover and
            \\its invoker button using the popovertarget attribute has two
            \\additional useful effects:
            \\
            \\- The browser creates an implicit aria-details and
            \\  aria-expanded relationship between popover and invoker,
            \\  and places the popover in a logical position in the
            \\  keyboard focus navigation order when shown. This makes
            \\  the popover more accessible to keyboard and assistive
            \\  technology (AT) users (see also Popover accessibility
            \\  features).
            \\    
            \\- The browser creates an implicit anchor reference between
            \\  the two, making it very convenient to position popovers
            \\  relative to their controls using CSS anchor positioning.
            \\  See Popover anchor positioning for more details.
            ,
        },
    },
    .{
        .name = "popovertargetaction",
        .model = .{
            .rule = .not_empty,
            .desc = "Specifies the action to be performed on a popover element being controlled by a control `<button>`.",
        },
    },
    .{
        .name = "type",
        .model = .{
            .desc = "The default behavior of the button.",
            .rule = .{
                .list = .init(.none, .one, &.{
                    .{
                        .label = "submit",
                        .desc = "The button submits the form data to the server. This is the default if the attribute is not specified for buttons associated with a `<form>z, or if the attribute is an empty or invalid value.",
                    },
                    .{
                        .label = "reset",
                        .desc = "The button resets all the controls to their initial values, like `<input type=\"reset\">`.",
                    },
                    .{
                        .label = "button",
                        .desc = "The button has no default behavior, and does nothing when pressed by default. It can have client-side scripts listen to the element's events, which are triggered when the events occur.",
                    },
                }),
            },
        },
    },
    .{
        .name = "value",
        .model = .{
            .rule = .any,
            .desc = "Defines the value associated with the button's `name` when it's submitted with the form data. This value is passed to the server in params when the form is submitted using this button.",
        },
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
    // The formaction, formenctype, formmethod, formnovalidate, and formtarget
    // must not be specified if the element is not a submit button.
    //
    //
    // A button element is said to be a submit button if any of the following
    // are true:
    //
    // - the type attribute is in the Auto state, both the command and commandfor
    //   content attributes are not present, and the parent node is not a select
    //   element; or
    //
    // - the type attribute is in the Submit Button state.

    var type_submit: ?bool = null;
    var command: ?Span = null;
    var commandfor: ?Span = null;
    var form_attrs: [5]Span = undefined;
    var form_idx: usize = 0;
    while (try vait.next(gpa, src)) |attr| {
        const name = attr.name.slice(src);
        const model = if (attributes.index(name)) |idx| blk: {
            switch (idx) {
                else => {},
                attributes.comptimeIndex("formaction"),
                attributes.comptimeIndex("formenctype"),
                attributes.comptimeIndex("formmethod"),
                attributes.comptimeIndex("formnovalidate"),
                attributes.comptimeIndex("formtarget"),
                => {
                    form_attrs[form_idx] = attr.name;
                    form_idx += 1;
                },
                attributes.comptimeIndex("command") => command = attr.name,
                attributes.comptimeIndex("commandfor") => commandfor = attr.name,
                attributes.comptimeIndex("type") => {
                    const value = attr.value orelse {
                        try errors.append(gpa, .{
                            .tag = .missing_attr_value,
                            .main_location = attr.name,
                            .node_idx = node_idx,
                        });
                        continue;
                    };
                    const value_slice = value.span.slice(src);
                    const model = comptime attributes.get("type").?;
                    const list_idx = model.rule.list.set.getIndex(value_slice) orelse {
                        try errors.append(gpa, .{
                            .tag = .{ .invalid_attr_value = .{} },
                            .main_location = attr.name,
                            .node_idx = node_idx,
                        });
                        continue;
                    };

                    const submit_idx = comptime model.rule.list.set.getIndex("submit").?;
                    type_submit = list_idx == submit_idx;
                    continue;
                },
                // attributes.comptimeIndex("target") => {},
            }

            break :blk attributes.list[idx].model;
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

    if (form_idx > 0) {
        const is_submit = (type_submit orelse false) or (type_submit == null and blk: {
            // - the type attribute is in the Auto state, both the command and commandfor
            //   content attributes are not present, and the parent node is not a select
            //   element; or
            if (commandfor != null or command != null) break :blk false;
            if (nodes[parent_idx].kind == .select) break :blk false;
            break :blk true;
        });

        if (!is_submit) {
            for (form_attrs[0..form_idx]) |span| {
                try errors.append(gpa, .{
                    .tag = .{
                        .invalid_attr_combination = blk: {
                            if (type_submit != null) break :blk "incompatible with [type] set to 'reset' or 'button'";

                            if (commandfor != null) break :blk "incompatible with [commandfor] when [type] is not 'submit'";

                            if (command != null) break :blk "incompatible with [command] when [type] is not 'submit'";

                            if (nodes[parent_idx].kind == .select) break :blk "incompatible with button being nested under a <select> when [type] is not 'submit'";

                            unreachable;
                            // "requires 'type=submit' or for the button element to not be the child of a 'select' and to not have 'command'/'commandfor' defined",
                        },
                    },
                    .main_location = span,
                    .node_idx = node_idx,
                });
            }
        }
    }

    return button.model;
}

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
    const parent_span = parent.startTagIterator(src, .html).name_span;
    const first_child_idx = parent.first_child_idx;
    if (first_child_idx == 0) return;
    const stop_idx = parent.stop(nodes);

    // If the element is the first child of a select element, then it may also
    // have zero or one descendant selectedcontent element.
    const can_have_selectedcontent = blk: {
        if (parent.parent_idx == 0) break :blk false;
        const granpa = nodes[parent.parent_idx];
        break :blk granpa.kind == .select and
            granpa.first_child_idx == parent_idx;
    };

    var seen_selectedcontent: ?Span = null;
    var next_idx = first_child_idx;
    while (next_idx < stop_idx) {
        const node_idx = next_idx;
        const node = nodes[next_idx];

        if (node.kind == .___) {
            next_idx = node.stop(nodes);
            continue;
        } else if (node.kind == .svg or node.kind == .math) {
            next_idx = node.stop(nodes);
        } else {
            next_idx += 1;
            if (!node.kind.isElement()) continue;
        }

        const node_span = node.startTagIterator(src, .html).name_span;

        if (node.kind == .selectedcontent) {
            if (!can_have_selectedcontent) {
                try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = parent_span,
                            .reason = "only allowed when button is the first child of a <select>",
                        },
                    },
                    .main_location = node_span,
                    .node_idx = node_idx,
                });
                continue;
            }

            if (seen_selectedcontent) |sc| {
                try errors.append(gpa, .{
                    .tag = .{
                        .duplicate_child = .{
                            .span = sc,
                            .reason = "button can only have one <selectedcontent> descendant",
                        },
                    },
                    .main_location = node_span,
                    .node_idx = node_idx,
                });
                continue;
            }

            seen_selectedcontent = node_span;
            // continue validation of extra

        }

        if (button.modelRejects(
            nodes,
            src,
            parent,
            parent_span,
            &Element.all.get(node.kind),
            node.model,
        )) |rejection| {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_nesting = .{
                        .span = rejection.span,
                        .reason = rejection.reason,
                    },
                },
                .main_location = node_span,
                .node_idx = node_idx,
            });
            continue;
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
    _ = src;
    _ = offset;

    const nodes = ast.nodes;
    const parent = nodes[parent_idx];
    const first_child_idx = parent.first_child_idx;

    // If the element is the first child of a select element, then it may also
    // have zero or one descendant selectedcontent element.
    const can_have_selectedcontent = blk: {
        if (parent.parent_idx == 0) break :blk false;
        const granpa = nodes[parent.parent_idx];
        break :blk granpa.kind == .select and
            granpa.first_child_idx == parent_idx;
    };

    const want_sc = can_have_selectedcontent and blk: {
        if (first_child_idx == 0) break :blk true;

        const stop_idx = parent.stop(nodes);

        var next_idx = first_child_idx;
        break :blk while (next_idx < stop_idx) {
            const node = nodes[next_idx];

            if (node.kind == .___) {
                next_idx = node.stop(nodes);
                continue;
            } else if (node.kind == .svg or node.kind == .math) {
                next_idx = node.stop(nodes);
            } else {
                next_idx += 1;
                if (!node.kind.isElement()) continue;
            }

            if (node.kind == .selectedcontent) break true;
        } else false;
    };

    const prefix: []const Ast.Kind = if (want_sc) &.{.selectedcontent} else &.{};
    return Element.simpleCompletions(
        arena,
        prefix,
        button.model.content,
        button.meta.content_reject,
        .{},
    );
}

fn validateCommand(value: []const u8) ?Attribute.Rule.ValueRejection {
    if (std.mem.startsWith(u8, value, "--")) return null;
    return .{
        .reason = "custom commands must start with '--'",
    };
}

fn validateName(
    gpa: Allocator,
    errors: *std.ArrayListUnmanaged(Ast.Error),
    src: []const u8,
    node_idx: u32,
    attr: Tokenizer.Attr,
) !void {
    log.debug("validating name", .{});
    const value = attr.value orelse return errors.append(gpa, .{
        .tag = .missing_attr_value,
        .main_location = attr.name,
        .node_idx = node_idx,
    });
    const value_slice = value.span.slice(src);
    if (value_slice.len != 0 and !std.mem.eql(u8, value_slice, "isindex")) return;

    return errors.append(gpa, .{
        .tag = .{
            .invalid_attr_value = .{},
        },
        .main_location = value.span,
        .node_idx = node_idx,
    });
}
