const Ast = @This();

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const tracy = @import("tracy");
const root = @import("../root.zig");
const Language = root.Language;
const Span = root.Span;
const Tokenizer = @import("Tokenizer.zig");
const Element = @import("Element.zig");
const elements = Element.all;
const kinds = Element.elements;
const Attribute = @import("Attribute.zig");

const log = std.log.scoped(.@"html/ast");

has_syntax_errors: bool,
language: Language,
nodes: []const Node,
errors: []const Error,

pub const Kind = enum {
    // zig fmt: off
    // Basic nodes
    root, doctype, comment, text,

    // superhtml
    extend, super, ctx,
    
    ___, // invalid or web component (or superhtml if not in shtml mode)
    
    // Begin of html tags
    a, abbr, address, area, article, aside, audio, b, base, bdi, bdo,
    blockquote, body, br, button, canvas, caption, cite, code, col, colgroup,
    data, datalist, dd, del, details, dfn, dialog, div, dl, dt, em, embed,
    fencedframe, fieldset, figcaption, figure, footer, form, h1, h2, h3, h4, h5,
    h6, head, header, hgroup, hr, html, i, iframe, img, input, ins, kbd, label,
    legend, li, link, main, map, math, mark, menu, meta, meter, nav, noscript,
    object, ol, optgroup, option, output, p, picture, pre, progress, q, rp,
    rt, ruby, s, samp, script, search, section, select, selectedcontent, slot,
    small, source, span, strong, style, sub, summary, sup, svg,  table, tbody,
    td, template, textarea, tfoot, th, thead, time, title, tr, track, u, ul,
    @"var", video, wbr,
    // zig fmt: on

    pub fn isElement(k: Kind) bool {
        return @intFromEnum(k) > @intFromEnum(Kind.text);
    }

    pub fn isVoid(k: Kind) bool {
        return switch (k) {
            .root,
            .doctype,
            .comment,
            .text,
            => unreachable,
            // shtml
            .extend,
            .super,
            // html
            .area,
            .base,
            .br,
            .col,
            .embed,
            .hr,
            .img,
            .input,
            .link,
            .meta,
            .source,
            .track,
            .wbr,
            => true,
            else => false,
        };
    }
};

pub const Set = std.StaticStringMapWithEql(
    void,
    std.static_string_map.eqlAsciiIgnoreCase,
);

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

pub const Node = struct {
    /// Span covering start_tag, diamond brackets included
    open: Span,
    /// Span covering end_tag, diamond brackets included
    /// Unset status is represented by .start = 0
    /// not set for doctype, element_void and element_self_closing
    close: Span = .{ .start = 0, .end = 0 },

    parent_idx: u32 = 0,
    first_child_idx: u32 = 0,
    next_idx: u32 = 0,

    kind: Kind,
    self_closing: bool = false, // TODO fold into element tags
    model: Element.Model,

    pub fn isClosed(n: Node) bool {
        return switch (n.kind) {
            .root => unreachable,
            .doctype, .text, .comment => true,
            else => if (n.kind.isVoid() or n.self_closing) true else n.close.start > 0,
        };
    }

    pub const Direction = enum { in, after };
    pub fn direction(n: Node) Direction {
        switch (n.kind) {
            .root => {
                std.debug.assert(n.first_child_idx == 0);
                return .in;
            },
            .doctype, .text, .comment => return .after,
            else => {
                if (n.kind.isVoid() or n.self_closing) return .after;
                if (n.close.start == 0) {
                    return .in;
                }
                return .after;
            },
        }
    }

    pub const TagIterator = struct {
        end: u32,
        name_span: Span,
        tokenizer: Tokenizer,

        pub fn next(ti: *TagIterator, src: []const u8) ?Tokenizer.Attr {
            while (ti.tokenizer.next(src[0..ti.end])) |maybe_attr| switch (maybe_attr) {
                .attr => |attr| return attr,
                else => {},
            } else return null;
        }
    };

    pub fn startTagIterator(n: Node, src: []const u8, language: Language) TagIterator {
        const zone = tracy.trace(@src());
        defer zone.end();

        var t: Tokenizer = .{
            .language = language,
            .idx = n.open.start,
            .return_attrs = true,
        };
        // TODO: depending on how we deal with errors with might
        //       need more sophisticated logic here than a yolo
        //       union access.
        const name = t.next(src[0..n.open.end]).?.tag_name;
        return .{
            .end = n.open.end,
            .tokenizer = t,
            .name_span = name,
        };
    }

    pub fn span(n: Node, src: []const u8) Span {
        if (n.kind.isElement()) {
            return n.startTagIterator(src, .html).name_span;
        }

        return n.open;
    }

    /// Calulates the stop index when iterating all descendants of a node
    /// it either equals the index of the next node after this one, or
    /// nodes.len in case there are no other nodes.
    pub fn stop(n: Node, nodes: []const Node) u32 {
        var cur = n;
        const result = while (true) {
            if (cur.next_idx != 0) break cur.next_idx;
            if (cur.parent_idx == 0) break nodes.len;
            cur = nodes[cur.parent_idx];
        };
        assert(result > n.first_child_idx);
        return @intCast(result);
    }

    pub fn debug(n: Node, src: []const u8) void {
        std.debug.print("{s}", .{n.open.slice(src)});
    }
};

