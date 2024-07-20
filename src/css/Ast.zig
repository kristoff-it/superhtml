const std = @import("std");
const Tokenizer = @import("Tokenizer.zig");
const root = @import("../root.zig");
const Span = root.Span;

const Ast = @This();

pub const Rule = struct {
    type: union(enum) {
        style: Style,
        at: At,
    },
    next: ?u32,

    pub const Style = struct {
        selectors: Span,
        declarations: Span,
        multiline_decl: bool,

        pub const Selector = union(enum) {
            simple: Simple,

            pub const Simple = struct {
                element_name: ?ElementName,
                specifiers: Span,

                pub const ElementName = union(enum) {
                    name: Span,
                    all,
                };

                pub const Specifier = union(enum) {
                    hash: Span,
                    class: Span,
                    attrib, // TODO
                    pseudo, // TODO
                };

                pub fn render(self: Simple, ast: Ast, src: []const u8, out_stream: anytype) !void {
                    if (self.element_name) |element_name| {
                        switch (element_name) {
                            .name => |name| _ = try out_stream.write(name.slice(src)),
                            .all => _ = try out_stream.write("*"),
                        }
                    }

                    for (ast.specifiers[self.specifiers.start..self.specifiers.end]) |specifier| {
                        switch (specifier) {
                            .hash => |hash| try out_stream.print("#{s}", .{hash.slice(src)}),
                            .class => |class| try out_stream.print(".{s}", .{class.slice(src)}),
                            .attrib => @panic("TODO"),
                            .pseudo => @panic("TODO"),
                        }
                    }
                }
            };

            pub fn render(self: Selector, ast: Ast, src: []const u8, out_stream: anytype) !void {
                switch (self) {
                    inline else => |sel| try sel.render(ast, src, out_stream),
                }
            }
        };

        pub const Declaration = struct {
            property: Span,
            value: Span,

            pub fn render(self: Declaration, src: []const u8, out_stream: anytype) !void {
                _ = try out_stream.write(self.property.slice(src));
                _ = try out_stream.write(": ");
                _ = try out_stream.write(self.value.slice(src));
            }
        };

        pub fn render(self: Style, ast: Ast, src: []const u8, out_stream: anytype, depth: usize) !void {
            for (0..depth) |_| _ = try out_stream.write("    ");
            for (ast.selectors[self.selectors.start..self.selectors.end], 0..) |selector, i| {
                if (i != 0) {
                    _ = try out_stream.write(", ");
                }

                try selector.render(ast, src, out_stream);
            }

            _ = try out_stream.write(" {");

            if (self.multiline_decl) {
                _ = try out_stream.write("\n");

                for (ast.declarations[self.declarations.start..self.declarations.end]) |declaration| {
                    for (0..depth + 1) |_| _ = try out_stream.write("    ");
                    try declaration.render(src, out_stream);
                    _ = try out_stream.write(";\n");
                }

                for (0..depth) |_| _ = try out_stream.write("    ");
            } else {
                _ = try out_stream.write(" ");
                for (ast.declarations[self.declarations.start..self.declarations.end], 0..) |declaration, i| {
                    if (i != 0) _ = try out_stream.write("; ");
                    try declaration.render(src, out_stream);
                }
                _ = try out_stream.write(" ");
            }

            _ = try out_stream.write("}");
        }
    };

    pub const At = struct {};

    pub fn render(self: Rule, ast: Ast, src: []const u8, out_stream: anytype, depth: usize) !void {
        switch (self.type) {
            .style => |style| try style.render(ast, src, out_stream, depth),
            .at => @panic("TODO"),
        }
    }
};

first_rule: u32,
rules: []const Rule,
selectors: []const Rule.Style.Selector,
declarations: []const Rule.Style.Declaration,
specifiers: []const Rule.Style.Selector.Simple.Specifier,

