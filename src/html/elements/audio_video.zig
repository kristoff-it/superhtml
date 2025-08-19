const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const root = @import("../../root.zig");
const Span = root.Span;
const Ast = @import("../Ast.zig");
const Element = @import("../Element.zig");
const Model = Element.Model;
const Categories = Element.Categories;
const Attribute = @import("../Attribute.zig");
const ValidatingIterator = Attribute.ValidatingIterator;
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
            // .embedded = true,
        },
        .content = .transparent,
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
                .reject = "presence of [control]",
                .accept = "missing [control]",
            },
        },
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
                .list = .init(.missing_or_empty, .one, &.{
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
    nodes: []const Ast.Node,
    parent_idx: u32,
    node_idx: u32,
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
                if (Attribute.isData(name)) continue;
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
        // .embedded = true,
        .interactive = has_controls,
    };

    const parent = nodes[parent_idx];
    return .{
        .categories = categories,
        .content = categories.intersect(parent.model.content),
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

    var seen_attrs: std.StringHashMapUnmanaged(Span) = .empty;
    defer seen_attrs.deinit(gpa);
    var state: enum { source, track, rest } = if (has_src) .track else .source;
    var first_default: ?Span = null;
    var child_idx = parent.first_child_idx;
    while (child_idx != 0) {
        const child = nodes[child_idx];
        defer child_idx = child.next_idx;

        const child_name = child.span(src);

        state: switch (state) {
            .source => {
                if (child.kind != .source) {
                    state = .track;
                    continue :state .track;
                }

                try validateSource(
                    gpa,
                    errors,
                    &seen_attrs,
                    src,
                    parent.kind,
                    child.open,
                    child_idx,
                );
            },
            .track => {
                if (child.kind == .source) {
                    try errors.append(gpa, .{
                        .tag = .{
                            .invalid_nesting = .{
                                .span = parent_span,
                                .reason = if (has_src)
                                    \\with [src] present, no <source> elements are allowed
                                else
                                    \\<source> elements must go before all other
                                ,
                            },
                        },
                        .main_location = child_name,
                        .node_idx = child_idx,
                    });
                    continue;
                }

                if (child.kind != .track) {
                    state = .rest;
                    continue :state .rest;
                }

                try validateTrack(
                    gpa,
                    errors,
                    &seen_attrs,
                    src,
                    parent.kind,
                    child.open,
                    child_idx,
                    &first_default,
                );
            },
            .rest => {
                if (child.kind == .source) {
                    try errors.append(gpa, .{
                        .tag = .{
                            .invalid_nesting = .{
                                .span = parent_span,
                                .reason = if (has_src)
                                    \\with [src] present, no <source> elements are allowed
                                else
                                    \\<source> elements must go before all other
                                ,
                            },
                        },
                        .main_location = child_name,
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
                                \\<track> elements must go before all non-<source> elements
                                ,
                            },
                        },
                        .main_location = child_name,
                        .node_idx = child_idx,
                    });
                    continue;
                }

                if (child.kind == .audio or child.kind == .video) {
                    try errors.append(gpa, .{
                        .tag = .{
                            .invalid_nesting = .{ .span = parent_span },
                        },
                        .main_location = child_name,
                        .node_idx = child_idx,
                    });
                    continue;
                }
            },
        }
    }
}

