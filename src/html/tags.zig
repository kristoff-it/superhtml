const std = @import("std");
const rules = @import("rules.zig");

const RuleMap = std.StaticStringMapWithEql(
    RuleEnum,
    std.static_string_map.eqlAsciiIgnoreCase,
);

pub const RuleEnum = blk: {
    var cases: []const std.builtin.Type.EnumField = &.{
        // https://html.spec.whatwg.org/multipage/dom.html#transparent
        .{
            .name = "transparent",
            .value = 0,
        },
    };

    for (std.meta.declarations(rules), 1..) |d, idx| {
        cases = cases ++ &[_]std.builtin.Type.EnumField{.{
            .name = d.name,
            .value = idx,
        }};
    }

    break :blk @Type(.{
        .@"enum" = .{
            .tag_type = u8,
            .fields = cases,
            .decls = &.{},
            .is_exhaustive = true,
        },
    });
};

pub const all = RuleMap.initComptime(.{
    .{ "a", .a }, // done
    .{ "abbr", .phrasing }, // done
    .{ "address", .address }, // done
    .{ "area", .text_void }, // done
    .{ "article", .flow }, // done
    .{ "aside", .flow }, // done
    .{ "audio", .audio_video }, // done
    .{ "b", .phrasing }, // done
    .{ "base", .text_void }, // done
    .{ "bdi", .phrasing }, // done
    .{ "bdo", .phrasing }, // done
    .{ "blockquote", .flow }, // done
    .{ "body", .flow }, // done
    .{ "br", .text_void }, // done
    .{ "button", .button }, // done
    .{ "canvas", .canvas }, // done
    .{ "caption", .caption }, // done
    .{ "cite", .phrasing }, // done
    .{ "code", .phrasing }, // done
    .{ "col", .text_void }, // done
    .{ "colgroup", .colgroup }, // done
    .{ "data", .phrasing }, // done
    .{ "datalist", .datalist }, // done
    .{ "dd", .flow }, // done
    .{ "del", .transparent }, // done
    .{ "details", .details }, // done
    .{ "dfn", .dfn }, // done
    .{ "dialog", .flow }, // done
    .{ "div", .t },
    .{ "dl", .t },
    .{ "dt", .t },
    .{ "em", .phrasing }, // done
    .{ "embed", .text_void }, // done
    .{ "fencedframe", .no_text_void }, // done
    .{ "fieldset", .fieldset }, // done
    .{ "figcaption", .flow }, // done
    .{ "figure", .t },
    .{ "footer", .header_footer }, // done
    .{ "form", .form }, // done
    .{ "h1", .phrasing }, // done
    .{ "h2", .phrasing }, // done
    .{ "h3", .phrasing }, // done
    .{ "h4", .phrasing }, // done
    .{ "h5", .phrasing }, // done
    .{ "h6", .phrasing }, // done
    .{ "head", .t },
    .{ "header", .header_footer }, // done
    .{ "hgroup", .hgroup }, // done
    .{ "hr", .text_void }, // done
    .{ "html", .html }, // done
    .{ "i", .phrasing }, // done
    .{ "iframe", .text_void }, // done
    .{ "img", .text_void }, // done
    .{ "input", .text_void }, // done
    .{ "ins", .transparent }, // done
    .{ "kbd", .phrasing }, // done
    .{ "label", .t },
    .{ "legend", .t },
    .{ "li", .flow }, // done
    .{ "link", .text_void }, // done
    .{ "main", .flow }, // done
    .{ "map", .transparent }, // done
    .{ "math", .t },
    .{ "mark", .phrasing }, // done
    .{ "menu", .menu_ul_ol }, // done
    .{ "meta", .text_void }, // done
    .{ "meter", .t },
    .{ "nav", .flow }, // done
    .{ "noscript", .t },
    .{ "object", .transparent }, // done
    .{ "ol", .menu_ul_ol }, // done
    .{ "optgroup", .t },
    .{ "option", .t },
    .{ "output", .phrasing }, // done
    .{ "p", .phrasing }, // done
    .{ "picture", .t },
    .{ "pre", .phrasing }, // done
    .{ "progress", .t },
    .{ "q", .phrasing }, // done
    .{ "rp", .text_void }, // done
    .{ "rt", .phrasing }, // done
    .{ "ruby", .t },
    .{ "s", .phrasing }, // done
    .{ "samp", .phrasing }, // done
    .{ "script", .text_void }, // done
    .{ "search", .flow }, // done
    .{ "section", .flow }, // done
    .{ "select", .t },
    .{ "selectedcontent", .text_void }, // done
    .{ "slot", .transparent }, // done
    .{ "small", .phrasing }, // done
    .{ "source", .text_void }, // done
    .{ "span", .t },
    .{ "strong", .phrasing }, // done
    .{ "style", .text_void }, // done
    .{ "sub", .phrasing }, // done
    .{ "summary", .summary }, // done
    .{ "sup", .phrasing }, // done
    .{ "svg", .t },
    .{ "table", .t },
    .{ "tbody", .thead_tbody_tfoot }, // done
    .{ "td", .flow }, // done
    .{ "template", .t },
    .{ "textarea", .text_void }, // done
    .{ "tfoot", .thead_tbody_tfoot }, // done
    .{ "th", .th }, // done
    .{ "thead", .thead_tbody_tfoot }, // done
    .{ "time", .phrasing }, // done
    .{ "title", .title }, // done
    .{ "tr", .tr }, // done
    .{ "track", .text_void }, // done
    .{ "u", .phrasing }, // done
    .{ "ul", .menu_ul_ol }, // done
    .{ "var", .phrasing }, // done
    .{ "video", .audio_video }, // done
    .{ "wbr", .text_void }, // done
});

