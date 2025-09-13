const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../../root.zig");
const Span = root.Span;
const Ast = @import("../Ast.zig");
const Element = @import("../Element.zig");
const Categories = Element.Categories;
const Model = Element.Model;
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;

pub const img: Element = .{
    .tag = .img,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
            // .embedded = true,
        },
        .content = .none, // void
    },
    .meta = .{
        .categories_superset = .{
            .flow = true,
            .phrasing = true,
            // .embedded = true,
            .interactive = true,
        },
    },
    .reasons = .{
        .categories = .{
            .interactive = .{
                .reject = "presence of [usemap]",
                .accept = "missing [usemap]",
            },
        },
    },
    .attributes = .{
        .dynamic = validate,
    },
    .content = .model,
    .desc =
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/u)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-u-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "alt",
        .model = Attribute.common.alt,
    },
    .{
        .name = "src",
        .model = .{
            .rule = .{ .url = .not_empty },
            .desc = "Specifies the URL of the media resource.",
        },
    },
    .{
        .name = "srcset",
        .model = .{
            .rule = .manual,
            .desc =
            \\One or more strings separated by commas, indicating possible
            \\image sources for the user agent to use. Each string is
            \\composed of:
            \\
            \\1. A URL to an image
            \\2. Optionally, whitespace followed by one of:
            \\                    
            \\    - A width descriptor (a positive integer directly
            \\      followed by w). The width descriptor is divided
            \\      by the source size given in the sizes attribute to
            \\      calculate the effective pixel density.
            \\    - A pixel density descriptor (a positive floating
            \\      point number directly followed by x).
            \\
            \\If no descriptor is specified, the source is assigned the
            \\default descriptor of 1x.
            \\
            \\It is incorrect to mix width descriptors and pixel density
            \\descriptors in the same srcset attribute. Duplicate
            \\descriptors (for instance, two sources in the same srcset
            \\which are both described with 2x) are also invalid.
            \\
            \\If the srcset attribute uses width descriptors, the sizes
            \\attribute must also be present, or the srcset itself will
            \\be ignored.
            \\
            \\The user agent selects any of the available sources at its
            \\discretion. This provides them with significant leeway to
            \\tailor their selection based on things like user preferences
            \\or bandwidth conditions. See our Responsive images tutorial
            \\for an example.
            ,
        },
    },

    .{
        .name = "sizes",
        .model = .{
            .rule = .manual,
            .desc =
            \\One or more strings separated by commas, indicating a set of
            \\source sizes. Each source size consists of:
            \\
            \\    1.  A media condition. This must be omitted for the last
            \\    item in the list.
            \\    2. A source size value.
            \\                       
            \\Media Conditions describe properties of the viewport, not of
            \\the image. For example, `(height <= 500px) 1000px` proposes to
            \\use a source of 1000px width, if the viewport is not higher
            \\than 500px. Because a source size descriptor is used to
            \\specify the width to use for the image during layout of the
            \\page, the media condition is typically (but not necessarily)
            \\based on the width information.
            \\
            \\Source size values specify the intended display size of the
            \\image. User agents use the current source size to select
            \\one of the sources supplied by the srcset attribute, when
            \\those sources are described using width (w) descriptors. The
            \\selected source size affects the intrinsic size of the image
            \\(the image's display size if no CSS styling is applied). If
            \\the srcset attribute is absent, or contains no values with a
            \\width descriptor, then the sizes attribute has no effect.
            \\
            \\A source size value can be any non-negative length. It must
            \\not use CSS functions other than the math functions. Units
            \\are interpreted in the same way as media queries, meaning
            \\that all relative length units are relative to the document
            \\root rather than the <img> element, so an em value is
            \\relative to the root font size, rather than the font size of
            \\the image. Percentage values are not allowed.
            \\
            \\The sizes attribute also accepts the `auto` keyword value.
            \\
            \\`auto` can replace the whole list of sizes or the first
            \\entry in the list. It is only valid when combined with
            \\loading="lazy", and resolves to the concrete size of the
            \\image. Since the intrinsic size of the image is not yet
            \\known, width and height attributes (or CSS equivalents)
            \\should also be specified to prevent the browser assuming a
            \\default width of 300px.
            ,
        },
    },

    .{
        .name = "crossorigin",
        .model = .{
            .rule = .cors,
            .desc =
            \\Indicates if the fetching of the image must be done using a
            \\CORS request. Image data from a CORS-enabled image returned
            \\from a CORS request can be reused in the <canvas> element
            \\without being marked "tainted".
            ,
        },
    },
    .{
        .name = "usemap",
        .model = .{
            .rule = .hash_name_ref,
            .desc = "The partial URL (starting with #) of an image map associated with the element.",
        },
    },
    .{
        .name = "ismap",
        .model = .{
            .rule = .bool,
            .desc = "This Boolean attribute indicates that the image is part of a server-side map. If so, the coordinates where the user clicked on the image are sent to the server.",
        },
    },
    .{
        .name = "width",
        .model = .{
            .rule = .{ .non_neg_int = .{} },
            .desc = "The intrinsic width of the image, in pixels. Must be an integer without a unit.",
        },
    },
    .{
        .name = "height",
        .model = .{
            .rule = .{ .non_neg_int = .{} },
            .desc = "The intrinsic height of the image, in pixels. Must be an integer without a unit.",
        },
    },
    .{
        .name = "referrerpolicy",
        .model = Attribute.common.referrerpolicy,
    },
    .{
        .name = "decoding",
        .model = .{
            .rule = .{
                .list = .init(.none, .one, &.{
                    .{
                        .label = "sync",
                        .desc = "Decode the image synchronously along with rendering the other DOM content, and present everything together.",
                    },
                    .{
                        .label = "async",
                        .desc = "Decode the image asynchronously, after rendering and presenting the other DOM content.",
                    },
                    .{
                        .label = "auto",
                        .desc = "No preference for the decoding mode; the browser decides what is best for the user. This is the default value.",
                    },
                }),
            },
            .desc =
            \\This attribute provides a hint to the browser as to whether
            \\it should perform image decoding along with rendering the
            \\other DOM content in a single presentation step that looks
            \\more "correct" (sync), or render and present the other DOM
            \\content first and then decode the image and present it later
            \\(async). In practice, async means that the next paint does
            \\not wait for the image to decode.
            ,
        },
    },
    .{
        .name = "loading",
        .model = .{
            .rule = .{
                .list = .init(.none, .one, &.{
                    .{
                        .label = "eager",
                        .desc =
                        \\Loads the image immediately, regardless of
                        \\whether or not the image is currently within the
                        \\visible viewport (this is the default value).
                        ,
                    },
                    .{
                        .label = "lazy",
                        .desc =
                        \\Defers loading the image until it reaches a
                        \\calculated distance from the viewport, as defined by
                        \\the browser. The intent is to avoid the network and
                        \\storage bandwidth needed to handle the image until
                        \\it's reasonably certain that it will be needed. This
                        \\generally improves the performance of the content in
                        \\most typical use cases.
                        ,
                    },
                }),
            },
            .desc = "Provides a hint of the relative priority to use when fetching the image.",
        },
    },
    .{
        .name = "fetchpriority",
        .model = .{
            .rule = .{
                .list = .init(.none, .one, &.{
                    .{
                        .label = "high",
                        .desc = "Fetch the image at a high priority relative to other images.",
                    },
                    .{
                        .label = "low",
                        .desc = "Fetch the image at a low priority relative to other images.",
                    },
                    .{
                        .label = "auto",
                        .desc = "Don't set a preference for the fetch priority. This is the default. It is used if no value or an invalid value is set.",
                    },
                }),
            },
            .desc = "Provides a hint of the relative priority to use when fetching the image.",
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
    var seen_descriptors: std.StringArrayHashMapUnmanaged(Span) = .empty;
    defer seen_descriptors.deinit(gpa);

    // An img element allows auto-sizes if:
    // - its loading attribute is in the Lazy state, and
    // - its sizes attribute's value is "auto" (ASCII case-insensitive), or
    //   starts with "auto," (ASCII case-insensitive).
    var loading_lazy = false;
    var seen_sizes = false;
    var sizes_auto = false;
    var sizes_value: ?Span = null;

    // At least one of the src and srcset attributes must be present.
    var seen_src = false;
    var seen_srcset = false;

    // If the element has a usemap attribute: Interactive content.
    var seen_usemap = false;
    var seen_ismap: ?Span = null;

    var seen_alt = false;
    var seen_any_w = false;
    while (try vait.next(gpa, src)) |attr| {
        const name = attr.name.slice(src);
        const model = if (attributes.index(name)) |idx| blk: {
            switch (idx) {
                else => {},
                attributes.comptimeIndex("alt") => {
                    seen_alt = true;
                },
                attributes.comptimeIndex("usemap") => {
                    seen_usemap = true;
                },
                attributes.comptimeIndex("ismap") => {
                    seen_ismap = attr.name;
                },
                attributes.comptimeIndex("src") => {
                    seen_src = true;
                },
                attributes.comptimeIndex("srcset") => {
                    try @import("picture.zig").validateSrcset(
                        gpa,
                        errors,
                        &seen_descriptors,
                        attr,
                        src,
                        node_idx,
                        &seen_any_w,
                    );

                    seen_srcset = true;
                    continue;
                },
                attributes.comptimeIndex("loading") => {
                    const value = attr.value orelse continue;
                    const value_slice = value.span.slice(src);
                    if (std.ascii.eqlIgnoreCase(value_slice, "lazy")) {
                        loading_lazy = true;
                    } else if (std.ascii.eqlIgnoreCase(value_slice, "eager")) {
                        // do nothing
                    } else try errors.append(gpa, .{
                        .tag = .{
                            .invalid_attr_value = .{},
                        },
                        .main_location = value.span,
                        .node_idx = node_idx,
                    });
                    continue;
                },
                attributes.comptimeIndex("sizes") => {
                    // TODO: validate this
                    const value = attr.value orelse continue;
                    const value_slice = value.span.slice(src);
                    seen_sizes = true;
                    sizes_value = value.span;
                    sizes_auto = std.ascii.startsWithIgnoreCase(value_slice, "auto");
                    continue;
                },
            }
            break :blk attributes.list[idx].model;
        } else Attribute.global.get(name) orelse {
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

    if (!seen_src and !seen_srcset) try errors.append(gpa, .{
        .tag = .{ .missing_required_attr = "'src' or 'srcset' must be present" },
        .main_location = vait.name,
        .node_idx = node_idx,
    });

    // If the srcset attribute is present and has any image candidate strings
    // using a width descriptor, the sizes attribute must also be present.
    if (seen_any_w and !seen_sizes) try errors.append(gpa, .{
        .tag = .{ .missing_required_attr = "sizes" },
        .main_location = vait.name,
        .node_idx = node_idx,
    });

    // If the srcset attribute is not specified, and the loading attribute is in
    // the Lazy state, the sizes attribute may be specified with the value "auto"
    // (ASCII case-insensitive).
    if (!seen_srcset and loading_lazy) {} else {
        if (sizes_value) |v| {
            if (std.ascii.eqlIgnoreCase(v.slice(src), "auto")) try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "cannot be auto if 'srcset' is present or 'loading' is not lazy",
                    },
                },
                .main_location = v,
                .node_idx = node_idx,
            });
        }
    }

    // The ismap attribute is a boolean attribute. The attribute must not be
    // specified on an element that does not have an ancestor a element with an
    // href attribute.
    const parent = nodes[parent_idx];
    if (seen_ismap) |span| {
        if (parent.kind != .a or !parent.model.categories.interactive) {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_nesting = .{
                        .kind = .a,
                        .reason = "with 'href' defined",
                    },
                },
                .main_location = span,
                .node_idx = node_idx,
            });
        }
    }

    if (!seen_alt) try errors.append(gpa, .{
        .tag = .{ .missing_required_attr = "alt" },
        .main_location = vait.name,
        .node_idx = node_idx,
    });

    var cats = img.model.categories;
    cats.interactive = seen_usemap;
    return .{
        .categories = cats,
        .content = img.model.content,
        .extra = .{ .autosizes_allowed = loading_lazy and sizes_auto },
    };
}
