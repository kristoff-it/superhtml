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
    // Keywords that affect case statement indentation
    kw_case: Span,
    kw_default: Span,
    kw_break: Span,
    kw_continue: Span,
    kw_return: Span,
    kw_throw: Span,
    // Control flow keywords that can have single-line bodies
    kw_if: Span,
    kw_else: Span,
    kw_for: Span,
    kw_while: Span,
    kw_do: Span,
    other: Span,

    pub fn span(self: Token) Span {
        return switch (self) {
            .string,
            .template_literal,
            .line_comment,
            .block_comment,
            .regex,
            .kw_case,
            .kw_default,
            .kw_break,
            .kw_continue,
            .kw_return,
            .kw_throw,
            .kw_if,
            .kw_else,
            .kw_for,
            .kw_while,
            .kw_do,
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
    const ident_span: Span = .{ .start = start, .end = self.idx };

    // Check for case-related keywords first (these also set regex context)
    if (std.mem.eql(u8, ident, "case")) {
        self.last_was_operator_context = true;
        return .{ .kw_case = ident_span };
    }
    if (std.mem.eql(u8, ident, "default")) {
        self.last_was_operator_context = true;
        return .{ .kw_default = ident_span };
    }
    if (std.mem.eql(u8, ident, "break")) {
        self.last_was_operator_context = true;
        return .{ .kw_break = ident_span };
    }
    if (std.mem.eql(u8, ident, "continue")) {
        self.last_was_operator_context = true;
        return .{ .kw_continue = ident_span };
    }
    if (std.mem.eql(u8, ident, "return")) {
        self.last_was_operator_context = true;
        return .{ .kw_return = ident_span };
    }
    if (std.mem.eql(u8, ident, "throw")) {
        self.last_was_operator_context = true;
        return .{ .kw_throw = ident_span };
    }

    // Control flow keywords
    if (std.mem.eql(u8, ident, "if")) {
        self.last_was_operator_context = true;
        return .{ .kw_if = ident_span };
    }
    if (std.mem.eql(u8, ident, "else")) {
        self.last_was_operator_context = true;
        return .{ .kw_else = ident_span };
    }
    if (std.mem.eql(u8, ident, "for")) {
        self.last_was_operator_context = true;
        return .{ .kw_for = ident_span };
    }
    if (std.mem.eql(u8, ident, "while")) {
        self.last_was_operator_context = true;
        return .{ .kw_while = ident_span };
    }
    if (std.mem.eql(u8, ident, "do")) {
        self.last_was_operator_context = true;
        return .{ .kw_do = ident_span };
    }

    // Other keywords that are followed by regex context
    const regex_context_keywords = [_][]const u8{
        "delete", "typeof", "void", "new", "in", "instanceof", "yield",
        "await",
    };

    for (regex_context_keywords) |kw| {
        if (std.mem.eql(u8, ident, kw)) {
            self.last_was_operator_context = true;
            return .{ .other = ident_span };
        }
    }

    self.last_was_operator_context = false;
    return .{ .other = ident_span };
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

pub const LineIndentInfo = struct {
    delta: i32,
    starts_with_close: bool,
    ends_with_open: bool,
    /// Line starts with `case X:` or `default:` (should outdent the label, then indent body)
    is_case_label: bool,
    /// Line contains break/continue/return/throw (ends the case block)
    ends_case_block: bool,
    /// Line ends with a control flow construct expecting a body (e.g., `if (x)`, `else`, `for (...)`, `while (...)`, `do`)
    /// This means the next line should be indented even without an opening brace
    expects_body: bool,
    /// Line starts with `else`
    starts_with_else: bool,
};

/// Compute the net indentation change for a line of JavaScript code.
/// Returns the delta to apply (positive = increase indent, negative = decrease).
/// Also returns whether the line starts with a closing bracket (for outdenting).
pub fn lineIndentInfo(src: []const u8) LineIndentInfo {
    var tokenizer = Tokenizer{};
    var delta: i32 = 0;
    var first_significant: ?Token = null;
    var last_significant: ?Token = null;

    // Track case label detection: need case/default followed by colon
    // We track whether we saw case/default at the START of the line (first token)
    var saw_case_or_default_first = false;
    var is_case_label = false;
    var ends_case_block = false;

    // Track control flow for single-line body detection
    // We need to detect patterns like:
    //   if (x)      -> kw_if followed by balanced parens ending line
    //   else        -> kw_else at end of line (not followed by if)
    //   else if (x) -> kw_else, kw_if, balanced parens
    //   for (...)   -> kw_for followed by balanced parens
    //   while (x)   -> kw_while followed by balanced parens
    //   do          -> kw_do at end of line
    var last_control_flow: ?Token = null;
    var paren_depth_at_control: i32 = 0;
    var paren_depth: i32 = 0;
    // Track if we've seen anything after the control flow's condition closed
    var control_flow_condition_closed = false;

    while (tokenizer.next(src)) |token| {
        switch (token) {
            .open_brace, .open_bracket => {
                delta += 1;
                if (first_significant == null) first_significant = token;
                last_significant = token;
                // Opening brace cancels control flow expectation
                last_control_flow = null;
            },
            .open_paren => {
                delta += 1;
                paren_depth += 1;
                if (first_significant == null) first_significant = token;
                last_significant = token;
                // If we've already closed the control flow condition and see another (,
                // there's a body on this line
                if (control_flow_condition_closed) {
                    last_control_flow = null;
                }
            },
            .close_brace, .close_bracket => {
                delta -= 1;
                if (first_significant == null) first_significant = token;
                last_significant = token;
                last_control_flow = null;
            },
            .close_paren => {
                delta -= 1;
                paren_depth -= 1;
                if (first_significant == null) first_significant = token;
                last_significant = token;
                // Check if this closes the control flow's condition
                if (last_control_flow) |cf| {
                    switch (cf) {
                        .kw_if, .kw_for, .kw_while => {
                            if (paren_depth == paren_depth_at_control) {
                                control_flow_condition_closed = true;
                            }
                        },
                        else => {},
                    }
                }
            },
            .kw_case, .kw_default => {
                if (first_significant == null) {
                    first_significant = token;
                    saw_case_or_default_first = true;
                }
                last_significant = token;
                last_control_flow = null;
            },
            .colon => {
                if (saw_case_or_default_first) {
                    is_case_label = true;
                }
                if (first_significant == null) first_significant = token;
                last_significant = token;
            },
            .kw_break, .kw_continue, .kw_return, .kw_throw => {
                ends_case_block = true;
                if (first_significant == null) first_significant = token;
                last_significant = token;
                last_control_flow = null;
            },
            .kw_if, .kw_for, .kw_while => {
                if (first_significant == null) first_significant = token;
                last_significant = token;
                last_control_flow = token;
                paren_depth_at_control = paren_depth;
                control_flow_condition_closed = false;
            },
            .kw_else, .kw_do => {
                if (first_significant == null) first_significant = token;
                last_significant = token;
                last_control_flow = token;
                paren_depth_at_control = paren_depth;
                control_flow_condition_closed = false;
            },
            .line_comment, .block_comment => {
                // Comments don't affect first/last significant token
            },
            .semicolon => {
                if (first_significant == null) first_significant = token;
                last_significant = token;
                // Semicolon ends any control flow expectation
                last_control_flow = null;
            },
            else => {
                if (first_significant == null) first_significant = token;
                last_significant = token;
                // Any other token after the condition closed means body is on this line
                if (control_flow_condition_closed) {
                    last_control_flow = null;
                }
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

    // Determine if line expects a body on the next line
    // This happens when:
    // 1. Line ends with else or do (not followed by anything else significant)
    // 2. Line has if/for/while and the condition closed but no body followed
    // NOTE: If the body is on the same line (e.g., `if (x) doSomething();`),
    // last_control_flow will have been set to null.
    const expects_body = if (last_control_flow) |cf| blk: {
        switch (cf) {
            .kw_else, .kw_do => {
                // else/do expect body if they're the last significant token
                // (but not if followed by { which would be caught by ends_with_open)
                if (last_significant) |ls| {
                    break :blk (ls == .kw_else or ls == .kw_do);
                }
                break :blk false;
            },
            .kw_if, .kw_for, .kw_while => {
                // if/for/while expect body if condition closed and nothing followed
                break :blk control_flow_condition_closed;
            },
            else => break :blk false,
        }
    } else false;

    // Check if line starts with else
    const starts_with_else = if (first_significant) |fs|
        fs == .kw_else
    else
        false;

    return .{
        .delta = delta,
        .starts_with_close = starts_with_close,
        .ends_with_open = ends_with_open,
        .is_case_label = is_case_label,
        .ends_case_block = ends_case_block,
        .expects_body = expects_body,
        .starts_with_else = starts_with_else,
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

test "case label detection" {
    {
        const info = lineIndentInfo("case 1:");
        try std.testing.expectEqual(true, info.is_case_label);
        try std.testing.expectEqual(false, info.ends_case_block);
    }
    {
        const info = lineIndentInfo("case 'foo':");
        try std.testing.expectEqual(true, info.is_case_label);
    }
    {
        const info = lineIndentInfo("default:");
        try std.testing.expectEqual(true, info.is_case_label);
        try std.testing.expectEqual(false, info.ends_case_block);
    }
    {
        // case without colon is not a label
        const info = lineIndentInfo("case");
        try std.testing.expectEqual(false, info.is_case_label);
    }
    {
        // colon without case is not a label
        const info = lineIndentInfo("foo:");
        try std.testing.expectEqual(false, info.is_case_label);
    }
}

test "case-ending statements" {
    {
        const info = lineIndentInfo("break");
        try std.testing.expectEqual(true, info.ends_case_block);
        try std.testing.expectEqual(false, info.is_case_label);
    }
    {
        const info = lineIndentInfo("break;");
        try std.testing.expectEqual(true, info.ends_case_block);
    }
    {
        const info = lineIndentInfo("continue");
        try std.testing.expectEqual(true, info.ends_case_block);
    }
    {
        const info = lineIndentInfo("return x");
        try std.testing.expectEqual(true, info.ends_case_block);
    }
    {
        const info = lineIndentInfo("throw new Error()");
        try std.testing.expectEqual(true, info.ends_case_block);
    }
}

test "case keywords in strings are not detected" {
    {
        const info = lineIndentInfo("const x = 'case 1:';");
        try std.testing.expectEqual(false, info.is_case_label);
    }
    {
        const info = lineIndentInfo("const x = 'break';");
        try std.testing.expectEqual(false, info.ends_case_block);
    }
}

test "control flow expects body" {
    // if (x) expects body
    {
        const info = lineIndentInfo("if (foo)");
        try std.testing.expectEqual(true, info.expects_body);
        try std.testing.expectEqual(false, info.starts_with_else);
    }
    // if (x) { does NOT expect body (has brace)
    {
        const info = lineIndentInfo("if (foo) {");
        try std.testing.expectEqual(false, info.expects_body);
    }
    // else expects body
    {
        const info = lineIndentInfo("else");
        try std.testing.expectEqual(true, info.expects_body);
        try std.testing.expectEqual(true, info.starts_with_else);
    }
    // else { does NOT expect body
    {
        const info = lineIndentInfo("else {");
        try std.testing.expectEqual(false, info.expects_body);
        try std.testing.expectEqual(true, info.starts_with_else);
    }
    // else if (x) expects body
    {
        const info = lineIndentInfo("else if (bar)");
        try std.testing.expectEqual(true, info.expects_body);
        try std.testing.expectEqual(true, info.starts_with_else);
    }
    // for loop expects body
    {
        const info = lineIndentInfo("for (const e of elements)");
        try std.testing.expectEqual(true, info.expects_body);
    }
    // while loop expects body
    {
        const info = lineIndentInfo("while (true)");
        try std.testing.expectEqual(true, info.expects_body);
    }
    // do expects body
    {
        const info = lineIndentInfo("do");
        try std.testing.expectEqual(true, info.expects_body);
    }
    // Complete statement does NOT expect body
    {
        const info = lineIndentInfo("if (foo) doSomething();");
        try std.testing.expectEqual(false, info.expects_body);
    }
    // while with body on same line
    {
        const info = lineIndentInfo("while (true) doSomething()");
        try std.testing.expectEqual(false, info.expects_body);
    }
    // for with body on same line
    {
        const info = lineIndentInfo("for (const x of arr) process(x)");
        try std.testing.expectEqual(false, info.expects_body);
    }
    // else with body on same line
    {
        const info = lineIndentInfo("else doSomething()");
        try std.testing.expectEqual(false, info.expects_body);
    }
    // Nested parens - should not be fooled
    {
        const info = lineIndentInfo("if (foo(bar))");
        try std.testing.expectEqual(true, info.expects_body);
    }
}
