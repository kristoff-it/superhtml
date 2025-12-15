const std = @import("std");
const root = @import("../root.zig");
const Span = root.Span;

/// Minimal JavaScript tokenizer for formatting purposes.
/// Only tracks tokens relevant to indentation: braces, brackets, parens,
/// strings, template literals, comments, and regex literals.
const Tokenizer = @This();

idx: u32 = 0,
/// Tracks whether we're in a context where `/` would start a regex.
last_was_operator_context: bool = true,

pub const Token = union(enum) {
    open_brace: u32,
    close_brace: u32,
    open_bracket: u32,
    close_bracket: u32,
    open_paren: u32,
    close_paren: u32,
    string: Span,
    template_literal: Span,
    line_comment: Span,
    block_comment: Span,
    regex: Span,
    semicolon: u32,
    comma: u32,
    colon: u32,
    other: Span,

    pub fn span(self: Token) Span {
        return switch (self) {
            .string,
            .template_literal,
            .line_comment,
            .block_comment,
            .regex,
            .other,
            => |s| s,
            .open_brace,
            .close_brace,
            .open_bracket,
            .close_bracket,
            .open_paren,
            .close_paren,
            .semicolon,
            .comma,
            .colon,
            => |i| .{ .start = i, .end = i + 1 },
        };
    }

    /// Returns true if this token affects indentation (opening bracket)
    pub fn opensBlock(self: Token) bool {
        return switch (self) {
            .open_brace, .open_bracket, .open_paren => true,
            else => false,
        };
    }

    /// Returns true if this token affects indentation (closing bracket)
    pub fn closesBlock(self: Token) bool {
        return switch (self) {
            .close_brace, .close_bracket, .close_paren => true,
            else => false,
        };
    }
};

fn peek(self: *Tokenizer, src: []const u8) ?u8 {
    if (self.idx >= src.len) return null;
    return src[self.idx];
}

fn peekN(self: *Tokenizer, src: []const u8, n: u32) ?u8 {
    if (self.idx + n >= src.len) return null;
    return src[self.idx + n];
}

fn advance(self: *Tokenizer) void {
    self.idx += 1;
}

fn consume(self: *Tokenizer, src: []const u8) ?u8 {
    if (self.idx >= src.len) return null;
    const c = src[self.idx];
    self.idx += 1;
    return c;
}

pub fn next(self: *Tokenizer, src: []const u8) ?Token {
    while (self.peek(src)) |c| {
        switch (c) {
            // Whitespace - skip
            ' ', '\t', '\n', '\r' => {
                self.advance();
                continue;
            },

            // Single-line comment
            '/' => {
                if (self.peekN(src, 1) == @as(u8, '/')) {
                    return self.lineComment(src);
                } else if (self.peekN(src, 1) == @as(u8, '*')) {
                    return self.blockComment(src);
                } else if (self.last_was_operator_context) {
                    // Regex literal
                    return self.regex(src);
                } else {
                    // Division operator
                    const start = self.idx;
                    self.advance();
                    self.last_was_operator_context = true;
                    return .{ .other = .{ .start = start, .end = self.idx } };
                }
            },

            // Strings
            '"', '\'' => return self.string(src),
            '`' => return self.templateLiteral(src),

            // Brackets
            '{' => {
                const idx = self.idx;
                self.advance();
                self.last_was_operator_context = true;
                return .{ .open_brace = idx };
            },
            '}' => {
                const idx = self.idx;
                self.advance();
                self.last_was_operator_context = false;
                return .{ .close_brace = idx };
            },
            '[' => {
                const idx = self.idx;
                self.advance();
                self.last_was_operator_context = true;
                return .{ .open_bracket = idx };
            },
            ']' => {
                const idx = self.idx;
                self.advance();
                self.last_was_operator_context = false;
                return .{ .close_bracket = idx };
            },
            '(' => {
                const idx = self.idx;
                self.advance();
                self.last_was_operator_context = true;
                return .{ .open_paren = idx };
            },
            ')' => {
                const idx = self.idx;
                self.advance();
                self.last_was_operator_context = false;
                return .{ .close_paren = idx };
            },

            // Punctuation that sets operator context
            ';' => {
                const idx = self.idx;
                self.advance();
                self.last_was_operator_context = true;
                return .{ .semicolon = idx };
            },
            ',' => {
                const idx = self.idx;
                self.advance();
                self.last_was_operator_context = true;
                return .{ .comma = idx };
            },
            ':' => {
                const idx = self.idx;
                self.advance();
                self.last_was_operator_context = true;
                return .{ .colon = idx };
            },

            // Operators that set operator context (regex can follow)
            '=', '+', '-', '*', '%', '<', '>', '&', '|', '^', '!', '~', '?' => {
                const start = self.idx;
                self.advance();
                // Skip multi-char operators
                while (self.peek(src)) |nc| {
                    switch (nc) {
                        '=', '+', '-', '*', '%', '<', '>', '&', '|', '^', '!' => self.advance(),
                        else => break,
                    }
                }
                self.last_was_operator_context = true;
                return .{ .other = .{ .start = start, .end = self.idx } };
            },

            // Identifiers and keywords
            'a'...'z', 'A'...'Z', '_', '$' => {
                return self.identifier(src);
            },

            // Numbers
            '0'...'9' => {
                return self.number(src);
            },

            // Dot (could be number like .5 or member access)
            '.' => {
                if (self.peekN(src, 1)) |nc| {
                    if (nc >= '0' and nc <= '9') {
                        return self.number(src);
                    }
                }
                const start = self.idx;
                self.advance();
                // Check for spread operator ...
                if (self.peek(src) == @as(u8, '.') and self.peekN(src, 1) == @as(u8, '.')) {
                    self.advance();
                    self.advance();
                    self.last_was_operator_context = true;
                } else {
                    self.last_was_operator_context = false;
                }
                return .{ .other = .{ .start = start, .end = self.idx } };
            },

            else => {
                // Unknown character, skip
                const start = self.idx;
                self.advance();
                return .{ .other = .{ .start = start, .end = self.idx } };
            },
        }
    }
    return null;
}

