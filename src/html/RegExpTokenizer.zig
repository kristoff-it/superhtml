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

    eof,
};

const TokenError = enum {
    generic_error,

    //
    unclosed_capture_group,
    invalid_escape_char,
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
    // quantifier: struct { kind: QuantifierKind, span: Span },

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
        // Character classes
        digit, //                        \d
        non_digit, //                    \D
        word, //                         \w
        non_word, //                     \W
        whitespace, //                   \s
        non_whitespace, //               \S

        // Control characters
        newline, //                      \n
        carriage_return, //              \r
        tab, //                          \t
        vertical_tab, //                 \v
        form_feed, //                    \f

        // Boundaries (zero-width)
        word_boundary, //                \b
        non_word_boundary, //            \B

        // Literal escapes (escaped special chars)
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

                // Control characters
                'n' => .newline,
                'r' => .carriage_return,
                't' => .tab,
                'v' => .vertical_tab,
                'f' => .form_feed,

                // Boundaries (zero-width)
                'b' => .word_boundary,
                'B' => .non_word_boundary,

                // Literal escapes (escaped special chars)
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
    // pub const QuantifierKind = enum {};
    // pub const AnchorKind = enum {};
};

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
                        self.state = .{ .escape_sequence = self.idx - 1 };
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
                        self.current -= 1;
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
                            .tag = .generic_error,
                            .span = .{
                                .start = start,
                                .end = self.idx,
                            },
                        },
                    };
                } else {
                    if (Token.EscapeKind.from_char(self.current)) |kind| {
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
                                .tag = .invalid_escape_char,
                                .span = .{
                                    .start = start,
                                    .end = self.idx,
                                },
                            },
                        };
                    }
                }
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
