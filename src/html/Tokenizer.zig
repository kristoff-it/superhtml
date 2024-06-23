// From https://github.com/marler8997/html-css-renderer/blob/master/HtmlTokenizer.zig
///
/// An html5 tokenizer.
/// Implements the state machine described here:
///     https://html.spec.whatwg.org/multipage/parsing.html#tokenization
/// This tokenizer does not perform any processing/allocation, it simply
/// splits the input text into higher-level tokens.
const Tokenizer = @This();

const std = @import("std");

const log = std.log.scoped(.tokenizer);

return_attrs: bool = false,
idx: u32 = 0,
current: u8 = undefined,
state: State = .data,
deferred_token: ?Token = null,

const DOCTYPE = "DOCTYPE";
const form_feed = 0xc;

pub const Span = struct {
    start: u32,
    end: u32,
    pub fn slice(self: Span, src: []const u8) []const u8 {
        return src[self.start..self.end];
    }
};

pub const TokenError = enum {
    abrupt_closing_of_empty_comment,
    eof_before_tag_name,
    eof_in_attribute_value,
    eof_in_comment,
    eof_in_doctype,
    eof_in_tag,
    incorrectly_opened_comment,
    invalid_first_character_of_tag_name,
    missing_attribute_value,
    missing_end_tag_name,
    missing_whitespace_before_doctype_name,
    missing_whitespace_between_attributes,
    unexpected_character_in_attribute_name,
    unexpected_character_in_unquoted_attribute_value,
    unexpected_equals_sign_before_attribute_name,
    unexpected_null_character,
    unexpected_solidus_in_tag,
};

pub const Token = union(enum) {
    // Only returned when return_attrs == true
    tag_name: Span,
    attr: struct {
        // NOTE: process the name_raw by replacing
        //     - upper-case ascii alpha with lower case (add 0x20)
        //     - 0 with U+FFFD
        name_raw: Span,
        // NOTE: process value...somehow...
        value_raw: ?struct {
            quote: enum { none, single, double },
            span: Span,
        },
    },

    // Returned during normal operation
    doctype: Doctype,
    tag: Tag,
    start_tag_self_closed: Span,

    comment: Span,
    text: Span,
    parse_error: struct {
        tag: TokenError,
        span: Span,
    },

    pub const Doctype = struct {
        // NOTE: process name_raw by replacing
        //     - upper-case ascii alpha with lower case (add 0x20)
        //     - 0 with U+FFFD
        lbracket: u32, // index of "<"
        name_raw: ?Span,
        force_quirks: bool,
        //public_id: usize,
        //system_id: usize,
    };

    pub const Tag = struct {
        span: Span,
        name: Span,
        kind: enum {
            start,
            start_attrs,
            end,
        },

        pub fn isVoid(st: @This(), src: []const u8) bool {
            const void_tags: []const []const u8 = &.{
                "area", "base",   "br",
                "col",  "embed",  "hr",
                "img",  "input",  "link",
                "meta", "source", "track",
                "wbr",
            };

            for (void_tags) |t| {
                if (std.ascii.eqlIgnoreCase(st.name.slice(src), t)) {
                    return true;
                }
            }
            return false;
        }
    };
};

const State = union(enum) {
    data: void,
    text: struct {
        start: u32,
        whitespace_only: bool = true,
        whitespace_streak: u32 = 0,
    },

    tag_open: u32,
    end_tag_open: u32,
    character_reference: void,
    markup_declaration_open: u32,
    doctype: u32,
    before_doctype_name: u32,
    doctype_name: struct {
        lbracket: u32,
        name_offset: u32,
    },
    after_doctype_name: struct {
        lbracket: u32,
        name_offset: u32,
        name_limit: u32,
    },
    comment_start: u32,
    comment_start_dash: void,
    comment: u32,
    comment_end_dash: Span,
    comment_end: Span,
    tag_name: Token.Tag,
    self_closing_start_tag: void,
    before_attribute_name: Token.Tag,
    attribute_name: struct {
        tag: Token.Tag,
        name_start: u32,
    },
    after_attribute_name: struct {
        tag: Token.Tag,
        name_raw: Span,
    },
    before_attribute_value: struct {
        tag: Token.Tag,
        name_raw: Span,
        equal_sign: u32,
    },
    attribute_value: struct {
        tag: Token.Tag,
        quote: enum { double, single },
        name_raw: Span,
        value_start: u32,
    },
    attribute_value_unquoted: struct {
        tag: Token.Tag,
        name_raw: Span,
        value_start: u32,
    },
    after_attribute_value: struct {
        tag: Token.Tag,
        attr_value_end: u32,
    },
    bogus_comment: u32,
    eof: void,
};

