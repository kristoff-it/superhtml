const std = @import("std");
const Ast = @import("Ast.zig");
const Rule = Ast.Rule;
const tags = @import("tags.zig");
const TagSet = tags.Set;

pub const t: Rule = .{
    .simple = .{
        .text = true,
        .tags = &.initComptime(.{}),
    },
};
pub const no_text_void: Rule = .{
    .simple = .{
        .text = false,
        .tags = &.initComptime(.{}),
    },
};
pub const text_void: Rule = .{
    .simple = .{
        .text = true,
        .tags = &.initComptime(.{}),
    },
};
pub const flow: Rule = .{
    .simple = .{
        .text = true,
        .tags = &tags.flow_tags,
    },
};
pub const phrasing: Rule = .{
    .simple = .{
        .text = true,
        .tags = &tags.phrasing_tags_map,
    },
};

pub const dfn: Rule = .{
    .simple = .{
        .text = true,
        .tags = blk: {
            const phrasing_tags: []const []const u8 = &.{
                "a",      "abbr",            "area",     "audio",
                "b",      "bdi",             "bdo",      "br",
                "button", "canvas",          "cite",     "code",
                "data",   "datalist",        "del",      "em",
                "embed",  "i",               "iframe",   "img",
                "input",  "ins",             "kbd",      "label",
                "link",   "map",             "mark",     "math",
                "meta",   "meter",           "noscript", "object",
                "output", "picture",         "progress", "q",
                "ruby",   "s",               "samp",     "script",
                "select", "selectedcontent", "slot",     "small",
                "span",   "strong",          "sub",      "sup",
                "svg",    "template",        "textarea", "time",
                "u",      "var",             "video",    "wbr",
            };

            var keys: []const struct { []const u8 } = &.{};
            for (phrasing_tags) |i| keys = keys ++ .{.{i}};
            break :blk &TagSet.initComptime(keys);
        },
    },
};
pub const form: Rule = .{
    .simple = .{
        .text = true,
        .tags = &TagSet.initComptime(.{
            .{"a"},       .{"abbr"},     .{"address"},    .{"area"},
            .{"article"}, .{"aside"},    .{"audio"},      .{"b"},
            .{"bdi"},     .{"bdo"},      .{"blockquote"}, .{"br"},
            .{"button"},  .{"canvas"},   .{"cite"},       .{"code"},
            .{"data"},    .{"datalist"}, .{"del"},        .{"details"},
            .{"dfn"},     .{"dialog"},   .{"div"},        .{"dl"},
            .{"em"},      .{"embed"},    .{"fieldset"},   .{"figure"},
            .{"footer"},  .{"h1"},       .{"h2"},         .{"h3"},
            .{"h4"},      .{"h5"},       .{"h6"},         .{"header"},
            .{"hgroup"},  .{"hr"},       .{"i"},          .{"iframe"},
            .{"img"},     .{"input"},    .{"ins"},        .{"kbd"},
            .{"label"},   .{"link"},     .{"main"},       .{"map"},
            .{"mark"},    .{"math"},     .{"menu"},       .{"meta"},
            .{"meter"},   .{"nav"},      .{"noscript"},   .{"object"},
            .{"ol"},      .{"output"},   .{"p"},          .{"picture"},
            .{"pre"},     .{"progress"}, .{"q"},          .{"ruby"},
            .{"s"},       .{"samp"},     .{"script"},     .{"search"},
            .{"section"}, .{"select"},   .{"slot"},       .{"small"},
            .{"span"},    .{"strong"},   .{"sub"},        .{"sup"},
            .{"svg"},     .{"table"},    .{"template"},   .{"textarea"},
            .{"time"},    .{"u"},        .{"ul"},         .{"var"},
            .{"video"},   .{"wbr"},
        }),
    },
};

pub const title: Rule = .{
    .simple = .{
        .text = false,
        .tags = &.initComptime(.{}),
    },
};
pub const colgroup: Rule = .{
    .simple = .{
        .text = false,
        .tags = &.initComptime(.{ .{"col"}, .{"template"} }),
    },
};
pub const thead_tbody_tfoot: Rule = .{
    .simple = .{
        .text = false,
        .tags = &.initComptime(.{ .{"tr"}, .{"script"}, .{"template"} }),
    },
};
pub const tr: Rule = .{
    .simple = .{
        .text = false,
        .tags = &.initComptime(.{ .{"td"}, .{"th"}, .{"script"}, .{"template"} }),
    },
};

pub const summary: Rule = .{
    .simple = .{
        .text = false,
        .tags = blk: {
            var keys: []const struct { []const u8 } = &.{
                .{"h1"},
                .{"h2"},
                .{"h3"},
                .{"h4"},
                .{"h5"},
                .{"h6"},
                .{"hgroup"},
            };

            for (tags.phrasing_tags) |i| keys = keys ++ .{.{i}};
            break :blk &TagSet.initComptime(keys);
        },
    },
};

pub const menu_ul_ol: Rule = .{
    .simple = .{
        .text = false,
        .tags = &.initComptime(.{
            .{"li"},
            .{"script"},
            .{"template"},
        }),
    },
};

pub const address: Rule = @import("rules/address.zig").rule;
pub const th: Rule = @import("rules/th.zig").rule;
pub const header_footer: Rule = @import("rules/header_footer.zig").rule;
pub const audio_video: Rule = @import("rules/audio_video.zig").rule;
// pub const div: Rule = @import("rules/div.zig").rule;
pub const details: Rule = @import("rules/details.zig").rule;
pub const datalist: Rule = @import("rules/datalist.zig").rule;
pub const fieldset: Rule = @import("rules/fieldset.zig").rule;
pub const hgroup: Rule = @import("rules/hgroup.zig").rule;
pub const button: Rule = @import("rules/button.zig").rule;
pub const a: Rule = @import("rules/a.zig").rule;
pub const canvas: Rule = @import("rules/canvas.zig").rule;
pub const caption: Rule = @import("rules/caption.zig").rule;
pub const html: Rule = @import("rules/html.zig").rule;
