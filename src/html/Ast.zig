const Ast = @This();

const std = @import("std");
const tracy = @import("tracy");
const root = @import("../root.zig");
const Language = root.Language;
const Span = root.Span;
const Tokenizer = @import("Tokenizer.zig");

const log = std.log.scoped(.@"html/ast");

const TagNameMap = std.StaticStringMapWithEql(
    void,
    std.static_string_map.eqlAsciiIgnoreCase,
);

const rcdata_names = TagNameMap.initComptime(.{
    .{ "title", {} },
    .{ "textarea", {} },
});

const rawtext_names = TagNameMap.initComptime(.{
    .{ "style", {} },
    .{ "xmp", {} },
    .{ "iframe", {} },
    .{ "noembed", {} },
    .{ "noframes", {} },
    .{ "noscript", {} },
});

const unsupported_names = TagNameMap.initComptime(.{
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
    kind: Kind,
    /// Span covering start_tag, diamond brackets included
    open: Span,
    /// Span covering end_tag, diamond brackets included
    /// Unset status is represented by .start = 0 and .end = 0
    /// not set for doctype, element_void and element_self_closing
    close: Span = .{ .start = 0, .end = 0 },

    parent_idx: u32 = 0,
    first_child_idx: u32 = 0,
    next_idx: u32 = 0,

    pub const Kind = enum {
        root,
        doctype,
        element,
        element_void,
        element_self_closing,
        comment,
        text,
    };

    pub fn isClosed(n: Node) bool {
        return switch (n.kind) {
            .root => unreachable,
            .element => n.close.start != 0,
            .doctype, .element_void, .element_self_closing, .text, .comment => true,
        };
    }

    pub const Direction = enum { in, after };
    pub fn direction(n: Node) Direction {
        switch (n.kind) {
            .root => {
                std.debug.assert(n.first_child_idx == 0);
                return .in;
            },
            .element => {
                if (n.close.start == 0) {
                    return .in;
                }
                return .after;
            },
            .doctype, .element_void, .element_self_closing, .text, .comment => return .after,
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

    pub fn debug(n: Node, src: []const u8) void {
        std.debug.print("{s}", .{n.open.slice(src)});
    }
};

pub const Error = struct {
    tag: union(enum) {
        token: Tokenizer.TokenError,
        ast: enum {
            html_elements_cant_self_close,
            missing_end_tag,
            erroneous_end_tag,
            duplicate_attribute_name,
            deprecated_and_unsupported,
        },
    },
    main_location: Span,
};

language: Language,
nodes: []const Node,
errors: []const Error,

pub fn cursor(ast: Ast, idx: u32) Cursor {
    return .{ .ast = ast, .idx = idx, .dir = .in };
}

pub fn printErrors(
    ast: Ast,
    src: []const u8,
    path: ?[]const u8,
    w: anytype,
) !void {
    for (ast.errors) |err| {
        const range = err.main_location.range(src);
        try w.print("{s}:{}:{}: {s}\n", .{
            path orelse "<stdin>",
            range.start.row,
            range.start.col,
            switch (err.tag) {
                inline else => |t| @tagName(t),
            },
        });
    }
}

pub fn deinit(ast: Ast, gpa: std.mem.Allocator) void {
    gpa.free(ast.nodes);
    gpa.free(ast.errors);
}

pub fn init(
    gpa: std.mem.Allocator,
    src: []const u8,
    language: Language,
) error{OutOfMemory}!Ast {
    if (src.len > std.math.maxInt(u32)) @panic("too long");

    var nodes = std.ArrayList(Node).init(gpa);
    errdefer nodes.deinit();

    var errors = std.ArrayList(Error).init(gpa);
    errdefer errors.deinit();

    var seen_attrs = std.StringHashMap(void).init(gpa);
    defer seen_attrs.deinit();

    try nodes.append(.{
        .kind = .root,
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
    });

    var tokenizer: Tokenizer = .{ .language = language };

    var current: *Node = &nodes.items[0];
    var current_idx: u32 = 0;
    var svg_lvl: u32 = 0;
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
                    const node_kind: Node.Kind = switch (tag.kind) {
                        else => unreachable,
                        .start_self => blk: {
                            if (svg_lvl == 0 and language != .xml) {
                                try errors.append(.{
                                    .tag = .{
                                        .ast = .html_elements_cant_self_close,
                                    },
                                    .main_location = tag.name,
                                });
                            }
                            break :blk .element_self_closing;
                        },
                        .start => if (tag.isVoid(src, language))
                            .element_void
                        else
                            .element,
                    };

                    const name = tag.name.slice(src);
                    if (std.ascii.eqlIgnoreCase(tag.name.slice(src), "svg")) {
                        svg_lvl += 1;
                    }

                    var new: Node = .{ .kind = node_kind, .open = tag.span };
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

                    if (std.ascii.eqlIgnoreCase("script", name)) {
                        tokenizer.gotoScriptData();
                        // } else if (rcdata_names.has(name)) {
                        //     tokenizer.gotoRcData(name);
                    } else if (rawtext_names.has(name)) {
                        tokenizer.gotoRawText(name);
                    } else if (unsupported_names.has(name)) {
                        try errors.append(.{
                            .tag = .{
                                .ast = .deprecated_and_unsupported,
                            },
                            .main_location = tag.name,
                        });
                    }

                    // check for duplicated attrs
                    {
                        seen_attrs.clearRetainingCapacity();
                        var tt: Tokenizer = .{
                            .language = language,
                            .idx = tag.span.start,
                            .return_attrs = true,
                        };

                        while (tt.next(src[0..tag.span.end])) |maybe_attr| {
                            switch (maybe_attr) {
                                else => {
                                    log.debug("found unexpected: '{s}' {any}", .{
                                        @tagName(maybe_attr),
                                        maybe_attr,
                                    });
                                    unreachable;
                                },
                                .tag_name => {},
                                .tag => break,
                                .parse_error => {},
                                .attr => |attr| {
                                    const attr_name = attr.name.slice(src);
                                    log.debug("attr_name = '{s}'", .{attr_name});
                                    const gop = try seen_attrs.getOrPut(attr_name);
                                    if (gop.found_existing) {
                                        try errors.append(.{
                                            .tag = .{
                                                .ast = .duplicate_attribute_name,
                                            },
                                            .main_location = .{
                                                .start = attr.name.start,
                                                .end = attr.name.end,
                                            },
                                        });
                                    }
                                },
                            }
                        }
                    }
                },
                .end, .end_self => {
                    if (current.kind == .root) {
                        try errors.append(.{
                            .tag = .{
                                .ast = .erroneous_end_tag,
                            },
                            .main_location = tag.name,
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

                    while (true) {
                        if (current.kind == .root) {
                            current = original_current;
                            current_idx = original_current_idx;
                            try errors.append(.{
                                .tag = .{ .ast = .erroneous_end_tag },
                                .main_location = tag.name,
                            });
                            break;
                        }

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

                        std.debug.assert(!current.isClosed());
                        if (std.ascii.eqlIgnoreCase(
                            current_name,
                            tag.name.slice(src),
                        )) {
                            if (std.ascii.eqlIgnoreCase(current_name, "svg")) {
                                svg_lvl -= 1;
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
                                    try errors.append(.{
                                        .tag = .{ .ast = .missing_end_tag },
                                        .main_location = cur_name,
                                    });
                                }

                                cur = &nodes.items[cur.parent_idx];
                            }

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
                log.debug("parse error: {any}", .{pe});

                // TODO: finalize ast when EOF?
                try errors.append(.{
                    .tag = .{
                        .token = pe.tag,
                    },
                    .main_location = pe.span,
                });
            },
        }
    }

    // finalize tree
    while (current.kind != .root) {
        if (!current.isClosed()) {
            try errors.append(.{
                .tag = .{ .ast = .missing_end_tag },
                .main_location = current.open,
            });
        }

        current = &nodes.items[current.parent_idx];
    }

    return .{
        .language = language,
        .nodes = try nodes.toOwnedSlice(),
        .errors = try errors.toOwnedSlice(),
    };
}

pub fn render(ast: Ast, src: []const u8, w: anytype) !void {
    std.debug.assert(ast.errors.len == 0);

    var indentation: u32 = 0;
    var current = ast.nodes[0];
    var direction: enum { enter, exit } = .enter;
    var last_rbracket: u32 = 0;
    // var last_open_was_vertical = false;
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
                        try w.writeAll("\n");
                        for (0..indentation) |_| {
                            try w.writeAll("  ");
                        }
                    }
                }

                switch (current.kind) {
                    else => {},
                    .element => indentation += 1,
                }
            },
            .exit => {
                const zone = tracy.trace(@src());
                defer zone.end();
                std.debug.assert(current.kind != .text);
                std.debug.assert(current.kind != .element_void);
                std.debug.assert(current.kind != .element_self_closing);
                if (current.kind == .root) return;

                log.debug("rendering exit ({}): {s} {any}", .{
                    indentation,
                    current.open.slice(src),
                    current,
                });

                switch (current.kind) {
                    else => {},
                    .element => indentation -= 1,
                }

                const open_was_vertical = std.ascii.isWhitespace(src[current.open.end]);

                if (pre > 0) {
                    const maybe_ws = src[last_rbracket..current.close.start];
                    try w.writeAll(maybe_ws);
                } else {
                    if (open_was_vertical) {
                        try w.writeAll("\n");
                        for (0..indentation) |_| {
                            try w.writeAll("  ");
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
                log.debug("text = '{s}', txt.len = {} src start = '{s}'", .{
                    txt,
                    txt.len,
                    src[0..10],
                });
                try w.writeAll(txt);
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

            .element, .element_void, .element_self_closing => switch (direction) {
                .enter => {
                    const zone = tracy.trace(@src());
                    defer zone.end();
                    last_rbracket = current.open.end;
                    var tt: Tokenizer = .{
                        .idx = current.open.start,
                        .return_attrs = true,
                        .language = ast.language,
                    };

                    log.debug("retokenizing: '{s}'", .{current.open.slice(src)});
                    const name = tt.next(src[0..current.open.end]).?.tag_name.slice(src);
                    log.debug("tag name: '{s}'", .{name});
                    if (std.ascii.eqlIgnoreCase("pre", name)) {
                        pre += 1;
                    }

                    try w.print("<{s}", .{name});

                    const vertical = std.ascii.isWhitespace(
                        // <div arst="arst" >
                        //                 ^
                        src[current.open.end - 2],
                    );

                    // if (std.mem.eql(u8, name, "path")) @breakpoint();

                    const extra: u32 = switch (current.kind) {
                        .doctype,
                        .element_void,
                        .element_self_closing,
                        => 1,
                        else => 0,
                    };

                    while (tt.next(src[0..current.open.end])) |maybe_attr| {
                        log.debug("tt: {s}", .{@tagName(maybe_attr)});
                        log.debug("tt: {any}", .{maybe_attr});
                        switch (maybe_attr) {
                            else => {
                                log.debug(
                                    "got unexpected {any}",
                                    .{maybe_attr},
                                );
                                unreachable;
                            },
                            .tag_name => {
                                log.debug(
                                    "got unexpected tag_name '{s}'",
                                    .{maybe_attr.tag_name.slice(src)},
                                );
                                unreachable;
                            },
                            .tag => break,
                            .attr => |attr| {
                                if (vertical) {
                                    try w.print("\n", .{});
                                    for (0..indentation + extra) |_| {
                                        try w.print("  ", .{});
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
                            },
                        }
                    }
                    if (vertical) {
                        try w.print("\n", .{});
                        for (0..indentation + extra -| 1) |_| {
                            try w.print("  ", .{});
                        }
                    }

                    if (current.kind == .element_self_closing) {
                        try w.print("/", .{});
                    }
                    try w.print(">", .{});

                    switch (current.kind) {
                        else => unreachable,
                        .element => {
                            if (current.first_child_idx == 0) {
                                direction = .exit;
                            } else {
                                current = ast.nodes[current.first_child_idx];
                            }
                        },
                        .element_void,
                        .element_self_closing,
                        => {
                            if (current.next_idx != 0) {
                                current = ast.nodes[current.next_idx];
                            } else {
                                direction = .exit;
                                current = ast.nodes[current.parent_idx];
                            }
                        },
                    }
                },
                .exit => {
                    const zone = tracy.trace(@src());
                    defer zone.end();
                    std.debug.assert(current.kind != .element_void);
                    std.debug.assert(current.kind != .element_self_closing);
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

    pub fn format(f: Formatter, out_stream: anytype) !void {
        try f.ast.render(f.src, out_stream);
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
    const ast = Ast{ .nodes = nodes, .errors = &.{}, .language = .html };
    ast.debug(src);
}

test "basics" {
    const case = "<html><head></head><body><div><link></div></body></html>";

    const ast = try Ast.init(std.testing.allocator, case, .html);
    defer ast.deinit(std.testing.allocator);

    try std.testing.expectFmt(case, "{f}", .{ast.formatter(case)});
}

test "basics - attributes" {
    const case = "<html><head></head><body>" ++
        \\<div id="foo" class="bar">
    ++ "<link></div></body></html>";

    const ast = try Ast.init(std.testing.allocator, case, .html);
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
    ;
    const ast = try Ast.init(std.testing.allocator, case, .html);
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
    const ast = try Ast.init(std.testing.allocator, case);
    defer ast.deinit(std.testing.allocator);

    try std.testing.expectFmt(case, "{f}", .{ast.formatter(case)});
}

test "formatting - simple" {
    const case =
        \\<!DOCTYPE html>   <html>
        \\<head></head>               <body> <div><link></div>
        \\  </body>               </html>
    ;
    const expected =
        \\<!DOCTYPE html>
        \\<html>
        \\  <head></head>
        \\  <body>
        \\    <div><link></div>
        \\  </body>
        \\</html>
    ;
    const ast = try Ast.init(std.testing.allocator, case, .html);
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
    const expected =
        \\<html>
        \\  <body>
        \\    <div>
        \\      <link>
        \\      <div
        \\        id="foo"
        \\        class="bar"
        \\        style="tarstarstarstarstarstarstarst"
        \\      ></div>
        \\    </div>
        \\  </body>
        \\</html>
    ;
    const ast = try Ast.init(std.testing.allocator, case, .html);
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
    ;

    const ast = try Ast.init(std.testing.allocator, case, .html);
    defer ast.deinit(std.testing.allocator);

    try std.testing.expectFmt(expected, "{f}", .{ast.formatter(case)});
}

test "pre text" {
    const case =
        \\<b> banana</b>
        \\<pre>   banana   </pre>
    ;
    const expected =
        \\<b>
        \\  banana
        \\</b>
        \\<pre>   banana   </pre>
    ;

    const ast = try Ast.init(std.testing.allocator, case, .html);
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

    const expected =
        \\<html>
        \\  <body>
        \\    <a href="#" foo="bar" banana="peach">
        \\      <b><link></b>
        \\      <b></b>
        \\      <pre></pre>
        \\    </a>
        \\  </body>
        \\</html>
        \\<a href="#">foo</a>
    ;

    const ast = try Ast.init(std.testing.allocator, case, .html);
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

    const expected =
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\  <head>
        \\    <meta charset="UTF-8">
        \\  </head>
        \\  <body>
        \\    <span>Hello</span><span>World</span>
        \\    <br>
        \\    <span>Hello</span>
        \\    <span>World</span>
        \\  </body>
        \\</html>
    ;

    const ast = try Ast.init(std.testing.allocator, case, .html);
    defer ast.deinit(std.testing.allocator);

    try std.testing.expectFmt(expected, "{f}", .{ast.formatter(case)});
}
test "arrow span" {
    const case =
        \\<a href="$if.permalink()">← <span var="$if.title"></span></a>
    ;
    const expected =
        \\<a href="$if.permalink()">←
        \\  <span var="$if.title"></span></a>
    ;

    const ast = try Ast.init(std.testing.allocator, case, .html);
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
    const expected =
        \\extend template="base.html"/>
        \\<div id="content">
        \\  <svg viewBox="0 0 24 24">
        \\    <path d="M14.4,6H20V16H13L12.6,14H7V21H5V4H14L14.4,6M14,14H16V12H18V10H16V8H14V10L13,8V6H11V8H9V6H7V8H9V10H7V12H9V10H11V12H13V10L14,12V14M11,10V8H13V10H11M14,10H16V12H14V10Z"/>
        \\  </svg>
        \\</div>
    ;
    const ast = try Ast.init(std.testing.allocator, case, .html);
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