pub const Error = struct {
    tag: union(enum) {
        token: Tokenizer.TokenError,
        unsupported_doctype,
        invalid_attr,
        invalid_attr_nesting: struct {
            kind: Kind,
            reason: []const u8 = "",
        },
        invalid_attr_value: struct {
            reason: []const u8 = "",
        },

        /// Only use for static limits
        int_out_of_bounds: struct { min: usize, max: usize },
        missing_attr_value,
        boolean_attr,
        invalid_attr_combination: []const u8, // reason
        duplicate_class: Span, // original
        missing_required_attr: []const u8,
        wrong_position: enum { first, second, first_or_last },
        missing_ancestor: Kind,
        missing_child: Kind,
        duplicate_child: struct {
            span: Span, // original child
            reason: []const u8 = "",
        },
        wrong_sibling_sequence: struct {
            span: ?Span = null, // previous sibling
            reason: []const u8 = "",
        },
        // Contains a span to the tag name of the ancestor that forbids this
        // nesting. Usually the parent, but not always. In the case of
        // elements with a transparent content model, the non-transparent
        // ancestor that forbits the node will be used.
        invalid_nesting: struct {
            span: Span, // parent node that caused this error
            reason: []const u8 = "",
        },
        invalid_html_tag_name,
        html_elements_cant_self_close,
        missing_end_tag,
        erroneous_end_tag,
        void_end_tag,
        duplicate_attribute_name: Span, // original attribute
        duplicate_sibling_attr: Span, // original attribute in another element
        deprecated_and_unsupported,

        const Tag = @This();
        pub fn fmt(tag: Tag, src: []const u8) Tag.Formatter {
            return .{ .tag = tag, .src = src };
        }
        const Formatter = struct {
            tag: Tag,
            src: []const u8,
            pub fn format(tf: Tag.Formatter, w: *std.Io.Writer) !void {
                return switch (tf.tag) {
                    .token => w.print("syntax error", .{}),
                    .unsupported_doctype => w.print(
                        "unsupported doctype: superhtml only supports the 'html' doctype",
                        .{},
                    ),
                    .invalid_attr => w.print(
                        "invalid attribute for this element",
                        .{},
                    ),
                    .invalid_attr_nesting => |nest| w.print(
                        "invalid attribute for this element when nested under '{t}' {s}",
                        .{ nest.kind, nest.reason },
                    ),
                    .invalid_attr_value => |iav| {
                        try w.print("invalid value for this attribute", .{});
                        if (iav.reason.len > 0) {
                            try w.print(": {s}", .{iav.reason});
                        }
                    },
                    .int_out_of_bounds => |ioob| {
                        try w.print(
                            "integer value out of bounds (min: {}, max: {})",
                            .{ ioob.min, ioob.max },
                        );
                    },
                    .invalid_attr_combination => |iac| w.print(
                        "invalid attribute combination: {s}",
                        .{iac},
                    ),
                    .missing_required_attr => |attr| w.print(
                        "missing required attribute(s): {s}",
                        .{attr},
                    ),
                    .missing_attr_value => w.print(
                        "missing attribute value",
                        .{},
                    ),
                    .boolean_attr => w.print(
                        "this attribute cannot have a value",
                        .{},
                    ),
                    .duplicate_class => w.print(
                        "duplicate class",
                        .{},
                    ),
                    .wrong_position => |p| w.print(
                        "element in wrong position, should be {s}",
                        .{switch (p) {
                            .first, .second => @tagName(p),
                            .first_or_last => "first or last",
                        }},
                    ),
                    .missing_ancestor => |e| w.print("missing ancestor: {t}", .{e}),
                    .missing_child => |e| w.print("missing child: <{t}>", .{e}),
                    .duplicate_child => |dc| {
                        try w.print("duplicate child", .{});
                        if (dc.reason.len > 0) {
                            try w.print(": {s}", .{dc.reason});
                        }
                    },
                    .wrong_sibling_sequence => |dc| {
                        try w.print("wrong sibling sequence", .{});
                        if (dc.reason.len > 0) {
                            try w.print(": {s}", .{dc.reason});
                        }
                    },
                    .invalid_nesting => |in| {
                        try w.print("invalid nesting under <{s}>", .{
                            in.span.slice(tf.src),
                        });
                        if (in.reason.len > 0) {
                            try w.print(": {s}", .{in.reason});
                        }
                    },
                    .invalid_html_tag_name => w.print(
                        "not a valid html element",
                        .{},
                    ),
                    .html_elements_cant_self_close => w.print(
                        "html elements can't self-close",
                        .{},
                    ),
                    .missing_end_tag => w.print("missing end tag", .{}),
                    .erroneous_end_tag => w.print("erroneous end tag", .{}),
                    .void_end_tag => w.print("void elements have no end tag", .{}),
                    .duplicate_attribute_name => w.print("duplicate attribute name", .{}),
                    .duplicate_sibling_attr => w.print(
                        "duplicate attribute name across sibling elements",
                        .{},
                    ),
                    .deprecated_and_unsupported => w.print("deprecated and unsupported", .{}),
                };
            }
        };
    },
    main_location: Span,
    node_idx: u32, // 0 = missing node
};

pub fn cursor(ast: Ast, idx: u32) Cursor {
    return .{ .ast = ast, .idx = idx, .dir = .in };
}

pub fn printErrors(
    ast: Ast,
    src: []const u8,
    path: ?[]const u8,
    w: *Writer,
) !void {
    for (ast.errors) |err| {
        const range = err.main_location.range(src);
        try w.print("{s}:{}:{}: {f}\n", .{
            path orelse "<stdin>",
            range.start.row,
            range.start.col,
            err.tag.fmt(src),
        });

        try printSourceLine(src, err.main_location, w);
    }
}

fn printSourceLine(src: []const u8, span: Span, w: *Writer) !void {
    // test.html:3:7: invalid attribute for this element
    //         <div foo bar baz>
    //              ^^^
    //
    var idx = span.start;
    var spaces_left: u32 = 0;
    const line_start = while (idx > 0) : (idx -= 1) switch (src[idx]) {
        '\n' => break idx + 1,
        ' ', '\t', ('\n' + 1)...'\r' => spaces_left += 1,
        else => spaces_left = 0,
    } else 0;

    idx = span.start;
    var last_non_space = idx;
    while (idx < src.len) : (idx += 1) switch (src[idx]) {
        '\n' => break,
        ' ', '\t', ('\n' + 1)...'\r' => {},
        else => last_non_space = idx,
    };

    const line = src[line_start + spaces_left .. last_non_space + 1];
    try w.print("   {s}\n", .{line});
    try w.splatByteAll(' ', span.start - (line_start + spaces_left) + 3);
    try w.splatByteAll('^', span.end - span.start);
    try w.print("\n", .{});
}

pub fn deinit(ast: Ast, gpa: Allocator) void {
    gpa.free(ast.nodes);
    gpa.free(ast.errors);
}