fn lineComment(self: *Tokenizer, src: []const u8) Token {
    const start = self.idx;
    // Skip //
    self.advance();
    self.advance();

    while (self.peek(src)) |c| {
        if (c == '\n') break;
        self.advance();
    }

    self.last_was_operator_context = true;
    return .{ .line_comment = .{ .start = start, .end = self.idx } };
}

fn blockComment(self: *Tokenizer, src: []const u8) Token {
    const start = self.idx;
    // Skip /*
    self.advance();
    self.advance();

    while (self.peek(src)) |c| {
        if (c == '*' and self.peekN(src, 1) == @as(u8, '/')) {
            self.advance();
            self.advance();
            break;
        }
        self.advance();
    }

    // Block comments don't change operator context
    return .{ .block_comment = .{ .start = start, .end = self.idx } };
}

fn string(self: *Tokenizer, src: []const u8) Token {
    const start = self.idx;
    const quote = self.consume(src).?;

    while (self.peek(src)) |c| {
        if (c == '\\') {
            // Escape sequence - skip next char
            self.advance();
            if (self.peek(src) != null) self.advance();
        } else if (c == quote) {
            self.advance();
            break;
        } else if (c == '\n' and quote != '`') {
            // Unterminated string (newline in non-template)
            break;
        } else {
            self.advance();
        }
    }

    self.last_was_operator_context = false;
    return .{ .string = .{ .start = start, .end = self.idx } };
}

fn templateLiteral(self: *Tokenizer, src: []const u8) Token {
    const start = self.idx;
    // Skip opening backtick
    self.advance();

    var brace_depth: u32 = 0;

    while (self.peek(src)) |c| {
        if (c == '\\') {
            // Escape sequence
            self.advance();
            if (self.peek(src) != null) self.advance();
        } else if (c == '$' and self.peekN(src, 1) == @as(u8, '{')) {
            // Template expression ${...}
            self.advance(); // $
            self.advance(); // {
            brace_depth = 1;

            // Skip the expression content, tracking nested braces
            while (self.peek(src)) |ec| {
                if (ec == '{') {
                    brace_depth += 1;
                    self.advance();
                } else if (ec == '}') {
                    brace_depth -= 1;
                    self.advance();
                    if (brace_depth == 0) break;
                } else if (ec == '"' or ec == '\'' or ec == '`') {
                    // String inside template expression - skip it
                    _ = self.skipNestedString(src, ec);
                } else if (ec == '/' and self.peekN(src, 1) == @as(u8, '/')) {
                    // Line comment in expression
                    self.advance();
                    self.advance();
                    while (self.peek(src)) |lc| {
                        if (lc == '\n') break;
                        self.advance();
                    }
                } else if (ec == '/' and self.peekN(src, 1) == @as(u8, '*')) {
                    // Block comment in expression
                    self.advance();
                    self.advance();
                    while (self.peek(src)) |bc| {
                        if (bc == '*' and self.peekN(src, 1) == @as(u8, '/')) {
                            self.advance();
                            self.advance();
                            break;
                        }
                        self.advance();
                    }
                } else {
                    self.advance();
                }
            }
        } else if (c == '`') {
            self.advance();
            break;
        } else {
            self.advance();
        }
    }

    self.last_was_operator_context = false;
    return .{ .template_literal = .{ .start = start, .end = self.idx } };
}

