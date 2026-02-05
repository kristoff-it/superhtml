const RegExpTokenizer = @This();
const named_character_references = @import("named_character_references.zig");

const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;
const root = @import("../root.zig");
const Span = root.Span;

const log = std.log.scoped(.regExpTokenizer);

const State = union(enum) {
    data,

    parens_open: u32,
    parens_open_questionmark: u32,

    escape_sequence: u32,

    quantifier_start: u32,

    quantifier_start_curly: u32,
    quantifier_curly_min: struct {
        start: u32,
        range: struct { min: Span, max: ?Span },
    },
    quantifier_curly_max: struct {
        start: u32,
        range: struct { min: Span, max: ?Span },
    },
    quantifier_end_curly: struct {
        start: u32,
        range: struct { min: Span, max: ?Span, exact: bool = false },
    },

    eof,
};

// errors to handle one layer up:
// - repeating quantifiers (double, triple, n-ple quantifiers)
// - quantifier at start of line
// - ranged quantifier where low > high

const TokenError = enum {
    generic_error,

    // groups
    unclosed_capture_group,

    // escape
    invalid_escape_sequence,
    dangling_backslash,

    // quantifiers
    non_terminated_quantifier,
    empty_quantifier,
    invalid_quantifier_syntax,
};

const Token = union(enum) {
    character: u32,

    group_open: struct { kind: GroupKind, span: Span },
    group_close: u32,

    // Character Classes & Escapes
    escape_sequence: struct { kind: EscapeKind, span: Span },
    char_class_open: u32, // [
    char_class_close: u32, // ]
    char_class_negated: u32, // ^ inside []
    char_class_range: u32, // - inside []

    // Quantifiers
    quantifier: struct { kind: QuantifierKind, lazy: bool, span: Span },

    // Anchors & Special
    // anchor: struct { kind: AnchorKind, span: Span },
    alternation: u32, // |
    dot: u32, // .

    parse_error: struct {
        tag: TokenError,
        span: Span,
    },

    pub const GroupKind = enum { regular, non_capturing };
    pub const EscapeKind = enum {
        // character classes
        digit, //                        \d
        non_digit, //                    \D
        word, //                         \w
        non_word, //                     \W
        whitespace, //                   \s
        non_whitespace, //               \S

        // control characters
        newline, //                      \n
        carriage_return, //              \r
        tab, //                          \t
        vertical_tab, //                 \v
        form_feed, //                    \f

        // boundaries (zero-width)
        word_boundary, //                \b
        non_word_boundary, //            \B

        // literal escapes (escaped special chars)
        literal_dot, //                  \.
        literal_asterisk, //             \*
        literal_plus, //                 \+
        literal_question, //             \?
        literal_caret, //                \^
        literal_dollar, //               \$
        literal_bracket_open, //         \[
        literal_bracket_close, //        \]
        literal_brace_open, //           \{
        literal_brace_close, //          \}
        literal_paren_open, //           \(
        literal_paren_close, //          \)
        literal_pipe, //                 \|
        literal_backslash, //            \\
        literal_slash, //                \/

        // null_char,          // \0
        // hex_escape,         // \xHH
        // unicode_escape,     // \uHHHH
        // unicode_codepoint,  // \u{HHHHH}
        // backreference,      // \1, \2, etc.

        pub fn from_char(char: u8) ?EscapeKind {
            return switch (char) {
                'd' => .digit,
                'D' => .non_digit,
                'w' => .word,
                'W' => .non_word,
                's' => .whitespace,
                'S' => .non_whitespace,

                // control characters
                'n' => .newline,
                'r' => .carriage_return,
                't' => .tab,
                'v' => .vertical_tab,
                'f' => .form_feed,

                // boundaries (zero-width)
                'b' => .word_boundary,
                'B' => .non_word_boundary,

                // literal escapes (escaped special chars)
                '.' => .literal_dot,
                '*' => .literal_asterisk,
                '+' => .literal_plus,
                '?' => .literal_question,
                '^' => .literal_caret,
                '$' => .literal_dollar,
                '[' => .literal_bracket_open,
                ']' => .literal_bracket_close,
                '{' => .literal_brace_open,
                '}' => .literal_brace_close,
                '(' => .literal_paren_open,
                ')' => .literal_paren_close,
                '|' => .literal_pipe,
                '\\' => .literal_backslash,
                '/' => .literal_slash,
                else => null,
            };
        }
    };
    pub const QuantifierKind = union(enum) {
        zero_or_more, //                        *
        one_or_more, //                         +
        zero_or_one, //                         ?
        exact_count: Span, //                   {n}
        min_count: Span, //                     {n,}
        range_count: struct { Span, Span }, //  {n,m}

    };
    // pub const AnchorKind = enum {};
};

