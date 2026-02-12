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
    parens_close: u32,

    escape_sequence: u32,

    quantifier_start: struct { char: u8, pos: u32 },

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

    anchor: struct { char: u8, pos: u32 },
    dot: u32,
    alternation: u32,

    character_class_start: u32,
    character_class_body: struct { is_first_transition: bool, pos: u32 },

    eof,
};

// errors to handle one layer up:
// - repeating quantifiers (double, triple, n-ple quantifiers)
// - quantifier at start of line
// - ranged quantifier where low > high
// - invalid anchor placement

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

    // character class
    non_terminated_character_class,
    invalid_character_class_token,
};

const Token = union(enum) {
    character: u32,

    group_open: struct { kind: GroupKind, span: Span },
    group_close: u32,

    // character classes & escapes
    escape_sequence: struct { kind: EscapeKind, span: Span },

    character_class_open: struct { negated: bool, span: Span },
    character_class_range: struct { low: u32, high: u32 },
    character_class_close: u32,

    // quantifiers
    quantifier: struct { kind: QuantifierKind, lazy: bool, span: Span },

    // anchors & special
    anchor: struct { kind: AnchorKind, pos: u32 },
    alternation: u32,
    dot: u32,

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
        literal_dash, //                 \-

        // advanced escapes
        null_char, //                    \0
        hex_escape, //                   \xHH
        unicode_escape, //               \uHHHH
        unicode_codepoint, //            \u{H+}
        control_char, //                 \cX

        // backreference,      // \1, \2, etc. (TODO)

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
                '-' => .literal_dash,
                '0' => .null_char,
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
    pub const AnchorKind = enum {
        start,
        end,
    };
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

fn peek(self: *RegExpTokenizer, src: []const u8) ?u8 {
    if (self.idx == src.len) {
        return null;
    }
    return src[self.idx];
}

fn next(self: *RegExpTokenizer, src: []const u8) ?Token {
    while (true) {
        // std.debug.print("state: {s}\n", .{@tagName(self.state)});
        switch (self.state) {
            .data => {
                // std.debug.print("state: {s}, token {d}: {c}\n", .{ @tagName(self.state), self.idx, self.current });
                if (!self.consume(src)) {
                    self.state = .eof;
                } else switch (self.current) {
                    '(' => {
                        self.state = .{
                            .parens_open = self.idx - 1,
                        };
                    },
                    ')' => {
                        self.state = .{
                            .parens_close = self.idx - 1,
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
                    '+', '*', '?' => |c| {
                        self.state = .{
                            .quantifier_start = .{
                                .char = c,
                                .pos = self.idx - 1,
                            },
                        };
                    },
                    '^', '$' => |c| {
                        self.state = .{
                            .anchor = .{
                                .char = c,
                                .pos = self.idx - 1,
                            },
                        };
                    },
                    '.' => {
                        self.state = .{
                            .dot = self.idx - 1,
                        };
                    },
                    '|' => {
                        self.state = .{
                            .alternation = self.idx - 1,
                        };
                    },
                    '[' => {
                        self.state = .{
                            .character_class_start = self.idx - 1,
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
            .parens_close => |pos| {
                self.state = .data;
                return .{ .group_close = pos };
            },
            .escape_sequence => |start| {
                const more_tokens = self.consume(src);
                if (!more_tokens) {
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
                    const parse_error: TokenError = switch_blk: switch (self.current) {
                        'x' => {
                            const consumed_first_char = self.consume(src);
                            const first_char = self.current;
                            const consumed_second_char = self.consume(src);
                            if (!consumed_first_char or !consumed_second_char) {
                                break :switch_blk .invalid_escape_sequence;
                            }
                            const isHex = std.ascii.isHex;
                            if (!isHex(first_char) or !isHex(self.current)) {
                                break :switch_blk .invalid_escape_sequence;
                            }

                            self.state = .data;
                            return .{
                                .escape_sequence = .{
                                    .kind = .hex_escape,
                                    .span = .{
                                        .start = start,
                                        .end = self.idx,
                                    },
                                },
                            };
                        },
                        'u' => {
                            var consumed_chars: ?bool = null;
                            var chars_are_hex: ?bool = null;

                            const isHex = std.ascii.isHex;

                            const next_is_curly = if (self.peek(src)) |c| c == '{' else false;
                            var escape_kind: Token.EscapeKind = undefined;

                            if (next_is_curly) {
                                if (!self.consume(src)) {
                                    break :switch_blk .dangling_backslash;
                                } else {
                                    // handle unicode codepoint, variable 1-6 hex chars + terminating '}'
                                    var i: u32 = 0;
                                    escape_kind = .unicode_codepoint;

                                    const err: ?TokenError = while_blk: while (true) : (i += 1) {
                                        const consumed = self.consume(src);
                                        if (!consumed) {
                                            break :while_blk .dangling_backslash;
                                        }

                                        const current_is_curly = self.current == '}';
                                        if (current_is_curly) {
                                            if (consumed_chars == null) {
                                                consumed_chars = false;
                                                chars_are_hex = false;
                                            }
                                            if (i < 7) {
                                                break :while_blk null;
                                            } else {
                                                break :while_blk .invalid_escape_sequence;
                                            }
                                        }
                                        if (consumed_chars) |b| {
                                            consumed_chars = b and consumed;
                                            chars_are_hex = chars_are_hex.? and isHex(self.current);
                                        } else {
                                            consumed_chars = consumed;
                                            chars_are_hex = isHex(self.current);
                                        }
                                    };

                                    if (err) |e| {
                                        break :switch_blk e;
                                    }
                                }
                            } else {
                                // handle unicode escape, constant 4 hex chars
                                escape_kind = .unicode_escape;
                                for (0..4) |_| {
                                    // std.debug.print("char norn: {c}\n", .{self.current});
                                    const consumed = self.consume(src);
                                    if (consumed_chars) |b| {
                                        consumed_chars = b and consumed;
                                        chars_are_hex = chars_are_hex.? and isHex(self.current);
                                    } else {
                                        consumed_chars = consumed;
                                        chars_are_hex = isHex(self.current);
                                    }
                                }
                            }

                            if (!consumed_chars.? or !chars_are_hex.?) {
                                break :switch_blk .invalid_escape_sequence;
                            }

                            self.state = .data;
                            return .{
                                .escape_sequence = .{
                                    .kind = escape_kind,
                                    .span = .{
                                        .start = start,
                                        .end = self.idx,
                                    },
                                },
                            };
                        },
                        'c' => {
                            const consumed_char = self.consume(src);
                            if (!consumed_char) {
                                break :switch_blk .dangling_backslash;
                            }

                            const valid_control_char = switch (self.current) {
                                'A', 'J', 'M', 'Z', 'a' => true,
                                else => false,
                            };

                            if (!valid_control_char) {
                                break :switch_blk .invalid_escape_sequence;
                            }

                            self.state = .data;
                            return .{
                                .escape_sequence = .{
                                    .kind = .control_char,
                                    .span = .{
                                        .start = start,
                                        .end = self.idx,
                                    },
                                },
                            };
                        },
                        else => {
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
                                break :switch_blk .invalid_escape_sequence;
                            }
                        },
                    };

                    self.state = .data;
                    return .{
                        .parse_error = .{
                            .tag = parse_error,
                            .span = .{
                                .start = start,
                                .end = self.idx,
                            },
                        },
                    };
                }
            },
            .quantifier_start => |state| {
                const more_tokens = self.consume(src);

                const kind: Token.QuantifierKind = switch (state.char) {
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
                            .span = .{ .start = state.pos, .end = self.idx },
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
                                .span = .{ .start = state.pos, .end = self.idx },
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
                                .span = .{ .start = state.pos, .end = self.idx },
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
            .anchor => |state| {
                const anchor: Token = .{
                    .anchor = .{
                        .kind = switch (state.char) {
                            '^' => .start,
                            '$' => .end,
                            else => unreachable,
                        },
                        .pos = self.idx - 1,
                    },
                };

                self.state = .data;

                return anchor;
            },
            .dot => |pos| {
                self.state = .data;

                return .{
                    .dot = pos,
                };
            },
            .alternation => |pos| {
                self.state = .data;

                return .{
                    .alternation = pos,
                };
            },
            .character_class_start => |pos| {
                const more_tokens = self.consume(src);

                if (!more_tokens) {
                    return .{
                        .parse_error = .{
                            .tag = .non_terminated_character_class,
                            .span = .{
                                .start = pos,
                                .end = self.idx,
                            },
                        },
                    };
                }

                self.state = .{
                    .character_class_body = .{
                        .pos = pos,
                        .is_first_transition = true,
                    },
                };

                // TODO: probably here in both cases peek the next char and
                // check if it's a [ or a -
                // or update the state variant to hold a bool do signify if
                // it's the first transition to it so it can now it's on the
                // first char in the range
                if (self.current == '^') {
                    return .{
                        .character_class_open = .{
                            .negated = true,
                            .span = .{
                                .start = pos,
                                .end = self.idx,
                            },
                        },
                    };
                } else {
                    self.idx -= 1;
                    return .{
                        .character_class_open = .{
                            .negated = false,
                            .span = .{
                                .start = pos,
                                .end = self.idx,
                            },
                        },
                    };
                }
            },
            .character_class_body => |state| {
                const more_tokens = self.consume(src);

                if (state.is_first_transition and more_tokens) switch (self.current) {
                    ']' => {
                        const current_idx = self.idx;
                        const bracket_idx = current_idx - 1;
                        var return_bracket = false;
                        while (self.consume(src)) {
                            if (self.current == ']') {
                                return_bracket = true;
                            }
                        }
                        self.idx = current_idx;
                        if (return_bracket) {
                            return .{ .character = bracket_idx };
                        }
                    },
                    else => {},
                };

                self.state = .{
                    .character_class_body = .{
                        .pos = state.pos,
                        .is_first_transition = false,
                    },
                };

                if (!more_tokens) {
                    self.state = .data;
                    return .{
                        .parse_error = .{
                            .tag = .non_terminated_character_class,
                            .span = .{
                                .start = state.pos,
                                .end = self.idx,
                            },
                        },
                    };
                }

                const current_is_backslash = self.current == '\\';
                const next_is_dash: bool = if (self.peek(src)) |c| c == '-' else false;

                if (!current_is_backslash and next_is_dash) {
                    const range_start = self.idx - 1;
                    const consumed_dash = self.consume(src);
                    const consumed_range_high = self.consume(src);
                    const cosumed_range = consumed_dash and consumed_range_high;

                    if (!cosumed_range) {
                        return .{
                            .parse_error = .{
                                .tag = .non_terminated_character_class,
                                .span = .{
                                    .start = state.pos,
                                    .end = self.idx,
                                },
                            },
                        };
                    } else if (self.current == ']') {
                        // hacky, for literal dash
                        // we undo one consume so that next iteration
                        // won't peek a '-' and choose this branch
                        // we return the first char in range as a char
                        self.idx -= 2;
                        return .{
                            .character = range_start,
                        };
                    } else {
                        return .{
                            .character_class_range = .{
                                .low = range_start,
                                .high = self.idx - 1,
                            },
                        };
                    }
                } else {
                    if (self.current == ']') {
                        self.state = .data;
                        return .{ .character_class_close = self.idx - 1 };
                    } else if (current_is_backslash) {
                        const backslash_idx = self.idx - 1;
                        if (self.consume(src)) {
                            if (Token.EscapeKind.from_char(self.current)) |kind| {
                                return .{
                                    .escape_sequence = .{
                                        .kind = kind,
                                        .span = .{
                                            .start = backslash_idx,
                                            .end = self.idx,
                                        },
                                    },
                                };
                            }
                        }

                        return .{
                            .parse_error = .{
                                .tag = .invalid_escape_sequence,
                                .span = .{
                                    .start = backslash_idx,
                                    .end = self.idx,
                                },
                            },
                        };
                    } else {
                        return .{ .character = self.idx - 1 };
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
        .{ .src = "\\-", .expected_escape = .literal_dash },
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
        .{ .quantifier = .{ .kind = .one_or_more, .lazy = false, .span = .{ .start = 3, .end = 4 } } }, // +
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
        .{ .quantifier = .{ .kind = .one_or_more, .lazy = false, .span = .{ .start = 3, .end = 4 } } },
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

test "regexp-escape-null-char" {
    // \0 - null character
    var tokenizer: RegExpTokenizer = .{};
    const src = "\\0";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{
            .escape_sequence = .{
                .kind = .null_char,
                .span = .{ .start = 0, .end = 2 },
            },
        },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-escape-hex-simple" {
    // \xHH - 2-digit hex escape
    var tokenizer: RegExpTokenizer = .{};
    const src = "\\x41"; // 'A'
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{
            .escape_sequence = .{
                .kind = .hex_escape,
                .span = .{ .start = 0, .end = 4 },
            },
        },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-escape-hex-lowercase" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "\\xff"; // 255
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{
            .escape_sequence = .{
                .kind = .hex_escape,
                .span = .{ .start = 0, .end = 4 },
            },
        },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-escape-hex-mixed-case" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "\\xAf";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{
            .escape_sequence = .{
                .kind = .hex_escape,
                .span = .{ .start = 0, .end = 4 },
            },
        },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-escape-hex-in-pattern" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "a\\x20b"; // 'a b' (space in middle)
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character = 0 }, // 'a'
        .{
            .escape_sequence = .{
                .kind = .hex_escape,
                .span = .{ .start = 1, .end = 5 },
            },
        },
        .{ .character = 5 }, // 'b'
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-escape-hex-error-incomplete" {
    // \x with only 1 hex digit should be an error
    var tokenizer: RegExpTokenizer = .{};
    const src = "\\x4";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    // Should get an error token
    try testing.expect(actual.items.len >= 1);
    try testing.expectEqual(Token.parse_error, @as(std.meta.Tag(Token), actual.items[0]));
    try testing.expectEqual(TokenError.invalid_escape_sequence, actual.items[0].parse_error.tag);
}

test "regexp-escape-hex-error-invalid-chars" {
    // \x with non-hex characters should be an error
    var tokenizer: RegExpTokenizer = .{};
    const src = "\\xGG";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    try testing.expect(actual.items.len >= 1);
    try testing.expectEqual(Token.parse_error, @as(std.meta.Tag(Token), actual.items[0]));
}

test "regexp-escape-unicode-simple" {
    // \uHHHH - 4-digit unicode escape
    var tokenizer: RegExpTokenizer = .{};
    const src = "\\u0041"; // 'A'
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{
            .escape_sequence = .{
                .kind = .unicode_escape,
                .span = .{ .start = 0, .end = 6 },
            },
        },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-escape-unicode-emoji" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "\\uD83D"; // High surrogate for emoji
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{
            .escape_sequence = .{
                .kind = .unicode_escape,
                .span = .{ .start = 0, .end = 6 },
            },
        },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-escape-unicode-in-pattern" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "\\u0061bc"; // 'abc'
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{
            .escape_sequence = .{
                .kind = .unicode_escape,
                .span = .{ .start = 0, .end = 6 },
            },
        },
        .{ .character = 6 }, // 'b'
        .{ .character = 7 }, // 'c'
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-escape-unicode-error-incomplete" {
    // \u with less than 4 hex digits should be an error
    var tokenizer: RegExpTokenizer = .{};
    const src = "\\u041";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    try testing.expect(actual.items.len >= 1);
    try testing.expectEqual(Token.parse_error, @as(std.meta.Tag(Token), actual.items[0]));
    try testing.expectEqual(TokenError.invalid_escape_sequence, actual.items[0].parse_error.tag);
}

test "regexp-escape-unicode-codepoint-simple" {
    // \u{H+} - Unicode code point (ES2015+)
    var tokenizer: RegExpTokenizer = .{};
    const src = "\\u{41}"; // 'A'
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{
            .escape_sequence = .{
                .kind = .unicode_codepoint,
                .span = .{ .start = 0, .end = 6 },
            },
        },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-escape-unicode-codepoint-emoji" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "\\u{1F600}"; // 😀
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{
            .escape_sequence = .{
                .kind = .unicode_codepoint,
                .span = .{ .start = 0, .end = 9 },
            },
        },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-escape-unicode-codepoint-variable-length" {
    // Unicode codepoints can be 1-6 hex digits
    const test_cases = [_]struct {
        src: []const u8,
        span_end: u32,
    }{
        .{ .src = "\\u{0}", .span_end = 5 }, // 1 digit
        .{ .src = "\\u{41}", .span_end = 6 }, // 2 digits
        .{ .src = "\\u{FFF}", .span_end = 7 }, // 3 digits
        .{ .src = "\\u{FFFF}", .span_end = 8 }, // 4 digits
        .{ .src = "\\u{10000}", .span_end = 9 }, // 5 digits
        .{ .src = "\\u{10FFFF}", .span_end = 10 }, // 6 digits (max)
    };
    for (test_cases) |tc| {
        var tokenizer: RegExpTokenizer = .{};
        var actual: std.ArrayList(Token) = .{};
        defer actual.deinit(testing.allocator);
        while (tokenizer.next(tc.src)) |got| {
            try actual.append(testing.allocator, got);
        }

        const expected = [_]Token{
            .{
                .escape_sequence = .{
                    .kind = .unicode_codepoint,
                    .span = .{ .start = 0, .end = tc.span_end },
                },
            },
        };

        try testing.expectEqualSlices(Token, &expected, actual.items);
    }
}

test "regexp-escape-unicode-codepoint-error-empty" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "\\u{}";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    try testing.expect(actual.items.len >= 1);
    try testing.expectEqual(Token.parse_error, @as(std.meta.Tag(Token), actual.items[0]));
}

test "regexp-escape-unicode-codepoint-error-unclosed" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "\\u{1F600";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    try testing.expect(actual.items.len >= 1);
    try testing.expectEqual(Token.parse_error, @as(std.meta.Tag(Token), actual.items[0]));
}

test "regexp-escape-unicode-codepoint-error-too-large" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "\\u{1100000}";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }

    const expected = [_]Token{
        .{
            .parse_error = .{
                .tag = .invalid_escape_sequence,
                .span = .{ .start = 0, .end = 11 },
            },
        },
    };

    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-escape-control-char" {
    // \cX - control characters (A-Z, a-z)
    const test_cases = [_]struct {
        src: []const u8,
        control_char: u8,
    }{
        .{ .src = "\\cA", .control_char = 'A' }, // Ctrl-A
        .{ .src = "\\cJ", .control_char = 'J' }, // Ctrl-J (newline)
        .{ .src = "\\cM", .control_char = 'M' }, // Ctrl-M (carriage return)
        .{ .src = "\\cZ", .control_char = 'Z' }, // Ctrl-Z
        .{ .src = "\\ca", .control_char = 'a' }, // lowercase also valid
    };
    for (test_cases) |tc| {
        var tokenizer: RegExpTokenizer = .{};
        var actual: std.ArrayList(Token) = .{};
        defer actual.deinit(testing.allocator);
        while (tokenizer.next(tc.src)) |got| {
            try actual.append(testing.allocator, got);
        }
        const expected = [_]Token{
            .{
                .escape_sequence = .{
                    .kind = .control_char,
                    .span = .{ .start = 0, .end = 3 },
                },
            },
        };
        try testing.expectEqualSlices(Token, &expected, actual.items);
    }
}

test "regexp-escape-control-char-error-invalid" {
    // \c must be followed by A-Z or a-z
    var tokenizer: RegExpTokenizer = .{};
    const src = "\\c1";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    try testing.expect(actual.items.len >= 1);
    try testing.expectEqual(Token.parse_error, @as(std.meta.Tag(Token), actual.items[0]));
    try testing.expectEqual(TokenError.invalid_escape_sequence, actual.items[0].parse_error.tag);
}

test "regexp-escape-mixed-advanced" {
    // Mix advanced escapes with regular pattern
    var tokenizer: RegExpTokenizer = .{};
    const src = "\\x41\\u0042\\u{43}";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{
            .escape_sequence = .{
                .kind = .hex_escape,
                .span = .{ .start = 0, .end = 4 },
            },
        },
        .{
            .escape_sequence = .{
                .kind = .unicode_escape,
                .span = .{ .start = 4, .end = 10 },
            },
        },
        .{
            .escape_sequence = .{
                .kind = .unicode_codepoint,
                .span = .{ .start = 10, .end = 16 },
            },
        },
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

test "regexp-dot-single" {
    var tokenizer: RegExpTokenizer = .{};
    const src = ".";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .dot = 0 },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-dot-in-pattern" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "a.b";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character = 0 }, // 'a'
        .{ .dot = 1 },
        .{ .character = 2 }, // 'b'
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-dot-with-quantifier" {
    var tokenizer: RegExpTokenizer = .{};
    const src = ".*";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .dot = 0 },
        .{ .quantifier = .{ .kind = .zero_or_more, .lazy = false, .span = .{ .start = 1, .end = 2 } } },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-dot-escaped" {
    // Escaped dot should be a literal, not the dot metacharacter
    var tokenizer: RegExpTokenizer = .{};
    const src = "\\.";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .escape_sequence = .{ .kind = .literal_dot, .span = .{ .start = 0, .end = 2 } } },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-anchor-start" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "^abc";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .anchor = .{ .kind = .start, .pos = 0 } },
        .{ .character = 1 }, // 'a'
        .{ .character = 2 }, // 'b'
        .{ .character = 3 }, // 'c'
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-anchor-end" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "abc$";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character = 0 }, // 'a'
        .{ .character = 1 }, // 'b'
        .{ .character = 2 }, // 'c'
        .{ .anchor = .{ .kind = .end, .pos = 3 } },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-anchor-both" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "^abc$";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .anchor = .{ .kind = .start, .pos = 0 } },
        .{ .character = 1 }, // 'a'
        .{ .character = 2 }, // 'b'
        .{ .character = 3 }, // 'c'
        .{ .anchor = .{ .kind = .end, .pos = 4 } },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-anchor-escaped" {
    // Escaped anchors should be literals
    var tokenizer: RegExpTokenizer = .{};
    const src = "\\^a\\$";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .escape_sequence = .{ .kind = .literal_caret, .span = .{ .start = 0, .end = 2 } } },
        .{ .character = 2 }, // 'a'
        .{ .escape_sequence = .{ .kind = .literal_dollar, .span = .{ .start = 3, .end = 5 } } },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-anchor-word-boundary" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "\\bword\\b";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .escape_sequence = .{ .kind = .word_boundary, .span = .{ .start = 0, .end = 2 } } },
        .{ .character = 2 }, // 'w'
        .{ .character = 3 }, // 'o'
        .{ .character = 4 }, // 'r'
        .{ .character = 5 }, // 'd'
        .{ .escape_sequence = .{ .kind = .word_boundary, .span = .{ .start = 6, .end = 8 } } },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-anchor-non-word-boundary" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "\\Bword\\B";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .escape_sequence = .{ .kind = .non_word_boundary, .span = .{ .start = 0, .end = 2 } } },
        .{ .character = 2 }, // 'w'
        .{ .character = 3 }, // 'o'
        .{ .character = 4 }, // 'r'
        .{ .character = 5 }, // 'd'
        .{ .escape_sequence = .{ .kind = .non_word_boundary, .span = .{ .start = 6, .end = 8 } } },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-complex-pattern-with-anchors-and-dot" {
    // Pattern: ^.*foo$
    var tokenizer: RegExpTokenizer = .{};
    const src = "^.*foo$";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .anchor = .{ .kind = .start, .pos = 0 } },
        .{ .dot = 1 },
        .{ .quantifier = .{ .kind = .zero_or_more, .lazy = false, .span = .{ .start = 2, .end = 3 } } },
        .{ .character = 3 }, // 'f'
        .{ .character = 4 }, // 'o'
        .{ .character = 5 }, // 'o'
        .{ .anchor = .{ .kind = .end, .pos = 6 } },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-alternation-simple" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "a|b";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character = 0 }, // 'a'
        .{ .alternation = 1 }, // '|'
        .{ .character = 2 }, // 'b'
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-alternation-multiple" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "cat|dog|bird";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character = 0 }, // 'c'
        .{ .character = 1 }, // 'a'
        .{ .character = 2 }, // 't'
        .{ .alternation = 3 }, // '|'
        .{ .character = 4 }, // 'd'
        .{ .character = 5 }, // 'o'
        .{ .character = 6 }, // 'g'
        .{ .alternation = 7 }, // '|'
        .{ .character = 8 }, // 'b'
        .{ .character = 9 }, // 'i'
        .{ .character = 10 }, // 'r'
        .{ .character = 11 }, // 'd'
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-alternation-with-groups" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "(foo|bar)";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .group_open = .{ .kind = .regular, .span = .{ .start = 0, .end = 1 } } },
        .{ .character = 1 }, // 'f'
        .{ .character = 2 }, // 'o'
        .{ .character = 3 }, // 'o'
        .{ .alternation = 4 }, // '|'
        .{ .character = 5 }, // 'b'
        .{ .character = 6 }, // 'a'
        .{ .character = 7 }, // 'r'
        .{ .group_close = 8 },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-alternation-with-quantifiers" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "a+|b*";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character = 0 }, // 'a'
        .{ .quantifier = .{ .kind = .one_or_more, .lazy = false, .span = .{ .start = 1, .end = 2 } } },
        .{ .alternation = 2 }, // '|'
        .{ .character = 3 }, // 'b'
        .{ .quantifier = .{ .kind = .zero_or_more, .lazy = false, .span = .{ .start = 4, .end = 5 } } },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-alternation-with-escapes" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "\\d|\\w";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .escape_sequence = .{ .kind = .digit, .span = .{ .start = 0, .end = 2 } } },
        .{ .alternation = 2 }, // '|'
        .{ .escape_sequence = .{ .kind = .word, .span = .{ .start = 3, .end = 5 } } },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-alternation-escaped" {
    // Escaped pipe should be a literal, not alternation
    var tokenizer: RegExpTokenizer = .{};
    const src = "a\\|b";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character = 0 }, // 'a'
        .{ .escape_sequence = .{ .kind = .literal_pipe, .span = .{ .start = 1, .end = 3 } } },
        .{ .character = 3 }, // 'b'
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-alternation-empty-alternatives" {
    // Empty alternatives are valid in JavaScript regex
    var tokenizer: RegExpTokenizer = .{};
    const src = "|a|";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .alternation = 0 }, // '|' at start (empty left alternative)
        .{ .character = 1 }, // 'a'
        .{ .alternation = 2 }, // '|' (empty right alternative)
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-alternation-complex-pattern" {
    // Pattern: ^(foo|bar|baz)$
    var tokenizer: RegExpTokenizer = .{};
    const src = "^(foo|bar|baz)$";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .anchor = .{ .kind = .start, .pos = 0 } },
        .{ .group_open = .{ .kind = .regular, .span = .{ .start = 1, .end = 2 } } },
        .{ .character = 2 }, // 'f'
        .{ .character = 3 }, // 'o'
        .{ .character = 4 }, // 'o'
        .{ .alternation = 5 }, // '|'
        .{ .character = 6 }, // 'b'
        .{ .character = 7 }, // 'a'
        .{ .character = 8 }, // 'r'
        .{ .alternation = 9 }, // '|'
        .{ .character = 10 }, // 'b'
        .{ .character = 11 }, // 'a'
        .{ .character = 12 }, // 'z'
        .{ .group_close = 13 },
        .{ .anchor = .{ .kind = .end, .pos = 14 } },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-alternation-with-dot" {
    var tokenizer: RegExpTokenizer = .{};
    const src = ".|a";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .dot = 0 },
        .{ .alternation = 1 }, // '|'
        .{ .character = 2 }, // 'a'
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-char-class-simple" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "[abc]";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character_class_open = .{ .negated = false, .span = .{ .start = 0, .end = 1 } } }, // '['
        .{ .character = 1 }, // 'a'
        .{ .character = 2 }, // 'b'
        .{ .character = 3 }, // 'c'
        .{ .character_class_close = 4 }, // ']'
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-char-class-empty" {
    // Empty character class [] is technically invalid in most regex engines,
    // but we should handle it gracefully
    var tokenizer: RegExpTokenizer = .{};
    const src = "[]";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character_class_open = .{ .negated = false, .span = .{ .start = 0, .end = 1 } } }, // '['
        .{ .character_class_close = 1 }, // ']'
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-char-class-negated" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "[^abc]";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{
            .character_class_open = .{
                .negated = true,
                .span = .{ .start = 0, .end = 2 },
            },
        }, // '[^'
        .{ .character = 2 }, // 'a'
        .{ .character = 3 }, // 'b'
        .{ .character = 4 }, // 'c'
        .{ .character_class_close = 5 }, // ']'
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-char-class-negated-empty" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "[^]";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{
            .character_class_open = .{
                .negated = true,
                .span = .{ .start = 0, .end = 2 },
            },
        }, // '[^'
        .{ .character_class_close = 2 }, // ']'
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-char-class-range-simple" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "[a-z]";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character_class_open = .{ .negated = false, .span = .{ .start = 0, .end = 1 } } }, // '['
        .{ .character_class_range = .{ .low = 1, .high = 3 } }, // 'a-z'
        .{ .character_class_close = 4 }, // ']'
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-char-class-range-multiple" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "[a-zA-Z0-9]";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character_class_open = .{ .negated = false, .span = .{ .start = 0, .end = 1 } } }, // '['
        .{ .character_class_range = .{ .low = 1, .high = 3 } }, // 'a-z'
        .{ .character_class_range = .{ .low = 4, .high = 6 } }, // 'A-Z'
        .{ .character_class_range = .{ .low = 7, .high = 9 } }, // '0-9'
        .{ .character_class_close = 10 }, // ']'
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-char-class-dash-at-start" {
    // Dash at the start is literal, not a range
    var tokenizer: RegExpTokenizer = .{};
    const src = "[-abc]";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character_class_open = .{ .negated = false, .span = .{ .start = 0, .end = 1 } } }, // '['
        .{ .character = 1 }, // '-' (literal)
        .{ .character = 2 }, // 'a'
        .{ .character = 3 }, // 'b'
        .{ .character = 4 }, // 'c'
        .{ .character_class_close = 5 }, // ']'
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-char-class-dash-at-end" {
    // Dash at the end is literal, not a range
    var tokenizer: RegExpTokenizer = .{};
    const src = "[abc-]";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character_class_open = .{ .negated = false, .span = .{ .start = 0, .end = 1 } } }, // '['
        .{ .character = 1 }, // 'a'
        .{ .character = 2 }, // 'b'
        .{ .character = 3 }, // 'c'
        .{ .character = 4 }, // '-' (literal)
        .{ .character_class_close = 5 }, // ']'
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-char-class-dash-only" {
    // Single dash inside brackets is literal
    var tokenizer: RegExpTokenizer = .{};
    const src = "[-]";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character_class_open = .{ .negated = false, .span = .{ .start = 0, .end = 1 } } }, // '['
        .{ .character = 1 }, // '-' (literal)
        .{ .character_class_close = 2 }, // ']'
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-char-class-bracket-close-first" {
    // First character after '[' or '[^' can be ']' as a literal
    var tokenizer: RegExpTokenizer = .{};
    const src = "[]]";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character_class_open = .{ .negated = false, .span = .{ .start = 0, .end = 1 } } }, // '['
        .{ .character = 1 }, // ']' (literal, first char)
        .{ .character_class_close = 2 }, // ']' (closes class)
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-char-class-bracket-close-first-negated" {
    // '[^]' followed by more characters
    var tokenizer: RegExpTokenizer = .{};
    const src = "[^]a]";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{
            .character_class_open = .{
                .negated = true,
                .span = .{ .start = 0, .end = 2 },
            },
        }, // '[^'
        .{ .character = 2 }, // ']' (literal, first char after ^)
        .{ .character = 3 }, // 'a'
        .{ .character_class_close = 4 }, // ']' (closes class)
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-char-class-escaped-bracket" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "[a\\]b]";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character_class_open = .{ .negated = false, .span = .{ .start = 0, .end = 1 } } }, // '['
        .{ .character = 1 }, // 'a'
        .{ .escape_sequence = .{ .kind = .literal_bracket_close, .span = .{ .start = 2, .end = 4 } } },
        .{ .character = 4 }, // 'b'
        .{ .character_class_close = 5 }, // ']'
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-char-class-escaped-dash" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "[a\\-b]";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character_class_open = .{ .negated = false, .span = .{ .start = 0, .end = 1 } } }, // '['
        .{ .character = 1 }, // 'a'
        .{ .escape_sequence = .{ .kind = .literal_dash, .span = .{ .start = 2, .end = 4 } } },
        .{ .character = 4 }, // 'b'
        .{ .character_class_close = 5 }, // ']'
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-char-class-escape-sequences" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "[\\d\\w\\s]";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character_class_open = .{ .negated = false, .span = .{ .start = 0, .end = 1 } } }, // '['
        .{ .escape_sequence = .{ .kind = .digit, .span = .{ .start = 1, .end = 3 } } },
        .{ .escape_sequence = .{ .kind = .word, .span = .{ .start = 3, .end = 5 } } },
        .{ .escape_sequence = .{ .kind = .whitespace, .span = .{ .start = 5, .end = 7 } } },
        .{ .character_class_close = 7 }, // ']'
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-char-class-special-chars-literal" {
    // Inside character class, most special regex chars are literal
    var tokenizer: RegExpTokenizer = .{};
    const src = "[.()+*?{}|]";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character_class_open = .{ .negated = false, .span = .{ .start = 0, .end = 1 } } }, // '['
        .{ .character = 1 }, // '.'
        .{ .character = 2 }, // '('
        .{ .character = 3 }, // ')'
        .{ .character = 4 }, // '+'
        .{ .character = 5 }, // '*'
        .{ .character = 6 }, // '?'
        .{ .character = 7 }, // '{'
        .{ .character = 8 }, // '}'
        .{ .character = 9 }, // '|'
        .{ .character_class_close = 10 }, // ']'
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-char-class-caret-not-at-start" {
    // Caret not at the start is a literal character
    var tokenizer: RegExpTokenizer = .{};
    const src = "[a^b]";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character_class_open = .{ .negated = false, .span = .{ .start = 0, .end = 1 } } }, // '['
        .{ .character = 1 }, // 'a'
        .{ .character = 2 }, // '^' (literal, not negation)
        .{ .character = 3 }, // 'b'
        .{ .character_class_close = 4 }, // ']'
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-char-class-with-quantifier" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "[a-z]+";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character_class_open = .{ .negated = false, .span = .{ .start = 0, .end = 1 } } }, // '['
        .{ .character_class_range = .{ .low = 1, .high = 3 } }, // 'a-z'
        .{ .character_class_close = 4 }, // ']'
        .{ .quantifier = .{ .kind = .one_or_more, .lazy = false, .span = .{ .start = 5, .end = 6 } } },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-char-class-in-context" {
    // Character class in a full pattern
    var tokenizer: RegExpTokenizer = .{};
    const src = "^[a-z]+@[a-z]+\\.[a-z]{2,4}$";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .anchor = .{ .kind = .start, .pos = 0 } },
        .{ .character_class_open = .{ .negated = false, .span = .{ .start = 1, .end = 2 } } },
        .{ .character_class_range = .{ .low = 2, .high = 4 } }, // 'a-z'
        .{ .character_class_close = 5 },
        .{ .quantifier = .{ .kind = .one_or_more, .lazy = false, .span = .{ .start = 6, .end = 7 } } },
        .{ .character = 7 }, // '@'
        .{ .character_class_open = .{ .negated = false, .span = .{ .start = 8, .end = 9 } } },
        .{ .character_class_range = .{ .low = 9, .high = 11 } }, // 'a-z'
        .{ .character_class_close = 12 },
        .{ .quantifier = .{ .kind = .one_or_more, .lazy = false, .span = .{ .start = 13, .end = 14 } } },
        .{ .escape_sequence = .{ .kind = .literal_dot, .span = .{ .start = 14, .end = 16 } } },
        .{ .character_class_open = .{ .negated = false, .span = .{ .start = 16, .end = 17 } } },
        .{ .character_class_range = .{ .low = 17, .high = 19 } }, // 'a-z'
        .{ .character_class_close = 20 },
        .{
            .quantifier = .{
                .kind = .{ .range_count = .{
                    .{ .start = 22, .end = 23 },
                    .{ .start = 24, .end = 25 },
                } },
                .lazy = false,
                .span = .{ .start = 21, .end = 26 },
            },
        },
        .{ .anchor = .{ .kind = .end, .pos = 26 } },
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}