pub const rcdata_names = Set.initComptime(.{
    .{ "title", {} },
    .{ "textarea", {} },
});

pub const rawtext_names = Set.initComptime(.{
    .{ "style", {} },
    .{ "xmp", {} },
    .{ "iframe", {} },
    .{ "noembed", {} },
    .{ "noframes", {} },
    .{ "noscript", {} },
});

pub const unsupported_names = Set.initComptime(.{
    .{ "applet", {} },
    .{ "acronym", {} },
    .{ "bgsound", {} },
    .{ "dir", {} },
    .{ "frame", {} },
    .{ "frameset", {} },
    .{ "noframes", {} },
    .{ "isindex", {} },
    .{ "keygen", {} },
    .{ "listing", {} },
    .{ "menuitem", {} },
    .{ "nextid", {} },
    .{ "noembed", {} },
    .{ "param", {} },
    .{ "plaintext", {} },
    .{ "rb", {} },
    .{ "rtc", {} },
    .{ "strike", {} },
    .{ "xmp", {} },
    .{ "basefont", {} },
    .{ "big", {} },
    .{ "blink", {} },
    .{ "center", {} },
    .{ "font", {} },
    .{ "marquee", {} },
    .{ "multicol", {} },
    .{ "nobr", {} },
    .{ "spacer", {} },
    .{ "tt", {} },
});

pub const all_shtml = Set.initComptime(.{
    .{ "extend", {} },
    .{ "super", {} },
    .{ "ctx", {} },
});

pub const phrasing_tags: []const []const u8 = &.{
    "a",      "abbr",     "area",            "audio",
    "b",      "bdi",      "bdo",             "br",
    "button", "canvas",   "cite",            "code",
    "data",   "datalist", "del",             "dfn",
    "em",     "embed",    "i",               "iframe",
    "img",    "input",    "ins",             "kbd",
    "label",  "link",     "map",             "mark",
    "math",   "meta",     "meter",           "noscript",
    "object", "output",   "picture",         "progress",
    "q",      "ruby",     "s",               "samp",
    "script", "select",   "selectedcontent", "slot",
    "small",  "span",     "strong",          "sub",
    "sup",    "svg",      "template",        "textarea",
    "time",   "u",        "var",             "video",
    "wbr",
};

pub const phrasing_tags_map = blk: {
    var keys: []const struct { []const u8 } = &.{};
    for (phrasing_tags) |i| keys = keys ++ .{.{i}};
    break :blk Set.initComptime(keys);
};

pub const flow_tags = Set.initComptime(.{
    .{"a"},        .{"abbr"},     .{"address"},    .{"area"},
    .{"article"},  .{"aside"},    .{"audio"},      .{"b"},
    .{"bdi"},      .{"bdo"},      .{"blockquote"}, .{"br"},
    .{"button"},   .{"canvas"},   .{"cite"},       .{"code"},
    .{"data"},     .{"datalist"}, .{"del"},        .{"details"},
    .{"dfn"},      .{"dialog"},   .{"div"},        .{"dl"},
    .{"em"},       .{"embed"},    .{"fieldset"},   .{"figure"},
    .{"footer"},   .{"form"},     .{"h1"},         .{"h2"},
    .{"h3"},       .{"h4"},       .{"h5"},         .{"h6"},
    .{"header"},   .{"hgroup"},   .{"hr"},         .{"i"},
    .{"iframe"},   .{"img"},      .{"input"},      .{"ins"},
    .{"kbd"},      .{"label"},    .{"link"},       .{"main"},
    .{"map"},      .{"mark"},     .{"math"},       .{"menu"},
    .{"meta"},     .{"meter"},    .{"nav"},        .{"noscript"},
    .{"object"},   .{"ol"},       .{"output"},     .{"p"},
    .{"picture"},  .{"pre"},      .{"progress"},   .{"q"},
    .{"ruby"},     .{"s"},        .{"samp"},       .{"script"},
    .{"search"},   .{"section"},  .{"select"},     .{"slot"},
    .{"small"},    .{"span"},     .{"strong"},     .{"sub"},
    .{"sup"},      .{"svg"},      .{"table"},      .{"template"},
    .{"textarea"}, .{"time"},     .{"u"},          .{"ul"},
    .{"var"},      .{"video"},    .{"wbr"},
});

// https://html.spec.whatwg.org/multipage/dom.html#interactive-content
// TODO: attribute conditionals
pub const interactive_content: []const []const u8 = &.{
    "a", // (if the href attribute is present)
    // "audio", // (if the controls attribute is present)
    "button",
    "details",
    "embed",
    "iframe",
    // "img", // (if the usemap attribute is present)
    // "input", // (if the type attribute is not in the Hidden state)
    "label",
    "select",
    "textarea",
    // "video", // (if the controls attribute is present)
};

pub const interactive_content_map = blk: {
    var keys: []const struct { []const u8 } = &.{};
    for (interactive_content) |i| keys = keys ++ .{.{i}};
    break :blk Set.initComptime(keys);
};

pub const canvas_interactive_content: []const []const u8 = &.{
    "details",
    "embed",
    "iframe",
    "label",
    "textarea",
};

pub const canvas_interactive_content_map = blk: {
    var keys: []const struct { []const u8 } = &.{};
    for (canvas_interactive_content) |i| keys = keys ++ .{.{i}};
    break :blk Set.initComptime(keys);
};
