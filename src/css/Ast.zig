const std = @import("std");
const Tokenizer = @import("Tokenizer.zig");
const root = @import("../root.zig");
const Span = root.Span;

const Ast = @This();

pub const Rule = union(enum) {
    style: Style,
    at: At,

    pub const Style = struct {
        selectors: []const Selector,
        declarations: []const Declaration,
        multiline_decl: bool,

        pub const Selector = union(enum) {
            simple: Simple,

            pub const Simple = struct {
                element_name: ?ElementName,
                specifiers: []const Specifier,

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

                pub fn deinit(self: Simple, allocator: std.mem.Allocator) void {
                    allocator.free(self.specifiers);
                }

                pub fn render(self: Simple, src: []const u8, out_stream: anytype) !void {
                    if (self.element_name) |element_name| {
                        switch (element_name) {
                            .name => |name| _ = try out_stream.write(name.slice(src)),
                            .all => _ = try out_stream.write("*"),
                        }
                    }

                    for (self.specifiers) |specifier| {
                        switch (specifier) {
                            .hash => |hash| try out_stream.print("#{s}", .{hash.slice(src)}),
                            .class => |class| try out_stream.print(".{s}", .{class.slice(src)}),
                            .attrib => @panic("TODO"),
                            .pseudo => @panic("TODO"),
                        }
                    }
                }
            };

            pub fn deinit(self: Selector, allocator: std.mem.Allocator) void {
                switch (self) {
                    inline else => |sel| sel.deinit(allocator),
                }
            }

            pub fn render(self: Selector, src: []const u8, out_stream: anytype) !void {
                switch (self) {
                    inline else => |sel| try sel.render(src, out_stream),
                }
            }
        };

        pub const Declaration = struct {
            property: Span,
            value: []const Expression,

            pub const Expression = union(enum) {
                keyword: Span,
                rgb3: Rgb3,
                rgb6: Rgb6,
                dimension: Dimension,

                pub const Rgb3 = struct {
                    r: u4,
                    g: u4,
                    b: u4,
                };

                pub const Rgb6 = struct {
                    r: u8,
                    g: u8,
                    b: u8,
                };

                pub const Dimension = struct {
                    number: f32,
                    unit: Unit,

                    pub const Unit = enum {
                        px,
                    };
                };

                pub fn render(self: Expression, src: []const u8, out_stream: anytype) !void {
                    switch (self) {
                        .keyword => |keyword| {
                            _ = try out_stream.write(keyword.slice(src));
                        },
                        .rgb3 => |rgb3| {
                            try out_stream.print("#{x:0>1}{x:0>1}{x:0>1}", .{ rgb3.r, rgb3.g, rgb3.b });
                        },
                        .rgb6 => |rgb6| {
                            try out_stream.print("#{x:0>2}{x:0>2}{x:0>2}", .{ rgb6.r, rgb6.g, rgb6.b });
                        },
                        .dimension => |dimension| {
                            try out_stream.print("{d}{s}", .{ dimension.number, @tagName(dimension.unit) });
                        },
                    }
                }
            };

            pub fn deinit(self: Declaration, allocator: std.mem.Allocator) void {
                allocator.free(self.value);
            }

            pub fn render(self: Declaration, src: []const u8, out_stream: anytype) !void {
                _ = try out_stream.write(self.property.slice(src));
                _ = try out_stream.write(":");
                for (self.value) |expression| {
                    _ = try out_stream.write(" ");
                    try expression.render(src, out_stream);
                }
            }
        };

        pub fn deinit(self: Style, allocator: std.mem.Allocator) void {
            for (self.selectors) |selector| {
                selector.deinit(allocator);
            }

            for (self.declarations) |declaration| {
                declaration.deinit(allocator);
            }

            allocator.free(self.selectors);
            allocator.free(self.declarations);
        }

        pub fn render(self: Style, src: []const u8, out_stream: anytype, depth: usize) !void {
            for (0..depth) |_| _ = try out_stream.write("    ");
            for (self.selectors, 0..) |selector, i| {
                if (i != 0) {
                    _ = try out_stream.write(", ");
                }

                try selector.render(src, out_stream);
            }

            _ = try out_stream.write(" {");

            if (self.multiline_decl) {
                _ = try out_stream.write("\n");

                for (self.declarations) |declaration| {
                    for (0..depth + 1) |_| _ = try out_stream.write("    ");
                    try declaration.render(src, out_stream);
                    _ = try out_stream.write(";\n");
                }

                for (0..depth) |_| _ = try out_stream.write("    ");
            } else {
                _ = try out_stream.write(" ");
                for (self.declarations, 0..) |declaration, i| {
                    if (i != 0) _ = try out_stream.write("; ");
                    try declaration.render(src, out_stream);
                }
                _ = try out_stream.write(" ");
            }

            _ = try out_stream.write("}");
        }
    };

    pub const At = struct {};

    pub fn deinit(self: Rule, allocator: std.mem.Allocator) void {
        switch (self) {
            .style => |style| style.deinit(allocator),
            .at => @panic("TODO"),
        }
    }

    pub fn render(self: Rule, src: []const u8, out_stream: anytype, depth: usize) !void {
        switch (self) {
            .style => |style| try style.render(src, out_stream, depth),
            .at => @panic("TODO"),
        }
    }
};

