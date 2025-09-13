const std = @import("std");
const Element = @import("../Element.zig");
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;

pub const slot: Element = .{
    .tag = .slot,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
        },
        .content = .transparent,
    },
    .meta = .{
        .categories_superset = .{
            .flow = true,
            .phrasing = true,
        },
    },
    .attributes = .static,
    .content = .model,
    .desc =
    \\The `<slot>` HTML element—part of the Web Components technology
    \\suite—is a placeholder inside a web component that you can fill
    \\with your own markup, which lets you create separate DOM trees and
    \\present them together.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/slot)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/grouping-content.html#the-slot-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "name",
        .model = .{
            .rule = .not_empty,
            .desc = "The slot's name. When the slot's containing component gets rendered, the slot is rendered with the custom element's child that has a matching `slot` attribute. A named slot is a `<slot>` element with a `name` attribute. Unnamed slots have the name default to the empty string. Names should be unique per shadow root: if you have two slots with the same name, all of the elements with a matching slot attribute will be assigned to the first slot with that name.",
        },
    },
});
