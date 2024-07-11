const Ast = @This();

const std = @import("std");
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
    .{ "hgroup", {} },
    .{ "isindex", {} },
    .{ "listing", {} },
    .{ "nextid", {} },
    .{ "noembed", {} },
    .{ "plaintext", {} },
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
    tag: enum {
        root,
        doctype,
        element,
        element_void,
        element_self_closing,
        comment,
        text,
    },

    /// Span covering start_tag, diamond brackets included
    open: Span,
    /// Span covering end_tag, diamond brackets included
    /// Unset status is represented by .start = 0 and .end = 0
    /// not set for doctype, element_void and elment_self_closing
    close: Span = .{ .start = 0, .end = 0 },

    parent_idx: u32 = 0,
    first_child_idx: u32 = 0,
    next_idx: u32 = 0,

    pub fn isClosed(n: Node) bool {
        return switch (n.tag) {
            .root => unreachable,
            .element => n.close.start != 0,
            .doctype, .element_void, .element_self_closing, .text, .comment => true,
        };
    }

    pub const Direction = enum { in, after };
    pub fn direction(n: Node) Direction {
        switch (n.tag) {
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

    pub fn startTag(n: Node, src: []const u8, language: Language) TagIterator {
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

pub fn printErrors(ast: Ast, src: []const u8, path: ?[]const u8) void {
    for (ast.errors) |err| {
        const range = err.main_location.range(src);
        std.debug.print("{s}:{}:{}: {s}\n", .{
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
        .tag = .root,
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

    while (tokenizer.next(src)) |t| {
        log.debug("cur_idx: {} cur_tag: {s} tok: {any}", .{
            current_idx,
            @tagName(current.tag),
            t,
        });
        switch (t) {
            .tag_name, .attr => unreachable,
            .doctype => |dt| {
                var new: Node = .{
                    .tag = .doctype,
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
                    var new: Node = .{
                        .tag = if (tag.isVoid(src, language)) .element_void else .element,
                        .open = tag.span,
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

                    const name = tag.name.slice(src);
                    if (std.ascii.eqlIgnoreCase("script", name)) {
                        tokenizer.gotoScriptData();
                    } else if (rcdata_names.has(name)) {
                        tokenizer.gotoRcData(name);
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
                    if (current.tag == .root) {
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
                        current_idx = current.parent_idx;
                        current = &nodes.items[current.parent_idx];
                    }

                    while (true) {
                        if (current.tag == .root) {
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
                            // all early exit brances are in the case of
                            // malformed HTML and we also expect in all of
                            // those cases that errors were already emitted
                            // by the tokenizer
                            const maybe_name = temp_tok.next(tag_src) orelse break;

                            switch (maybe_name) {
                                .tag_name => |n| break :blk n.slice(tag_src),
                                else => break,
                            }
                        };

                        log.debug("matching cn: {s} tag: {s}", .{
                            current_name,
                            tag.name.slice(src),
                        });

                        std.debug.assert(!current.isClosed());
                        if (std.ascii.eqlIgnoreCase(
                            current_name,
                            tag.name.slice(src),
                        )) {
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
                                        const rel_name = temp_tok.next(tag_src).?.tag_name;
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
                    .tag = .text,
                    .open = txt,
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
            .comment => |c| {
                var new: Node = .{
                    .tag = .comment,
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
    while (current.tag != .root) {
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
        switch (direction) {
            .enter => {
                log.debug("rendering enter ({}): {s} {any}", .{
                    indentation,
                    "",
                    // current.open.slice(src),
                    current,
                });
                const maybe_ws = src[last_rbracket..current.open.start];
                if (pre > 0) {
                    try w.writeAll(maybe_ws);
                } else {
                    const vertical = maybe_ws.len > 0;

                    if (vertical) {
                        try w.writeAll("\n");
                        for (0..indentation) |_| {
                            try w.writeAll("  ");
                        }
                    }
                    switch (current.tag) {
                        else => {},
                        .element => indentation += 1,
                    }
                }
            },
            .exit => {
                std.debug.assert(current.tag != .text);
                std.debug.assert(current.tag != .element_void);
                std.debug.assert(current.tag != .element_self_closing);
                if (current.tag == .root) return;

                log.debug("rendering exit ({}): {s} {any}", .{
                    indentation,
                    current.open.slice(src),
                    current,
                });

                switch (current.tag) {
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

        switch (current.tag) {
            inline else => |tag| @panic("TODO: implement " ++ @tagName(tag) ++ " in Ast.render()"),
            .root => switch (direction) {
                .enter => {
                    if (current.first_child_idx == 0) break;
                    current = ast.nodes[current.first_child_idx];
                },
                .exit => break,
            },

            .text => {
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

            .comment => {
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

            .element, .element_void => switch (direction) {
                .enter => {
                    last_rbracket = current.open.end;
                    var tt: Tokenizer = .{
                        .idx = current.open.start,
                        .return_attrs = true,
                        .language = ast.language,
                    };

                    log.debug("retokenizing: '{s}'", .{current.open.slice(src)});
                    const name = tt.next(src[0..current.open.end]).?.tag_name.slice(src);
                    if (std.ascii.eqlIgnoreCase("pre", name)) {
                        pre += 1;
                    }

                    try w.print("<{s}", .{name});

                    const vertical = std.ascii.isWhitespace(
                        // <div arst="arst" >
                        //                 ^
                        src[current.open.end - 2],
                    );

                    while (tt.next(src[0..current.open.end])) |maybe_attr| {
                        log.debug("tt: {s}", .{@tagName(maybe_attr)});
                        log.debug("tt: {any}", .{maybe_attr});
                        switch (maybe_attr) {
                            else => unreachable,
                            .tag => break,
                            .attr => |attr| {
                                if (vertical) {
                                    try w.print("\n", .{});
                                    for (0..indentation) |_| {
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
                        for (0..indentation - 1) |_| {
                            try w.print("  ", .{});
                        }
                    }
                    try w.print(">", .{});

                    switch (current.tag) {
                        else => unreachable,
                        .element => {
                            if (current.first_child_idx == 0) {
                                direction = .exit;
                            } else {
                                current = ast.nodes[current.first_child_idx];
                            }
                        },
                        .element_void => {
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
                    std.debug.assert(current.tag != .element_void);
                    last_rbracket = current.close.end;
                    if (current.close.start != 0) {
                        const name = blk: {
                            var tt: Tokenizer = .{
                                .language = ast.language,
                                .return_attrs = true,
                            };
                            const tag = current.close.slice(src);
                            log.debug("retokenize {s}\n", .{tag});
                            break :blk tt.next(tag).?.tag_name.slice(tag);
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

    pub fn format(
        f: Formatter,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        out_stream: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try f.ast.render(f.src, out_stream);
    }
};

test "basics" {
    const case = "<html><head></head><body><div><link></div></body></html>";

    const ast = try Ast.init(std.testing.allocator, case, .html);
    defer ast.deinit(std.testing.allocator);

    try std.testing.expectFmt(case, "{s}", .{ast.formatter(case)});
}

test "basics - attributes" {
    const case = "<html><head></head><body>" ++
        \\<div id="foo" class="bar">
    ++ "<link></div></body></html>";

    const ast = try Ast.init(std.testing.allocator, case, .html);
    defer ast.deinit(std.testing.allocator);

    try std.testing.expectFmt(case, "{s}", .{ast.formatter(case)});
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

    try std.testing.expectFmt(case, "{s}", .{ast.formatter(case)});
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

    try std.testing.expectFmt(case, "{s}", .{ast.formatter(case)});
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

    try std.testing.expectFmt(expected, "{s}", .{ast.formatter(case)});
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

    try std.testing.expectFmt(expected, "{s}", .{ast.formatter(case)});
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

    try std.testing.expectFmt(expected, "{s}", .{ast.formatter(case)});
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

    try std.testing.expectFmt(expected, "{s}", .{ast.formatter(case)});
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

    try std.testing.expectFmt(expected, "{s}", .{ast.formatter(case)});
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

    try std.testing.expectFmt(expected, "{s}", .{ast.formatter(case)});
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