// tokenizer state

idx: u32 = 0,
current: u8 = undefined,
state: State = .data,

fn consume(self: *RegExpTokenizer, src: []const u8) bool {
    if (self.idx == src.len) {
        return false;
    }

    // idx points to the non-consumed char?
    self.current = src[self.idx];
    self.idx += 1;

    return true;
}

fn next(self: *RegExpTokenizer, src: []const u8) ?Token {
    while (true) {
        // std.debug.print("token {d}: {c}\n", .{ self.idx, self.current });
        switch (self.state) {
            .data => {
                if (!self.consume(src)) {
                    self.state = .eof;
                } else switch (self.current) {
                    '(' => {
                        self.state = .{
                            .parens_open = self.idx - 1,
                        };
                    },
                    ')' => {
                        return .{
                            .group_close = self.idx - 1,
                        };
                    },
                    '\\' => {
                        self.state = .{
                            .escape_sequence = self.idx - 1,
                        };
                    },

                    '{' => {
                        self.state = .{
                            .quantifier_start_curly = self.idx - 1,
                        };
                    },
                    '+', '*', '?' => {
                        self.state = .{
                            .quantifier_start = self.idx - 1,
                        };
                    },
                    else => {
                        return .{
                            .character = self.idx - 1,
                        };
                    },
                }
            },
            .parens_open => |start| {
                if (!self.consume(src)) {
                    self.state = .eof;
                    return .{
                        .parse_error = .{
                            .tag = .unclosed_capture_group,
                            .span = .{
                                .start = start,
                                .end = self.idx,
                            },
                        },
                    };
                } else switch (self.current) {
                    '?' => {
                        self.state = .{
                            .parens_open_questionmark = start,
                        };
                    },
                    else => {
                        self.idx -= 1;
                        self.state = .data;
                        return .{
                            .group_open = .{
                                .kind = .regular,
                                .span = .{ .start = start, .end = self.idx },
                            },
                        };
                    },
                }
            },
            .parens_open_questionmark => |start| {
                if (!self.consume(src)) {
                    self.state = .eof;
                    return .{
                        .parse_error = .{
                            .tag = .unclosed_capture_group,
                            .span = .{
                                .start = start,
                                .end = self.idx,
                            },
                        },
                    };
                } else switch (self.current) {
                    // '?' => {
                    //     self.state = .{
                    //         .parens_open_questionmark = start,
                    //     };
                    // },
                    else => {
                        self.idx -= 1;
                        self.state = .data;
                        return .{
                            .group_open = .{
                                .kind = .non_capturing,
                                .span = .{
                                    .start = start,
                                    .end = self.idx,
                                },
                            },
                        };
                    },
                }
            },
            .escape_sequence => |start| {
                if (!self.consume(src)) {
                    self.state = .eof;
                    return .{
                        .parse_error = .{
                            .tag = .dangling_backslash,
                            .span = .{
                                .start = start,
                                .end = self.idx,
                            },
                        },
                    };
                } else {
                    if (Token.EscapeKind.from_char(self.current)) |kind| {
                        self.state = .data;
                        return .{
                            .escape_sequence = .{
                                .kind = kind,
                                .span = .{
                                    .start = start,
                                    .end = self.idx,
                                },
                            },
                        };
                    } else {
                        return .{
                            .parse_error = .{
                                .tag = .invalid_escape_sequence,
                                .span = .{
                                    .start = start,
                                    .end = self.idx,
                                },
                            },
                        };
                    }
                }
            },
            .quantifier_start => |start| {
                const more_tokens = self.consume(src);

                const kind: Token.QuantifierKind = switch (src[start]) {
                    '+' => .one_or_more,
                    '*' => .zero_or_more,
                    '?' => .zero_or_one,
                    else => unreachable,
                };

                if (!more_tokens) {
                    self.state = .eof;
                    return .{
                        .quantifier = .{
                            .kind = kind,
                            .lazy = false,
                            .span = .{ .start = start, .end = self.idx },
                        },
                    };
                } else {
                    const is_lazy = self.current == '?';
                    const is_quantifier_token = switch (self.current) {
                        //  while ++, *+, +*, and ** are instances of repeating
                        //  a quantifier, ?? is legal
                        '?' => false,
                        '+', '*' => true,
                        else => false,
                    };

                    if (is_lazy and !is_quantifier_token) {
                        self.state = .data;
                        return .{
                            .quantifier = .{
                                .kind = kind,
                                .lazy = true,
                                .span = .{ .start = start, .end = self.idx },
                            },
                        };
                    }
                    if (!is_quantifier_token and !is_lazy) {
                        self.state = .data;
                        self.idx -= 1;
                        return .{
                            .quantifier = .{
                                .kind = kind,
                                .lazy = false,
                                .span = .{ .start = start, .end = self.idx },
                            },
                        };
                    }
                }
            },
            .quantifier_start_curly => |start| {
                if (!self.consume(src)) {
                    self.state = .eof;
                    return .{
                        .parse_error = .{
                            .tag = .non_terminated_quantifier,
                            .span = .{
                                .start = start,
                                .end = self.idx,
                            },
                        },
                    };
                } else {
                    if (self.current == '}') {
                        self.state = .data;
                        return .{
                            .parse_error = .{
                                .tag = .empty_quantifier,
                                .span = .{
                                    .start = start,
                                    .end = self.idx,
                                },
                            },
                        };
                    } else if (!std.ascii.isDigit(self.current)) {
                        self.state = .data;
                        return .{
                            .parse_error = .{
                                .tag = .invalid_quantifier_syntax,
                                .span = .{
                                    .start = start,
                                    .end = self.idx,
                                },
                            },
                        };
                    }
                    self.state = .{
                        .quantifier_curly_min = .{
                            .start = start,
                            .range = .{
                                .min = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                                .max = null,
                            },
                        },
                    };
                }
            },
            .quantifier_curly_min => |state| {
                if (!self.consume(src)) {
                    self.state = .eof;
                    return .{
                        .parse_error = .{
                            .tag = .non_terminated_quantifier,
                            .span = .{
                                .start = state.start,
                                .end = self.idx,
                            },
                        },
                    };
                } else {
                    if (self.current == ',') {
                        self.state = .{
                            .quantifier_curly_max = .{
                                .start = state.start,
                                .range = .{
                                    .min = state.range.min,
                                    .max = null,
                                },
                            },
                        };
                    } else if (self.current == '}') {
                        self.state = .{
                            .quantifier_end_curly = .{
                                .start = state.start,
                                .range = .{
                                    .exact = true,
                                    .min = .{
                                        .start = state.range.min.start,
                                        .end = self.idx - 1,
                                    },
                                    .max = null,
                                },
                            },
                        };
                    } else {
                        if (!std.ascii.isDigit(self.current)) {
                            self.state = .data;
                            return .{
                                .parse_error = .{
                                    .tag = .invalid_quantifier_syntax,
                                    .span = .{
                                        .start = state.start,
                                        .end = self.idx,
                                    },
                                },
                            };
                        }
                        var new_state = state;
                        new_state.range.min.end = self.idx;
                        self.state = .{ .quantifier_curly_min = new_state };
                    }
                }
            },
            .quantifier_curly_max => |state| {
                if (!self.consume(src)) {
                    self.state = .eof;
                    return .{
                        .parse_error = .{
                            .tag = .non_terminated_quantifier,
                            .span = .{
                                .start = state.start,
                                .end = self.idx,
                            },
                        },
                    };
                } else {
                    const is_first_transition = state.range.max == null;
                    const current_is_curly = self.current == '}';

                    if (is_first_transition and current_is_curly) {
                        const new_state: State = .{
                            .quantifier_end_curly = .{
                                .start = state.start,
                                .range = .{
                                    .min = state.range.min,
                                    .max = null,
                                    .exact = false,
                                },
                            },
                        };
                        self.state = new_state;
                    } else if (is_first_transition) {
                        const new_state: State = .{
                            .quantifier_curly_max = .{
                                .start = state.start,
                                .range = .{
                                    .min = state.range.min,
                                    .max = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                        self.state = new_state;
                    } else if (current_is_curly) {
                        const new_state: State = .{
                            .quantifier_end_curly = .{
                                .start = state.start,
                                .range = .{
                                    .min = state.range.min,
                                    .max = .{
                                        .start = state.range.max.?.start,
                                        .end = self.idx - 1,
                                    },
                                    .exact = false,
                                },
                            },
                        };
                        self.state = new_state;
                    } else {
                        if (!std.ascii.isDigit(self.current)) {
                            self.state = .data;
                            return .{
                                .parse_error = .{
                                    .tag = .invalid_quantifier_syntax,
                                    .span = .{
                                        .start = state.start,
                                        .end = self.idx,
                                    },
                                },
                            };
                        }
                        const new_state: State = .{
                            .quantifier_curly_max = .{
                                .start = state.start,
                                .range = .{
                                    .min = state.range.min,
                                    .max = .{
                                        .start = state.range.max.?.start,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                        self.state = new_state;
                    }
                }
            },
            .quantifier_end_curly => |state| {
                const more_tokens = self.consume(src);

                const is_lazy = self.current == '?';

                if (!is_lazy and more_tokens) self.idx -= 1;

                const quantifier: Token = if (state.range.max) |max| blk: {
                    // upper and lower bounds

                    break :blk .{
                        .quantifier = .{
                            .kind = .{ .range_count = .{ state.range.min, max } },
                            .lazy = is_lazy,
                            .span = .{ .start = state.start, .end = self.idx },
                        },
                    };
                } else if (state.range.exact) blk: {
                    // exact
                    break :blk .{
                        .quantifier = .{
                            .kind = .{ .exact_count = state.range.min },
                            .lazy = is_lazy,
                            .span = .{ .start = state.start, .end = self.idx },
                        },
                    };
                } else blk: {
                    // lower bound only
                    break :blk .{
                        .quantifier = .{
                            .kind = .{ .min_count = state.range.min },
                            .lazy = is_lazy,
                            .span = .{ .start = state.start, .end = self.idx },
                        },
                    };
                };

                if (!more_tokens) {
                    self.state = .eof;
                } else {
                    self.state = .data;
                }

                return quantifier;
            },
            .eof => return null,
        }
    }
}

test "regexp-scan" {
    var tokenizer: RegExpTokenizer = .{};

    const src = "(?foo)dxedo(";

    var tokens: std.ArrayList(Token) = .{};
    defer tokens.deinit(testing.allocator);

    var got_eof = false;

    while (tokenizer.next(src)) |tk| {
        try tokens.append(testing.allocator, tk);
    } else {
        got_eof = true;
    }

    const expected = &[_]Token{
        .{
            .group_open = .{
                .kind = .non_capturing,
                .span = .{
                    .start = 0,
                    .end = 2,
                },
            },
        },
        .{ .character = 2 },
        .{ .character = 3 },
        .{ .character = 4 },
        .{ .group_close = 5 },
        .{ .character = 6 },
        .{ .character = 7 },
        .{ .character = 8 },
        .{ .character = 9 },
        .{ .character = 10 },
        .{
            .parse_error = .{
                .tag = .unclosed_capture_group,
                .span = .{
                    .start = 11,
                    .end = 12,
                },
            },
        },
    };

    try std.testing.expectEqualSlices(Token, expected, tokens.items);
}

test "regexp-escapes" {
    const test_cases = [_]struct {
        src: []const u8,
        expected_escape: Token.EscapeKind,
    }{
        // character class escapes
        .{ .src = "\\d", .expected_escape = .digit },
        .{ .src = "\\D", .expected_escape = .non_digit },
        .{ .src = "\\w", .expected_escape = .word },
        .{ .src = "\\W", .expected_escape = .non_word },
        .{ .src = "\\s", .expected_escape = .whitespace },
        .{ .src = "\\S", .expected_escape = .non_whitespace },

        // control character escapes
        .{ .src = "\\n", .expected_escape = .newline },
        .{ .src = "\\r", .expected_escape = .carriage_return },
        .{ .src = "\\t", .expected_escape = .tab },
        .{ .src = "\\v", .expected_escape = .vertical_tab },
        .{ .src = "\\f", .expected_escape = .form_feed },

        // boundaries escapes
        .{ .src = "\\b", .expected_escape = .word_boundary },
        .{ .src = "\\B", .expected_escape = .non_word_boundary },

        // literal special characters
        .{ .src = "\\.", .expected_escape = .literal_dot },
        .{ .src = "\\*", .expected_escape = .literal_asterisk },
        .{ .src = "\\+", .expected_escape = .literal_plus },
        .{ .src = "\\?", .expected_escape = .literal_question },
        .{ .src = "\\^", .expected_escape = .literal_caret },
        .{ .src = "\\$", .expected_escape = .literal_dollar },
        .{ .src = "\\[", .expected_escape = .literal_bracket_open },
        .{ .src = "\\]", .expected_escape = .literal_bracket_close },
        .{ .src = "\\{", .expected_escape = .literal_brace_open },
        .{ .src = "\\}", .expected_escape = .literal_brace_close },
        .{ .src = "\\(", .expected_escape = .literal_paren_open },
        .{ .src = "\\)", .expected_escape = .literal_paren_close },
        .{ .src = "\\|", .expected_escape = .literal_pipe },
        .{ .src = "\\\\", .expected_escape = .literal_backslash },
        .{ .src = "\\/", .expected_escape = .literal_slash },
    };
    for (test_cases) |tc| {
        var tokenizer: RegExpTokenizer = .{};
        const token = tokenizer.next(tc.src).?;

        try testing.expectEqual(Token.escape_sequence, @as(std.meta.Tag(Token), token));
        try testing.expectEqual(tc.expected_escape, token.escape_sequence.kind);
        try testing.expectEqual(@as(u32, 0), token.escape_sequence.span.start);
        try testing.expectEqual(@as(u32, 2), token.escape_sequence.span.end);
    }
}

test "regexp-escape-in-context" {
    // Test escapes mixed with regular characters and groups
    var tokenizer: RegExpTokenizer = .{};
    const src = "a\\d+b\\wc";

    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);

    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }

    const expected = [_]Token{
        .{ .character = 0 }, // 'a'
        .{ .escape_sequence = .{ .kind = .digit, .span = .{ .start = 1, .end = 3 } } }, // \d
        .{ .quantifier = .{ .kind = .one_or_more, .span = .{ .start = 3, .end = 4 } } }, // +
        .{ .character = 4 }, // 'b'
        .{ .escape_sequence = .{ .kind = .word, .span = .{ .start = 5, .end = 7 } } }, // \w
        .{ .character = 7 }, // 'c'
    };

    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-escape-inside-groups" {
    // Test escapes inside capturing groups
    var tokenizer: RegExpTokenizer = .{};
    const src = "(\\d+)";

    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);

    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }

    const expected = [_]Token{
        .{ .group_open = .{ .kind = .regular, .span = .{ .start = 0, .end = 1 } } },
        .{ .escape_sequence = .{ .kind = .digit, .span = .{ .start = 1, .end = 3 } } },
        .{ .quantifier = .{ .kind = .one_or_more, .span = .{ .start = 3, .end = 4 } } },
        .{ .group_close = 4 },
    };

    try testing.expectEqualSlices(Token, &expected, actual.items);
}
test "regexp-escape-invalid-sequences" {
    // Test that invalid escape sequences produce errors
    const test_cases = [_]struct {
        src: []const u8,
        error_tag: TokenError,
    }{
        .{ .src = "\\", .error_tag = .dangling_backslash }, // Backslash at end
        .{ .src = "\\x", .error_tag = .invalid_escape_sequence }, // Invalid escape (if not implementing hex)
        .{ .src = "\\q", .error_tag = .invalid_escape_sequence }, // Unknown escape
    };
    for (test_cases) |tc| {
        var tokenizer: RegExpTokenizer = .{};
        const token = tokenizer.next(tc.src).?;

        try testing.expectEqual(Token.parse_error, @as(std.meta.Tag(Token), token));
        try testing.expectEqual(tc.error_tag, token.parse_error.tag);
    }
}
test "regexp-escape-case-sensitivity" {
    // Verify that case matters for escapes
    var tokenizer1: RegExpTokenizer = .{};
    var tokenizer2: RegExpTokenizer = .{};

    const token_d = tokenizer1.next("\\d").?; // digit
    const token_D = tokenizer2.next("\\D").?; // non-digit

    try testing.expectEqual(Token.EscapeKind.digit, token_d.escape_sequence.kind);
    try testing.expectEqual(Token.EscapeKind.non_digit, token_D.escape_sequence.kind);
}
test "regexp-escape-multiple-in-sequence" {
    // Test multiple escapes in a row
    var tokenizer: RegExpTokenizer = .{};
    const src = "\\d\\w\\s";

    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);

    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }

    const expected = [_]Token{
        .{ .escape_sequence = .{ .kind = .digit, .span = .{ .start = 0, .end = 2 } } },
        .{ .escape_sequence = .{ .kind = .word, .span = .{ .start = 2, .end = 4 } } },
        .{ .escape_sequence = .{ .kind = .whitespace, .span = .{ .start = 4, .end = 6 } } },
    };

    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-quantifier-simple-greedy" {
    const test_cases = [_]struct {
        src: []const u8,
        kind: Token.QuantifierKind,
    }{
        .{ .src = "a*", .kind = .zero_or_more },
        .{ .src = "b+", .kind = .one_or_more },
        .{ .src = "c?", .kind = .zero_or_one },
    };
    for (test_cases) |tc| {
        var tokenizer: RegExpTokenizer = .{};

        var actual: std.ArrayList(Token) = .{};
        defer actual.deinit(testing.allocator);
        while (tokenizer.next(tc.src)) |got| {
            try actual.append(testing.allocator, got);
        }
        try testing.expectEqual(@as(usize, 2), actual.items.len);
        try testing.expectEqual(Token.character, @as(std.meta.Tag(Token), actual.items[0]));
        try testing.expectEqual(Token.quantifier, @as(std.meta.Tag(Token), actual.items[1]));
        try testing.expectEqual(tc.kind, actual.items[1].quantifier.kind);
        try testing.expectEqual(false, actual.items[1].quantifier.lazy);
    }
}
test "regexp-quantifier-simple-lazy" {
    const test_cases = [_]struct {
        src: []const u8,
        kind: Token.QuantifierKind,
    }{
        .{ .src = "a*?", .kind = .zero_or_more },
        .{ .src = "b+?", .kind = .one_or_more },
        .{ .src = "c??", .kind = .zero_or_one },
    };
    for (test_cases) |tc| {
        var tokenizer: RegExpTokenizer = .{};

        var actual: std.ArrayList(Token) = .{};
        defer actual.deinit(testing.allocator);
        while (tokenizer.next(tc.src)) |got| {
            try actual.append(testing.allocator, got);
        }
        try testing.expectEqual(@as(usize, 2), actual.items.len);
        try testing.expectEqual(Token.character, @as(std.meta.Tag(Token), actual.items[0]));
        try testing.expectEqual(Token.quantifier, @as(std.meta.Tag(Token), actual.items[1]));
        try testing.expectEqual(tc.kind, actual.items[1].quantifier.kind);
        try testing.expectEqual(true, actual.items[1].quantifier.lazy);
    }
}
test "regexp-quantifier-exact-count" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "a{5}";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character = 0 }, // 'a'
        .{
            .quantifier = .{
                .kind = .{ .exact_count = .{ .start = 2, .end = 3 } }, // "5" is at position 2-3
                .lazy = false,
                .span = .{ .start = 1, .end = 4 },
            },
        },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}
