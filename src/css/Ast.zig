const std = @import("std");
const Tokenizer = @import("Tokenizer.zig");

const Ast = @This();

pub const Rule = union(enum) {
    style: Style,
    at: At,

    pub const Style = struct {
        selectors: []const Selector,
        declarations: []const Declaration,

        pub const Selector = union(enum) {
            simple: Simple,

            pub const Simple = struct {
                element_name: ?ElementName,

                pub const ElementName = union(enum) {
                    name: Tokenizer.Span,
                    all,
                };
            };
        };

        pub const Declaration = struct {
            property: Tokenizer.Span,
            value: Expression,

            pub const Expression = union(enum) {
                keyword: Tokenizer.Span,
            };
        };

        pub fn deinit(self: Style, allocator: std.mem.Allocator) void {
            allocator.free(self.selectors);
            allocator.free(self.declarations);
        }
    };

    pub const At = struct {};

    pub fn deinit(self: Rule, allocator: std.mem.Allocator) void {
        switch (self) {
            .style => |style| style.deinit(allocator),
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

    // TODO: Support multiple selectors
    try selectors.append(try parseSelector(s));

    if (s.consume()) |token| {
        switch (token) {
            .open_curly => {},
            else => @panic("TODO"),
        }
    } else {
        @panic("TODO");
    }

    // TODO: Support multiple declarations
    try declarations.append(try parseDeclaration(s));

    if (s.peek()) |token| {
        if (token == .semicolon) _ = s.consume();
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
        .value = try parseDeclarationExpression(s),
    };
}

fn parseSimpleSelector(s: *State) !Rule.Style.Selector.Simple {
    // TODO: Support hash, class, etc.
    // TODO: Support `*`

    return .{
        .element_name = .{
            .name = s.consume().?.ident,
        },
    };
}

fn parseDeclarationExpression(s: *State) !Rule.Style.Declaration.Expression {
    // TODO: Support operators
    // TODO: Support other expression types

    return .{ .keyword = s.consume().?.ident };
}

pub fn deinit(self: Ast, allocator: std.mem.Allocator) void {
    for (self.rules) |rule| {
        rule.deinit(allocator);
    }
    allocator.free(self.rules);
}

test {
    const src =
        \\p {
        \\    color: red;
        \\}
    ;

    const ast = try Ast.init(std.testing.allocator, src);
    defer ast.deinit(std.testing.allocator);

    try std.testing.expectEqualDeep(Ast{
        .rules = &.{
            .{
                .style = .{
                    .selectors = &.{
                        .{
                            .simple = .{
                                .element_name = .{
                                    .name = .{ .start = 0, .end = 1 },
                                },
                            },
                        },
                    },
                    .declarations = &.{
                        .{
                            .property = .{ .start = 8, .end = 13 },
                            .value = .{
                                .keyword = .{ .start = 15, .end = 18 },
                            },
                        },
                    },
                },
            },
        },
    }, ast);
}