pub fn init(
    gpa: Allocator,
    src: []const u8,
    language: Language,
    /// When true only official HTML tag names will be allowed.
    /// Strict mode currently only supports HTML and SuperHTML.
    strict: bool,
) error{OutOfMemory}!Ast {
    if (src.len > std.math.maxInt(u32)) @panic("too long");

    var nodes = std.array_list.Managed(Node).init(gpa);
    errdefer nodes.deinit();

    var errors: std.ArrayListUnmanaged(Error) = .empty;
    errdefer errors.deinit(gpa);

    var seen_attrs: std.StringHashMapUnmanaged(Span) = .empty;
    defer seen_attrs.deinit(gpa);

    var has_syntax_errors = false;

    try nodes.append(.{
        .open = .{
            .start = 0,
            .end = 0,
        },
        .close = .{
            .start = @intCast(src.len),
            .end = @intCast(src.len),
        },
        .parent_idx = 0,
        .first_child_idx = 0,
        .next_idx = 0,

        .kind = .root,
        .model = .{
            .categories = .none,
            .content = .all,
        },
    });

    var tokenizer: Tokenizer = .{ .language = language };

    var current: *Node = &nodes.items[0];
    var current_idx: u32 = 0;
    var svg_lvl: u32 = 0;
    var math_lvl: u32 = 0;
    while (tokenizer.next(src)) |t| {
        log.debug("cur_idx: {} cur_kind: {s} tok: {any}", .{
            current_idx,
            @tagName(current.kind),
            t,
        });
        switch (t) {
            .tag_name, .attr => unreachable,
            .doctype => |dt| {
                var new: Node = .{
                    .kind = .doctype,
                    .open = dt.span,
                    .model = .{
                        .categories = .none,
                        .content = .none,
                    },
                };

                switch (current.direction()) {
                    .in => {
                        new.parent_idx = current_idx;
                        std.debug.assert(current.first_child_idx == 0);
                        current_idx = @intCast(nodes.items.len);
                        current.first_child_idx = current_idx;
                    },
                    .after => {
                        new.parent_idx = current.parent_idx;
                        current_idx = @intCast(nodes.items.len);
                        current.next_idx = current_idx;
                    },
                }

                try nodes.append(new);
                current = &nodes.items[current_idx];
            },
            .tag => |tag| switch (tag.kind) {
                .start,
                .start_self,
                => {
                    const name = tag.name.slice(src);
                    var new: Node = node: switch (tag.kind) {
                        else => unreachable,
                        .start_self => {
                            if (svg_lvl != 0 or math_lvl != 0 or language == .xml) {
                                break :node .{
                                    .kind = .___,
                                    .open = tag.span,
                                    .model = .{
                                        .categories = .all,
                                        .content = .all,
                                    },
                                    .self_closing = true,
                                };
                            }
                            try errors.append(gpa, .{
                                .tag = .html_elements_cant_self_close,
                                .main_location = tag.name,
                                .node_idx = current_idx + 1,
                            });
                            continue :node .start;
                        },
                        .start => switch (language) {
                            .superhtml => {
                                const kind: Ast.Kind = if (std.ascii.eqlIgnoreCase("ctx", name))
                                    .ctx
                                else if (std.ascii.eqlIgnoreCase("super", name))
                                    .super
                                else if (std.ascii.eqlIgnoreCase("extend", name))
                                    .extend
                                else
                                    kinds.get(name) orelse .___;

                                break :node .{
                                    .open = tag.span,
                                    .kind = kind,
                                    .model = .{
                                        .categories = .all,
                                        .content = .all,
                                    },
                                };
                            },
                            .html => {
                                if (kinds.get(name)) |kind| {
                                    const parent_idx = switch (current.direction()) {
                                        .in => current_idx,
                                        .after => nodes.items[current_idx].parent_idx,
                                    };

                                    const e = elements.get(kind);
                                    const model = try e.validateAttrs(
                                        gpa,
                                        language,
                                        &errors,
                                        &seen_attrs,
                                        nodes.items,
                                        parent_idx,
                                        src,
                                        tag.span,
                                        @intCast(nodes.items.len),
                                    );

                                    break :node .{
                                        .open = tag.span,
                                        .kind = kind,
                                        .model = model,
                                    };
                                } else if (std.mem.indexOfScalar(u8, name, '-') == null) {
                                    try errors.append(gpa, .{
                                        .tag = .invalid_html_tag_name,
                                        .main_location = tag.name,
                                        .node_idx = @intCast(nodes.items.len),
                                    });
                                }

                                break :node .{
                                    .kind = .___,
                                    .open = tag.span,
                                    .model = .{
                                        .categories = .all,
                                        .content = .all,
                                    },
                                };
                            },
                            .xml => break :node .{
                                .kind = .___,
                                .open = tag.span,
                                .model = .{
                                    .categories = .all,
                                    .content = .all,
                                },
                            },
                        },
                    };

                    // This comparison is done via strings instead of kinds
                    // because we will not attempt to match the kind of an
                    // svg nested inside another svg, and same for math.
                    if (std.ascii.eqlIgnoreCase("svg", name)) {
                        svg_lvl += 1;
                    }
                    if (std.ascii.eqlIgnoreCase("math", name)) {
                        math_lvl += 1;
                    }

                    switch (current.direction()) {
                        .in => {
                            new.parent_idx = current_idx;
                            std.debug.assert(current.first_child_idx == 0);
                            current_idx = @intCast(nodes.items.len);
                            current.first_child_idx = current_idx;
                        },
                        .after => {
                            new.parent_idx = current.parent_idx;
                            current_idx = @intCast(nodes.items.len);
                            current.next_idx = current_idx;
                        },
                    }

                    try nodes.append(new);
                    current = &nodes.items[current_idx];

                    if (strict and current.kind == .main) {
                        var ancestor_idx = current.parent_idx;
                        while (ancestor_idx != 0) {
                            const ancestor = nodes.items[ancestor_idx];
                            defer ancestor_idx = ancestor.parent_idx;

                            switch (ancestor.kind) {
                                .html,
                                .body,
                                .div,
                                .___,
                                => {},
                                .form => {
                                    // TODO: check accessible name
                                },
                                else => {
                                    try errors.append(gpa, .{
                                        .tag = .{
                                            .invalid_nesting = .{
                                                .span = ancestor.span(src),
                                                .reason = "main can only nest under html, body, div and form",
                                            },
                                        },
                                        .main_location = tag.name,
                                        .node_idx = current_idx,
                                    });
                                },
                            }
                        }
                    }

                    if (std.ascii.eqlIgnoreCase("script", name)) {
                        tokenizer.gotoScriptData();
                    } else if (rawtext_names.has(name)) {
                        tokenizer.gotoRawText(name);
                    } else if (unsupported_names.has(name)) {
                        try errors.append(gpa, .{
                            .tag = .deprecated_and_unsupported,
                            .main_location = tag.name,
                            .node_idx = current_idx,
                        });
                    }
                },
                .end, .end_self => {
                    if (current.kind == .root) {
                        has_syntax_errors = true;
                        try errors.append(gpa, .{
                            .tag = .erroneous_end_tag,
                            .main_location = tag.name,
                            .node_idx = 0,
                        });
                        continue;
                    }

                    const original_current = current;
                    const original_current_idx = current_idx;

                    if (current.isClosed()) {
                        log.debug("current {} is closed, going up to {}", .{
                            current_idx,
                            current.parent_idx,
                        });
                        current_idx = current.parent_idx;
                        current = &nodes.items[current.parent_idx];
                    }

                    const name = tag.name.slice(src);
                    const end_kind = switch (language) {
                        .superhtml => if (std.ascii.eqlIgnoreCase("ctx", name))
                            .ctx
                        else if (std.ascii.eqlIgnoreCase("super", name))
                            .super
                        else if (std.ascii.eqlIgnoreCase("extend", name))
                            .extend
                        else
                            kinds.get(name) orelse .___,
                        .html => kinds.get(name) orelse .___,
                        .xml => .___,
                    };

                    while (true) {
                        if (current.kind == .root) {
                            current = original_current;
                            current_idx = original_current_idx;

                            const is_void = blk: {
                                const k = Element.elements.get(
                                    tag.name.slice(src),
                                ) orelse break :blk false;
                                assert(k.isElement());
                                break :blk k.isVoid() and
                                    original_current.kind.isElement() and
                                    original_current.kind.isVoid();
                            };

                            has_syntax_errors = true;
                            try errors.append(gpa, .{
                                .tag = if (is_void) .void_end_tag else .erroneous_end_tag,
                                .main_location = tag.name,
                                .node_idx = 0,
                            });
                            break;
                        }

                        assert(!current.isClosed());
                        const current_name = blk: {
                            var temp_tok: Tokenizer = .{
                                .language = language,
                                .return_attrs = true,
                            };
                            const tag_src = current.open.slice(src);
                            // all early exit branches are in the case of
                            // malformed HTML and we also expect in all of
                            // those cases that errors were already emitted
                            // by the tokenizer
                            const name_span = temp_tok.getName(tag_src) orelse {
                                current = original_current;
                                current_idx = original_current_idx;
                                break;
                            };
                            break :blk name_span.slice(tag_src);
                        };

                        const same_name = end_kind == current.kind and
                            (end_kind != .___ or std.ascii.eqlIgnoreCase(
                                current_name,
                                tag.name.slice(src),
                            ));

                        if (same_name) {
                            if (std.ascii.eqlIgnoreCase(current_name, "svg")) {
                                svg_lvl -= 1;
                            }
                            if (std.ascii.eqlIgnoreCase(current_name, "math")) {
                                math_lvl -= 1;
                            }
                            current.close = tag.span;
                            var cur = original_current;
                            while (cur != current) {
                                if (!cur.isClosed()) {
                                    const cur_name: Span = blk: {
                                        var temp_tok: Tokenizer = .{
                                            .language = language,
                                            .return_attrs = true,
                                        };
                                        const tag_src = cur.open.slice(src);
                                        const rel_name = temp_tok.getName(tag_src).?;
                                        break :blk .{
                                            .start = rel_name.start + cur.open.start,
                                            .end = rel_name.end + cur.open.start,
                                        };
                                    };
                                    has_syntax_errors = true;
                                    try errors.append(gpa, .{
                                        .tag = .missing_end_tag,
                                        .main_location = cur_name,
                                        .node_idx = current_idx,
                                    });
                                }

                                cur = &nodes.items[cur.parent_idx];
                            }

                            log.debug("----- closing '{s}' cur: {} par: {}", .{
                                tag.name.slice(src),
                                current_idx,
                                current.parent_idx,
                            });

                            break;
                        }

                        current_idx = current.parent_idx;
                        current = &nodes.items[current.parent_idx];
                    }
                },
            },
            .text => |txt| {
                var new: Node = .{
                    .kind = .text,
                    .open = txt,
                    .model = .{
                        .categories = .{
                            .flow = true,
                            .phrasing = true,
                        },
                        .content = .none,
                    },
                };

                switch (current.direction()) {
                    .in => {
                        new.parent_idx = current_idx;
                        if (current.first_child_idx != 0) {
                            debugNodes(nodes.items, src);
                        }
                        std.debug.assert(current.first_child_idx == 0);
                        current_idx = @intCast(nodes.items.len);
                        current.first_child_idx = current_idx;
                    },
                    .after => {
                        new.parent_idx = current.parent_idx;
                        current_idx = @intCast(nodes.items.len);
                        current.next_idx = current_idx;
                    },
                }

                try nodes.append(new);
                current = &nodes.items[current_idx];
            },
            .comment => |c| {
                var new: Node = .{
                    .kind = .comment,
                    .open = c,
                    .model = .{
                        .categories = .all,
                        .content = .none,
                    },
                };

                log.debug("comment => current ({any})", .{current.*});

                switch (current.direction()) {
                    .in => {
                        new.parent_idx = current_idx;
                        std.debug.assert(current.first_child_idx == 0);
                        current_idx = @intCast(nodes.items.len);
                        current.first_child_idx = current_idx;
                    },
                    .after => {
                        new.parent_idx = current.parent_idx;
                        current_idx = @intCast(nodes.items.len);
                        current.next_idx = current_idx;
                    },
                }

                try nodes.append(new);
                current = &nodes.items[current_idx];
            },
            .parse_error => |pe| {
                has_syntax_errors = true;
                log.debug("================= parse error: {any} {}", .{ pe, current_idx });

                // TODO: finalize ast when EOF?
                try errors.append(gpa, .{
                    .tag = .{
                        .token = pe.tag,
                    },
                    .main_location = pe.span,
                    .node_idx = switch (current.direction()) {
                        .in => current_idx,
                        .after => current.parent_idx,
                    },
                });
            },
        }
    }

    // finalize tree
    while (current.kind != .root) {
        if (!current.isClosed()) {
            try errors.append(gpa, .{
                .tag = .missing_end_tag,
                .main_location = current.open,
                .node_idx = current_idx,
            });
        }

        current_idx = current.parent_idx;
        current = &nodes.items[current.parent_idx];
    }

    if (strict and !has_syntax_errors and language == .html) try validateNesting(
        gpa,
        nodes.items,
        &errors,
        src,
        language,
    );

    return .{
        .has_syntax_errors = has_syntax_errors,
        .language = language,
        .nodes = try nodes.toOwnedSlice(),
        .errors = try errors.toOwnedSlice(gpa),
    };
}

