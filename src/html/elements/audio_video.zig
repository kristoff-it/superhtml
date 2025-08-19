const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../../root.zig");
const Span = root.Span;
const Ast = @import("../Ast.zig");
const Element = @import("../Element.zig");
const Model = Element.Model;
const Categories = Element.Categories;
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;

pub const video: Element = .{
    .tag = .video,
    .model = audio.model,
    .meta = audio.meta,
    .reasons = audio.reasons,
    .attributes = audio.attributes,
    .content = audio.content,
    .desc =
    \\The `<video>` HTML element embeds a media player which supports video
    \\playback into the document. You can use `<video>` for audio content
    \\as well, but the `<audio>` element may provide a more appropriate
    \\user experience.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/video)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-video-element)
    ,
};
pub const audio: Element = .{
    .tag = .audio,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
            .embedded = true,
        },
        .content = .transparent,
    },
    .meta = .{
        .categories_superset = .{
            .flow = true,
            .phrasing = true,
            .embedded = true,
            .interactive = true,
        },
    },
    .reasons = .{
        .categories = .{ .interactive = "presence of 'controls' attribute" },
    },
    .attributes = .{ .dynamic = validateAttrs },
    .content = .{
        .custom = .{
            .validate = validateContent,
            .completions = completionsContent,
        },
    },
    .desc =
    \\The `<audio>` HTML element is used to embed sound content in
    \\documents. It may contain one or more audio sources, represented
    \\using the `src` attribute or the `<source>` element: the browser will
    \\choose the most suitable one. It can also be the destination for
    \\streamed media, using a `MediaStream`.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/audio)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-audio-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "src",
        .model = .{
            .rule = .{ .url = .not_empty },
            .desc =
            \\The URL of the media to embed. This is subject to HTTP
            \\access controls. This is optional; you may instead use the
            \\`<source>` element within the element to specify the media
            \\to embed.
            ,
        },
    },
    .{
        .name = "autoplay",
        .model = .{
            .rule = .bool,
            .desc =
            \\If specified, the media will automatically begin playback as
            \\soon as it can do so, without waiting for the entire media
            \\file to finish downloading.
            ,
        },
    },
    .{
        .name = "loop",
        .model = .{
            .rule = .bool,
            .desc =
            \\If specified, the media player will automatically seek back
            \\to the start upon reaching the end of the media.
            ,
        },
    },
    .{
        .name = "muted",
        .model = .{
            .rule = .bool,
            .desc =
            \\If specified, the audio will be initially muted.
            ,
        },
    },
    .{
        .name = "controls",
        .model = .{
            .rule = .bool,
            .desc =
            \\If specified, the browser will offer controls to allow the
            \\user to control media playback, including volume, seeking,
            \\and pause/resume playback.
            ,
        },
    },
    .{
        .name = "preload",
        .model = .{
            .rule = .{
                .list = .init(.missing_or_empty, &.{
                    .{
                        .label = "none",
                        .desc =
                        \\Indicates that the media should not be preloaded.
                        ,
                    },
                    .{
                        .label = "auto",
                        .desc =
                        \\Indicates that the whole media file can be downloaded, even if the user is not expected to use it.
                        ,
                    },
                    .{
                        .label = "metadata",
                        .desc =
                        \\Indicates that only media metadata (e.g., length) is fetched.
                        ,
                    },
                }),
            },
            .desc =
            \\Provides a hint to the browser about what the author thinks
            \\will lead to the best user experience.
            \\
            \\- The autoplay attribute has precedence over preload. If autoplay
            \\  is specified, the browser would obviously need to start
            \\  downloading the media for playback.
            \\
            \\- The browser is not forced by the specification to follow the
            \\  value of this attribute; it is a mere hint.
            ,
        },
    },
    .{
        .name = "crossorigin",
        .model = .{
            .rule = .cors,
            .desc =
            \\Indicates whether to use CORS to fetch the related media file.
            \\CORS-enabled resources can be reused in the `<canvas>` element
            \\without being tainted.
            \\
            \\When not present, the resource is fetched without a CORS request
            \\(i.e., without sending the `Origin:` HTTP header), preventing its
            \\non-tainted use in `<canvas>` elements. 
            ,
        },
    },
});

pub fn validateAttrs(
    gpa: Allocator,
    errors: *std.ArrayListUnmanaged(Ast.Error),
    src: []const u8,
    node_idx: u32,
    parent_content: Categories,
    vait: *Attribute.ValidatingIterator,
) !Model {
    var has_controls = false;
    while (try vait.next(gpa, src)) |attr| {
        const name = attr.name.slice(src);
        const attr_model = blk: {
            if (attributes.index(name)) |idx| {
                if (attributes.comptimeIndex("controls") == idx) has_controls = true;
                break :blk attributes.list[idx].model;
            }

            break :blk Attribute.global.get(name) orelse {
                try errors.append(gpa, .{
                    .tag = .invalid_attr,
                    .main_location = attr.name,
                    .node_idx = node_idx,
                });

                continue;
            };
        };

        try attr_model.rule.validate(gpa, errors, src, node_idx, attr);
    }

    const categories: Categories = .{
        .flow = true,
        .phrasing = true,
        .embedded = true,
        .interactive = has_controls,
    };

    return .{
        .categories = categories,
        .content = categories.intersect(parent_content),
    };
}

