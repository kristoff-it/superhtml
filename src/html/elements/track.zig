const std = @import("std");
const Element = @import("../Element.zig");
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;

pub const track: Element = .{
    .tag = .track,
    .model = .{
        .categories = .none,
        .content = .none,
    },
    .meta = .{ .categories_superset = .none },
    .attributes = .manual,
    .content = .{
        .simple = .{
            .extra_children = &.{ .td, .th, .script, .template },
        },
    },
    .desc =
    \\The `<track>` HTML element is used as a child of the media
    \\elements, `<audio>` and `<video>`. Each track element lets
    \\you specify a timed text track (or time-based data) that can
    \\be displayed in parallel with the media element, for example
    \\to overlay subtitles or closed captions on top of a video or
    \\alongside audio tracks.
    \\
    \\Multiple tracks can be specified for a media element, containing
    \\different kinds of timed text data, or timed text data that has
    \\been translated for different locales. The data that is used
    \\will either be the track that has been set to be the default, or
    \\a kind and translation based on user preferences.
    \\
    \\The tracks are formatted in WebVTT format (.vtt files) — Web
    \\Video Text Tracks.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/track)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-track-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "src",
        .model = .{
            .rule = .{ .url = .not_empty },
            .desc = "Address of the track (.vtt file). Must be a valid URL. This attribute must be specified and its URL value must have the same origin as the document — unless the `<audio>` or `<video>` parent element of the track element has a crossorigin attribute.",
        },
    },
    .{
        .name = "kind",
        .model = .{
            .desc = "How the text track is meant to be used. If omitted the default kind is subtitles. If the attribute contains an invalid value, it will use metadata.",
            .rule = .{
                .list = .init(.none, .one, &.{
                    .{
                        .label = "subtitles",
                        .desc = "Subtitles provide translation of content that cannot be understood by the viewer. For example speech or text that is not English in an English language film.",
                    },
                    .{
                        .label = "captions",
                        .desc = "Closed captions provide a transcription and possibly a translation of audio.",
                    },
                    .{
                        .label = "descriptions",
                        .desc = "Textual descriptions of the video component of the media resource, intended for audio synthesis when the visual component is obscured, unavailable, or not usable (e.g. because the user is interacting with the application without a screen while driving, or because the user is blind). Synthesized as audio.",
                    },
                    .{
                        .label = "chapters",
                        .desc = "Chapter titles are intended to be used when the user is navigating the media resource.",
                    },
                    .{
                        .label = "metadata",
                        .desc = "Tracks used by scripts. Not visible to the user.",
                    },
                }),
            },
        },
    },
    .{
        .name = "srclang",
        .model = .{
            .rule = .lang,
            .desc = "Language of the track text data. It must be a valid BCP 47 language tag. If the `kind` attribute is set to 'subtitles', then `srclang` must be defined.",
        },
    },
    .{
        .name = "label",
        .model = .{
            .desc = "A user-readable title of the text track which is used by the browser when listing available text tracks.",
            .rule = .not_empty,
        },
    },
    .{
        .name = "default",
        .model = .{
            .desc = "This attribute indicates that the track should be enabled unless the user's preferences indicate that another track is more appropriate. This may only be used on one track element per media element.",
            .rule = .bool,
        },
    },
});