rules: []const Rule,

const State = struct {
    allocator: std.mem.Allocator,
    tokenizer: Tokenizer,
    src: []const u8,
    reconsumed: ?Tokenizer.Token,

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
    for (self.rules, 0..) |rule, i| {
        if (i != 0) {
            _ = try out_stream.write("\n\n");
        }

        try rule.render(src, out_stream, 0);
    }
}

pub fn init(allocator: std.mem.Allocator, src: []const u8) error{OutOfMemory}!Ast {
    if (src.len > std.math.maxInt(u32)) @panic("too long");

    var state: State = .{
        .allocator = allocator,
        .tokenizer = .{},
        .src = src,
        .reconsumed = null,
    };

    return .{
        .rules = try parseRules(&state),
    };
}

fn parseRules(s: *State) ![]const Rule {
    var rules = std.ArrayList(Rule).init(s.allocator);
    defer rules.deinit();

    while (true) {
        if (s.consume()) |token| {
            switch (token) {
                .cdo => @panic("TODO"),
                .cdc => @panic("TODO"),
                .at_keyword => @panic("TODO"),
                else => {
                    s.reconsume(token);

                    const rule = .{
                        .style = try parseStyleRule(s),
                    };

                    try rules.append(rule);
                },
            }
        } else break;
    }

    return try rules.toOwnedSlice();
}

