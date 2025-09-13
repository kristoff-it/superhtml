const std = @import("std");
const Allocator = std.mem.Allocator;
const Element = @import("../Element.zig");
const AttributeSet = @import("../Attribute.zig").AttributeSet;

pub const source: Element = .{
    .tag = .source,
    .model = .{
        .categories = .none,
        .content = .none,
    },
    .meta = .{
        .categories_superset = .none,
    },
    .attributes = .manual, // done by <audio>, <video> and <picture>
    .content = .model,
    .desc =
    \\The `<source>` HTML element specifies one or more media resources for
    \\the `<picture>`, `<audio>`, and `<video>` elements. It is a void element,
    \\which means that it has no content and does not require a closing
    \\tag. This element is commonly used to offer the same media content
    \\in multiple file formats in order to provide compatibility with a
    \\broad range of browsers given their differing support for image file
    \\formats and media file formats.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/source)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-source-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "src",
        .model = .{
            .rule = .{ .url = .not_empty }, // only in audio/video
            .desc = "Specifies the URL of the media resource.",
        },
    },
    .{
        .name = "type",
        .model = .{
            .rule = .mime,
            .desc =
            \\Specifies the MIME media type, optionally including a `codecs` parameter.
            ,
        },
    },
    .{
        .name = "media",
        .model = .{
            .rule = .not_empty, // TODO
            .desc = "Specifies the media query for the resource's intended media.",
        },
    },
    .{
        .name = "srcset",
        .model = .{
            .rule = .manual, // validated by <picture>
            .desc =
            \\Specifies a comma-separated list of one or more image URLs
            \\and their descriptors. Required if the parent of `<source>` is
            \\``<picture>`. Not allowed if the parent is `<audio>` or `<video>`.
            \\
            \\The list consists of strings separated by commas, indicating a
            \\set of possible images for the browser to use. Each string is
            \\composed of:
            \\
            \\A URL specifying an image location.
            \\
            \\An optional width descriptor—a positive integer directly
            \\followed by "w", such as `300w`.
            \\
            \\An optional pixel density descriptor—a positive floating number
            \\directly followed by "x", such as `2x`.
            \\
            \\Each string in the list must have either a width descriptor
            \\or a pixel density descriptor to be valid. These two
            \\descriptors should not be used together; only one should
            \\be used consistently throughout the list. The value of each
            \\descriptor in the list must be unique. The browser chooses the
            \\most adequate image to display at a given point of time based
            \\on these descriptors. If the descriptors are not specified,
            \\the default value used is `1x`. If the sizes attribute is also
            \\present, then each string must include a width descriptor. If
            \\the browser does not support `srcset`, then src will be used for
            \\the default image source.
            ,
        },
    },
    .{
        .name = "sizes",
        .model = .{
            .rule = .any, // TODO
            .desc =
            \\Specifies a list of source sizes that describe the final
            \\rendered width of the image. Allowed if the parent of
            \\`<source>` is `<picture>`. Not allowed if the parent is `<audio>`
            \\or `<video>`.
            \\
            \\The list consists of source sizes separated by commas. Each
            \\source size is a media condition-length pair. Before laying
            \\the page out, the browser uses this information to determine
            \\which image defined in srcset to display. Note that sizes
            \\will take effect only if width descriptors are provided with
            \\`srcset`, not pixel density descriptors (i.e., `200w` should be
            \\used instead of `2x`).
            ,
        },
    },
    .{
        .name = "width",
        .model = .{
            .rule = .{ .non_neg_int = .{} },
            .desc =
            \\Specifies the intrinsic height of the image in pixels.
            \\Allowed if the parent of `<source>` is a `<picture>`. Not
            \\allowed if the parent is `<audio>` or `<video>`.
            \\
            \\The height value must be a non-negative integer without
            \\any units.
            ,
        },
    },
    .{
        .name = "height",
        .model = .{
            .rule = .{ .non_neg_int = .{} },
            .desc =
            \\Specifies the intrinsic width of the image in pixels.
            \\Allowed if the parent of `<source>` is a `<picture>`. Not
            \\allowed if the parent is `<audio>` or `<video>`.
            \\
            \\The width value must be a non-negative integer without any units.
            ,
        },
    },
});