test "regexp-quantifier-at-least" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "b{3,}";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character = 0 }, // 'b'
        .{
            .quantifier = .{
                .kind = .{ .min_count = .{ .start = 2, .end = 3 } }, // "3" is at position 2-3
                .lazy = false,
                .span = .{ .start = 1, .end = 5 },
            },
        },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}
test "regexp-quantifier-range" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "c{2,7}";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character = 0 }, // 'c'
        .{
            .quantifier = .{
                .kind = .{
                    .range_count = .{
                        .{ .start = 2, .end = 3 }, // "2" is at position 2-3
                        .{ .start = 4, .end = 5 }, // "7" is at position 4-5
                    },
                },
                .lazy = false,
                .span = .{ .start = 1, .end = 6 },
            },
        },
    };
    try testing.expectEqualDeep(&expected, actual.items);
}
test "regexp-quantifier-curly-lazy" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "d{2,5}?";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character = 0 }, // 'd'
        .{
            .quantifier = .{
                .kind = .{
                    .range_count = .{
                        .{ .start = 2, .end = 3 }, // "2" at position 2-3
                        .{ .start = 4, .end = 5 }, // "5" at position 4-5
                    },
                },
                .lazy = true,
                .span = .{ .start = 1, .end = 7 }, // whole "{2,5}?" from 1-7
            },
        },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}
