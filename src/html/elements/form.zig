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
const log = std.log.scoped(.details);

pub const form: Element = .{
    .tag = .form,
    .model = .{
        .categories = .{ .flow = true },
        .content = .{ .flow = true },
    },
    .meta = .{
        .categories_superset = .{ .flow = true },
    },
    .attributes = .static,
    .content = .{ .simple = .{ .forbidden_children = &.{.form} } },
    .desc =
    \\The `<form>` HTML element represents a document section containing
    \\interactive controls for submitting information.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/form)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-form-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "action",
        .model = .{
            .rule = .{ .url = .not_empty },
            .desc = "The URL that processes the form submission. This value can be overridden by a formaction attribute on a `<button>`, `<input type=\"submit\">`, or `<input type=\"image\">` element. This attribute is ignored when `method=\"dialog\"` is set.",
        },
    },
    .{
        .name = "method",
        .model = .{
            .rule = @import("button.zig").attributes.get("formmethod").?.rule,
            .desc = "The HTTP method to submit the form with.",
        },
    },
    .{
        .name = "enctype",
        .model = .{
            .rule = @import("button.zig").attributes.get("formenctype").?.rule,
            .desc = "If the value of the `method` attribute is post, `enctype` is the MIME type of the form submission.",
        },
    },
    .{
        .name = "target",
        .model = .{
            .desc = "Indicates where to display the response after submitting the form. It is a name/keyword for a browsing context (for example, tab, window, or iframe).",
            .rule = Attribute.common.target.rule,
        },
    },
    .{
        .name = "autocomplete",
        .model = .{
            .desc = "Controls whether inputted text is automatically capitalized and, if so, in what manner.",
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
        .name = "name",
        .model = .{
            .rule = .not_empty,
            .desc = "The name of the form. The value must not be the empty string, and must be unique among the form elements in the forms collection that it is in, if any. The name becomes a property of the `Window`, `Document`, and `document.forms` objects, containing a reference to the form element.",
        },
    },
    .{
        .name = "novalidate",
        .model = .{
            .rule = .bool,
            .desc = "This Boolean attribute indicates that the form shouldn't be validated when submitted. If this attribute is not set (and therefore the form is validated), it can be overridden by a `formnovalidate` attribute on a `<button>`, `<input type=\"submit\">`, or `<input type=\"image\">` element belonging to the form.",
        },
    },
    .{
        .name = "accept-encoding",
        .model = .{
            .rule = .{
                .list = .init(.none, .one, &.{
                    .{
                        .label = "UTF-8",
                        .desc = "This is the only allowed value.",
                    },
                }),
            },
            .desc = "Only accepts 'UTF-8' as a value, no reason to specify this atttribute.",
        },
    },
});
