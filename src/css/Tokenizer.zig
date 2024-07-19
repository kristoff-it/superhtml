const std = @import("std");

const Tokenizer = @import("Tokenizer.zig");
const root = @import("../root.zig");
const Span = root.Span;

idx: u32 = 0,
current: u8 = undefined,

pub const Token = union(enum) {
    ident: Span,
    function: Span,
    at_keyword: Span,
    hash: Span,
    string: Span,
    bad_string: Span,
    url: Span,
    bad_url: Span,
    delim: u32,
    number: Span,
    percentage: Span,
    dimension: Dimension,
    cdo: u32,
    cdc: u32,
    colon: u32,
    semicolon: u32,
    comma: u32,
    open_square: u32,
    close_square: u32,
    open_paren: u32,
    close_paren: u32,
    open_curly: u32,
    close_curly: u32,

    pub const Dimension = struct {
        number: Span,
        unit: Span,
    };

    pub fn span(self: Token) Span {
        return switch (self) {
            .ident,
            .function,
            .at_keyword,
            .hash,
            .string,
            .bad_string,
            .url,
            .bad_url,
            .number,
            .percentage,
            => |s| s,
            .dimension,
            => |d| .{ .start = d.number.start, .end = d.unit.end },
            .cdo,
            => |i| .{ .start = i, .end = i + 4 },
            .cdc,
            => |i| .{ .start = i, .end = i + 3 },
            .delim,
            .colon,
            .semicolon,
            .comma,
            .open_square,
            .close_square,
            .open_paren,
            .close_paren,
            .open_curly,
            .close_curly,
            => |i| .{ .start = i, .end = i + 1 },
        };
    }
};

fn consume(self: *Tokenizer, src: []const u8) bool {
    if (self.idx == src.len) {
        return false;
    }
    self.current = src[self.idx];
    self.idx += 1;
    return true;
}

fn reconsume(self: *Tokenizer, src: []const u8) void {
    self.idx -= 1;
    if (self.idx == 0) {
        self.current = undefined;
    } else {
        self.current = src[self.idx - 1];
    }
}

fn peek(self: *Tokenizer, src: []const u8) ?u8 {
    if (self.idx >= src.len) {
        return null;
    }
    return src[self.idx];
}

// https://www.w3.org/TR/css-syntax-3/#ident-start-code-point
fn isIdentStartChar(char: u8) bool {
    return switch (char) {
        'A'...'Z', 'a'...'z', 0x80...0xff, '_' => true,
        else => false,
    };
}

// https://www.w3.org/TR/css-syntax-3/#ident-code-point
fn isIdentChar(char: u8) bool {
    return switch (char) {
        '0'...'9', '-' => true,
        else => isIdentStartChar(char),
    };
}

// https://www.w3.org/TR/css-syntax-3/#check-if-three-code-points-would-start-an-ident-sequence
fn next3WouldStartIdent(self: *Tokenizer, src: []const u8) bool {
    if (self.idx + 2 >= src.len) return false;

    const chars = src[self.idx .. self.idx + 3];

    // TODO: Support escape sequences
    return switch (chars[0]) {
        '-' => isIdentStartChar(chars[1]) or chars[1] == '-',
        '\\' => @panic("TODO"),
        else => isIdentStartChar(chars[0]),
    };
}