pub fn render(ast: Ast, src: []const u8, w: *Writer) !void {
    assert(!ast.has_syntax_errors);

    if (ast.nodes.len < 2) return;

    var indentation: u32 = 0;
    var current = ast.nodes[1];
    var direction: enum { enter, exit } = .enter;
    var last_rbracket: u32 = 0;
    var pre: u32 = 0;
    while (true) {
        const zone_outer = tracy.trace(@src());
        defer zone_outer.end();
        log.debug("looping, ind: {}, dir: {s}", .{
            indentation,
            @tagName(direction),
        });
        switch (direction) {
            .enter => {
                const zone = tracy.trace(@src());
                defer zone.end();
                log.debug("rendering enter ({}): {s} {any}", .{
                    indentation,
                    "",
                    // current.open.slice(src),
                    current,
                });

                const maybe_ws = src[last_rbracket..current.open.start];
                log.debug("maybe_ws = '{s}'", .{maybe_ws});
                if (pre > 0) {
                    try w.writeAll(maybe_ws);
                } else {
                    const vertical = maybe_ws.len > 0;

                    if (vertical) {
                        log.debug("adding a newline", .{});
                        const lines = std.mem.count(u8, maybe_ws, "\n");
                        if (last_rbracket > 0) {
                            if (lines >= 2) {
                                try w.writeAll("\n\n");
                            } else {
                                try w.writeAll("\n");
                            }
                        }

                        for (0..indentation) |_| {
                            try w.writeAll("\t");
                        }
                    }
                }

                const child_is_vertical = if (ast.child(current)) |c|
                    (c.kind == .text or c.open.start - current.open.end > 0)
                else
                    false;
                if (!current.self_closing and
                    current.kind.isElement() and
                    !current.kind.isVoid() and
                    child_is_vertical)
                {
                    indentation += 1;
                }
            },
            .exit => {
                const zone = tracy.trace(@src());
                defer zone.end();
                assert(current.kind != .text);
                assert(!current.kind.isElement() or !current.kind.isVoid());
                assert(!current.self_closing);

                if (current.kind == .root) {
                    try w.writeAll("\n");
                    return;
                }

                log.debug("rendering exit ({}): {s} {any}", .{
                    indentation,
                    current.open.slice(src),
                    current,
                });

                const child_was_vertical = if (ast.child(current)) |c|
                    (c.kind == .text or c.open.start - current.open.end > 0)
                else
                    false;
                if (!current.self_closing and
                    current.kind.isElement() and
                    !current.kind.isVoid() and
                    child_was_vertical)
                {
                    indentation -= 1;
                }

                const open_was_vertical = std.ascii.isWhitespace(src[current.open.end]);

                if (pre > 0) {
                    const maybe_ws = src[last_rbracket..current.close.start];
                    try w.writeAll(maybe_ws);
                } else {
                    if (open_was_vertical) {
                        try w.writeAll("\n");
                        for (0..indentation) |_| {
                            try w.writeAll("\t");
                        }
                    }
                }
            },
        }

        switch (current.kind) {
            .root => switch (direction) {
                .enter => {
                    const zone = tracy.trace(@src());
                    defer zone.end();
                    if (current.first_child_idx == 0) break;
                    current = ast.nodes[current.first_child_idx];
                },
                .exit => break,
            },

            .text => {
                const zone = tracy.trace(@src());
                defer zone.end();
                std.debug.assert(direction == .enter);

                const txt = current.open.slice(src);
                const parent_kind = ast.nodes[current.parent_idx].kind;
                switch (parent_kind) {
                    else => try w.writeAll(txt),
                    .style, .script => {
                        var css_indent = indentation;
                        var it = std.mem.splitScalar(u8, txt, '\n');
                        var first = true;
                        var empty_line = false;
                        while (it.next()) |raw_line| {
                            const line = std.mem.trim(
                                u8,
                                raw_line,
                                &std.ascii.whitespace,
                            );
                            if (line.len == 0) {
                                if (empty_line) continue;
                                empty_line = true;
                                if (!first) for (0..css_indent) |_| try w.print("\t", .{});
                                try w.print("\n", .{});
                                continue;
                            } else empty_line = false;
                            if (std.mem.endsWith(u8, line, "{")) {
                                if (!first) for (0..css_indent) |_| try w.print("\t", .{});
                                try w.print("{s}", .{line});
                                css_indent += 1;
                            } else if (std.mem.eql(u8, line, "}")) {
                                css_indent -|= 1;
                                if (!first) for (0..css_indent) |_| try w.print("\t", .{});
                                try w.print("{s}", .{line});
                            } else {
                                if (!first) for (0..css_indent) |_| try w.print("\t", .{});
                                try w.print("{s}", .{line});
                            }

                            if (it.peek() != null) try w.print("\n", .{});

                            first = false;
                        }
                    },
                }
                last_rbracket = current.open.end;

                if (current.next_idx != 0) {
                    log.debug("text next: {}", .{current.next_idx});
                    current = ast.nodes[current.next_idx];
                } else {
                    current = ast.nodes[current.parent_idx];
                    direction = .exit;
                }
            },

            .comment => {
                const zone = tracy.trace(@src());
                defer zone.end();
                std.debug.assert(direction == .enter);

                try w.writeAll(current.open.slice(src));
                last_rbracket = current.open.end;

                if (current.next_idx != 0) {
                    current = ast.nodes[current.next_idx];
                } else {
                    current = ast.nodes[current.parent_idx];
                    direction = .exit;
                }
            },

            .doctype => {
                const zone = tracy.trace(@src());
                defer zone.end();
                last_rbracket = current.open.end;
                const maybe_name, const maybe_extra = blk: {
                    var tt: Tokenizer = .{ .language = ast.language };
                    const tag = current.open.slice(src);
                    log.debug("doctype tag: {s} {any}", .{ tag, current });
                    const dt = tt.next(tag).?.doctype;
                    const maybe_name: ?[]const u8 = if (dt.name) |name|
                        name.slice(tag)
                    else
                        null;
                    const maybe_extra: ?[]const u8 = if (dt.extra.start > 0)
                        dt.extra.slice(tag)
                    else
                        null;

                    break :blk .{ maybe_name, maybe_extra };
                };

                if (maybe_name) |n| {
                    try w.print("<!DOCTYPE {s}", .{n});
                } else {
                    try w.print("<!DOCTYPE", .{});
                }

                if (maybe_extra) |e| {
                    try w.print(" {s}>", .{e});
                } else {
                    try w.print(">", .{});
                }

                if (current.next_idx != 0) {
                    current = ast.nodes[current.next_idx];
                } else {
                    current = ast.nodes[current.parent_idx];
                    direction = .exit;
                }
            },

            else => switch (direction) {
                .enter => {
                    const zone = tracy.trace(@src());
                    defer zone.end();
                    last_rbracket = current.open.end;

                    var sti = current.startTagIterator(src, ast.language);
                    const name = sti.name_span.slice(src);

                    if (current.kind == .pre) {
                        pre += 1;
                    }

                    try w.print("<{s}", .{name});

                    const vertical = std.ascii.isWhitespace(
                        // <div arst="arst" >
                        //                 ^
                        src[current.open.end - 2],
                    ) and blk: {
                        // Don't do vertical alignment if we don't have
                        // at least 2 attributes.
                        var temp_sti = sti;
                        _ = temp_sti.next(src) orelse break :blk false;
                        _ = temp_sti.next(src) orelse break :blk false;
                        break :blk true;
                    };

                    log.debug("element <{s}> vertical = {}", .{ name, vertical });

                    // if (std.mem.eql(u8, name, "path")) @breakpoint();

                    const child_is_vertical = if (ast.child(current)) |c|
                        (c.kind == .text or c.open.start - current.open.end > 0)
                    else
                        false;
                    const attr_indent = indentation - @intFromBool(!current.kind.isVoid() and !current.self_closing and child_is_vertical);
                    const extra = blk: {
                        if (current.kind == .doctype) break :blk 1;
                        assert(current.kind.isElement());
                        break :blk name.len + 2;
                    };

                    var first = true;
                    while (sti.next(src)) |attr| {
                        if (vertical) {
                            if (first) {
                                first = false;
                                try w.print(" ", .{});
                            } else {
                                try w.print("\n", .{});
                                for (0..attr_indent) |_| {
                                    try w.print("\t", .{});
                                }
                                for (0..extra) |_| {
                                    try w.print(" ", .{});
                                }
                            }
                        } else {
                            try w.print(" ", .{});
                        }
                        try w.print("{s}", .{
                            attr.name.slice(src),
                        });
                        if (attr.value) |val| {
                            const q = switch (val.quote) {
                                .none => "",
                                .single => "'",
                                .double => "\"",
                            };
                            try w.print("={s}{s}{s}", .{
                                q,
                                val.span.slice(src),
                                q,
                            });
                        }
                    }
                    if (vertical) {
                        try w.print("\n", .{});
                        for (0..attr_indent) |_| {
                            try w.print("\t", .{});
                        }
                    }

                    if (current.self_closing) {
                        try w.print("/", .{});
                    }
                    try w.print(">", .{});

                    assert(current.kind.isElement());

                    if (current.self_closing or current.kind.isVoid()) {
                        if (current.next_idx != 0) {
                            current = ast.nodes[current.next_idx];
                        } else {
                            direction = .exit;
                            current = ast.nodes[current.parent_idx];
                        }
                    } else {
                        if (current.first_child_idx == 0) {
                            direction = .exit;
                        } else {
                            current = ast.nodes[current.first_child_idx];
                        }
                    }
                },
                .exit => {
                    const zone = tracy.trace(@src());
                    defer zone.end();
                    std.debug.assert(!current.kind.isVoid());
                    std.debug.assert(!current.self_closing);
                    last_rbracket = current.close.end;
                    if (current.close.start != 0) {
                        const name = blk: {
                            var tt: Tokenizer = .{
                                .language = ast.language,
                                .return_attrs = true,
                            };
                            const tag = current.open.slice(src);
                            log.debug("retokenize {s}\n", .{tag});
                            break :blk tt.getName(tag).?.slice(tag);
                        };

                        if (std.ascii.eqlIgnoreCase("pre", name)) {
                            pre -= 1;
                        }
                        try w.print("</{s}>", .{name});
                    }
                    if (current.next_idx != 0) {
                        direction = .enter;
                        current = ast.nodes[current.next_idx];
                    } else {
                        current = ast.nodes[current.parent_idx];
                    }
                },
            },
        }
    }
}

