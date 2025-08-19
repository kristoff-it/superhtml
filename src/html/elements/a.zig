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
            .interactive = "presence of 'href' attribute",
        },
    },

    .attributes = .{ .dynamic = validateAttrs },
    .content = .{
        .simple = .{
            .forbidden_descendants = &.{.a},
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

const temp: Attribute = .{
    .rule = .any,
    .desc = "#temp a attribute#",
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
        .model = .{
            .rule = .{
                .list = .{
                    .extra = .{ .custom = checkNavigableName },
                    .set = .initComptime(.{
                        .{"_self"},        .{"_blank"},
                        .{"_parent"},      .{"_top"},
                        .{"_unfencedTop"},
                    }),
                    .completions = &.{
                        .{
                            .label = "_self",
                            .desc = "The current browsing context. (Default)",
                        },
                        .{
                            .label = "_blank",
                            .desc =
                            \\Usually a new tab, but users can configure
                            \\browsers to open a new window instead.
                            \\
                            \\When set on `<a>` elements, it implicitly
                            \\provides the same rel behavior as
                            \\setting rel="noopener" which does not set
                            \\`window.opener`.
                            ,
                        },
                        .{
                            .label = "_parent",
                            .desc = "The parent browsing context of the current one. If no parent, behaves as `_self`.",
                        },
                        .{
                            .label = "_top",
                            .desc =
                            \\The topmost browsing context. To be
                            \\specific, this means the "highest" context
                            \\that's an ancestor of the current one. If no
                            \\ancestors, behaves as `_self`.
                            ,
                        },
                        .{
                            .label = "_unfencedTop",
                            .desc =
                            \\Allows embedded fenced frames to navigate
                            \\the top-level frame (i.e., traversing
                            \\beyond the root of the fenced frame, unlike
                            \\other reserved destinations). Note that the
                            \\navigation will still succeed if this is
                            \\used outside of a fenced frame context, but
                            \\it will not act like a reserved keyword.
                            ,
                        },
                    },
                },
            },
            .desc =
            \\Where to display the linked URL, as the name for a browsing
            \\context (a tab, window, or `<iframe>`).
            \\
            \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/a#target)
            \\- [HTML Spec](https://html.spec.whatwg.org/multipage/links.html#attr-hyperlink-target)
            ,
        },
    },
    .{
        .name = "download",
        .model = .{
            .rule = .any,
            .desc =
            \\Causes the browser to treat the linked URL as a
            \\download. Can be used with or without a filename value.
            \\
            \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/a#download)
            \\- [HTML Spec](https://html.spec.whatwg.org/multipage/links.html#attr-hyperlink-download)
            ,
        },
    },
    .{
        .name = "ping",
        .model = .{
            .rule = .any, // TODO
            .desc =
            \\A space-separated list of URLs. When the link is
            \\followed, the browser will send POST requests with the
            \\body PING to the URLs. Typically for tracking.
            \\
            \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/a#ping)
            \\- [HTML Spec](https://html.spec.whatwg.org/multipage/links.html#attr-hyperlink-ping)
            ,
        },
    },
    .{ .name = "rel", .model = temp },
    .{ .name = "hreflang", .model = temp },
    .{ .name = "type", .model = temp },
    .{ .name = "referrerpolicy", .model = temp },
});

pub fn validateAttrs(
    gpa: Allocator,
    errors: *std.ArrayListUnmanaged(Ast.Error),
    src: []const u8,
    node_idx: u32,
    parent_content: Categories,
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

    const has_href = seen_attrs[0] != null;
    if (!has_href) {
        for (seen_attrs[1..]) |maybe_span| if (maybe_span) |span| {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_combination = "missing href",
                },
                .main_location = span,
                .node_idx = node_idx,
            });
        };

        if (has_itemprop) |span| {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_combination = "missing href",
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

    return .{
        .categories = categories,
        .content = categories.intersect(parent_content),
    };
}

// A valid navigable target name is any string with at least one character that
// does not contain both an ASCII tab or newline and a U+003C (<), and it does
// not start with a U+005F (_). (Names starting with a U+005F (_) are reserved
// for special keywords.)
// A valid navigable target name or keyword is any string that is either a valid
// navigable target name or that is an ASCII case-insensitive match for one of:
// _blank, _self, _parent, or _top.

fn checkNavigableName(value: []const u8) ?Attribute.Rule.ValueRejection {
    if (value.len == 0) return .{};

    if (value[0] == '_') return .{
        .reason = "reserved for special keywords, did you mistype?",
        .offset = 0,
    };

    if (std.mem.indexOfAny(u8, value, "\t\n<")) |idx| return .{
        .reason = "invalid character in navigable target name",
        .offset = @intCast(idx),
    };

    return null;
}
