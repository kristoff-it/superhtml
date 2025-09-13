const std = @import("std");
const Allocator = std.mem.Allocator;
const Element = @import("../Element.zig");
const Model = Element.Model;
const Ast = @import("../Ast.zig");
const Content = Ast.Node.Categories;
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;

pub const dialog: Element = .{
    .tag = .dialog,
    .model = .{
        .categories = .{ .flow = true },
        .content = .{ .flow = true },
    },
    .meta = .{ .categories_superset = .{ .flow = true } },
    .attributes = .{ .dynamic = validate },
    .content = .model,
    .desc =
    \\The `<dialog>` HTML element represents a modal or non-modal
    \\dialog box or other interactive component, such as a dismissible
    \\alert, inspector, or subwindow.
    \\
    \\The HTML `<dialog>` element is used to create both modal and
    \\non-modal dialog boxes. Modal dialog boxes interrupt interaction
    \\with the rest of the page being inert, while non-modal dialog
    \\boxes allow interaction with the rest of the page.
    \\
    \\JavaScript should be used to display the `<dialog>` element.
    \\Use the `.showModal()` method to display a modal dialog and the
    \\`.show()` method to display a non-modal dialog. The dialog box
    \\can be closed using the `.close()` method or using the dialog
    \\method when submitting a `<form>` that is nested within the
    \\`<dialog>` element. Modal dialogs can also be closed by pressing
    \\the `Esc` key.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/dialog)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-dialog-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "open",
        .model = .{
            .rule = .bool,
            .desc =
            \\Indicates that the dialog box is active and is available for
            \\interaction. If the open attribute is not set, the dialog
            \\box will not be visible to the user. It is recommended
            \\to use the `.show()` or `.showModal()` method to render
            \\dialogs, rather than the open attribute. If a `<dialog>` is
            \\opened using the open attribute, it is non-modal.
            ,
        },
    },
    .{
        .name = "closedby",
        .model = .{
            .desc =
            \\Specifies the types of user actions that can be used to
            \\close the `<dialog>` element. This attribute distinguishes
            \\three methods by which a dialog might be closed:
            \\
            \\- A light dismiss user action, in which the `<dialog>` is
            \\  closed when the user clicks or taps outside it. This is
            \\  equivalent to the "light dismiss" behavior of "auto" state
            \\  popovers.
            \\
            \\- A platform-specific user action, such as pressing the Esc
            \\  key on desktop platforms, or a "back" or "dismiss" gesture
            \\  on mobile platforms.
            \\
            \\- A developer-specified mechanism such as a `<button>` with a
            \\  click handler that invokes `HTMLDialogElement.close()` or a
            \\  `<form>` submission.
            ,
            .rule = .{
                .list = .init(.none, .one, &.{
                    .{
                        .label = "any",
                        .desc = "The dialog can be dismissed using any of the three methods.",
                    },
                    .{
                        .label = "closerequest",
                        .desc = "The dialog can be dismissed with a platform-specific user action or a developer-specified mechanism.",
                    },
                    .{
                        .label = "none",
                        .desc = "The dialog can only be dismissed with a developer-specified mechanism.",
                    },
                }),
            },
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
    // The tabindex attribute must not be specified on dialog elements.
    while (try vait.next(gpa, src)) |attr| {
        const name = attr.name.slice(src);
        const model = attributes.get(name) orelse if (Attribute.global.index(name)) |idx| blk: {
            if (idx == Attribute.global.comptimeIndex("tabindex")) {
                try errors.append(gpa, .{
                    .tag = .invalid_attr,
                    .main_location = attr.name,
                    .node_idx = node_idx,
                });

                continue;
            }
            break :blk Attribute.global.list[idx].model;
        } else {
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

    return dialog.model;
}
