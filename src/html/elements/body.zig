const std = @import("std");
const Allocator = std.mem.Allocator;
const Ast = @import("../Ast.zig");
const Element = @import("../Element.zig");
const Model = Element.Model;
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;

pub const body: Element = .{
    .tag = .body,
    .model = .{
        .categories = .none,
        .content = .{ .flow = true },
    },
    .meta = .{
        .categories_superset = .{ .flow = true },
    },
    .attributes = .static,
    .content = .model,
    .desc =
    \\The `<body>` HTML element represents the content of an HTML document.
    \\There can be only one `<body>` element in a document.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/body)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-body-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "onafterprint",
        .model = .{
            .rule = .any,
            .desc = "Function to call after the user has printed the document.",
        },
    },
    .{
        .name = "onbeforeprint",
        .model = .{
            .rule = .any,
            .desc = "Function to call when the user requests printing of the document.",
        },
    },
    .{
        .name = "onbeforeunload",
        .model = .{
            .rule = .any,
            .desc = "Function to call when the document is about to be unloaded.",
        },
    },
    .{
        .name = "onhashchange",
        .model = .{
            .rule = .any,
            .desc = "Function to call when the fragment identifier part (starting with the hash ('#') character) of the document's current address has changed.",
        },
    },
    .{
        .name = "onlanguagechange",
        .model = .{
            .rule = .any,
            .desc = "Function to call when the preferred languages changed.",
        },
    },
    .{
        .name = "onmessage",
        .model = .{
            .rule = .any,
            .desc = "Function to call when the document has received a message.",
        },
    },
    .{
        .name = "onmessageerror",
        .model = .{
            .rule = .any,
            .desc = "Function to call when the document has received a message that cannot be deserialized.",
        },
    },
    .{
        .name = "onoffline",
        .model = .{
            .rule = .any,
            .desc = "Function to call when network communication has failed.",
        },
    },
    .{
        .name = "ononline",
        .model = .{
            .rule = .any,
            .desc = "Function to call when network communication has been restored.",
        },
    },
    .{
        .name = "onpageswap",
        .model = .{
            .rule = .any,
            .desc = "Function to call when you navigate across documents, when the previous document is about to unload.",
        },
    },
    .{
        .name = "onpagehide",
        .model = .{
            .rule = .any,
            .desc = "Function to call when the browser hides the current page in the process of presenting a different page from the session's history.",
        },
    },
    .{
        .name = "onpagereveal",
        .model = .{
            .rule = .any,
            .desc = "Function to call when a document is first rendered, either when loading a fresh document from the network or activating a document.",
        },
    },
    .{
        .name = "onpageshow",
        .model = .{
            .rule = .any,
            .desc = "Function to call when the browser displays the window's document due to navigation.",
        },
    },
    .{
        .name = "onpopstate",
        .model = .{
            .rule = .any,
            .desc = "Function to call when the user has navigated session history.",
        },
    },
    .{
        .name = "onrejectionhandled",
        .model = .{
            .rule = .any,
            .desc = "Function to call when a JavaScript Promise is handled late.",
        },
    },
    .{
        .name = "onstorage",
        .model = .{
            .rule = .any,
            .desc = "Function to call when the storage area has changed.",
        },
    },
    .{
        .name = "onunhandledrejection",
        .model = .{
            .rule = .any,
            .desc = "Function to call when a JavaScript Promise that has no rejection handler is rejected.",
        },
    },
    .{
        .name = "onunload",
        .model = .{
            .rule = .any,
            .desc = "Function to call when the document is going away.",
        },
    },
});
