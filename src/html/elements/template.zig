const std = @import("std");
const Allocator = std.mem.Allocator;
const Element = @import("../Element.zig");
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;

pub const template: Element = .{
    .tag = .template,
    .model = .{
        .categories = .{
            .metadata = true,
            .flow = true,
            .phrasing = true,
        },
        .content = .all,
    },
    .meta = .{
        .categories_superset = .{
            .metadata = true,
            .flow = true,
            .phrasing = true,
        },
    },
    .attributes = .manual,
    .content = .anything,
    .desc =
    \\The `<template>` HTML element serves as a mechanism for holding
    \\HTML fragments, which can either be used later via JavaScript or
    \\generated immediately into shadow DOM.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/template)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-template-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "shadowrootmode",
        .model = .{
            .desc = "Creates a shadow root for the parent element. It is a declarative version of the `Element.attachShadow()` method and accepts the same enumerated values.",
            .rule = .{
                .list = .init(.none, .one, &.{
                    .{
                        .label = "open",
                        .desc = "Exposes the internal shadow root DOM for JavaScript (recommended for most use cases).",
                    },
                    .{
                        .label = "closed",
                        .desc = "Hides the internal shadow root DOM from JavaScript.",
                    },
                }),
            },
        },
    },
    .{
        .name = "shadowrootclonable",
        .model = .{
            .rule = .bool,
            .desc = "Sets the value of the `clonable` property of a `ShadowRoot` created using this element to true. If set, a clone of the shadow host (the parent element of this `<template>`) created with `Node.cloneNode()` or `Document.importNode()` will include a shadow root in the copy.",
        },
    },
    .{
        .name = "shadowrootdelegatesfocus",
        .model = .{
            .rule = .bool,
            .desc = "Sets the value of the `delegatesFocus` property of a `ShadowRoot` created using this element to true. If this is set and a non-focusable element in the shadow tree is selected, then focus is delegated to the first focusable element in the tree. The value defaults to false.",
        },
    },
    .{
        .name = "shadowrootserializable",
        .model = .{
            .rule = .bool,
            .desc = "Sets the value of the `serializable` property of a `ShadowRoot` created using this element to true. If set, the shadow root may be serialized by calling the `Element.getHTML()` or `ShadowRoot.getHTML()` methods with the `options.serializableShadowRoots` parameter set true. The value defaults to false.",
        },
    },
});