test "regexp-char-class-unclosed" {
    // Unclosed character class should produce an error
    var tokenizer: RegExpTokenizer = .{};
    const src = "[abc";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    // Should get character_class_open, then characters, then an error for unclosed bracket
    try testing.expect(actual.items.len >= 4);
    try testing.expectEqual(Token.character_class_open, @as(std.meta.Tag(Token), actual.items[0]));
    try testing.expectEqual(Token.parse_error, @as(std.meta.Tag(Token), actual.items[actual.items.len - 1]));
}

test "regexp-char-class-range-mixed-with-literals" {
    var tokenizer: RegExpTokenizer = .{};
    const src = "[a-cx-z123]";
    var actual: std.ArrayList(Token) = .{};
    defer actual.deinit(testing.allocator);
    while (tokenizer.next(src)) |got| {
        try actual.append(testing.allocator, got);
    }
    const expected = [_]Token{
        .{ .character_class_open = .{ .negated = false, .span = .{ .start = 0, .end = 1 } } }, // '['
        .{ .character_class_range = .{ .low = 1, .high = 3 } }, // 'a-c'
        .{ .character_class_range = .{ .low = 4, .high = 6 } }, // 'x-z'
        .{ .character = 7 }, // '1'
        .{ .character = 8 }, // '2'
        .{ .character = 9 }, // '3'
        .{ .character_class_close = 10 }, // ']'
    };
    try testing.expectEqualSlices(Token, &expected, actual.items);
}