const State = struct {
    allocator: std.mem.Allocator,
    tokenizer: Tokenizer,
    src: []const u8,
    reconsumed: ?Tokenizer.Token,
    rules: std.ArrayListUnmanaged(Rule),
    selectors: std.ArrayListUnmanaged(Rule.Style.Selector),
    declarations: std.ArrayListUnmanaged(Rule.Style.Declaration),
    specifiers: std.ArrayListUnmanaged(Rule.Style.Selector.Simple.Specifier),

    fn consume(self: *State) ?Tokenizer.Token {
        if (self.reconsumed) |tok| {
            self.reconsumed = null;
            return tok;
        }

        return self.tokenizer.next(self.src);
    }

    fn reconsume(self: *State, token: Tokenizer.Token) void {
        std.debug.assert(self.reconsumed == null);

        self.reconsumed = token;
    }

    fn peek(self: *State) ?Tokenizer.Token {
        const token = self.consume();
        if (token) |tok| self.reconsume(tok);

        return token;
    }
};

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

pub fn formatter(self: Ast, src: []const u8) Formatter {
    return .{
        .ast = self,
        .src = src,
    };
}

pub fn render(self: Ast, src: []const u8, out_stream: anytype) !void {
    var first = true;
    var rule = self.rules[self.first_rule];
    while (true) {
        if (!first) {
            _ = try out_stream.write("\n\n");
        }
        first = false;

        try rule.render(self, src, out_stream, 0);

        rule = self.rules[rule.next orelse break];
    }
}

pub fn init(allocator: std.mem.Allocator, src: []const u8) error{OutOfMemory}!Ast {
    if (src.len > std.math.maxInt(u32)) @panic("too long");

    var state: State = .{
        .allocator = allocator,
        .tokenizer = .{},
        .src = src,
        .reconsumed = null,
        .rules = .{},
        .selectors = .{},
        .declarations = .{},
        .specifiers = .{},
    };

    const first_rule = try parseRules(&state);

    return .{
        .first_rule = first_rule,
        .rules = try state.rules.toOwnedSlice(allocator),
        .selectors = try state.selectors.toOwnedSlice(allocator),
        .declarations = try state.declarations.toOwnedSlice(allocator),
        .specifiers = try state.specifiers.toOwnedSlice(allocator),
    };
}

fn parseRules(s: *State) !u32 {
    var last_rule: ?u32 = null;
    var first_rule: ?u32 = null;

    while (true) {
        if (s.consume()) |token| {
            switch (token) {
                .cdo => @panic("TODO"),
                .cdc => @panic("TODO"),
                .at_keyword => @panic("TODO"),
                else => {
                    s.reconsume(token);

                    const rule = .{
                        .type = .{
                            .style = try parseStyleRule(s),
                        },
                        .next = null,
                    };

                    try s.rules.append(s.allocator, rule);

                    if (first_rule == null) first_rule = @intCast(s.rules.items.len - 1);

                    if (last_rule) |idx| {
                        s.rules.items[idx].next = @intCast(s.rules.items.len - 1);
                    }

                    last_rule = @intCast(s.rules.items.len - 1);
                },
            }
        } else break;
    }

    return first_rule orelse @panic("TODO");
}

fn parseStyleRule(s: *State) !Rule.Style {
    try s.selectors.append(s.allocator, try parseSelector(s));
    const sel_start = s.selectors.items.len - 1;

    while (true) {
        if (s.consume()) |token| {
            if (token == .comma) {
                if (s.peek() != null and s.peek().? == .open_curly) break;

                try s.selectors.append(s.allocator, try parseSelector(s));
            } else {
                s.reconsume(token);
                break;
            }
        } else {
            break;
        }
    }

    if (s.consume()) |token| {
        switch (token) {
            .open_curly => {},
            else => @panic("TODO"),
        }
    } else {
        @panic("TODO");
    }

    try s.declarations.append(s.allocator, parseDeclaration(s));
    const decl_start = s.declarations.items.len - 1;

    var multiline_decl = false;

    while (true) {
        if (s.consume()) |token| {
            if (token == .semicolon) {
                if (s.peek() != null and s.peek().? == .close_curly) {
                    multiline_decl = true;
                    break;
                }

                try s.declarations.append(s.allocator, parseDeclaration(s));
            } else {
                s.reconsume(token);
                break;
            }
        } else {
            break;
        }
    }

    if (s.consume()) |token| {
        switch (token) {
            .close_curly => {},
            else => @panic("TODO"),
        }
    } else {
        @panic("TODO");
    }

    return .{
        .selectors = .{ .start = @intCast(sel_start), .end = @intCast(s.selectors.items.len) },
        .declarations = .{ .start = @intCast(decl_start), .end = @intCast(s.declarations.items.len) },
        .multiline_decl = multiline_decl,
    };
}

