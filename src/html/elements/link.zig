const std = @import("std");
const assert = std.debug.assert;
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

pub const link: Element = .{
    .tag = .link,
    .model = .{
        .categories = .{ .metadata = true },
        .content = .none,
    },
    .meta = .{
        .categories_superset = .{
            .flow = true,
            .phrasing = true,
            .metadata = true,
        },
    },
    .reasons = .{
        .categories = .{
            .flow = .{
                .reject = "presence of [itemprop], or [rel] with a \"body-ok\" value",
                .accept = "missing [itemprop], or [rel] with a \"body-ok\" value",
            },
            .phrasing = .{
                .reject = "presence of [itemprop], or [rel] with a \"body-ok\" value",
                .accept = "missing [itemprop], or [rel] with a \"body-ok\" value",
            },
        },
    },
    .attributes = .{ .dynamic = validate },
    .content = .model,
    .desc =
    \\The `<link>` HTML element specifies relationships between the
    \\current document and an external resource. This element is
    \\most commonly used to link to stylesheets, but is also used to
    \\establish site icons (both "favicon" style icons and icons for
    \\the home screen and apps on mobile devices) among other things.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/link)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-link-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "href",
        .model = .{
            .rule = .{ .url = .not_empty },
            .desc = "This attribute specifies the URL of the linked resource. A URL can be absolute or relative.",
        },
    },
    .{
        .name = "rel",
        .model = .{
            .desc = "This attribute names a relationship of the linked document to the current document. The attribute must be a space-separated list of link type values.",
            .rule = .{
                .list = .init(.none, .many_unique, &.{
                    .{
                        .label = "alternate",
                        .desc = "Alternate representations of the current document.",
                    },
                    .{
                        .label = "author",
                        .desc = "Gives a link to the author of the current document or article.",
                    },
                    .{
                        .label = "canonical",
                        .desc = "Gives the preferred URL for the current document.",
                    },
                    .{
                        .label = "dns-prefetch",
                        .desc = "Tells the browser to preemptively perform DNS resolution for the target resource's origin.",
                    },
                    .{
                        .label = "expect",
                        .desc = "When used with `blocking=\"render\"`, allows the page to be render-blocked until the essential parts of the document are parsed so it will render consistently.",
                    },
                    .{
                        .label = "help",
                        .desc = "Provides a link to context-sensitive help.",
                    },
                    .{
                        .label = "icon",
                        .desc = "An icon representing the current document.",
                    },
                    .{
                        .label = "apple-touch-icon",
                        .desc = "An icon representing the current document.",
                    },
                    .{
                        .label = "manifest",
                        .desc = "Web app manifest.",
                    },
                    .{
                        .label = "modulepreload",
                        .desc = "Tells to browser to preemptively fetch the script and store it in the document's module map for later evaluation. Optionally, the module's dependencies can be fetched as well.",
                    },
                    .{
                        .label = "license",
                        .desc = "Indicates that the main content of the current document is covered by the copyright license described by the referenced document.",
                    },
                    .{
                        .label = "next",
                        .desc = "Indicates that the current document is a part of a series and that the next document in the series is the referenced document.",
                    },
                    .{
                        .label = "pingback",
                        .desc = "Gives the address of the pingback server that handles pingbacks to the current document.",
                    },
                    .{
                        .label = "preconnect",
                        .desc = "Specifies that the user agent should preemptively connect to the target resource's origin.",
                    },
                    .{
                        .label = "prefetch",
                        .desc = "Specifies that the user agent should preemptively fetch and cache the target resource as it is likely to be required for a followup navigation.",
                    },
                    .{
                        .label = "preload",
                        .desc = "Specifies that the user agent must preemptively fetch and cache the target resource for current navigation according to the potential destination given by the `as` attribute (and the priority associated with the corresponding destination).",
                    },
                    .{
                        .label = "prev",
                        .desc = "Indicates that the current document is a part of a series, and that the previous document in the series is the referenced document.",
                    },
                    .{
                        .label = "privacy-policy",
                        .desc = "Gives a link to information about the data collection and usage practices that apply to the current document.",
                    },
                    .{
                        .label = "search",
                        .desc = "Gives a link to a resource that can be used to search through the current document and its related pages.",
                    },
                    .{
                        .label = "stylesheet",
                        .desc = "Imports a style sheet.",
                    },
                    .{
                        .label = "terms-of-service",
                        .desc = "Gives a link to information about the agreements between the current document's provider and users who wish to use the current document.",
                    },
                }),
            },
        },
    },
    .{
        .name = "crossorigin",
        .model = .{
            .desc = "This enumerated attribute indicates whether CORS must be used when fetching the resource. CORS-enabled images can be reused in the `<canvas>` element without being tainted.",
            .rule = .{
                .list = .init(.missing, .one, &.{
                    .{
                        .label = "anonymous",
                        .desc = "A cross-origin request (i.e., with an `Origin` HTTP header) is performed, but no credential is sent (i.e., no cookie, X.509 certificate, or HTTP Basic authentication). If the server does not give credentials to the origin site (by not setting the `Access-Control-Allow-Origin` HTTP header) the resource will be tainted and its usage restricted.",
                    },
                    .{
                        .label = "use-credentials",
                        .desc = "A cross-origin request (i.e., with an `Origin` HTTP header) is performed along with a credential sent (i.e., a cookie, certificate, and/or HTTP Basic authentication is performed). If the server does not give credentials to the origin site (through `Access-Control-Allow-Credentials` HTTP header), the resource will be tainted and its usage restricted.",
                    },
                }),
            },
        },
    },
    .{
        .name = "media",
        .model = .{
            .rule = .any, // TODO validate
            .desc = "This attribute specifies the media that the linked resource applies to. Its value must be a media type / media query. This attribute is mainly useful when linking to external stylesheets — it allows the user agent to pick the best adapted one for the device it runs on.",
        },
    },
    .{
        .name = "integrity",
        .model = .{
            .rule = .not_empty, // TODO validate
            .desc = "Contains inline metadata — a base64-encoded cryptographic hash of the resource (file) you're telling the browser to fetch. The browser can use this to verify that the fetched resource has been delivered without unexpected manipulation. The attribute must only be specified when the `rel` attribute is specified to `stylesheet`, `preload`, or `modulepreload`.",
        },
    },
    .{
        .name = "hreflang",
        .model = .{
            .rule = .not_empty, // TODO validate
            .desc = "This attribute indicates the language of the linked resource. It is purely advisory.",
        },
    },
    .{
        .name = "referrerpolicy",
        .model = Attribute.common.referrerpolicy,
    },
    .{
        .name = "sizes",
        .model = .{
            .desc = "This attribute defines the sizes of the icons for visual media contained in the resource. It must be present only if the `rel` attribute contains a value of `icon` or a non-standard type such as Apple's `apple-touch-icon`. ",
            .rule = .{
                .list = .init(.{ .custom = validateSizes }, .many_unique, &.{
                    .{
                        .label = "any",
                        .desc = "Meaning that the icon can be scaled to any size as it is in a vector format, like `image/svg+xml`.",
                    },
                    .{
                        .label = "<W>x<H>",
                        .desc = "A white-space separated list of sizes, each in the format `<width in pixels>x<height in pixels>` or `<width in pixels>X<height in pixels>`. Each of these sizes must be contained in the resource.",
                    },
                }),
            },
        },
    },
    .{
        .name = "imagesrcset",
        .model = .{
            .rule = .manual,
            .desc = "For `rel=\"preload\"` and `as=\"image\"` only, the imagesrcset attribute has similar syntax and semantics as the srcset attribute that indicates to preload the appropriate resource used by an img element with corresponding values for its srcset and sizes attributes.",
        },
    },
    .{
        .name = "imagesizes",
        .model = .{
            .rule = .any, // TODO
            .desc = "For `rel=\"preload\"` and `as=\"image\"` only, the imagesizes attribute has similar syntax and semantics as the sizes attribute that indicates to preload the appropriate resource used by an img element with corresponding values for its srcset and sizes attributes.",
        },
    },
    .{
        .name = "as",
        .model = .{
            .desc = "This attribute is required when `rel=\"preload\"` has been set on the `<link>` element, optional when `rel=\"modulepreload\"` has been set, and otherwise should not be used. It specifies the type of content being loaded by the `<link>`, which is necessary for request matching, application of correct content security policy, and setting of correct `Accept` request header.",
            .rule = .{
                .list = .init(.none, .one, &.{
                    .{
                        .label = "audio",
                        .desc = "Applies to `<audio>` elements.",
                    },
                    .{
                        .label = "document",
                        .desc = "Applies to `<iframe>` and `<frame>` elements.",
                    },
                    .{
                        .label = "embed",
                        .desc = "Applies to `<embed>` elements.",
                    },
                    .{
                        .label = "fetch",
                        .desc =
                        \\Applies to `fetch`, `XHR`.
                        \\
                        \\## NOTE
                        \\This value also requires `<link>` to contain
                        \\the `crossorigin` attribute.
                        ,
                    },
                    .{
                        .label = "font",
                        .desc =
                        \\Applies to CSS `@font-face`.
                        \\
                        \\## NOTE
                        \\This value also requires `<link>` to contain
                        \\the `crossorigin` attribute.
                        ,
                    },
                    .{
                        .label = "image",
                        .desc = "Applies to `<img>` and `<picture>` elements with `srcset` or `imageset` attributes, SVG `<image>` elements, CSS `*-image` rules.",
                    },
                    .{
                        .label = "object",
                        .desc = "Applies to `<object>` elements.",
                    },
                    .{
                        .label = "script",
                        .desc = "Applies to `<script>` elements, Worker `importScripts`.",
                    },
                    .{
                        .label = "style",
                        .desc = "Applies to `<link rel=stylesheet>` elements, CSS `@import`.",
                    },
                    .{
                        .label = "track",
                        .desc = "Applies to `<track>` elements.",
                    },
                    .{
                        .label = "video",
                        .desc = "Applies to `<video>` elements.",
                    },
                    .{
                        .label = "worker",
                        .desc = "Applies to Worker, SharedWorker",
                    },
                }),
            },
        },
    },
    .{
        .name = "blocking",
        .model = .{
            .desc = "This attribute explicitly indicates that certain operations should be blocked until specific conditions are met. It must only be used when the rel attribute contains the `expect` or `stylesheet` keywords. With `rel=\"expect\"`, it indicates that operations should be blocked until a specific DOM node has been parsed. With `rel=\"stylesheet\"`, it indicates that operations should be blocked until an external stylesheet and its critical subresources have been fetched and applied to the document.",
            .rule = .{
                .list = .init(.none, .many_unique, &.{
                    .{
                        .label = "render",
                        .desc = "The rendering of content on the screen is blocked.",
                    },
                }),
            },
        },
    },
    .{
        .name = "color",
        .model = .{
            .rule = .any,
            .desc = "A suggested color that user agents can use to customize the display of the icon that the user sees when they pin your site",
        },
    },
    .{
        .name = "disabled",
        .model = .{
            .rule = .bool,
            .desc =
            \\For `rel="stylesheet"` only, the disabled Boolean attribute
            \\indicates whether the described stylesheet should be loaded and
            \\applied to the document. If disabled is specified in the HTML
            \\when it is loaded, the stylesheet will not be loaded during page
            \\load. Instead, the stylesheet will be loaded on-demand, if and
            \\when the disabled attribute is changed to false or removed.
            \\
            \\Setting the disabled property in the DOM causes the stylesheet to be
            \\removed from the document's `Document.styleSheets` list.
            ,
        },
    },
    .{
        .name = "fetchpriority",
        .model = Attribute.common.fetchpriority,
    },
    .{
        .name = "type",
        .model = .{
            .rule = .any,
            .desc = "This attribute is used to define the type of the content linked to. The value of the attribute should be a MIME type such as `text/html`, `text/css`, and so on. The common use of this attribute is to define the type of stylesheet being referenced (such as `text/css`), but given that CSS is the only stylesheet language used on the web, not only is it possible to omit the type attribute, but is actually now recommended practice. It is also used on `rel=\"preload\"` link types, to make sure the browser only downloads file types that it supports.",
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

    // One or both of the href or imagesrcset attributes must be present.
    var has_itemprop = false;
    var attrs: [attributes.list.len]?Tokenizer.Attr = @splat(null);
    while (try vait.next(gpa, src)) |attr| {
        const name = attr.name.slice(src);
        const model = if (attributes.index(name)) |idx| {
            attrs[idx] = attr;
            continue;
        } else if (Attribute.global.index(name)) |idx| blk: {
            if (idx == Attribute.global.comptimeIndex("itemprop")) {
                has_itemprop = true;
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

    const rel_idx = attributes.comptimeIndex("rel");
    const rel_rule = attributes.list[rel_idx].model.rule.list;
    var rel_values: [rel_rule.completions.len]bool = @splat(false);
    if (attrs[rel_idx]) |attr| {
        const value = attr.value orelse {
            try errors.append(gpa, .{
                .tag = .missing_attr_value,
                .main_location = attr.name,
                .node_idx = node_idx,
            });
            return link.model;
        };

        const value_slice = value.span.slice(src);
        var it = std.mem.tokenizeAny(u8, value_slice, &std.ascii.whitespace);
        while (it.next()) |token| {
            const match = try rel_rule.match(
                gpa,
                errors,
                node_idx,
                @intCast(value.span.start + it.index - token.len),
                token,
            );

            switch (match) {
                .list => |idx| rel_values[idx] = true,
                else => {},
            }
        }

        if (has_itemprop) try errors.append(gpa, .{
            .tag = .{
                .invalid_attr_combination = "[rel] and [itemprop] are mutually exclusive",
            },
            .main_location = vait.name,
            .node_idx = node_idx,
        });
    } else if (!has_itemprop) try errors.append(gpa, .{
        .tag = .{
            .invalid_attr_combination = "[rel] or [itemprop] must be specified",
        },
        .main_location = vait.name,
        .node_idx = node_idx,
    });

    var as_needs_crossorigin = false;
    var as_is_image = false;
    if (attrs[attributes.comptimeIndex("as")]) |attr| as: {
        if (rel_values[rel_rule.comptimeIndex("preload")] or
            rel_values[rel_rule.comptimeIndex("modulepreload")])
        {
            const model = comptime attributes.get("as").?;
            const value = attr.value orelse {
                try errors.append(gpa, .{
                    .tag = .missing_attr_value,
                    .main_location = attr.name,
                    .node_idx = node_idx,
                });
                break :as;
            };
            const match = try model.rule.list.match(
                gpa,
                errors,
                node_idx,
                value.span.start,
                value.span.slice(src),
            );

            switch (match) {
                .list => |list_idx| switch (list_idx) {
                    model.rule.list.comptimeIndex("font"),
                    model.rule.list.comptimeIndex("fetch"),
                    => {
                        as_needs_crossorigin = true;
                    },
                    model.rule.list.comptimeIndex("image") => {
                        as_is_image = true;
                    },
                    else => {},
                },
                else => {},
            }
        } else try errors.append(gpa, .{
            .tag = .{
                .invalid_attr_combination = "requires [rel] to contain 'preload' or 'modulepreload'",
            },
            .main_location = attr.name,
            .node_idx = node_idx,
        });
    } else {
        if (rel_values[rel_rule.comptimeIndex("preload")]) {
            try errors.append(gpa, .{
                .tag = .{ .missing_required_attr = "as" },
                .main_location = vait.name,
                .node_idx = node_idx,
            });
        }
    }

    if (attrs[attributes.comptimeIndex("blocking")]) |attr| {
        if (rel_values[rel_rule.comptimeIndex("expect")] or
            rel_values[rel_rule.comptimeIndex("stylesheet")])
        {
            const model = comptime attributes.get("blocking").?;
            try model.rule.validate(gpa, errors, src, node_idx, attr);
        } else try errors.append(gpa, .{
            .tag = .{
                .invalid_attr_combination = "requires [rel] to contain 'expect' or 'stylesheet'",
            },
            .main_location = attr.name,
            .node_idx = node_idx,
        });
    }

    if (attrs[attributes.comptimeIndex("crossorigin")]) |attr| {
        const model = comptime attributes.get("crossorigin").?;
        try model.rule.validate(gpa, errors, src, node_idx, attr);
    } else if (as_needs_crossorigin) try errors.append(gpa, .{
        .tag = .{
            .missing_required_attr = "[crossorigin] (because [as] is 'fetch' or 'font')",
        },
        .main_location = vait.name,
        .node_idx = node_idx,
    });

    if (attrs[attributes.comptimeIndex("disabled")]) |attr| {
        if (rel_values[rel_rule.comptimeIndex("stylesheet")]) {
            const model = comptime attributes.get("disabled").?;
            try model.rule.validate(gpa, errors, src, node_idx, attr);
        } else try errors.append(gpa, .{
            .tag = .{
                .invalid_attr_combination = "requires [rel] to contain 'stylesheet'",
            },
            .main_location = attr.name,
            .node_idx = node_idx,
        });
    }

    if (attrs[attributes.comptimeIndex("fetchpriority")]) |attr| {
        const model = comptime attributes.get("fetchpriority").?;
        try model.rule.validate(gpa, errors, src, node_idx, attr);
    }

    if (attrs[attributes.comptimeIndex("href")]) |attr| {
        const model = comptime attributes.get("href").?;
        try model.rule.validate(gpa, errors, src, node_idx, attr);
    }

    if (attrs[attributes.comptimeIndex("hreflang")]) |attr| {
        if (attrs[attributes.comptimeIndex("href")] != null) {
            const model = comptime attributes.get("hreflang").?;
            try model.rule.validate(gpa, errors, src, node_idx, attr);
        } else try errors.append(gpa, .{
            .tag = .{
                .invalid_attr_combination = "requires [href]",
            },
            .main_location = attr.name,
            .node_idx = node_idx,
        });
    }

    if (attrs[attributes.comptimeIndex("imagesizes")]) |attr| {
        if (rel_values[rel_rule.comptimeIndex("preload")] and as_is_image) {
            const model = comptime attributes.get("imagesizes").?;
            try model.rule.validate(gpa, errors, src, node_idx, attr);
        } else try errors.append(gpa, .{
            .tag = .{
                .invalid_attr_combination = "requires [rel] to contain 'preload' and [as] to be 'image'",
            },
            .main_location = attr.name,
            .node_idx = node_idx,
        });
    }
    if (attrs[attributes.comptimeIndex("imagesrcset")]) |attr| {
        if (rel_values[rel_rule.comptimeIndex("preload")] and as_is_image) {
            var seen_descriptors: std.StringArrayHashMapUnmanaged(Span) = .{};
            defer seen_descriptors.deinit(gpa);

            var seen_any_w = false;
            try @import("picture.zig").validateSrcset(
                gpa,
                errors,
                &seen_descriptors,
                attr,
                src,
                node_idx,
                &seen_any_w,
            );
        } else try errors.append(gpa, .{
            .tag = .{
                .invalid_attr_combination = "requires [rel] to contain 'preload' and [as] to be 'image'",
            },
            .main_location = attr.name,
            .node_idx = node_idx,
        });
    } else if (attrs[attributes.comptimeIndex("href")] == null) {
        try errors.append(gpa, .{
            .tag = .{
                .invalid_attr_combination = "[href] or [imagesrcset] are required",
            },
            .main_location = vait.name,
            .node_idx = node_idx,
        });
    }

    if (attrs[attributes.comptimeIndex("integrity")]) |attr| {
        if (rel_values[rel_rule.comptimeIndex("stylesheet")] or
            rel_values[rel_rule.comptimeIndex("preload")] or
            rel_values[rel_rule.comptimeIndex("modulepreload")])
        {
            const model = comptime attributes.get("integrity").?;
            try model.rule.validate(gpa, errors, src, node_idx, attr);
        } else try errors.append(gpa, .{
            .tag = .{
                .invalid_attr_combination = "requires [rel] to contain 'expect' or 'stylesheet'",
            },
            .main_location = attr.name,
            .node_idx = node_idx,
        });
    }

    if (attrs[attributes.comptimeIndex("media")]) |attr| {
        const model = comptime attributes.get("media").?;
        try model.rule.validate(gpa, errors, src, node_idx, attr);
    }

    if (attrs[attributes.comptimeIndex("referrerpolicy")]) |attr| {
        const model = comptime attributes.get("referrerpolicy").?;
        try model.rule.validate(gpa, errors, src, node_idx, attr);
    }

    if (attrs[attributes.comptimeIndex("sizes")]) |attr| {
        if (rel_values[rel_rule.comptimeIndex("icon")] or
            rel_values[rel_rule.comptimeIndex("apple-touch-icon")])
        {
            const model = comptime attributes.get("sizes").?;
            try model.rule.validate(gpa, errors, src, node_idx, attr);
        } else try errors.append(gpa, .{
            .tag = .{
                .invalid_attr_combination = "requires [rel] to contain 'icon' or 'apple-touch-icon'",
            },
            .main_location = attr.name,
            .node_idx = node_idx,
        });
    }

    // If a link element has an itemprop attribute, or has a rel attribute that
    // contains only keywords that are body-ok, then the element is said to
    // be allowed in the body. This means that the element can be used where
    // phrasing content is expected.

    const body_ok = has_itemprop or
        (!rel_values[rel_rule.comptimeIndex("alternate")] and
            !rel_values[rel_rule.comptimeIndex("author")] and
            !rel_values[rel_rule.comptimeIndex("canonical")] and
            !rel_values[rel_rule.comptimeIndex("expect")] and
            !rel_values[rel_rule.comptimeIndex("help")] and
            !rel_values[rel_rule.comptimeIndex("icon")] and
            !rel_values[rel_rule.comptimeIndex("apple-touch-icon")] and
            !rel_values[rel_rule.comptimeIndex("manifest")] and
            !rel_values[rel_rule.comptimeIndex("license")] and
            !rel_values[rel_rule.comptimeIndex("next")] and
            !rel_values[rel_rule.comptimeIndex("prev")] and
            !rel_values[rel_rule.comptimeIndex("privacy-policy")] and
            !rel_values[rel_rule.comptimeIndex("search")] and
            !rel_values[rel_rule.comptimeIndex("terms-of-service")]);

    var model = link.model;
    model.categories.phrasing = body_ok;
    model.categories.flow = body_ok;
    return model;
}

fn validateSizes(value: []const u8) ?Attribute.Rule.ValueRejection {
    const x_idx = std.mem.indexOfAny(u8, value, "xX") orelse {
        return .{
            .reason = "missing dimension separator 'x' (or 'X')",
        };
    };

    const w = value[0..x_idx];
    const h = value[x_idx + 1 ..];

    _ = std.fmt.parseInt(u64, w, 10) catch return .{
        .reason = "invalid width value",
    };
    _ = std.fmt.parseInt(u64, h, 10) catch return .{
        .reason = "invalid height value",
    };

    return null;
}