fn skipNestedString(self: *Tokenizer, src: []const u8, quote: u8) void {
    self.advance(); // opening quote
    while (self.peek(src)) |c| {
        if (c == '\\') {
            self.advance();
            if (self.peek(src) != null) self.advance();
        } else if (c == quote) {
            self.advance();
            break;
        } else if (c == '\n' and quote != '`') {
            break;
        } else {
            self.advance();
        }
    }
}

fn regex(self: *Tokenizer, src: []const u8) Token {
    const start = self.idx;
    // Skip opening /
    self.advance();

    var in_class = false;
    while (self.peek(src)) |c| {
        if (c == '\\') {
            // Escape sequence
            self.advance();
            if (self.peek(src) != null) self.advance();
        } else if (c == '[' and !in_class) {
            in_class = true;
            self.advance();
        } else if (c == ']' and in_class) {
            in_class = false;
            self.advance();
        } else if (c == '/' and !in_class) {
            self.advance();
            // Consume flags
            while (self.peek(src)) |fc| {
                switch (fc) {
                    'g', 'i', 'm', 's', 'u', 'y', 'd', 'v' => self.advance(),
                    else => break,
                }
            }
            break;
        } else if (c == '\n') {
            // Unterminated regex
            break;
        } else {
            self.advance();
        }
    }

    self.last_was_operator_context = false;
    return .{ .regex = .{ .start = start, .end = self.idx } };
}

fn identifier(self: *Tokenizer, src: []const u8) Token {
    const start = self.idx;

    while (self.peek(src)) |c| {
        switch (c) {
            'a'...'z', 'A'...'Z', '0'...'9', '_', '$' => self.advance(),
            else => break,
        }
    }

    const ident = src[start..self.idx];

    // Keywords that are followed by regex context
    const regex_context_keywords = [_][]const u8{
        "return", "throw", "case", "delete",     "typeof",
        "void",   "new",   "in",   "instanceof", "yield",
        "await",  "else",  "do",
    };

    for (regex_context_keywords) |kw| {
        if (std.mem.eql(u8, ident, kw)) {
            self.last_was_operator_context = true;
            return .{ .other = .{ .start = start, .end = self.idx } };
        }
    }

    self.last_was_operator_context = false;
    return .{ .other = .{ .start = start, .end = self.idx } };
}

fn number(self: *Tokenizer, src: []const u8) Token {
    const start = self.idx;

    // Handle hex, octal, binary prefixes
    if (self.peek(src) == @as(u8, '0')) {
        self.advance();
        if (self.peek(src)) |c| {
            switch (c) {
                'x', 'X' => {
                    self.advance();
                    while (self.peek(src)) |hc| {
                        switch (hc) {
                            '0'...'9', 'a'...'f', 'A'...'F', '_' => self.advance(),
                            else => break,
                        }
                    }
                    self.last_was_operator_context = false;
                    return .{ .other = .{ .start = start, .end = self.idx } };
                },
                'o', 'O' => {
                    self.advance();
                    while (self.peek(src)) |oc| {
                        switch (oc) {
                            '0'...'7', '_' => self.advance(),
                            else => break,
                        }
                    }
                    self.last_was_operator_context = false;
                    return .{ .other = .{ .start = start, .end = self.idx } };
                },
                'b', 'B' => {
                    self.advance();
                    while (self.peek(src)) |bc| {
                        switch (bc) {
                            '0', '1', '_' => self.advance(),
                            else => break,
                        }
                    }
                    self.last_was_operator_context = false;
                    return .{ .other = .{ .start = start, .end = self.idx } };
                },
                else => {},
            }
        }
    }

    // Regular decimal number
    while (self.peek(src)) |c| {
        switch (c) {
            '0'...'9', '_' => self.advance(),
            else => break,
        }
    }

    // Decimal part
    if (self.peek(src) == @as(u8, '.')) {
        if (self.peekN(src, 1)) |nc| {
            if (nc >= '0' and nc <= '9') {
                self.advance(); // .
                while (self.peek(src)) |c| {
                    switch (c) {
                        '0'...'9', '_' => self.advance(),
                        else => break,
                    }
                }
            }
        }
    }

    // Exponent
    if (self.peek(src)) |c| {
        if (c == 'e' or c == 'E') {
            self.advance();
            if (self.peek(src)) |sc| {
                if (sc == '+' or sc == '-') self.advance();
            }
            while (self.peek(src)) |ec| {
                switch (ec) {
                    '0'...'9', '_' => self.advance(),
                    else => break,
                }
            }
        }
    }

    // BigInt suffix
    if (self.peek(src) == @as(u8, 'n')) {
        self.advance();
    }

    self.last_was_operator_context = false;
    return .{ .other = .{ .start = start, .end = self.idx } };
}

