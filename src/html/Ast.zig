const Ast = @This();

const std = @import("std");
const Tokenizer = @import("Tokenizer.zig");

const log = std.log.scoped(.ast);

const Node = struct {
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
    open: Tokenizer.Span,
    /// Span covering end_tag, diamond brackets included
    /// Unset status is represented by .start = 0 and .end = 0
    /// not set for doctype, element_void and elment_self_closing
    close: Tokenizer.Span = .{ .start = 0, .end = 0 },

    parent_idx: u32 = 0,
    first_child_idx: u32 = 0,
    next_idx: u32 = 0,

    pub fn isClosed(n: Node) bool {
        return switch (n.tag) {
            .root, .comment => unreachable,
            .element => n.close.start != 0,
            .doctype, .element_void, .element_self_closing, .text => true,
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
            .comment => {
                if (n.close.start == 0) {
                    return .in;
                }
                return .after;
            },
            .doctype, .element_void, .element_self_closing, .text => return .after,
        }
    }
};

const Error = struct {
    tag: enum {
        missing_end_tag,
        erroneous_end_tag,
        eof_in_tag,
        missing_attribute_value,
        unexpected_character_in_attribute_name,
    },
    // TODO: this is optonal only temporarily because
    //       the tokenizer doesn't return error locations
    //       as we actually implement good error reporting
    //       this type should stop being optional
    span: ?Tokenizer.Span = null,
};

nodes: []const Node,
errors: []const Error,

pub fn deinit(ast: Ast, gpa: std.mem.Allocator) void {
    gpa.free(ast.nodes);
    gpa.free(ast.errors);
}