// Only executed if strict is enabled
pub fn validateNesting(
    gpa: Allocator,
    nodes: []const Node,
    errors: *std.ArrayListUnmanaged(Error),
    src: []const u8,
    language: Language,
) !void {
    if (language != .html) return;

    var node_idx: u32 = 0;
    while (node_idx < nodes.len) {
        log.debug("validating {}", .{node_idx});
        const n = nodes[node_idx];
        switch (n.kind) {
            .extend,
            .super,
            // html
            .area,
            .base,
            .br,
            .col,
            .embed,
            .hr,
            .img,
            .input,
            .link,
            .meta,
            .source,
            .track,
            .wbr,
            // end void
            .svg,
            .math,
            .___,
            .comment,
            .text,
            .doctype,
            => {
                var next = n;
                node_idx = while (true) {
                    if (next.next_idx != 0) break next.next_idx;
                    if (next.parent_idx == 0) return;
                    next = nodes[next.parent_idx];
                };
                continue;
            },
            else => {},
        }

        defer node_idx += 1;
        const element: Element = elements.get(n.kind);
        try element.validateContent(
            gpa,
            nodes,
            errors,
            src,
            node_idx,
        );
    }
}

pub const Completion = struct {
    label: []const u8,
    desc: []const u8,
    value: ?[]const u8 = null,
};