test "regexp-quantifier-with-escapes" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "\\d+\\w*\\s?";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .escape_sequence = .{ .kind = .digit, .span = .{ .start = 0, .end = 2 } } },
        .{ .quantifier = .{ .kind = .one_or_more, .lazy = false, .span = .{ .start = 2, .end = 3 } } },
        .{ .escape_sequence = .{ .kind = .word, .span = .{ .start = 3, .end = 5 } } },
        .{ .quantifier = .{ .kind = .zero_or_more, .lazy = false, .span = .{ .start = 5, .end = 6 } } },
        .{ .escape_sequence = .{ .kind = .whitespace, .span = .{ .start = 6, .end = 8 } } },
        .{ .quantifier = .{ .kind = .zero_or_one, .lazy = false, .span = .{ .start = 8, .end = 9 } } },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}
test "regexp-quantifier-in-groups" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "(abc)+";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .group_open = .{ .kind = .regular, .span = .{ .start = 0, .end = 1 } } },
        .{ .character = 1 }, // 'a'
        .{ .character = 2 }, // 'b'
        .{ .character = 3 }, // 'c'
        .{ .group_close = 4 },
        .{ .quantifier = .{ .kind = .one_or_more, .lazy = false, .span = .{ .start = 5, .end = 6 } } },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}