/// Compute the net indentation change for a line of JavaScript code.
/// Returns the delta to apply (positive = increase indent, negative = decrease).
/// Also returns whether the line starts with a closing bracket (for outdenting).
pub fn lineIndentInfo(src: []const u8) struct { delta: i32, starts_with_close: bool, ends_with_open: bool } {
    var tokenizer = Tokenizer{};
    var delta: i32 = 0;
    var first_significant: ?Token = null;
    var last_significant: ?Token = null;

    while (tokenizer.next(src)) |token| {
        switch (token) {
            .open_brace, .open_bracket, .open_paren => {
                delta += 1;
                if (first_significant == null) first_significant = token;
                last_significant = token;
            },
            .close_brace, .close_bracket, .close_paren => {
                delta -= 1;
                if (first_significant == null) first_significant = token;
                last_significant = token;
            },
            .line_comment, .block_comment => {
                // Comments don't affect first/last significant token
            },
            else => {
                if (first_significant == null) first_significant = token;
                last_significant = token;
            },
        }
    }

    const starts_with_close = if (first_significant) |t|
        t.closesBlock()
    else
        false;

    const ends_with_open = if (last_significant) |t|
        t.opensBlock()
    else
        false;

    return .{
        .delta = delta,
        .starts_with_close = starts_with_close,
        .ends_with_open = ends_with_open,
    };
}

test "basic tokenization" {
    const src = "{ foo }";
    var tokenizer = Tokenizer{};

    try std.testing.expectEqual(Token{ .open_brace = 0 }, tokenizer.next(src).?);
    const other = tokenizer.next(src).?;
    try std.testing.expect(other == .other);
    try std.testing.expectEqual(Token{ .close_brace = 6 }, tokenizer.next(src).?);
    try std.testing.expectEqual(null, tokenizer.next(src));
}

test "string literals" {
    const src =
        \\"hello" 'world' `template`
    ;
    var tokenizer = Tokenizer{};

    const t1 = tokenizer.next(src).?;
    try std.testing.expect(t1 == .string);

    const t2 = tokenizer.next(src).?;
    try std.testing.expect(t2 == .string);

    const t3 = tokenizer.next(src).?;
    try std.testing.expect(t3 == .template_literal);
}

test "comments" {
    const src =
        \\// line comment
        \\/* block comment */
    ;
    var tokenizer = Tokenizer{};

    const t1 = tokenizer.next(src).?;
    try std.testing.expect(t1 == .line_comment);

    const t2 = tokenizer.next(src).?;
    try std.testing.expect(t2 == .block_comment);
}

test "regex vs division" {
    // After identifier, / is division
    {
        const src = "a / b";
        var tokenizer = Tokenizer{};
        _ = tokenizer.next(src); // a
        const div = tokenizer.next(src).?;
        try std.testing.expect(div == .other); // division operator
    }

    // After operator, / starts regex
    {
        const src = "x = /pattern/g";
        var tokenizer = Tokenizer{};
        _ = tokenizer.next(src); // x
        _ = tokenizer.next(src); // =
        const regex_token = tokenizer.next(src).?;
        try std.testing.expect(regex_token == .regex);
    }
}

test "line indent info - simple block" {
    {
        const info = lineIndentInfo("function foo() {");
        try std.testing.expectEqual(@as(i32, 1), info.delta);
        try std.testing.expectEqual(false, info.starts_with_close);
        try std.testing.expectEqual(true, info.ends_with_open);
    }
    {
        const info = lineIndentInfo("}");
        try std.testing.expectEqual(@as(i32, -1), info.delta);
        try std.testing.expectEqual(true, info.starts_with_close);
        try std.testing.expectEqual(false, info.ends_with_open);
    }
    {
        const info = lineIndentInfo("const x = 1;");
        try std.testing.expectEqual(@as(i32, 0), info.delta);
        try std.testing.expectEqual(false, info.starts_with_close);
        try std.testing.expectEqual(false, info.ends_with_open);
    }
}

test "line indent info - balanced braces" {
    const info = lineIndentInfo("if (x) { return y; }");
    try std.testing.expectEqual(@as(i32, 0), info.delta);
}

test "braces in strings don't count" {
    const info = lineIndentInfo("const x = '{ not a brace }';");
    try std.testing.expectEqual(@as(i32, 0), info.delta);
}

test "braces in comments don't count" {
    {
        const info = lineIndentInfo("// { comment brace }");
        try std.testing.expectEqual(@as(i32, 0), info.delta);
    }
    {
        const info = lineIndentInfo("/* { block } */");
        try std.testing.expectEqual(@as(i32, 0), info.delta);
    }
}

test "braces in regex don't count" {
    const info = lineIndentInfo("const re = /{.*}/;");
    try std.testing.expectEqual(@as(i32, 0), info.delta);
}

test "template literal with expression" {
    const info = lineIndentInfo("const x = `hello ${name}`;");
    try std.testing.expectEqual(@as(i32, 0), info.delta);
}