fn consume(self: *Tokenizer, src: []const u8) bool {
    if (self.idx == src.len) {
        return false;
    }
    self.current = src[self.idx];
    self.idx += 1;
    return true;
}

pub fn next(self: *Tokenizer, src: []const u8) ?Token {
    if (self.deferred_token) |t| {
        const token_copy = t;
        self.deferred_token = null;
        return token_copy;
    }
    const result = self.next2(src) orelse return null;
    if (result.deferred) |d| {
        self.deferred_token = d;
    }
    return result.token;
}

fn next2(self: *Tokenizer, src: []const u8) ?struct {
    token: Token,
    deferred: ?Token = null,
} {
    while (true) {
        log.debug("{any}", .{self.state});
        switch (self.state) {
            .data => {
                if (!self.consume(src)) return null;
                switch (self.current) {
                    //'&' => {} we don't process character references in the tokenizer
                    '<' => self.state = .{ .tag_open = self.idx - 1 },
                    0 => {
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .unexpected_null_character,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                            // .deferred = .{
                            //     .char = .{
                            //         .start = self.idx - 1,
                            //         .end = self.idx,
                            //     },
                            // },
                        };
                    },
                    else => self.state = .{
                        .text = .{
                            .start = self.idx - 1,
                            .whitespace_only = std.ascii.isWhitespace(self.current),
                        },
                    },
                }
            },
            .text => {
                if (!self.consume(src)) {
                    defer self.state = .eof;
                    if (!self.state.text.whitespace_only) {
                        return .{
                            .token = .{
                                .text = .{
                                    .start = self.state.text.start,
                                    .end = self.idx - self.state.text.whitespace_streak,
                                },
                            },
                        };
                    }
                    return null;
                }
                switch (self.current) {
                    //'&' => {} we don't process character references in the tokenizer
                    '<' => {
                        defer self.state = .{ .tag_open = self.idx - 1 };
                        if (!self.state.text.whitespace_only) {
                            return .{
                                .token = .{
                                    .text = .{
                                        .start = self.state.text.start,
                                        .end = self.idx - 1 - self.state.text.whitespace_streak,
                                    },
                                },
                            };
                        }
                    },
                    0 => {
                        self.state = .data;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .unexpected_null_character,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                            // .deferred = .{
                            //     .text = .{
                            //         .start = text.start,
                            //         .end = self.idx,
                            //     },
                            // },
                        };
                    },
                    else => {
                        if (self.state.text.whitespace_only) {
                            self.state.text.start = self.idx - 1;
                            self.state.text.whitespace_only = std.ascii.isWhitespace(self.current);
                        } else {
                            if (std.ascii.isWhitespace(self.current)) {
                                self.state.text.whitespace_streak += 1;
                            } else {
                                self.state.text.whitespace_streak = 0;
                            }
                        }
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#tag-open-state
            .tag_open => |lbracket| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-before-tag-name parse error. Emit a U+003C LESS-THAN SIGN character token and an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_before_tag_name,
                                .span = .{
                                    .start = lbracket,
                                    .end = self.idx,
                                },
                            },
                        },
                        // .deferred = .{
                        //     .char = .{
                        //         .start = tag_open_start,
                        //         .end = self.idx,
                        //     },
                        // },
                    };
                }
                switch (self.current) {
                    // U+0021 EXCLAMATION MARK (!)
                    // Switch to the markup declaration open state.
                    '!' => self.state = .{
                        .markup_declaration_open = lbracket,
                    },

                    // U+002F SOLIDUS (/)
                    // Switch to the end tag open state.
                    '/' => self.state = .{
                        .end_tag_open = lbracket,
                    },
                    // U+003F QUESTION MARK (?)
                    // This is an unexpected-question-mark-instead-of-tag-name parse error. Create a comment token whose data is the empty string. Reconsume in the bogus comment state.
                    '?' => @panic("TODO: implement start_tag.question_mark"),
                    else => |c| if (isAsciiAlpha(c)) {
                        // ASCII alpha
                        // Create a new start tag token, set its tag name to the empty string. Reconsume in the tag name state.
                        self.state = .{
                            .tag_name = .{
                                .kind = .start,
                                .name = .{
                                    .start = self.idx - 1,
                                    .end = 0,
                                },
                                .span = .{
                                    .start = lbracket,
                                    .end = 0,
                                },
                            },
                        };
                    } else {
                        // Anything else
                        // This is an invalid-first-character-of-tag-name parse error. Emit a U+003C LESS-THAN SIGN character token. Reconsume in the data state.
                        self.state = .data;
                        self.idx -= 1;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .invalid_first_character_of_tag_name,
                                    .span = .{
                                        .start = self.idx,
                                        .end = self.idx + 1,
                                    },
                                },
                            },
                            // .deferred = .{
                            //     .char = .{
                            //         .start = tag_open_start,
                            //         .end = tag_open_start + 1,
                            //     },
                            // },
                        };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#end-tag-open-state
            .end_tag_open => |lbracket| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-before-tag-name parse error. Emit a U+003C LESS-THAN SIGN character token, a U+002F SOLIDUS character token and an end-of-file token.
                    self.state = .data;
                    self.idx -= 1;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_before_tag_name,
                                .span = .{
                                    .start = self.idx,
                                    .end = self.idx + 1,
                                },
                            },
                        },

                        // .deferred = .{
                        //     .char = .{
                        //         .start = tag_open_start,
                        //         .end = tag_open_start + 1,
                        //     },
                        // },
                    };
                }
                switch (self.current) {
                    // U+003E GREATER-THAN SIGN (>)
                    // This is a missing-end-tag-name parse error. Switch to the data state.
                    '>' => {
                        self.state = .data;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_end_tag_name,
                                    .span = .{
                                        .start = lbracket,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                    else => |c| if (isAsciiAlpha(c)) {
                        // ASCII alpha
                        // Create a new end tag token, set its tag name to the empty string. Reconsume in the tag name state.
                        self.state = .{
                            .tag_name = .{
                                .kind = .end,

                                .name = .{
                                    .start = self.idx - 1,
                                    .end = 0,
                                },
                                .span = .{
                                    .start = lbracket,
                                    .end = 0,
                                },
                            },
                        };
                    } else {
                        // Anything else
                        // This is an invalid-first-character-of-tag-name parse error. Create a comment token whose data is the empty string. Reconsume in the bogus comment state.
                        self.state = .{ .bogus_comment = self.idx - 1 };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .invalid_first_character_of_tag_name,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#tag-name-state
            .tag_name => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-tag parse error. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_tag,
                                .span = .{
                                    .start = state.span.start,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                }
                switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Switch to the before attribute name state.
                    '\t', '\n', form_feed, ' ' => {
                        var tag = state;
                        tag.name.end = self.idx - 1;
                        self.state = .{ .before_attribute_name = tag };

                        if (self.return_attrs) {
                            return .{ .token = .{ .tag_name = tag.name } };
                        }
                    },
                    // U+002F SOLIDUS (/)
                    // Switch to the self-closing start tag state.
                    '/' => self.state = .self_closing_start_tag,
                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the data state. Emit the current tag token.
                    '>' => {
                        var tag = state;
                        tag.name.end = self.idx - 1;
                        tag.span.end = self.idx;

                        self.state = .data;
                        if (self.return_attrs) {
                            return .{ .token = .{ .tag_name = tag.name } };
                        } else {
                            return .{ .token = .{ .tag = tag } };
                        }
                    },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current tag token's tag name.
                    0 => return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .unexpected_null_character,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                    },
                    // ASCII upper alpha
                    // Append the lowercase version of the current input character (add 0x0020 to the character's code point) to the current tag token's tag name.
                    // Anything else
                    // Append the current input character to the current tag token's tag name.
                    else => {},
                }
            },
            .self_closing_start_tag => {
                if (true) @panic("TODO");
                if (!self.consume(src)) {
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_tag,
                                .span = .{
                                    // TODO: report starting from the beginning of this tag
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                } else switch (self.current) {
                    '>' => {
                        self.state = .data;
                        return .{
                            .token = .{
                                // TODO: can we assume the start will be 2 bytes back?
                                .start_tag_self_closed = .{
                                    .start = self.idx - 2,
                                    .end = self.idx,
                                },
                            },
                        };
                    },
                    else => {
                        self.state = .{
                            .before_attribute_name = undefined,
                        };
                        self.idx -= 1;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .unexpected_solidus_in_tag,
                                    .span = .{
                                        .start = self.idx,
                                        .end = self.idx + 1,
                                    },
                                },
                            },
                        };
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#before-attribute-name-state
            .before_attribute_name => |state| {
                // See EOF case from below
                if (!self.consume(src)) {
                    self.idx -= 1;
                    self.state = .{
                        .after_attribute_name = .{
                            .tag = state,
                            .name_raw = .{
                                .start = self.idx,
                                .end = self.idx + 1,
                            },
                        },
                    };
                } else switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Ignore the character.
                    '\t', '\n', form_feed, ' ' => {},

                    // U+002F SOLIDUS (/)
                    // U+003E GREATER-THAN SIGN (>)
                    // EOF
                    // Reconsume in the after attribute name state.
                    //
                    // (EOF handled above)
                    '/', '>' => {
                        self.idx -= 1;
                        self.state = .{
                            .after_attribute_name = .{
                                .tag = state,
                                .name_raw = .{
                                    .start = self.idx,
                                    .end = self.idx + 1,
                                },
                            },
                        };
                    },

                    //U+003D EQUALS SIGN (=)
                    //This is an unexpected-equals-sign-before-attribute-name parse error. Start a new attribute in the current tag token. Set that attribute's name to the current input character, and its value to the empty string. Switch to the attribute name state.
                    '=' => {
                        self.state = .{
                            .attribute_name = .{
                                .tag = state,
                                .name_start = self.idx - 1,
                            },
                        };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .unexpected_equals_sign_before_attribute_name,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },

                    // Anything else
                    // Start a new attribute in the current tag token. Set that attribute name and value to the empty string. Reconsume in the attribute name state.
                    else => self.state = .{
                        .attribute_name = .{
                            .tag = state,
                            .name_start = self.idx - 1,
                        },
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#attribute-name-state
            .attribute_name => |state| {
                if (!self.consume(src)) {
                    self.idx -= 1;
                    self.state = .{
                        .after_attribute_name = .{
                            .tag = state.tag,
                            .name_raw = .{
                                .start = state.name_start,
                                .end = self.idx,
                            },
                        },
                    };
                } else switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // U+002F SOLIDUS (/)
                    // U+003E GREATER-THAN SIGN (>)
                    // EOF
                    // Reconsume in the after attribute name state.
                    '\t', '\n', form_feed, ' ', '/', '>' => {
                        self.idx -= 1;
                        self.state = .{
                            .after_attribute_name = .{
                                .tag = state.tag,
                                .name_raw = .{
                                    .start = state.name_start,
                                    .end = self.idx,
                                },
                            },
                        };
                    },

                    // U+003D EQUALS SIGN (=)
                    // Switch to the before attribute value state.
                    '=' => self.state = .{
                        .before_attribute_value = .{
                            .tag = state.tag,
                            .equal_sign = self.idx - 1,
                            .name_raw = .{
                                .start = state.name_start,
                                .end = self.idx - 1,
                            },
                        },
                    },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current attribute's name.
                    0 => return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .unexpected_null_character,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                    },
                    // U+0022 QUOTATION MARK (")
                    // U+0027 APOSTROPHE (')
                    // U+003C LESS-THAN SIGN (<)
                    // This is an unexpected-character-in-attribute-name parse error. Treat it as per the "anything else" entry below.
                    '"', '\'', '<' => return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .unexpected_character_in_attribute_name,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                    },
                    // ASCII upper alpha
                    // Append the lowercase version of the current input character (add 0x0020 to the character's code point) to the current attribute's name.
                    // Anything else
                    // Append the current input character to the current attribute's name.
                    else => {},
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#after-attribute-name-state
            .after_attribute_name => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-tag parse error. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_tag,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                } else switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Ignore the character.
                    '\t', '\n', form_feed, ' ' => {},
                    // U+002F SOLIDUS (/)
                    // Switch to the self-closing start tag state.
                    '/' => self.state = .self_closing_start_tag,
                    // U+003D EQUALS SIGN (=)
                    // Switch to the before attribute value state.
                    '=' => self.state = .{
                        .before_attribute_value = .{
                            .tag = state.tag,
                            .name_raw = state.name_raw,
                            .equal_sign = self.idx - 1,
                        },
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the data state. Emit the current tag token.
                    '>' => {
                        var tag = state.tag;
                        tag.span.end = self.idx + 1;

                        self.state = .data;
                        if (self.return_attrs) {
                            return .{
                                .token = .{
                                    .attr = .{
                                        .name_raw = state.name_raw,
                                        .value_raw = null,
                                    },
                                },
                            };
                        } else {
                            return .{ .token = .{ .tag = tag } };
                        }
                    },
                    // Anything else
                    // Start a new attribute in the current tag token. Set that attribute name and value to the empty string. Reconsume in the attribute name state.
                    else => {
                        if (self.return_attrs) {
                            return .{
                                .token = .{
                                    .attr = .{
                                        .name_raw = state.name_raw,
                                        .value_raw = null,
                                    },
                                },
                            };
                        }

                        self.idx -= 1;
                        self.state = .{
                            .attribute_name = .{
                                .tag = state.tag,
                                .name_start = self.idx,
                            },
                        };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#before-attribute-value-state
            .before_attribute_value => |state| {
                if (!self.consume(src)) {
                    self.idx -= 1;
                    self.state = .{
                        .attribute_value_unquoted = .{
                            .tag = state.tag,
                            .name_raw = state.name_raw,
                            .value_start = self.idx,
                        },
                    };
                } else switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Ignore the character.
                    '\t', '\n', form_feed, ' ' => {},
                    // U+0022 QUOTATION MARK (")
                    // Switch to the attribute value (double-quoted) state.
                    '"' => self.state = .{
                        .attribute_value = .{
                            .tag = state.tag,
                            .name_raw = state.name_raw,
                            .quote = .double,
                            .value_start = self.idx,
                        },
                    },
                    // U+0027 APOSTROPHE (')
                    // Switch to the attribute value (single-quoted) state.
                    '\'' => self.state = .{
                        .attribute_value = .{
                            .tag = state.tag,
                            .name_raw = state.name_raw,
                            .quote = .single,
                            .value_start = self.idx,
                        },
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // This is a missing-attribute-value parse error. Switch to the data state. Emit the current tag token.
                    '>' => {
                        var tag = state.tag;
                        tag.span.end = self.idx;

                        self.state = .data;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_attribute_value,
                                    .span = .{
                                        .start = state.equal_sign,
                                        .end = state.equal_sign + 1,
                                    },
                                },
                            },
                            .deferred = .{ .tag = tag },
                        };
                    },
                    // Anything else
                    // Reconsume in the attribute value (unquoted) state.
                    //
                    // (EOF handled above)
                    else => {
                        self.idx -= 1;
                        self.state = .{
                            .attribute_value_unquoted = .{
                                .tag = state.tag,
                                .name_raw = state.name_raw,
                                .value_start = self.idx,
                            },
                        };
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#attribute-value-(double-quoted)-state
            // https://html.spec.whatwg.org/multipage/parsing.html#attribute-value-(single-quoted)-state
            .attribute_value => |state| {
                if (!self.consume(src)) {
                    self.state = .eof;

                    // EOF
                    // This is an eof-in-tag parse error. Emit an end-of-file token.
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_attribute_value,
                                .span = .{
                                    .start = state.value_start,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                } else switch (self.current) {
                    // U+0022 QUOTATION MARK (")
                    // Switch to the after attribute value (quoted) state.
                    '"' => switch (state.quote) {
                        .single => {
                            // Just a normal char in this case
                        },
                        .double => {
                            self.state = .{
                                .after_attribute_value = .{
                                    .tag = state.tag,
                                    .attr_value_end = self.idx,
                                },
                            };
                            if (self.return_attrs) {
                                return .{
                                    .token = .{
                                        .attr = .{
                                            .name_raw = state.name_raw,
                                            .value_raw = .{
                                                .quote = .double,
                                                .span = .{
                                                    .start = state.value_start,
                                                    .end = self.idx - 1,
                                                },
                                            },
                                        },
                                    },
                                };
                            }
                        },
                    },

                    // U+0027 APOSTROPHE (')
                    // Switch to the after attribute value (quoted) state.
                    '\'' => switch (state.quote) {
                        .double => {
                            // Just a normal char in this case
                        },
                        .single => {
                            self.state = .{
                                .after_attribute_value = .{
                                    .tag = state.tag,
                                    .attr_value_end = self.idx,
                                },
                            };
                            if (self.return_attrs) {
                                return .{
                                    .token = .{
                                        .attr = .{
                                            .name_raw = state.name_raw,
                                            .value_raw = .{
                                                .quote = .single,
                                                .span = .{
                                                    .start = state.value_start,
                                                    .end = self.idx - 1,
                                                },
                                            },
                                        },
                                    },
                                };
                            }
                        },
                    },
                    // U+0026 AMPERSAND (&)
                    // Set the return state to the attribute value (double-quoted) state. Switch to the character reference state.
                    //
                    // (handled downstream)
                    // '&' => {},

                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current attribute's value.
                    0 => return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .unexpected_null_character,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                    },
                    // Anything else
                    // Append the current input character to the current attribute's value.
                    else => {},
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#attribute-value-(unquoted)-state
            .attribute_value_unquoted => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-tag parse error. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_tag,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                } else switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Switch to the before attribute name state.
                    '\t', '\n', form_feed, ' ' => {
                        if (self.return_attrs) {
                            return .{
                                .token = .{
                                    .attr = .{
                                        .name_raw = state.name_raw,
                                        .value_raw = .{
                                            .quote = .single,
                                            .span = .{
                                                .start = state.value_start,
                                                .end = self.idx - 1,
                                            },
                                        },
                                    },
                                },
                            };
                        }
                        self.state = .{ .before_attribute_name = state.tag };
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the data state. Emit the current tag token.
                    '>' => {
                        var tag = state.tag;
                        tag.span.end = self.idx;

                        self.state = .data;

                        if (self.return_attrs) {
                            return .{
                                .token = .{
                                    .attr = .{
                                        .name_raw = state.name_raw,
                                        .value_raw = .{
                                            .quote = .single,
                                            .span = .{
                                                .start = state.value_start,
                                                .end = self.idx - 1,
                                            },
                                        },
                                    },
                                },
                            };
                        } else {
                            return .{ .token = .{ .tag = tag } };
                        }
                    },

                    // U+0026 AMPERSAND (&)
                    // Set the return state to the attribute value (unquoted) state. Switch to the character reference state.
                    //
                    // (handled elsewhere)
                    //'&' => {},

                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current attribute's value.
                    0 => return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .unexpected_null_character,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                    },
                    // U+0022 QUOTATION MARK (")
                    // U+0027 APOSTROPHE (')
                    // U+003C LESS-THAN SIGN (<)
                    // U+003D EQUALS SIGN (=)
                    // U+0060 GRAVE ACCENT (`)
                    // This is an unexpected-character-in-unquoted-attribute-value parse error. Treat it as per the "anything else" entry below.
                    '"', '\'', '<', '=', '`' => {
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .unexpected_character_in_unquoted_attribute_value,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                    // Anything else
                    // Append the current input character to the current attribute's value.
                    else => {},
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#after-attribute-value-(quoted)-state

            .after_attribute_value => |state| {
                if (!self.consume(src)) {
                    self.state = .eof;
                    // EOF
                    // This is an eof-in-tag parse error. Emit an end-of-file token.
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_tag,
                                .span = .{
                                    .start = state.attr_value_end,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                } else switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Switch to the before attribute name state.
                    '\t', '\n', form_feed, ' ' => self.state = .{
                        .before_attribute_name = state.tag,
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the data state. Emit the current tag token.
                    '>' => {
                        var tag = state.tag;
                        tag.span.end = self.idx;

                        self.state = .data;
                        return .{ .token = .{ .tag = tag } };
                    },
                    // U+002F SOLIDUS (/)
                    // Switch to the self-closing start tag state.
                    '/' => self.state = .self_closing_start_tag,
                    // Anything else
                    // This is a missing-whitespace-between-attributes parse error. Reconsume in the before attribute name state.
                    else => {
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_whitespace_between_attributes,
                                    .span = .{
                                        .start = state.attr_value_end,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                }
            },
            .markup_declaration_open => |lbracket| {
                if (self.nextCharsAre("--", src)) {
                    self.idx += 2;
                    self.state = .{
                        .comment_start = self.idx,
                    };
                } else if (self.nextCharsAreIgnoreCase(DOCTYPE, src)) {
                    self.idx += @intCast(DOCTYPE.len);
                    self.state = .{ .doctype = lbracket };
                } else if (self.nextCharsAre("[CDATA[", src)) {
                    @panic("TODO: implement CDATA");
                } else {
                    self.state = .{ .bogus_comment = self.idx - 1 };
                    return .{ .token = .{
                        .parse_error = .{
                            .tag = .incorrectly_opened_comment,
                            .span = .{
                                .start = self.idx - 1,
                                .end = self.idx,
                            },
                        },
                    } };
                }
            },
            .character_reference => {
                @panic("TODO: implement character reference");
            },
            .doctype => |lbracket| {
                if (!self.consume(src)) {
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_doctype,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                        .deferred = .{
                            .doctype = .{
                                .lbracket = lbracket,
                                .force_quirks = true,
                                .name_raw = null,
                            },
                        },
                    };
                }
                switch (self.current) {
                    '\t', '\n', form_feed, ' ' => self.state = .{
                        .before_doctype_name = lbracket,
                    },
                    '>' => {
                        self.idx -= 1;
                        self.state = .{
                            .before_doctype_name = lbracket,
                        };
                    },
                    else => {
                        self.idx -= 1;
                        self.state = .{
                            .before_doctype_name = lbracket,
                        };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_whitespace_before_doctype_name,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                }
            },
            .before_doctype_name => |lbracket| {
                if (!self.consume(src)) {
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_doctype,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                        .deferred = .{
                            .doctype = .{
                                .lbracket = lbracket,
                                .force_quirks = true,
                                .name_raw = null,
                            },
                        },
                    };
                }
                switch (self.current) {
                    '\t', '\n', form_feed, ' ' => {},
                    0 => {
                        self.state = .{
                            .doctype_name = .{
                                .lbracket = lbracket,
                                .name_offset = self.idx - 1,
                            },
                        };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .unexpected_null_character,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                    '>' => {
                        self.idx -= 1;
                        self.state = .data;
                        return .{
                            .token = .{
                                .doctype = .{
                                    .lbracket = lbracket,
                                    .force_quirks = true,
                                    .name_raw = null,
                                },
                            },
                        };
                    },
                    else => {
                        // NOTE: same thing for isAsciiAlphaUpper since we post-process the name
                        self.state = .{
                            .doctype_name = .{
                                .lbracket = lbracket,
                                .name_offset = self.idx - 1,
                            },
                        };
                    },
                }
            },
            .doctype_name => |doctype_state| {
                if (!self.consume(src)) {
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_doctype,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                        .deferred = .{
                            .doctype = .{
                                .lbracket = 0, //todo
                                .force_quirks = true,
                                .name_raw = null,
                            },
                        },
                    };
                }
                switch (self.current) {
                    '\t', '\n', form_feed, ' ' => {
                        self.state = .{
                            .after_doctype_name = .{
                                .lbracket = doctype_state.lbracket,
                                .name_offset = doctype_state.name_offset,
                                .name_limit = self.idx - 1,
                            },
                        };
                    },
                    '>' => {
                        self.state = .data;
                        return .{
                            .token = .{
                                .doctype = .{
                                    .lbracket = doctype_state.lbracket,
                                    .name_raw = .{
                                        .start = doctype_state.name_offset,
                                        .end = self.idx - 1,
                                    },
                                    .force_quirks = false,
                                },
                            },
                        };
                    },
                    0 => return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .unexpected_null_character,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                    },
                    else => {},
                }
            },
            .after_doctype_name => {
                @panic("TODO: implement after_doctype_name");
            },
            .comment_start => |comment_start| {
                if (!self.consume(src)) {
                    self.idx -= 1;
                    self.state = .{ .comment = comment_start };
                } else switch (self.current) {
                    '-' => self.state = .comment_start_dash,
                    '>' => {
                        self.state = .data;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .abrupt_closing_of_empty_comment,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                    else => {
                        self.idx -= 1;
                        self.state = .{ .comment = comment_start };
                    },
                }
            },
            .comment_start_dash => {
                @panic("TODO: implement comment_start_dash");
            },
            .comment => |comment_start| {
                if (!self.consume(src)) {
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_comment,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                        .deferred = .{
                            .comment = .{
                                .start = comment_start,
                                .end = self.idx,
                            },
                        },
                    };
                }
                switch (self.current) {
                    '<' => @panic("TODO"),
                    '-' => self.state = .{
                        .comment_end_dash = .{
                            .start = comment_start,
                            .end = self.idx - 1,
                        },
                    },
                    0 => @panic("TODO"),
                    else => {},
                }
            },
            .comment_end_dash => |comment_span| {
                if (!self.consume(src)) {
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_comment,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                        .deferred = .{ .comment = comment_span },
                    };
                }
                switch (self.current) {
                    '-' => self.state = .{ .comment_end = comment_span },
                    else => {
                        self.idx -= 1;
                        self.state = .{ .comment = comment_span.start };
                    },
                }
            },
            .comment_end => |comment_span| {
                if (!self.consume(src)) {
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_comment,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                        .deferred = .{ .comment = comment_span },
                    };
                }
                switch (self.current) {
                    '>' => {
                        self.state = .data;
                        return .{ .token = .{ .comment = comment_span } };
                    },
                    '!' => @panic("TODO"),
                    '-' => @panic("TODO"),
                    else => @panic("TODO"),
                }
            },
            // 13.2.5.41 Bogus comment state
            .bogus_comment => |start| {
                if (!self.consume(src)) {
                    // EOF
                    // Emit the comment. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .comment = .{
                                .start = start,
                                .end = self.idx,
                            },
                        },
                    };
                }
                switch (self.current) {
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error.
                    0 => return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .unexpected_null_character,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the data state. Emit the current comment token.
                    '>' => {
                        self.state = .data;
                        return .{
                            .token = .{
                                .comment = .{
                                    .start = start,
                                    .end = self.idx,
                                },
                            },
                        };
                    },
                    else => {},
                }
            },
            .eof => return null,
        }
    }
}

fn nextCharsAre(self: Tokenizer, needle: []const u8, src: []const u8) bool {
    return std.mem.startsWith(u8, src[self.idx..], needle);
}

fn nextCharsAreIgnoreCase(self: Tokenizer, needle: []const u8, src: []const u8) bool {
    return std.ascii.startsWithIgnoreCase(src[self.idx..], needle);
}

fn isAsciiAlphaLower(c: u8) bool {
    return (c >= 'a' and c <= 'z');
}
fn isAsciiAlphaUpper(c: u8) bool {
    return (c >= 'A' and c <= 'Z');
}
fn isAsciiAlpha(c: u8) bool {
    return isAsciiAlphaLower(c) or isAsciiAlphaUpper(c);
}
