const std = @import("std");
const Allocator = std.mem.Allocator;
const Ast = @import("../Ast.zig");
const root = @import("../../root.zig");
const Span = root.Span;
const Language = root.Language;
const Element = @import("../Element.zig");
const Categories = Element.Categories;
const Model = Element.Model;
const CompletionMode = Element.CompletionMode;
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;

pub const address: Element = .{
    .tag = .address,
    .model = .{
        .categories = .{
            .flow = true,
        },
        .content = .{ .flow = true },
    },

    .meta = .{
        .categories_superset = .{ .flow = true },
    },

    .attributes = .static,
    .content = .{
        .simple = .{
            .forbidden_descendants = .init(.{
                .h1 = true,
                .h2 = true,
                .h3 = true,
                .h4 = true,
                .h5 = true,
                .h6 = true,
                .hgroup = true,
                .article = true,
                .aside = true,
                .nav = true,
                .section = true,
                .header = true,
                .footer = true,
                .address = true,
            }),
        },
    },
    .desc =
    \\The `<address>` HTML element indicates that the enclosed HTML
    \\provides contact information for a person or people, or for an
    \\organization.
    \\
    \\The contact information provided by an `<address>` element's
    \\contents can take whatever form is appropriate for the context,
    \\and may include any type of contact information that is needed,
    \\such as a physical address, URL, email address, phone number,
    \\social media handle, geographic coordinates, and so forth. The
    \\`<address>` element should include the name of the person, people,
    \\or organization to which the contact information refers.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/address)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-address-element)
    ,
};