test "regexp-quantifier-complex-pattern" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "a{2,4}b*c+d?";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character = 0 }, // 'a'
        .{
            .quantifier = .{
                .kind = .{
                    .range_count = .{
                        .{ .start = 2, .end = 3 }, // "2"
                        .{ .start = 4, .end = 5 }, // "4"
                    },
                },
                .lazy = false,
                .span = .{ .start = 1, .end = 6 },
            },
        },
        .{ .character = 6 }, // 'b'
        .{ .quantifier = .{ .kind = .zero_or_more, .lazy = false, .span = .{ .start = 7, .end = 8 } } },
        .{ .character = 8 }, // 'c'
        .{ .quantifier = .{ .kind = .one_or_more, .lazy = false, .span = .{ .start = 9, .end = 10 } } },
        .{ .character = 10 }, // 'd'
        .{ .quantifier = .{ .kind = .zero_or_one, .lazy = false, .span = .{ .start = 11, .end = 12 } } },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}
test "regexp-quantifier-double-digit-numbers" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "x{12,345}";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character = 0 }, // 'x'
        .{
            .quantifier = .{
                .kind = .{
                    .range_count = .{
                        .{ .start = 2, .end = 4 }, // "12" at positions 2-4
                        .{ .start = 5, .end = 8 }, // "345" at positions 5-8
                    },
                },
                .lazy = false,
                .span = .{ .start = 1, .end = 9 },
            },
        },
    };
    try testing.expectEqualDeep(&expected, actual.items);
}
test "regexp-quantifier-error-empty-braces" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "a{}";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character = 0 }, // 'a'
        .{ .parse_error = .{ .tag = .empty_quantifier, .span = .{ .start = 1, .end = 3 } } },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-quantifier-error-unclosed-braces" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "a{3,5";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character = 0 }, // 'a'
        .{ .parse_error = .{ .tag = .non_terminated_quantifier, .span = .{ .start = 1, .end = 5 } } },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}
test "regexp-quantifier-error-invalid-characters" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "a{3x5}";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character = 0 }, // 'a'
        .{ .parse_error = .{ .tag = .invalid_quantifier_syntax, .span = .{ .start = 1, .end = 4 } } },
        .{ .character = 4 }, // '5'
        .{ .character = 5 }, // '}'
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}
test "regexp-quantifier-escaped-special-chars" {
    // Escaped quantifier chars should be literals, not quantifiers
    var tokenizer: RegExpTokenizer = .{};
    const src = "a\\*b\\+c\\?";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character = 0 }, // 'a'
        .{ .escape_sequence = .{ .kind = .literal_asterisk, .span = .{ .start = 1, .end = 3 } } },
        .{ .character = 3 }, // 'b'
        .{ .escape_sequence = .{ .kind = .literal_plus, .span = .{ .start = 4, .end = 6 } } },
        .{ .character = 6 }, // 'c'
        .{ .escape_sequence = .{ .kind = .literal_question, .span = .{ .start = 7, .end = 9 } } },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}