fn validateSource(
    gpa: Allocator,
    errors: *std.ArrayList(Ast.Error),
    seen_attrs: *std.StringHashMapUnmanaged(Span),
    src: []const u8,
    parent_kind: Ast.Kind,
    node_span: Span,
    node_idx: u32,
) !void {
    assert(parent_kind == .audio or parent_kind == .video);
    const source_attrs = comptime Attribute.element_attrs.get(.source);

    var vait: ValidatingIterator = .init(
        errors,
        seen_attrs,
        .html,
        node_span,
        src,
        node_idx,
    );

    var seen_src = false;
    while (try vait.next(gpa, src)) |attr| {
        const name = attr.name.slice(src);
        const model = if (source_attrs.index(name)) |idx| blk: {
            switch (idx) {
                source_attrs.comptimeIndex("src") => {
                    seen_src = true;
                },
                source_attrs.comptimeIndex("type"),
                source_attrs.comptimeIndex("media"),
                => {},
                else => {
                    try errors.append(gpa, .{
                        .tag = .{
                            .invalid_attr_nesting = .{
                                .kind = parent_kind,
                            },
                        },
                        .main_location = attr.name,
                        .node_idx = node_idx,
                    });
                    continue;
                },
            }

            break :blk source_attrs.list[idx].model;
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

    if (!seen_src) return errors.append(gpa, .{
        .tag = .{
            .missing_required_attr = "src",
        },
        .main_location = vait.name,
        .node_idx = node_idx,
    });
}

fn validateTrack(
    gpa: Allocator,
    errors: *std.ArrayList(Ast.Error),
    seen_attrs: *std.StringHashMapUnmanaged(Span),
    src: []const u8,
    parent_kind: Ast.Kind,
    node_span: Span,
    node_idx: u32,
    first_default: *?Span,
) !void {
    assert(parent_kind == .audio or parent_kind == .video);
    const track_attrs = comptime Attribute.element_attrs.get(.track);

    // The src attribute gives the URL of the text track data. The value must be a valid non-empty URL potentially surrounded by spaces. This attribute must be present.

    // The srclang attribute gives the language of the text track data. The value must be a valid BCP 47 language tag. This attribute must be present if the element's kind attribute is in the subtitles state.

    // The default attribute is a boolean attribute, which, if specified, indicates that the track is to be enabled if the user's preferences do not indicate that another track would be more appropriate.

    // Each media element must have no more than one track element child whose kind attribute is in the subtitles or captions state and whose default attribute is specified.

    // Each media element must have no more than one track element child whose kind attribute is in the description state and whose default attribute is specified.

    // Each media element must have no more than one track element child whose kind attribute is in the chapters metadata state and whose default attribute is specified.

    // There is no limit on the number of track elements whose kind attribute is in the metadata state and whose default attribute is specified.

    // TODO
    // The value of the label attribute, if the attribute is present, must not be the empty string. Furthermore, there must not be two track element children of the same media element whose kind attributes are in the same state, whose srclang attributes are both missing or have values that represent the same language, and whose label attributes are again both missing or both have the same value.

    var vait: ValidatingIterator = .init(
        errors,
        seen_attrs,
        .html,
        node_span,
        src,
        node_idx,
    );

    var seen_src = false;
    var seen_srclang = false;
    var seen_default: ?Span = null;
    var kind_state: enum {
        missing,
        subtitles,
        captions,
        descriptions,
        chapters,
        metadata,
    } = .missing;
    while (try vait.next(gpa, src)) |attr| {
        const name = attr.name.slice(src);
        const model = if (track_attrs.index(name)) |idx| blk: {
            switch (idx) {
                else => {},
                track_attrs.comptimeIndex("src") => {
                    seen_src = true;
                },
                track_attrs.comptimeIndex("srclang") => {
                    seen_srclang = true;
                },
                track_attrs.comptimeIndex("default") => {
                    seen_default = attr.name;
                },
                track_attrs.comptimeIndex("kind") => {
                    const rule = comptime track_attrs.get("kind").?.rule;

                    const value = attr.value orelse {
                        try errors.append(gpa, .{
                            .tag = .missing_attr_value,
                            .main_location = attr.name,
                            .node_idx = node_idx,
                        });
                        continue;
                    };

                    switch (try rule.list.match(
                        gpa,
                        errors,
                        node_idx,
                        value.span.start,
                        value.span.slice(src),
                    )) {
                        else => {},
                        .list => |lidx| kind_state = switch (lidx) {
                            else => unreachable,
                            rule.list.comptimeIndex("subtitles") => .subtitles,
                            rule.list.comptimeIndex("captions") => .captions,
                            rule.list.comptimeIndex("descriptions") => .descriptions,
                            rule.list.comptimeIndex("chapters") => .chapters,
                            rule.list.comptimeIndex("metadata") => .metadata,
                        },
                    }
                    continue;
                },
            }

            break :blk track_attrs.list[idx].model;
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

    if (!seen_src) try errors.append(gpa, .{
        .tag = .{
            .missing_required_attr = "[src]",
        },
        .main_location = vait.name,
        .node_idx = node_idx,
    });

    if ((kind_state == .missing or kind_state == .subtitles) and
        !seen_srclang) return errors.append(gpa, .{
        .tag = .{
            .missing_required_attr = if (kind_state == .missing)
                "[srclang] (mandatory when [kind] is not defined)"
            else
                "[srclang] (mandatory when [kind] is 'subtitles')",
        },
        .main_location = vait.name,
        .node_idx = node_idx,
    });

    if (kind_state != .metadata) {
        if (first_default.*) |fd| {
            if (seen_default) |sd| {
                try errors.append(gpa, .{
                    .tag = .{
                        .duplicate_sibling_attr = fd,
                    },
                    .main_location = sd,
                    .node_idx = node_idx,
                });
            }
        } else if (seen_default) |sd| {
            first_default.* = sd;
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
                audio.meta.content_reject,
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
                audio.meta.content_reject,
                .{ .forbidden_children = &.{.source} },
            ),
        },
        .rest => return Element.simpleCompletions(
            arena,
            &.{},
            parent.model.content,
            audio.meta.content_reject,
            .{ .forbidden_children = &.{ .source, .track } },
        ),
    }
}
