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

pub const meta: Element = .{
    .tag = .meta,
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
                .reject = "presence of [itemprop]",
                .accept = "missing [itemprop]",
            },
            .phrasing = .{
                .reject = "presence of [itemprop]",
                .accept = "missing [itemprop]",
            },
        },
    },
    .attributes = .{ .dynamic = validate },
    .content = .model,
    .desc =
    \\The `<meta>` HTML element represents metadata that cannot be
    \\represented by other meta-related elements, such as `<base>`,
    \\`<link>`, `<script>`, `<style>`, or `<title>`.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/meta)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-meta-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "name",
        .model = .{
            .desc = "The `name` and `content` attributes can be used together to provide document metadata in terms of name-value pairs, with the `name` attribute giving the metadata name, and the `content` attribute giving the value.",
            .rule = .{
                .list = .init(.not_empty, .one, &.{
                    .{
                        .label = "application-name",
                        .desc = "Browsers may use this to identify the application running in the web page. It is different from the `<title>` element, which may contain an application (or website) name, but a `<title>` may add contextual information like a document name or a status. Individual pages shouldn't define their own, unique application-name. To provide translations, use multiple `<meta>` tags with the `lang` attribute for each language.",
                    },
                    .{
                        .label = "author",
                        .desc = "The document author's name.",
                    },
                    .{
                        .label = "color-scheme",
                        .desc = "Specifies one or more color schemes with which the document is compatible. The browser will use this information in tandem with the user's browser or device settings to determine what colors to use for everything from background and foregrounds to form controls and scrollbars. The primary use for `<meta name=\"color-scheme\">` is to indicate compatibility and order of preference for light and dark color modes.",
                    },
                    .{
                        .label = "description",
                        .desc = "A short and accurate summary of the content of the page usually referred to as a 'meta description'.",
                    },
                    .{
                        .label = "generator",
                        .desc = "The identifier of the software that generated the page.",
                    },
                    .{
                        .label = "keywords",
                        .desc = "Words relevant to the page's content separated by commas.",
                    },
                    .{
                        .label = "referrer",
                        .desc = "Controls the HTTP Referer header of requests sent from the document.",
                    },
                    .{
                        .label = "theme-color",
                        .desc = "Indicates a suggested color that user agents should use to customize the display of the page or of the surrounding user interface. The `content` attribute contains a valid CSS color. The `media` attribute with a valid media query list can be included to set the media that the theme color metadata applies to.",
                    },
                    .{
                        .label = "Non-standard meta name",
                        .value = "my-custom-name",
                        .desc = "This attribute supports also non-standard names.",
                    },
                }),
            },
        },
    },
    .{
        .name = "content",
        .model = .{
            .rule = .manual,
            .desc = "The `name` and `content` attributes can be used together to provide document metadata in terms of name-value pairs, with the `name` attribute giving the metadata name, and the `content` attribute giving the value.",
        },
    },
    .{
        .name = "property",
        .model = .{
            .rule = .not_empty,
            .desc = "Sometimes this attribute is used instead of `name`, for example when defining OpenGraph properties. Not part of the HTML spec.",
        },
    },
    .{
        .name = "media",
        .model = .{
            .rule = .not_empty,
            .desc = "The `media` attribute defines which media the theme color defined in the `content` attribute should be applied to. Its value is a media query, which defaults to `all` if the attribute is missing. This attribute is only relevant when the element's `name` attribute is set to `theme-color`. Otherwise, it has no effect, and should not be included.",
        },
    },
    .{
        .name = "http-equiv",
        .model = .{
            .desc = "Defines a pragma directive, which are instructions for the browser for processing the document. The attribute's name is short for `http-equivalent` because the allowed values are names of equivalent HTTP headers.",
            .rule = .{
                .list = .init(.none, .one, &.{
                    .{
                        .label = "content-type",
                        .desc = "Declares the document's media type (MIME type) and character encoding. The content attribute must be `\"text/html; charset=utf-8\"` if specified. This is equivalent to a `<meta>` element with the `charset` attribute specified and carries the same restriction on placement within the document. Can only be used in documents served with a `text/html` media type — not in documents served with an XML (`application/xml` or `application/xhtml+xml`) type.",
                    },
                    .{
                        .label = "content-security-policy",
                        .desc = "Allows page authors to define a content security policy (CSP) for the current page, typically to specify allowed origins and script endpoints to guard against cross-site scripting attacks.",
                    },
                    .{
                        .label = "default-style",
                        .desc = "Sets the name of the default CSS style sheet set.",
                    },
                    .{
                        .label = "refresh",
                        .desc =
                        \\Equivalent to the Refresh HTTP header.
                        \\This instruction specifies:
                        \\
                        \\- The number of seconds until the page should be
                        \\  reloaded if the content attribute is a non-negative
                        \\  integer.
                        \\
                        \\- The number of seconds until the page should
                        \\  redirect to another URL if the content attribute
                        \\  is a non-negative integer followed by `;url=` and a
                        \\  valid URL.
                        \\
                        \\- The timer starts when the page is completely
                        \\  loaded, which is after the `load` and `pageshow` events
                        \\  have both fired.
                        ,
                    },
                    .{
                        .label = "x-ua-compatible",
                        .desc = "Used by legacy versions of the now-retired Microsoft Internet Explorer so that it more closely followed specified behavior. If specified, the `content` attribute must have the value \"IE=edge\". User agents now ignore this pragma.",
                    },
                }),
            },
        },
    },
    .{
        .name = "charset",
        .model = .{
            .rule = .{ .custom = validateCharset },
            .desc = "This attribute declares the document's character encoding. If the attribute is present, its value must be an ASCII case-insensitive match for the string 'utf-8', because UTF-8 is the only valid encoding for HTML5 documents. Since this attribute only accepts one value, its usage is not recommended.",
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

    const superset: Model = .{
        .content = meta.model.content,
        .categories = meta.meta.categories_superset,
    };

    // This element only validates itself when

    // If either name, http-equiv, or itemprop is specified, then the content attribute must also be specified. Otherwise, it must be omitted.

    // The charset attribute specifies the character encoding used by the document. This is a character encoding declaration. If the attribute is present, its value must be an ASCII case-insensitive match for the string "utf-8".

    // There must not be more than one meta element with a charset attribute per document.

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

    // Exactly one of the name, http-equiv, charset, and itemprop attributes must be specified.

    const mutex: Ast.Error = .{
        .tag = .{
            .invalid_attr_combination = "[name], [http-equiv], [charset], and [itemprop] are mutually exclusive",
        },
        .main_location = vait.name,
        .node_idx = node_idx,
    };

    if (attrs[attributes.comptimeIndex("name")] == null) {
        if (attrs[attributes.comptimeIndex("media")]) |media| {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_combination = "only allowed when [name] is 'theme-color'",
                },
                .main_location = media.name,
                .node_idx = node_idx,
            });
        }
    }

    if (attrs[attributes.comptimeIndex("name")]) |attr| {
        if (attrs[attributes.comptimeIndex("http-equiv")] != null or
            attrs[attributes.comptimeIndex("charset")] != null or
            has_itemprop)
        {
            try errors.append(gpa, mutex);
            return superset;
        }

        const name_value = attr.value orelse {
            try errors.append(gpa, .{
                .tag = .missing_attr_value,
                .main_location = attr.name,
                .node_idx = node_idx,
            });

            return superset;
        };

        const name_value_slice = name_value.span.slice(src);
        const rule = comptime attributes.get("name").?.rule.list;
        const match = try rule.match(
            gpa,
            errors,
            node_idx,
            name_value.span.start,
            name_value_slice,
        );

        const content = attrs[attributes.comptimeIndex("content")] orelse {
            try errors.append(gpa, .{
                .tag = .{ .missing_required_attr = "[content]" },
                .main_location = vait.name,
                .node_idx = node_idx,
            });

            return superset;
        };

        // const content_value = content.value orelse {
        //     try errors.append(gpa, .{
        //         .tag = .missing_attr_value,
        //         .main_location = attr.name,
        //         .node_idx = node_idx,
        //     });

        //     return meta.model;
        // };

        // const content_slice = content_value.span.slice(src);
        switch (match) {
            else => {},
            .list => |idx| {
                if (idx != rule.comptimeIndex("theme-color")) {
                    if (attrs[attributes.comptimeIndex("media")]) |media| {
                        try errors.append(gpa, .{
                            .tag = .{
                                .invalid_attr_combination = "only allowed when [name] is 'theme-color'",
                            },
                            .main_location = media.name,
                            .node_idx = node_idx,
                        });
                    }
                }
                switch (idx) {
                    else => {},
                    rule.comptimeIndex("description") => {
                        // There must not be more than one meta element where the name attribute value is an ASCII case-insensitive match for description per document.
                    },

                    rule.comptimeIndex("color-scheme") => {
                        // To aid user agents in rendering the page background with the desired color scheme immediately (rather than waiting for all CSS in the page to load), a 'color-scheme' value can be provided in a meta element.

                        // The value must be a string that matches the syntax for the CSS 'color-scheme' property value. It determines the page's supported color-schemes.

                        // There must not be more than one meta element with its name attribute value set to an ASCII case-insensitive match for color-scheme per document.

                    },
                    rule.comptimeIndex("theme-color") => {

                        // The value must be a string that matches the CSS <color> production, defining a suggested color that user agents should use to customize the display of the page or of the surrounding user interface.

                        // Within an HTML document, the media attribute value must be unique amongst all the meta elements with their name attribute value set to an ASCII case-insensitive match for theme-color.
                    },
                    rule.comptimeIndex("referrer") => {
                        try Attribute.common.referrerpolicy.rule.validate(
                            gpa,
                            errors,
                            src,
                            node_idx,
                            content,
                        );
                    },
                }
            },
        }
    } else if (attrs[attributes.comptimeIndex("http-equiv")]) |attr| {
        if (attrs[attributes.comptimeIndex("name")] != null or
            attrs[attributes.comptimeIndex("charset")] != null or
            has_itemprop)
        {
            try errors.append(gpa, mutex);
            return superset;
        }

        const equiv_value = attr.value orelse {
            try errors.append(gpa, .{
                .tag = .missing_attr_value,
                .main_location = attr.name,
                .node_idx = node_idx,
            });

            return superset;
        };

        const equiv_value_slice = equiv_value.span.slice(src);
        const model = comptime attributes.get("http-equiv").?.rule.list;
        const match = try model.match(
            gpa,
            errors,
            node_idx,
            equiv_value.span.start,
            equiv_value_slice,
        );

        const content = attrs[attributes.comptimeIndex("content")] orelse {
            try errors.append(gpa, .{
                .tag = .{ .missing_required_attr = "content" },
                .main_location = vait.name,
                .node_idx = node_idx,
            });

            return superset;
        };

        const content_value = content.value orelse {
            try errors.append(gpa, .{
                .tag = .missing_attr_value,
                .main_location = content.name,
                .node_idx = node_idx,
            });

            return superset;
        };

        const content_slice = content_value.span.slice(src);

        switch (match) {
            else => {},
            .list => |idx| switch (idx) {
                else => {},
                model.comptimeIndex("content-type") => blk: {
                    // A document must not contain both a meta element with an http-equiv
                    // attribute in the Encoding declaration state and a meta element with
                    // the charset attribute present.

                    // For meta elements with an http-equiv attribute in the
                    // Encoding declaration state, the content attribute must have
                    // a value that is an ASCII case-insensitive match for a string
                    // that consists of: "text/html;", optionally followed by any
                    // number of ASCII whitespace, followed by "charset=utf-8".

                    const err: Ast.Error = .{
                        .tag = .{ .invalid_attr_value = .{
                            .reason = "must be 'text/html;charset=utf-8'",
                        } },
                        .main_location = content_value.span,
                        .node_idx = node_idx,
                    };
                    var it = std.mem.tokenizeAny(u8, content_slice, &std.ascii.whitespace);
                    const tok1 = it.next() orelse {
                        try errors.append(gpa, err);
                        break :blk;
                    };

                    if (std.ascii.eqlIgnoreCase(tok1, "text/html;charset=utf-8")) {
                        break :blk;
                    }

                    if (!std.ascii.eqlIgnoreCase(tok1, "text/html;")) {
                        try errors.append(gpa, err);
                        break :blk;
                    }

                    const tok2 = it.next() orelse {
                        try errors.append(gpa, err);
                        break :blk;
                    };

                    if (!std.ascii.eqlIgnoreCase(tok2, "charset=utf-8")) {
                        try errors.append(gpa, err);
                    }
                },
                model.comptimeIndex("refresh") => {
                    // TODO: parse content
                },
                model.comptimeIndex("content-security-policy") => {
                    // TODO: parse content
                },
            },
        }
    } else if (attrs[attributes.comptimeIndex("charset")]) |attr| {
        if (attrs[attributes.comptimeIndex("http-equiv")] != null or
            attrs[attributes.comptimeIndex("name")] != null or
            has_itemprop)
        {
            try errors.append(gpa, mutex);
            return superset;
        }

        if (attrs[attributes.comptimeIndex("content")]) |content| {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_combination = "requires [name], [http-equiv] or [itemprop]",
                },
                .main_location = content.name,
                .node_idx = node_idx,
            });

            return superset;
        }

        const value = attr.value orelse {
            try errors.append(gpa, .{
                .tag = .missing_attr_value,
                .main_location = attr.name,
                .node_idx = node_idx,
            });

            return superset;
        };

        const content_slice = value.span.slice(src);
        if (!std.ascii.eqlIgnoreCase(content_slice, "utf-8")) {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "must be 'utf-8' (case-insensitive)",
                    },
                },
                .main_location = value.span,
                .node_idx = node_idx,
            });
        }
    } else if (has_itemprop) {
        if (attrs[attributes.comptimeIndex("http-equiv")] != null or
            attrs[attributes.comptimeIndex("charset")] != null or
            attrs[attributes.comptimeIndex("name")] != null)
        {
            try errors.append(gpa, mutex);
            return superset;
        }

        const content = attrs[attributes.comptimeIndex("content")] orelse {
            try errors.append(gpa, .{
                .tag = .{ .missing_required_attr = "content" },
                .main_location = vait.name,
                .node_idx = node_idx,
            });

            return superset;
        };

        const content_value = content.value orelse {
            try errors.append(gpa, .{
                .tag = .missing_attr_value,
                .main_location = content.name,
                .node_idx = node_idx,
            });

            return superset;
        };
        _ = content_value;
        return superset;
    } else if (attrs[attributes.comptimeIndex("property")] != null) {
        // Not officially part of the spec, but used in the wild
        // for open graph attributes. What a mess.
    } else try errors.append(gpa, .{
        .tag = .{
            .missing_required_attr = "one of [name], [http-equiv], [charset], [itemprop] must be defined",
        },
        .main_location = vait.name,
        .node_idx = node_idx,
    });

    return meta.model;
}

fn validateCharset(
    gpa: Allocator,
    errors: *std.ArrayListUnmanaged(Ast.Error),
    src: []const u8,
    node_idx: u32,
    attr: Tokenizer.Attr,
) error{OutOfMemory}!void {
    const value = attr.value orelse return errors.append(gpa, .{
        .tag = .missing_attr_value,
        .main_location = attr.name,
        .node_idx = node_idx,
    });

    const value_slice = value.span.slice(src);
    if (!std.ascii.eqlIgnoreCase(value_slice, "utf-8")) {
        return errors.append(gpa, .{
            .tag = .{
                .invalid_attr_value = .{ .reason = "must be 'utf-8' (case insensitive)" },
            },
            .main_location = value.span,
            .node_idx = node_idx,
        });
    }
}
