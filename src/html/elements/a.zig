const std = @import("std");
const assert = std.debug.assert;
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

pub const a: Element = .{
    .tag = .a,
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
            .interactive = true,
        },
        .content_reject = .{
            .interactive = true,
        },
    },

    .reasons = .{
        .categories = .{
            .interactive = .{
                .reject = "presence of [href]",
                .accept = "missing [href]",
            },
        },
    },

    .attributes = .{ .dynamic = validateAttrs },
    .content = .{
        .simple = .{
            .forbidden_descendants = .init(.{ .a = true }),
            .forbidden_descendants_extra = .{
                .tabindex = true,
            },
        },
    },
    .desc =
    \\The `<a>` HTML element (or anchor element), with its `href` attribute,
    \\creates a hyperlink to web pages, files, email addresses, locations in
    \\the same page, or anything else a URL can address. Content within each
    \\`<a>` should indicate the link's destination. If the `href` attribute is
    \\present, pressing the enter key while focused on the `<a>` element will
    \\activate it.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/a)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-a-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "href",
        .model = .{
            .rule = .{ .url = .empty },
            .desc =
            \\The URL that the hyperlink points to. Links are not
            \\restricted to HTTP-based URLs — they can use any URL scheme
            \\supported by browsers.
            \\
            \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/a#href)
            \\- [HTML Spec](https://html.spec.whatwg.org/multipage/links.html#attr-hyperlink-href)
            ,
        },
    },
    .{
        .name = "target",
        .model = Attribute.common.target,
    },
    .{
        .name = "download",
        .model = Attribute.common.download,
    },
    .{
        .name = "ping",
        .model = Attribute.common.ping,
    },
    .{
        .name = "rel",
        .model = Attribute.common.rel,
    },
    .{
        .name = "hreflang",
        .model = .{
            .rule = .any,
            .desc =
            \\Hints at the human language of the linked URL. No built-in
            \\functionality. Allowed values are the same as the global lang
            \\attribute.
            ,
        },
    },
    .{
        .name = "type",
        .model = Attribute.common.type,
    },
    .{
        .name = "referrerpolicy",
        .model = Attribute.common.referrerpolicy,
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
) !Model {
    var seen_attrs: [attributes.list.len]?Span = undefined;
    @memset(&seen_attrs, null);

    var has_itemprop: ?Span = null;
    while (try vait.next(gpa, src)) |attr| {
        const name = attr.name.slice(src);
        const attr_model = blk: {
            if (attributes.index(name)) |idx| {
                seen_attrs[idx] = attr.name;
                break :blk attributes.list[idx].model;
            }

            const gidx = Attribute.global.index(name) orelse {
                if (Attribute.isData(name)) continue;
                try errors.append(gpa, .{
                    .tag = .invalid_attr,
                    .main_location = attr.name,
                    .node_idx = node_idx,
                });

                continue;
            };

            if (Attribute.global.comptimeIndex("itemprop") == gidx) {
                has_itemprop = attr.name;
            }

            break :blk Attribute.global.list[gidx].model;
        };

        try attr_model.rule.validate(gpa, errors, src, node_idx, attr);
    }

    assert(attributes.comptimeIndex("href") == 0);
    const has_href = seen_attrs[0] != null;
    if (!has_href) {
        for (seen_attrs[1..]) |maybe_span| if (maybe_span) |span| {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_combination = "missing [href]",
                },
                .main_location = span,
                .node_idx = node_idx,
            });
        };

        if (has_itemprop) |span| {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_combination = "missing [href]",
                },
                .main_location = span,
                .node_idx = node_idx,
            });
        }
    }

    const categories: Categories = .{
        .flow = true,
        .phrasing = true,
        .interactive = has_href,
    };

    const parent = nodes[parent_idx];
    return .{
        .categories = categories,
        .content = categories.intersect(parent.model.content),
    };
}