pub fn completions(
    ast: Ast,
    arena: Allocator,
    src: []const u8,
    offset: u32,
) ![]const Completion {
    for (ast.errors) |err| {
        if (err.tag != .token or offset != err.main_location.start) continue;

        var idx = offset;
        while (idx > 0) {
            idx -= 1;
            switch (src[idx]) {
                '<', '/' => break,
                ' ', '\n', '\t', '\r' => continue,
                else => return &.{},
            }
        } else return &.{};

        log.debug("completions before check", .{});
        const parent_idx = err.node_idx;
        const parent_node = ast.nodes[parent_idx];
        if ((!parent_node.kind.isElement() and
            parent_node.kind != .root) or
            parent_node.kind == .svg or
            parent_node.kind == .math) return &.{};

        log.debug("completions past check", .{});

        const e = Element.all.get(parent_node.kind);
        log.debug("===== completions content: {t}", .{parent_node.kind});
        return e.completions(arena, ast, src, parent_idx, offset, .content);
    }

    const node_idx = ast.findNodeTagsIdx(offset);
    log.debug("===== completions: attrs node: {}", .{node_idx});
    if (node_idx == 0) return &.{};

    const n = ast.nodes[node_idx];
    log.debug("===== node: {any}", .{n});
    if (!n.kind.isElement()) return &.{};
    if (offset >= n.open.end) return &.{};

    const e = Element.all.get(n.kind);
    return e.completions(arena, ast, src, node_idx, offset, .attrs);
}

pub fn description(ast: *const Ast, src: []const u8, offset: u32) ?[]const u8 {
    const node_idx = ast.findNodeTagsIdx(offset);
    if (node_idx == 0) return null;
    const n = ast.nodes[node_idx];

    if (!n.kind.isElement() or n.kind == .___) return null;

    if (n.open.end > offset) {
        var it = n.startTagIterator(src, ast.language);
        if (offset < it.name_span.end and offset >= it.name_span.start) {
            // element name
            const e = Element.all.get(n.kind);
            return e.desc;
        }

        while (it.next(src)) |attr| {
            const end = if (attr.value) |v| v.span.end else attr.name.end;
            if (offset < end and offset >= attr.name.start) {
                const name = attr.name.slice(src);
                const attr_model = Attribute.element_attrs.get(n.kind).get(name) orelse
                    Attribute.global.get(name) orelse return null;

                return attr_model.desc;
            }
        }

        return null;
    }

    // end tag
    const e = Element.all.get(n.kind);
    return e.desc;
}

/// Returns the node index whose start or end tag overlaps the provided offset.
/// Returns zero if the offset is outside of a start/end tag.
pub fn findNodeTagsIdx(ast: *const Ast, offset: u32) u32 {
    if (ast.nodes.len < 2) return 0;
    var cur_idx: u32 = 1;
    while (cur_idx != 0) {
        const n = ast.nodes[cur_idx];
        if (n.open.start <= offset and n.open.end > offset) {
            break;
        }
        if (n.close.end != 0 and n.close.start <= offset and n.close.end > offset) {
            break;
        }

        if (n.open.end <= offset and n.close.start > offset) {
            cur_idx = n.first_child_idx;
        } else {
            cur_idx = n.next_idx;
        }
    }

    return cur_idx;
}

// pub fn transparentAncestorRule(
//     nodes: []const Node,
//     src: []const u8,
//     language: Language,
//     parent_idx: u32,
// ) ?struct {
//     tag: tags.RuleEnum,
//     span: Span,
//     idx: u32,
// } {
//     var ancestor_idx = parent_idx;
//     while (ancestor_idx != 0) {
//         const ancestor = nodes[ancestor_idx];
//         var ptt: Tokenizer = .{
//             .idx = ancestor.open.start,
//             .return_attrs = true,
//             .language = language,
//         };

//         const ancestor_span = ptt.next(
//             src[0..ancestor.open.end],
//         ).?.tag_name;
//         const ancestor_name = ancestor_span.slice(src);

//         const ancestor_rule = tags.all.get(
//             ancestor_name,
//         ) orelse return null;

//         if (ancestor_rule == .transparent) {
//             ancestor_idx = ancestor.parent_idx;
//             continue;
//         }