fn parseSelector(s: *State) !Rule.Style.Selector {
    // TODO: Support other selectors

    return .{
        .simple = try parseSimpleSelector(s),
    };
}

fn parseDeclaration(s: *State) Rule.Style.Declaration {
    const property = if (s.consume()) |token| switch (token) {
        .ident => |ident| ident,
        else => @panic("TODO"),
    } else @panic("TODO");

    if (s.consume()) |token| {
        switch (token) {
            .colon => {},
            else => @panic("TODO"),
        }
    } else {
        @panic("TODO");
    }

    return .{
        .property = property,
        .value = parseDeclarationValue(s),
    };
}

fn parseSimpleSelector(s: *State) !Rule.Style.Selector.Simple {
    var element_name: ?Rule.Style.Selector.Simple.ElementName = null;

    const spec_start = s.specifiers.items.len;

    if (s.consume()) |token| {
        switch (token) {
            .ident => |ident| element_name = .{ .name = ident },
            .delim => |delim| switch (s.src[delim]) {
                '*' => element_name = .all,
                else => s.reconsume(token),
            },
            else => s.reconsume(token),
        }
    }

    while (true) {
        if (s.consume()) |token| {
            switch (token) {
                .hash => |hash| {
                    var span = hash;
                    span.start += 1;
                    try s.specifiers.append(s.allocator, .{ .hash = span });
                },
                .delim => |delim| switch (s.src[delim]) {
                    '.' => {
                        const name_token = s.consume() orelse @panic("TODO");
                        if (name_token != .ident) @panic("TODO");
                        const name = name_token.ident;

                        try s.specifiers.append(s.allocator, .{ .class = name });
                    },
                    else => @panic("TODO"),
                },
                .open_square => @panic("TODO"),
                .colon => @panic("TODO"),
                else => {
                    s.reconsume(token);
                    break;
                },
            }
        } else {
            break;
        }
    }

    const spec_end = s.specifiers.items.len;

    if (element_name == null and spec_start == spec_end) {
        @panic("TODO");
    }

    return .{
        .element_name = element_name,
        .specifiers = .{ .start = @intCast(spec_start), .end = @intCast(spec_end) },
    };
}

fn parseDeclarationValue(s: *State) Span {
    var start: ?u32 = null;
    var end: u32 = undefined;

    while (s.peek()) |token| {
        switch (token) {
            .semicolon, .close_curly => break,
            else => {
                std.debug.assert(s.consume() != null);
                if (start == null) {
                    start = token.span().start;
                }
                end = token.span().end;
            },
        }
    }

    if (start == null) {
        @panic("TODO");
    } else {
        return .{ .start = start.?, .end = end };
    }
}

pub fn deinit(self: Ast, allocator: std.mem.Allocator) void {
    allocator.free(self.rules);
    allocator.free(self.selectors);
    allocator.free(self.declarations);
    allocator.free(self.specifiers);
}

test "simple stylesheet" {
    const src =
        \\   p {
        \\color
        \\ : red
        \\   ;}
    ;

    const expected =
        \\p {
        \\    color: red;
        \\}
    ;

    const ast = try Ast.init(std.testing.allocator, src);
    defer ast.deinit(std.testing.allocator);

    try std.testing.expectFmt(expected, "{s}", .{ast.formatter(src)});
}

test "full example" {
    const src =
        \\div.foo, #bar {
        \\    display: block;
        \\    padding: 4px 2px;
        \\}
        \\
        \\* { color: #fff }
    ;

    const ast = try Ast.init(std.testing.allocator, src);
    defer ast.deinit(std.testing.allocator);

    try std.testing.expectFmt(src, "{s}", .{ast.formatter(src)});
}