fn parseStyleRule(s: *State) !Rule.Style {
    var selectors = std.ArrayList(Rule.Style.Selector).init(s.allocator);
    defer selectors.deinit();

    var declarations = std.ArrayList(Rule.Style.Declaration).init(s.allocator);
    defer declarations.deinit();

    try selectors.append(try parseSelector(s));

    while (true) {
        if (s.consume()) |token| {
            if (token == .comma) {
                if (s.peek() != null and s.peek().? == .open_curly) break;

                try selectors.append(try parseSelector(s));
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

    try declarations.append(try parseDeclaration(s));

    var multiline_decl = false;

    while (true) {
        if (s.consume()) |token| {
            if (token == .semicolon) {
                if (s.peek() != null and s.peek().? == .close_curly) {
                    multiline_decl = true;
                    break;
                }

                try declarations.append(try parseDeclaration(s));
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
        .selectors = try selectors.toOwnedSlice(),
        .declarations = try declarations.toOwnedSlice(),
        .multiline_decl = multiline_decl,
    };
}

fn parseSelector(s: *State) !Rule.Style.Selector {
    // TODO: Support other selectors

    return .{
        .simple = try parseSimpleSelector(s),
    };
}

fn parseDeclaration(s: *State) !Rule.Style.Declaration {
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
        .value = try parseDeclarationValue(s),
    };
}

fn parseSimpleSelector(s: *State) !Rule.Style.Selector.Simple {
    var element_name: ?Rule.Style.Selector.Simple.ElementName = null;

    var specifiers = std.ArrayList(Rule.Style.Selector.Simple.Specifier).init(s.allocator);
    defer specifiers.deinit();

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
                    try specifiers.append(.{ .hash = span });
                },
                .delim => |delim| switch (s.src[delim]) {
                    '.' => {
                        const name_token = s.consume() orelse @panic("TODO");
                        if (name_token != .ident) @panic("TODO");
                        const name = name_token.ident;

                        try specifiers.append(.{ .class = name });
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

    if (element_name == null and specifiers.items.len == 0) {
        @panic("TODO");
    }

    return .{
        .element_name = element_name,
        .specifiers = try specifiers.toOwnedSlice(),
    };
}

fn parseDeclarationValue(s: *State) ![]const Rule.Style.Declaration.Expression {
    var value = std.ArrayList(Rule.Style.Declaration.Expression).init(s.allocator);
    defer value.deinit();

    while (s.peek()) |token| {
        switch (token) {
            .semicolon, .close_curly => break,
            else => {
                try value.append(try parseDeclarationExpression(s));
            },
        }
    }

    if (value.items.len == 0) {
        @panic("TODO");
    }

    return try value.toOwnedSlice();
}

fn parseDeclarationExpression(s: *State) !Rule.Style.Declaration.Expression {
    // TODO: Support operators

    if (s.consume()) |token| {
        switch (token) {
            .number => @panic("TODO"),
            .percentage => @panic("TODO"),
            .dimension => |dimension| {
                return .{
                    .dimension = .{
                        .number = std.fmt.parseFloat(f32, dimension.number.slice(s.src)) catch @panic("TODO"),
                        .unit = unit: {
                            inline for (std.meta.fields(Rule.Style.Declaration.Expression.Dimension.Unit)) |field| {
                                if (std.mem.eql(u8, dimension.unit.slice(s.src), field.name)) {
                                    break :unit @enumFromInt(field.value);
                                }
                            }

                            @panic("TODO");
                        },
                    },
                };
            },
            .string => @panic("TODO"),
            .ident => |ident| return .{ .keyword = ident },
            .url => @panic("TODO"),
            .hash => |hash| {
                const slice = hash.slice(s.src)[1..];

                for (slice) |char| {
                    switch (char) {
                        '0'...'9', 'a'...'f', 'A'...'F' => {},
                        else => @panic("TODO"),
                    }
                }

                return switch (slice.len) {
                    6 => .{
                        .rgb6 = .{
                            .r = std.fmt.parseUnsigned(u8, slice[0..2], 16) catch unreachable,
                            .g = std.fmt.parseUnsigned(u8, slice[2..4], 16) catch unreachable,
                            .b = std.fmt.parseUnsigned(u8, slice[4..6], 16) catch unreachable,
                        },
                    },
                    3 => .{
                        .rgb3 = .{
                            .r = std.fmt.parseUnsigned(u4, slice[0..1], 16) catch unreachable,
                            .g = std.fmt.parseUnsigned(u4, slice[1..2], 16) catch unreachable,
                            .b = std.fmt.parseUnsigned(u4, slice[2..3], 16) catch unreachable,
                        },
                    },
                    else => @panic("TODO"),
                };
            },
            .function => @panic("TODO"),
            else => @panic("TODO"),
        }
    } else {
        @panic("TODO");
    }
}

pub fn deinit(self: Ast, allocator: std.mem.Allocator) void {
    for (self.rules) |rule| {
        rule.deinit(allocator);
    }
    allocator.free(self.rules);
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