//         return .{
//             .tag = ancestor_rule,
//             .span = ancestor_span,
//             .idx = ancestor_idx,
//         };
//     }
//     return null;
// }

fn at(ast: Ast, idx: u32) ?Node {
    if (idx == 0) return null;
    return ast.nodes[idx];
}

pub fn parent(ast: Ast, n: Node) ?Node {
    if (n.parent_idx == 0) return null;
    return ast.nodes[n.parent_idx];
}

pub fn nextSibling(ast: Ast, n: Node) ?Node {
    return ast.at(n.next_idx);
}

pub fn lastChild(ast: Ast, n: Node) ?Node {
    _ = ast;
    _ = n;
    @panic("TODO");
}

pub fn child(ast: Ast, n: Node) ?Node {
    return ast.at(n.first_child_idx);
}

pub fn formatter(ast: Ast, src: []const u8) Formatter {
    return .{ .ast = ast, .src = src };
}
const Formatter = struct {
    ast: Ast,
    src: []const u8,

    pub fn format(f: Formatter, w: *Writer) !void {
        try f.ast.render(f.src, w);
    }
};

pub fn debug(ast: Ast, src: []const u8) void {
    var c = ast.cursor(0);
    var last_depth: u32 = 0;
    std.debug.print(" \n node count: {}\n", .{ast.nodes.len});
    while (c.next()) |n| {
        if (c.dir == .out) {
            std.debug.print("\n", .{});
            while (last_depth > c.depth) : (last_depth -= 1) {
                for (0..last_depth - 2) |_| std.debug.print("    ", .{});
                std.debug.print(")", .{});
                if (last_depth - c.depth > 1) {
                    std.debug.print("\n", .{});
                }
            }
            last_depth = c.depth;
            continue;
        }
        std.debug.print("\n", .{});
        for (0..c.depth - 1) |_| std.debug.print("    ", .{});
        const range = n.open.range(src);
        std.debug.print("({s} #{} @{} [{}, {}] - [{}, {}]", .{
            @tagName(n.kind),
            c.idx,
            c.depth,
            range.start.row,
            range.start.col,
            range.end.row,
            range.end.col,
        });
        if (n.first_child_idx == 0) {
            std.debug.print(")", .{});
        }
        last_depth = c.depth;
    }
    std.debug.print("\n", .{});
    while (last_depth > 1) : (last_depth -= 1) {
        for (0..last_depth - 2) |_| std.debug.print("    ", .{});
        std.debug.print(")\n", .{});
    }
}

fn debugNodes(nodes: []const Node, src: []const u8) void {
    const ast = Ast{
        .language = .html,
        .nodes = nodes,
        .errors = &.{},
        .has_syntax_errors = false,
    };
    ast.debug(src);
}

test "basics" {
    const case = "<html><head></head><body><div><br></div></body></html>\n";

    const ast = try Ast.init(std.testing.allocator, case, .html, true);
    defer ast.deinit(std.testing.allocator);

    try std.testing.expectFmt(case, "{f}", .{ast.formatter(case)});
}

test "basics - attributes" {
    const case = "<html><head></head><body>" ++
        \\<div id="foo" class="bar">
    ++ "<link></div></body></html>\n";

    const ast = try Ast.init(std.testing.allocator, case, .html, true);
    defer ast.deinit(std.testing.allocator);

    try std.testing.expectFmt(case, "{f}", .{ast.formatter(case)});
}

test "newlines" {
    const case =
        \\<!DOCTYPE html>
        \\<html>
        \\  <head></head>
        \\  <body>
        \\    <div><link></div>
        \\  </body>
        \\</html>
        \\
    ;
    const expected = comptime std.fmt.comptimePrint(
        \\<!DOCTYPE html>
        \\<html>
        \\{0c}<head></head>
        \\{0c}<body>
        \\{0c}{0c}<div><link></div>
        \\{0c}</body>
        \\</html>
        \\
    , .{'\t'});
    const ast = try Ast.init(std.testing.allocator, case, .html, true);
    defer ast.deinit(std.testing.allocator);

    try std.testing.expectFmt(expected, "{f}", .{ast.formatter(case)});
}

test "tight tags inner indentation" {
    const case = comptime std.fmt.comptimePrint(
        \\<!DOCTYPE html>
        \\<html>
        \\{0c}<head></head>
        \\{0c}<body>
        \\{0c}{0c}<div><nav><ul>
        \\{0c}{0c}{0c}<li></li>
        \\{0c}{0c}</ul></nav></div>
        \\{0c}</body>
        \\</html>
        \\
    , .{'\t'});
    const ast = try Ast.init(std.testing.allocator, case, .html, true);
    defer ast.deinit(std.testing.allocator);

    try std.testing.expectFmt(case, "{f}", .{ast.formatter(case)});
}

test "bad html" {
    // TODO: handle ast.errors.len != 0
    if (true) return error.SkipZigTest;

    const case =
        \\<html>
        \\<body>
        \\<p $class=" arst>Foo</p>
        \\
        \\</html>
    ;
    const ast = try Ast.init(std.testing.allocator, case, .html, true);
    defer ast.deinit(std.testing.allocator);

    try std.testing.expectFmt(case, "{f}", .{ast.formatter(case)});
}

test "formatting - simple" {
    const case =
        \\<!DOCTYPE html>   <html>
        \\<head></head>               <body> <div><link></div>
        \\  </body>               </html>
    ;
    const expected = comptime std.fmt.comptimePrint(
        \\<!DOCTYPE html>
        \\<html>
        \\{0c}<head></head>
        \\{0c}<body>
        \\{0c}{0c}<div><link></div>
        \\{0c}</body>
        \\</html>
        \\
    , .{'\t'});
    const ast = try Ast.init(std.testing.allocator, case, .html, true);
    defer ast.deinit(std.testing.allocator);

    try std.testing.expectFmt(expected, "{f}", .{ast.formatter(case)});
}

test "formatting - attributes" {
    const case =
        \\<html>
        \\  <body>
        \\    <div>
        \\      <link>
        \\      <div id="foo" class="bar" style="tarstarstarstarstarstarstarst"
        \\      ></div>
        \\    </div>
        \\  </body>
        \\</html>
    ;
    const expected = comptime std.fmt.comptimePrint(
        \\<html>
        \\{0c}<body>
        \\{0c}{0c}<div>
        \\{0c}{0c}{0c}<link>
        \\{0c}{0c}{0c}<div id="foo"
        \\{0c}{0c}{0c}     class="bar"
        \\{0c}{0c}{0c}     style="tarstarstarstarstarstarstarst"
        \\{0c}{0c}{0c}></div>
        \\{0c}{0c}</div>
        \\{0c}</body>
        \\</html>
        \\
    , .{'\t'});
    const ast = try Ast.init(std.testing.allocator, case, .html, true);
    defer ast.deinit(std.testing.allocator);

    try std.testing.expectFmt(expected, "{f}", .{ast.formatter(case)});
}