pub fn init(src: []const u8, gpa: std.mem.Allocator) !Ast {
    if (src.len > std.math.maxInt(u32)) @panic("too long");

    var tokenizer: Tokenizer = .{};
    var nodes = std.ArrayList(Node).init(gpa);
    var errors = std.ArrayList(Error).init(gpa);

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

    const root = &nodes.items[0];

    var current: *Node = root;
    var current_idx: u32 = 0;

    while (tokenizer.next(src)) |t| {
        log.debug("cur_idx: {} tok: {any}", .{ current_idx, t });
        std.debug.print("cur_idx: {} tok: {any}\n", .{ current_idx, t });
        switch (t) {
            inline else => |_, tag| @panic("TODO: implement " ++ @tagName(tag) ++ " in Ast.init()"),
            .attr => {},
            .doctype => |dt| {
                var new: Node = .{
                    .tag = .doctype,
                    .open = .{ .start = dt.lbracket, .end = 0 },
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
            .doctype_rbracket => |idx| {
                std.debug.assert(current.open.end == 0);
                current.open.end = idx;
            },
            .start_tag => |st| {
                var new: Node = .{
                    .tag = if (st.isVoid(src)) .element_void else .element,
                    .open = .{
                        .start = st.lbracket,
                        .end = 0,
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
            .start_tag_rbracket => |idx| {
                std.debug.assert(current.open.end == 0);
                current.open.end = idx;
            },
            .end_tag => |et| {
                if (current.tag == .root) {
                    try errors.append(.{
                        .tag = .erroneous_end_tag,
                        .span = et.name,
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
                            .tag = .erroneous_end_tag,
                            .span = et.name,
                        });
                        break;
                    }

                    const current_name = blk: {
                        var temp_tok: Tokenizer = .{};
                        const tag = current.open.slice(src);
                        break :blk temp_tok.next(tag).?.start_tag.name.slice(tag);
                    };

                    log.debug("matching cn: {s} tag: {s}", .{
                        current_name,
                        et.name.slice(src),
                    });

                    std.debug.assert(!current.isClosed());
                    if (std.ascii.eqlIgnoreCase(current_name, et.name.slice(src))) {
                        current.close = .{
                            .start = et.lbracket,
                            .end = 0,
                        };
                        break;
                    }

                    current_idx = current.parent_idx;
                    current = &nodes.items[current.parent_idx];
                }
            },
            .end_tag_rbracket => |idx| {
                log.debug("end_rbracket: {any}", .{current});
                // std.debug.assert(current.close.end == 0);
                current.close.end = idx;
            },
            .start_tag_self_closed => |stsc| {
                var new: Node = .{
                    .tag = .element_self_closing,
                    .open = stsc,
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
                std.debug.print("AST text node: '{s}'\n", .{new.open.slice(src)});
                current = &nodes.items[current_idx];
            },
            .parse_error => |pe| {
                log.debug("parse error: {any}", .{pe});

                switch (pe) {
                    inline else => |tag| @panic("TODO: implement " ++ @tagName(tag) ++ "Ast.init.parse_error"),
                    .eof_in_tag => {
                        try errors.append(.{
                            .tag = .eof_in_tag,
                        });
                        // TODO: finalize ast
                    },
                    .missing_attribute_value => {
                        try errors.append(.{
                            .tag = .missing_attribute_value,
                        });
                    },
                    .unexpected_character_in_attribute_name => {
                        try errors.append(.{
                            .tag = .unexpected_character_in_attribute_name,
                        });
                    },
                }
            },
        }
    }

    return .{
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
                    current.open.slice(src),
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
                std.debug.print("rendering exit ({}): {s} {any}\n", .{
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

            .doctype => {
                last_rbracket = current.open.end;
                const maybe_name_raw: ?[]const u8 = blk: {
                    var tt: Tokenizer = .{};
                    const tag = current.open.slice(src);
                    log.debug("doctype tag: {s} {any}", .{ tag, current });
                    break :blk if (tt.next(tag).?.doctype.name_raw) |name| name.slice(tag) else null;
                };

                if (maybe_name_raw) |n| {
                    try w.print("<!DOCTYPE {s}>", .{n});
                } else {
                    try w.print("<!DOCTYPE>", .{});
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
                    var tt: Tokenizer = .{};
                    const tag_src = current.open.slice(src);
                    log.debug("retokenize: {s}", .{tag_src});
                    const name = tt.next(tag_src).?.start_tag.name.slice(tag_src);

                    if (std.ascii.eqlIgnoreCase("pre", name)) {
                        pre += 1;
                    }

                    try w.print("<{s}", .{name});

                    const vertical = std.ascii.isWhitespace(tag_src[tag_src.len - 2]);

                    while (tt.next(tag_src)) |maybe_attr| {
                        switch (maybe_attr) {
                            else => unreachable,
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
                                    attr.name_raw.slice(tag_src),
                                });
                                if (attr.value_raw) |val| {
                                    const q = switch (val.quote) {
                                        .none => "",
                                        .single => "'",
                                        .double => "\"",
                                    };
                                    try w.print("={s}{s}{s}", .{
                                        q,
                                        val.span.slice(tag_src),
                                        q,
                                    });
                                }
                            },
                            .start_tag_rbracket => {
                                if (vertical) {
                                    try w.print("\n", .{});
                                    for (0..indentation - 1) |_| {
                                        try w.print("  ", .{});
                                    }
                                }
                                try w.print(">", .{});
                                break;
                            },
                        }
                    }

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
                            var tt: Tokenizer = .{};
                            const tag = current.close.slice(src);
                            log.debug("retokenize {s}\n", .{tag});
                            break :blk tt.next(tag).?.end_tag.name.slice(tag);
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

    const ast = try Ast.init(case, std.testing.allocator);
    defer ast.deinit(std.testing.allocator);

    try std.testing.expectFmt(case, "{s}", .{ast.formatter(case)});
}

test "basics - attributes" {
    const case = "<html><head></head><body>" ++
        \\<div id="foo" class="bar">
    ++ "<link></div></body></html>";

    const ast = try Ast.init(case, std.testing.allocator);
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
    const ast = try Ast.init(case, std.testing.allocator);
    defer ast.deinit(std.testing.allocator);

    try std.testing.expectFmt(case, "{s}", .{ast.formatter(case)});
}

test "bad html" {
    const case =
        \\<html>
        \\<body>
        \\<p $class=" arst>Foo</p>
        \\
        \\</html>    
    ;
    const ast = try Ast.init(case, std.testing.allocator);
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
    const ast = try Ast.init(case, std.testing.allocator);
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
    const ast = try Ast.init(case, std.testing.allocator);
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

    const ast = try Ast.init(case, std.testing.allocator);
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

    const ast = try Ast.init(case, std.testing.allocator);
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

    const ast = try Ast.init(case, std.testing.allocator);
    defer ast.deinit(std.testing.allocator);

    try std.testing.expectFmt(case, "{s}", .{ast.formatter(case)});
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

    const ast = try Ast.init(case, std.testing.allocator);
    defer ast.deinit(std.testing.allocator);

    try std.testing.expectFmt(expected, "{s}", .{ast.formatter(case)});
}
