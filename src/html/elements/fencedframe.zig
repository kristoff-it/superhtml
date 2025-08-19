const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../../root.zig");
const Language = root.Language;
const Span = root.Span;
const Tokenizer = @import("../Tokenizer.zig");
const Ast = @import("../Ast.zig");
const Element = @import("../Element.zig");
const Model = Element.Model;
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;

pub const fencedframe: Element = .{
    .tag = .fencedframe,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
            // .embedded = true,
            .interactive = true,
        },
        .content = .none,
    },
    .meta = .{
        .categories_superset = .{
            .flow = true,
            .phrasing = true,
            // .embedded = true,
            .interactive = true,
        },
    },
    .attributes = .static,
    .content = .model,

    .desc =
    \\The `<fencedframe>` HTML element represents a nested browsing
    \\context, embedding another HTML page into the current one.
    \\`<fencedframe>`s are very similar to `<iframe>` elements in form
    \\and function, except that:
    \\
    \\- Communication is restricted between the `<fencedframe>`
    \\  content and its embedding site.
    \\
    \\- A `<fencedframe>` can access cross-site data, but only
    \\  in a very specific set of controlled circumstances that
    \\  preserve user privacy.
    \\
    \\- A `<fencedframe>` cannot be manipulated or have its data
    \\  accessed via regular scripting (for example reading or
    \\  setting the source URL). `<fencedframe>` content can only be
    \\  embedded via specific APIs.
    \\                  
    \\- A `<fencedframe>` cannot access the embedding
    \\  context's DOM, nor can the embedding context access the
    \\  `<fencedframe>`'s DOM.
    \\                
    \\- The `<fencedframe>` element is a type of `<iframe>`
    \\  with more native privacy features built in. It addresses
    \\  shortcomings of `<iframe>`s such as reliance on third-party
    \\  cookies and other privacy risks.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/fencedframe)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/semantics.html#the-fencedframe-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "allow",
        .model = .{
            .desc = "Specifies a Permissions Policy for the `<fencedframe>`, which defines what features are available to the `<fencedframe>` based on the origin of the request. See Permissions policies available to fenced frames for more details of which features can be controlled via a policy set on a fenced frame.",
            .rule = .{ .custom = @import("iframe.zig").validateAllow },
        },
    },
    .{
        .name = "width",
        .model = .{
            .rule = .{ .non_neg_int = .{} },
            .desc = "The width of the fenced frame in CSS pixels. Default is 300.",
        },
    },
    .{
        .name = "height",
        .model = .{
            .rule = .{ .non_neg_int = .{} },
            .desc = "The height of the fenced frame in CSS pixels. Default is 150.",
        },
    },
});