test "pre" {
    const case =
        \\<b>    </b>
        \\<pre>      </pre>
    ;
    const expected =
        \\<b>
        \\</b>
        \\<pre>      </pre>
        \\
    ;

    const ast = try Ast.init(std.testing.allocator, case, .html, true);
    defer ast.deinit(std.testing.allocator);

    try std.testing.expectFmt(expected, "{f}", .{ast.formatter(case)});
}

test "pre text" {
    const case =
        \\<b> banana</b>
        \\<pre>   banana   </pre>
    ;
    const expected = comptime std.fmt.comptimePrint(
        \\<b>
        \\{0c}banana
        \\</b>
        \\<pre>   banana   </pre>
        \\
    , .{'\t'});

    const ast = try Ast.init(std.testing.allocator, case, .html, true);
    defer ast.deinit(std.testing.allocator);

    try std.testing.expectFmt(expected, "{f}", .{ast.formatter(case)});
}

test "what" {
    const case =
        \\<html>
        \\  <body>
        \\    <a href="#" foo="bar" banana="peach">
        \\      <b><link>
        \\      </b>
        \\      <b></b>
        \\      <pre></pre>
        \\    </a>
        \\  </body>
        \\</html>
        \\
        \\
        \\<a href="#">foo </a>
    ;

    const expected = comptime std.fmt.comptimePrint(
        \\<html>
        \\{0c}<body>
        \\{0c}{0c}<a href="#" foo="bar" banana="peach">
        \\{0c}{0c}{0c}<b><link></b>
        \\{0c}{0c}{0c}<b></b>
        \\{0c}{0c}{0c}<pre></pre>
        \\{0c}{0c}</a>
        \\{0c}</body>
        \\</html>
        \\
        \\<a href="#">foo</a>
        \\
    , .{'\t'});

    const ast = try Ast.init(std.testing.allocator, case, .html, true);
    defer ast.deinit(std.testing.allocator);

    try std.testing.expectFmt(expected, "{f}", .{ast.formatter(case)});
}

test "spans" {
    const case =
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\  <head>
        \\    <meta charset="UTF-8">
        \\  </head>
        \\  <body>
        \\    <span>Hello</span><span>World</span>
        \\    <br>
        \\    <span>Hello</span> <span>World</span>
        \\  </body>
        \\</html>
    ;

    const expected = comptime std.fmt.comptimePrint(
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\{0c}<head>
        \\{0c}{0c}<meta charset="UTF-8">
        \\{0c}</head>
        \\{0c}<body>
        \\{0c}{0c}<span>Hello</span><span>World</span>
        \\{0c}{0c}<br>
        \\{0c}{0c}<span>Hello</span>
        \\{0c}{0c}<span>World</span>
        \\{0c}</body>
        \\</html>
        \\
    , .{'\t'});

    const ast = try Ast.init(std.testing.allocator, case, .html, true);
    defer ast.deinit(std.testing.allocator);

    try std.testing.expectFmt(expected, "{f}", .{ast.formatter(case)});
}
test "arrow span" {
    const case =
        \\<a href="$if.permalink()">← <span var="$if.title"></span></a>
    ;
    const expected = comptime std.fmt.comptimePrint(
        \\<a href="$if.permalink()">←
        \\{c}<span var="$if.title"></span></a>
        \\
    , .{'\t'});

    const ast = try Ast.init(std.testing.allocator, case, .html, true);
    defer ast.deinit(std.testing.allocator);

    try std.testing.expectFmt(expected, "{f}", .{ast.formatter(case)});
}

test "self-closing tag complex example" {
    const case =
        \\extend template="base.html"/>
        \\
        \\<div id="content">
        \\<svg viewBox="0 0 24 24">
        \\<path d="M14.4,6H20V16H13L12.6,14H7V21H5V4H14L14.4,6M14,14H16V12H18V10H16V8H14V10L13,8V6H11V8H9V6H7V8H9V10H7V12H9V10H11V12H13V10L14,12V14M11,10V8H13V10H11M14,10H16V12H14V10Z" />
        \\</svg>
        \\</div>
    ;
    const expected = comptime std.fmt.comptimePrint(
        \\extend template="base.html"/>
        \\
        \\<div id="content">
        \\{0c}<svg viewBox="0 0 24 24">
        \\{0c}{0c}<path d="M14.4,6H20V16H13L12.6,14H7V21H5V4H14L14.4,6M14,14H16V12H18V10H16V8H14V10L13,8V6H11V8H9V6H7V8H9V10H7V12H9V10H11V12H13V10L14,12V14M11,10V8H13V10H11M14,10H16V12H14V10Z"/>
        \\{0c}</svg>
        \\</div>
        \\
    , .{'\t'});
    const ast = try Ast.init(std.testing.allocator, case, .html, true);
    defer ast.deinit(std.testing.allocator);

    try std.testing.expectFmt(expected, "{f}", .{ast.formatter(case)});
}

test "respect empty lines" {
    const case =
        \\
        \\<div> a
        \\</div>
        \\
        \\<div></div>
        \\
        \\<div></div>
        \\<div></div>
        \\
        \\
        \\<div></div>
        \\
        \\
        \\
        \\<div></div>
        \\<div> a
        \\</div>
        \\
        \\
        \\
        \\<div> a
        \\</div>
    ;
    const expected = comptime std.fmt.comptimePrint(
        \\<div>
        \\{0c}a
        \\</div>
        \\
        \\<div></div>
        \\
        \\<div></div>
        \\<div></div>
        \\
        \\<div></div>
        \\
        \\<div></div>
        \\<div>
        \\{0c}a
        \\</div>
        \\
        \\<div>
        \\{0c}a
        \\</div>
        \\
    , .{'\t'});
    const ast = try Ast.init(std.testing.allocator, case, .html, true);
    defer ast.deinit(std.testing.allocator);

    try std.testing.expectFmt(expected, "{f}", .{ast.formatter(case)});
}

pub const Cursor = struct {
    ast: Ast,
    idx: u32,
    depth: u32 = 0,
    dir: enum { in, next, out } = .in,

    pub fn reset(c: *Cursor, n: Node) void {
        _ = c;
        _ = n;
        @panic("TODO");
    }

    pub fn node(c: Cursor) Node {
        return c.ast.nodes[c.idx];
    }

    pub fn next(c: *Cursor) ?Node {
        if (c.idx == 0 and c.dir == .out) return null;

        var n = c.node();
        if (c.ast.child(n)) |ch| {
            c.idx = n.first_child_idx;
            c.dir = .in;
            c.depth += 1;
            return ch;
        }

        if (c.ast.nextSibling(n)) |s| {
            c.idx = n.next_idx;
            c.dir = .next;
            return s;
        }

        return while (c.ast.parent(n)) |p| {
            n = p;
            c.depth -= 1;
            const uncle = c.ast.nextSibling(p) orelse continue;
            c.idx = p.next_idx;
            c.dir = .out;
            break uncle;
        } else blk: {
            c.idx = 0;
            c.dir = .out;
            break :blk null;
        };
    }
};