// https://www.w3.org/TR/css-syntax-3/#consume-token
pub fn next(self: *Tokenizer, src: []const u8) ?Token {
    if (self.consume(src)) {
        switch (self.current) {
            '\n', '\t', ' ' => {
                while (true) {
                    if (self.peek(src)) |c| switch (c) {
                        '\n', '\t', ' ' => std.debug.assert(self.consume(src)),
                        else => break,
                    } else break;
                }

                return self.next(src);
            },
            '"' => @panic("TODO"),
            '#' => {
                // TODO: Support escape sequeces

                if (self.peek(src) != null and isIdentChar(self.peek(src).?)) {
                    var token = .{ .hash = self.identSequence(src) };
                    token.hash.start -= 1;
                    return token;
                } else {
                    return .{ .delim = self.idx - 1 };
                }
            },
            '\'' => @panic("TODO"),
            '(' => @panic("TODO"),
            ')' => @panic("TODO"),
            '+' => @panic("TODO"),
            ',' => return .{ .comma = self.idx - 1 },
            '-' => @panic("TODO"),
            '.' => {
                if (self.peek(src)) |char| {
                    switch (char) {
                        '0'...'9' => @panic("TODO"),
                        else => {},
                    }
                }

                return .{ .delim = self.idx - 1 };
            },
            ':' => return .{ .colon = self.idx - 1 },
            ';' => return .{ .semicolon = self.idx - 1 },
            '<' => @panic("TODO"),
            '@' => @panic("TODO"),
            '[' => @panic("TODO"),
            '\\' => @panic("TODO"),
            ']' => @panic("TODO"),
            '{' => return .{ .open_curly = self.idx - 1 },
            '}' => return .{ .close_curly = self.idx - 1 },
            '0'...'9' => {
                self.reconsume(src);
                return self.numeric(src);
            },
            else => |c| if (isIdentStartChar(c)) {
                self.reconsume(src);
                return self.identLike(src);
            } else {
                return .{ .delim = self.idx - 1 };
            },
        }
    } else {
        return null;
    }
}

// https://www.w3.org/TR/css-syntax-3/#consume-an-ident-sequence
fn identSequence(self: *Tokenizer, src: []const u8) Span {
    // TODO: Support escape sequences

    const start = self.idx;

    while (true) {
        if (self.consume(src)) {
            if (!isIdentChar(self.current)) {
                self.reconsume(src);
                break;
            }
        } else break;
    }

    return .{ .start = start, .end = self.idx };
}

// https://www.w3.org/TR/css-syntax-3/#consume-an-ident-like-token
fn identLike(self: *Tokenizer, src: []const u8) Token {
    const span = self.identSequence(src);

    if (std.ascii.eqlIgnoreCase(span.slice(src), "url") and
        self.peek(src) != null and self.peek(src).? == '(')
    {
        @panic("TODO");
    } else if (self.peek(src) != null and self.peek(src).? == '(') {
        @panic("TODO");
    } else {
        return .{ .ident = span };
    }
}

// https://www.w3.org/TR/css-syntax-3/#consume-a-numeric-token
fn numeric(self: *Tokenizer, src: []const u8) Token {
    const start = self.idx;

    if (self.peek(src)) |c| {
        if (c == '+' or c == '-') {
            std.debug.assert(self.consume(src));
        }
    }

    while (self.peek(src)) |c| {
        switch (c) {
            '0'...'9' => std.debug.assert(self.consume(src)),
            else => break,
        }
    }

    // TODO: Support fractional part (e.g. 1.2)

    // TODO: Support exponents

    if (self.next3WouldStartIdent(src)) {
        const num_end = self.idx;

        const unit = self.identSequence(src);

        return .{
            .dimension = .{
                .number = .{ .start = start, .end = num_end },
                .unit = unit,
            },
        };
    } else if (self.peek(src) != null and self.peek(src).? == '%') {
        std.debug.assert(self.consume(src));
        return .{
            .percentage = .{ .start = start, .end = self.idx },
        };
    } else {
        return .{
            .number = .{ .start = start, .end = self.idx },
        };
    }
}

test {
    const src =
        \\p {
        \\    color: red;
        \\}
    ;

    var tokenizer = Tokenizer{};

    try std.testing.expectEqual(Token{ .ident = .{ .start = 0, .end = 1 } }, tokenizer.next(src).?);
    try std.testing.expectEqual(Token{ .open_curly = 2 }, tokenizer.next(src).?);
    try std.testing.expectEqual(Token{ .ident = .{ .start = 8, .end = 13 } }, tokenizer.next(src).?);
    try std.testing.expectEqual(Token{ .colon = 13 }, tokenizer.next(src).?);
    try std.testing.expectEqual(Token{ .ident = .{ .start = 15, .end = 18 } }, tokenizer.next(src).?);
    try std.testing.expectEqual(Token{ .semicolon = 18 }, tokenizer.next(src).?);
    try std.testing.expectEqual(Token{ .close_curly = 20 }, tokenizer.next(src).?);
    try std.testing.expectEqual(null, tokenizer.next(src));
}