pub fn validateContent(
    gpa: Allocator,
    nodes: []const Ast.Node,
    errors: *std.ArrayListUnmanaged(Ast.Error),
    src: []const u8,
    parent_idx: u32,
) !void {
    const parent = nodes[parent_idx];
    const parent_span, const has_src = blk: {
        var it = parent.startTagIterator(src, .html);

        while (it.next(src)) |attr| {
            if (attributes.index(attr.name.slice(src))) |idx| {
                if (attributes.comptimeIndex("src") == idx) {
                    break :blk .{ it.name_span, true };
                }
            }
        }

        break :blk .{ it.name_span, false };
    };

    var state: enum { source, track, rest } = if (has_src) .track else .source;
    var child_idx = parent.first_child_idx;
    while (child_idx != 0) {
        const child = nodes[child_idx];
        defer child_idx = child.next_idx;

        const child_span = child.span(src);

        state: switch (state) {
            .source => {
                if (child.kind != .source) {
                    state = .track;
                    continue :state .track;
                }
            },
            .track => {
                if (child.kind == .source) {
                    try errors.append(gpa, .{
                        .tag = .{
                            .invalid_nesting = .{
                                .span = parent_span,
                                .reason = if (has_src)
                                    \\with src attribute present, no source elements are allowed
                                else
                                    \\source elements must go before all other
                                ,
                            },
                        },
                        .main_location = child_span,
                        .node_idx = child_idx,
                    });
                    continue;
                }

                if (child.kind != .track) {
                    state = .rest;
                    continue :state .rest;
                }
            },
            .rest => {
                if (child.kind == .source) {
                    try errors.append(gpa, .{
                        .tag = .{
                            .invalid_nesting = .{
                                .span = parent_span,
                                .reason = if (has_src)
                                    \\with src attribute present, no source elements are allowed
                                else
                                    \\source elements must go before all other
                                ,
                            },
                        },
                        .main_location = child_span,
                        .node_idx = child_idx,
                    });
                    continue;
                }

                if (child.kind == .track) {
                    try errors.append(gpa, .{
                        .tag = .{
                            .invalid_nesting = .{
                                .span = parent_span,
                                .reason =
                                \\track elements must go before all non-source elements
                                ,
                            },
                        },
                        .main_location = child_span,
                        .node_idx = child_idx,
                    });
                    continue;
                }

                if (child.kind == .audio or child.kind == .video) {
                    try errors.append(gpa, .{
                        .tag = .{
                            .invalid_nesting = .{ .span = parent_span },
                        },
                        .main_location = child_span,
                        .node_idx = child_idx,
                    });
                    continue;
                }
            },
        }
    }
}

fn completionsContent(
    arena: Allocator,
    ast: Ast,
    src: []const u8,
    parent_idx: u32,
    offset: u32,
) error{OutOfMemory}![]const Ast.Completion {
    const parent = ast.nodes[parent_idx];
    const has_src = blk: {
        var it = parent.startTagIterator(src, .html);

        while (it.next(src)) |attr| {
            if (attributes.index(attr.name.slice(src))) |idx| {
                if (attributes.comptimeIndex("src") == idx) {
                    break :blk true;
                }
            }
        }

        break :blk false;
    };

    var state: enum { source, track, rest } = if (has_src) .track else .source;
    var kind_after_cursor: Ast.Kind = .root;
    var child_idx = parent.first_child_idx;
    while (child_idx != 0) {
        const child = ast.nodes[child_idx];
        defer child_idx = child.next_idx;

        if (child.open.start > offset) {
            kind_after_cursor = child.kind;
            break;
        }

        state: switch (state) {
            .source => if (child.kind != .source) {
                state = .track;
                continue :state .track;
            },
            .track => if (child.kind != .track and child.kind != .source) {
                state = .rest;
                continue :state .rest;
            },
            .rest => break,
        }
    }

    const source = comptime Element.all.get(.source);
    const track = comptime Element.all.get(.track);

    switch (state) {
        .source => switch (kind_after_cursor) {
            .source => return &.{
                .{ .label = @tagName(source.tag), .desc = source.desc },
            },
            .track => return &.{
                .{ .label = @tagName(source.tag), .desc = source.desc },
                .{ .label = @tagName(track.tag), .desc = track.desc },
            },
            else => return Element.simpleCompletions(
                arena,
                &.{ .source, .track },
                parent.model.content,
                .{},
            ),
        },

        .track => switch (kind_after_cursor) {
            .track => return &.{
                .{ .label = @tagName(track.tag), .desc = track.desc },
            },
            else => return Element.simpleCompletions(
                arena,
                &.{.track},
                parent.model.content,
                .{ .forbidden_children = &.{.source} },
            ),
        },
        .rest => return Element.simpleCompletions(
            arena,
            &.{},
            parent.model.content,
            .{ .forbidden_children = &.{ .source, .track } },
        ),
    }
}
