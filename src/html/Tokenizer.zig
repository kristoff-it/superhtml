///! A HTML5 tokenizer.
///! Implements the state machine described here:
///!     https://html.spec.whatwg.org/multipage/parsing.html#tokenization
///! This tokenizer does not perform any processing/allocation, it simply
///! splits the input text into higher-level tokens.
///!
///! As it's main usecase is powering developer tooling for handwritten
///! HTML, on occasion i'ts more strict than the official spec in order
///! to catch common mistakes.
const Tokenizer = @This();
const named_character_references = @import("named_character_references.zig");

const std = @import("std");
const root = @import("../root.zig");
const Language = root.Language;
const Span = root.Span;

const log = std.log.scoped(.@"html/tokenizer");
const form_feed = std.ascii.control_code.ff;

language: Language,
return_attrs: bool = false,
idx: u32 = 0,
current: u8 = undefined,
state: State = .data,
deferred_token: ?Token = null,
last_start_tag_name: []const u8 = "",

const TagNameMap = std.StaticStringMapWithEql(
    void,
    std.static_string_map.eqlAsciiIgnoreCase,
);
const super_void_tag_names = TagNameMap.initComptime(.{
    .{ "extend", {} },
    .{ "super", {} },
});
const void_tag_names = TagNameMap.initComptime(.{
    .{ "area", {} },
    .{ "base", {} },
    .{ "br", {} },
    .{ "col", {} },
    .{ "embed", {} },
    .{ "hr", {} },
    .{ "img", {} },
    .{ "input", {} },
    .{ "link", {} },
    .{ "meta", {} },
    .{ "source", {} },
    .{ "track", {} },
    .{ "wbr", {} },
});

pub const TokenError = enum {
    abrupt_closing_of_empty_comment,
    abrupt_doctype_public_identifier,
    abrupt_doctype_system_identifier,

    end_tag_with_trailing_solidus,
    eof_before_tag_name,
    eof_in_attribute_value,
    eof_in_cdata,
    eof_in_comment,
    eof_in_doctype,
    eof_in_script_html_comment_like_text,
    eof_in_tag,

    incorrectly_opened_comment,
    incorrectly_closed_comment,

    invalid_character_sequence_after_doctype_name,
    invalid_first_character_of_tag_name,
    missing_attribute_value,
    missing_doctype_name,
    missing_doctype_public_identifier,
    missing_doctype_system_identifier,
    missing_end_tag_name,
    missing_quote_before_doctype_public_identifier,

    missing_quote_before_doctype_system_identifier,
    missing_whitespace_after_doctype_public_keyword,
    missing_whitespace_after_doctype_system_keyword,
    missing_whitespace_before_doctype_name,
    missing_whitespace_between_attributes,
    missing_whitespace_between_doctype_public_and_system_identifiers,

    nested_comment,

    unexpected_character_after_doctype_system_identifier,
    unexpected_character_in_attribute_name,
    unexpected_character_in_unquoted_attribute_value,
    unexpected_equals_sign_before_attribute_name,
    unexpected_null_character,
    unexpected_solidus_in_tag,

    missing_semicolon_after_character_reference,
    unknown_named_character_reference,
    absence_of_digits_in_numeric_character_reference,
    null_character_reference,
    character_reference_outside_unicode_range,
    surrogate_character_reference,
    noncharacter_character_reference,
    control_character_reference,
};

pub const Attr = struct {
    name: Span,
    value: ?Value,

    pub fn span(attr: Attr) Span {
        if (attr.value) |v| {
            return .{
                .start = attr.name.start,
                .end = v.span.end,
            };
        }

        return attr.name;
    }

    pub const Value = struct {
        quote: enum { none, single, double },
        span: Span,

        pub const UnescapedSlice = struct {
            must_free: bool = false,
            slice: []const u8 = &.{},

            pub fn deinit(
                self: UnescapedSlice,
                allocator: std.mem.Allocator,
            ) void {
                if (self.must_free) allocator.free(self.slice);
            }
        };

        pub fn unescape(
            value: Value,
            gpa: std.mem.Allocator,
            src: []const u8,
        ) !UnescapedSlice {
            _ = gpa;
            // TODO: sqeek-senpai please implement this for real
            return .{ .slice = value.span.slice(src) };
        }
    };
};

pub const Token = union(enum) {
    // Only returned when return_attrs == true
    tag_name: Span,
    attr: Attr,

    // Returned during normal operation
    doctype: Doctype,
    tag: Tag,

    comment: Span,
    text: Span,
    parse_error: struct {
        tag: TokenError,
        span: Span,
    },

    pub const Doctype = struct {
        span: Span,
        name: ?Span,
        extra: Span = .{ .start = 0, .end = 0 },
        force_quirks: bool,
    };

    pub const Tag = struct {
        span: Span,
        name: Span,
        attr_count: u32 = 0,
        kind: enum {
            start,
            start_self,
            end,
            end_self,
        },

        pub fn isVoid(st: @This(), src: []const u8, language: Language) bool {
            std.debug.assert(st.name.end != 0);

            if (language == .superhtml) {
                if (super_void_tag_names.has(st.name.slice(src))) {
                    return true;
                }
            }

            if (void_tag_names.has(st.name.slice(src))) {
                return true;
            }

            return false;
        }
    };
};

const Data = struct {
    data_start: u32,
    tag_start: u32,
    name_start: u32 = 0,
};
const State = union(enum) {
    text: struct {
        start: u32,
        whitespace_only: bool = true,
        whitespace_streak: u32 = 0,
    },

    data: void,
    rcdata: u32,
    rawtext: u32,
    script_data: u32,
    plaintext: u32,
    tag_open: u32,
    end_tag_open: u32,
    tag_name: Token.Tag,

    rcdata_less_than_sign: Data,
    rcdata_end_tag_open: Data,
    rcdata_end_tag_name: Data,

    rawtext_less_than_sign: Data,
    rawtext_end_tag_open: Data,
    rawtext_end_tag_name: Data,

    script_data_less_than_sign: Data,
    script_data_end_tag_open: Data,
    script_data_end_tag_name: Data,
    script_data_escape_start: Data,
    script_data_escape_start_dash: Data,
    script_data_escaped: Data,
    script_data_escaped_dash: Data,
    script_data_escaped_dash_dash: Data,
    script_data_escaped_less_than_sign: Data,
    script_data_escaped_end_tag_open: Data,
    script_data_escaped_end_tag_name: Data,
    script_data_double_escape_start: Data,
    script_data_double_escaped: Data,
    script_data_double_escaped_dash: Data,
    script_data_double_escaped_dash_dash: Data,
    script_data_double_escaped_less_than_sign: Data,
    script_data_double_escape_end: Data,

    character_reference: CharacterReferenceState,
    named_character_reference: CharacterReferenceState,
    ambiguous_ampersand: CharacterReferenceState,
    numeric_character_reference: NumericCharacterReferenceState,
    hexadecimal_character_reference_start: NumericCharacterReferenceState,
    decimal_character_reference_start: NumericCharacterReferenceState,
    hexadecimal_character_reference: NumericCharacterReferenceState,
    decimal_character_reference: NumericCharacterReferenceState,
    numeric_character_reference_end: NumericCharacterReferenceState,

    markup_declaration_open: u32,
    doctype: u32,
    before_doctype_name: u32,
    doctype_name: struct {
        lbracket: u32,
        name_start: u32,
    },
    after_doctype_name: struct {
        lbracket: u32,
        name: Span,
    },

    after_doctype_public_kw: Token.Doctype,
    before_doctype_public_identifier: Token.Doctype,
    doctype_public_identifier_double: Token.Doctype,
    doctype_public_identifier_single: Token.Doctype,
    after_doctype_public_identifier: Token.Doctype,

    beteen_doctype_public_and_system_identifiers: Token.Doctype,
    after_doctype_system_kw: Token.Doctype,

    before_doctype_system_identifier: Token.Doctype,
    doctype_system_identifier_double: Token.Doctype,
    doctype_system_identifier_single: Token.Doctype,
    after_doctype_system_identifier: Token.Doctype,

    comment_start: u32,
    comment_start_dash: u32,
    comment: u32,
    comment_less_than_sign: u32,
    comment_less_than_sign_bang: u32,
    comment_less_than_sign_bang_dash: u32,
    comment_less_than_sign_bang_dash_dash: u32,
    comment_end_dash: u32,
    comment_end: u32,
    comment_end_bang: u32,
    self_closing_start_tag: Token.Tag,
    before_attribute_name: Token.Tag,
    attribute_name: struct {
        tag: Token.Tag,
        name_start: u32,
    },
    after_attribute_name: struct {
        tag: Token.Tag,
        name: Span,
    },
    before_attribute_value: struct {
        tag: Token.Tag,
        name: Span,
        equal_sign: u32,
    },
    attribute_value: AttributeValueState,
    attribute_value_unquoted: AttributeValueUnquotedState,
    after_attribute_value: struct {
        tag: Token.Tag,
        attr_value_end: u32,
    },
    bogus_comment: u32,

    bogus_doctype: Token.Doctype,
    cdata_section: u32,
    cdata_section_bracket: u32,
    cdata_section_end: u32,

    eof: void,

    const AttributeValueState = struct {
        tag: Token.Tag,
        quote: enum { double, single },
        name: Span,
        value_start: u32,
    };

    const AttributeValueUnquotedState = struct {
        tag: Token.Tag,
        name: Span,
        value_start: u32,
    };

    const CharacterReferenceState = struct {
        ampersand: u32,
        return_state: union(enum) {
            text: u32,
            rcdata: u32,
            attribute_value: AttributeValueState,
            attribute_value_unquoted: AttributeValueUnquotedState,
        },

        pub fn getReturnState(self: CharacterReferenceState) State {
            switch (self.return_state) {
                .rcdata => |start| return .{
                    .rcdata = start,
                },
                .text => |start| return .{
                    .text = .{
                        .start = start,
                        // We can set whitespace_only to false unconditionally since
                        // the text will at least contain the ampersand character.
                        .whitespace_only = false,
                        // Also reset the streak for the same reason.
                        .whitespace_streak = 0,
                    },
                },
                .attribute_value => |state| return .{
                    .attribute_value = state,
                },
                .attribute_value_unquoted => |state| return .{
                    .attribute_value_unquoted = state,
                },
            }
        }
    };

    const NumericCharacterReferenceState = struct {
        code: u21,
        ref: CharacterReferenceState,
    };
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
            .text => |state| {
                if (!self.consume(src)) {
                    self.state = .eof;
                    if (!state.whitespace_only) {
                        return .{
                            .token = .{
                                .text = .{
                                    .start = state.start,
                                    .end = self.idx - state.whitespace_streak,
                                },
                            },
                        };
                    }
                    return null;
                } else switch (self.current) {
                    '&' => {
                        self.state = .{ .character_reference = .{
                            .ampersand = self.idx - 1,
                            .return_state = .{ .text = state.start },
                        } };
                    },
                    '<' => {
                        self.state = .{ .tag_open = self.idx - 1 };
                        if (!state.whitespace_only) {
                            return .{
                                .token = .{
                                    .text = .{
                                        .start = state.start,
                                        .end = self.idx - 1 - state.whitespace_streak,
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
                        };
                    },
                    else => {
                        if (state.whitespace_only) {
                            self.state.text.start = self.idx - 1;
                            self.state.text.whitespace_only = std.ascii.isWhitespace(
                                self.current,
                            );
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

            //https://html.spec.whatwg.org/multipage/parsing.html#data-state
            .data => {
                // EOF
                // Emit an end-of-file token.
                if (!self.consume(src)) {
                    self.state = .eof;
                    return null;
                } else switch (self.current) {
                    // U+0026 AMPERSAND (&)
                    // Set the return state to the data state. Switch to the character reference state.
                    '&' => {
                        self.state = .{
                            .character_reference = .{
                                .ampersand = self.idx - 1,
                                // When starting in the data state, we actually want to return to the
                                // text state since the character reference characters are emitted
                                // as text.
                                .return_state = .{ .text = self.idx - 1 },
                            },
                        };
                    },

                    // U+003C LESS-THAN SIGN (<)
                    // Switch to the tag open state.
                    '<' => self.state = .{ .tag_open = self.idx - 1 },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Emit the current input character as a character token.
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
                        };
                    },
                    // Anything else
                    // Emit the current input character as a character token.
                    else => self.state = .{
                        .text = .{
                            .start = self.idx - 1,
                            .whitespace_only = std.ascii.isWhitespace(self.current),
                        },
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#rcdata-state
            .rcdata => |start| {
                if (!self.consume(src)) {
                    // EOF
                    // Emit an end-of-file token.
                    self.state = .eof;
                    return null;
                } else switch (self.current) {
                    // U+0026 AMPERSAND (&)
                    // Set the return state to the RCDATA state. Switch to the character reference state.
                    '&' => {
                        self.state = .{
                            .character_reference = .{
                                .ampersand = self.idx - 1,
                                .return_state = .{ .rcdata = start },
                            },
                        };
                    },
                    // U+003C LESS-THAN SIGN (<)
                    // Switch to the RCDATA less-than sign state.
                    '<' => self.state = .{
                        .rcdata_less_than_sign = .{
                            .data_start = start,
                            .tag_start = self.idx - 1,
                            .name_start = 0, // not known yet
                        },
                    },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Emit a U+FFFD REPLACEMENT CHARACTER character token.
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
                        };
                    },
                    // Anything else
                    // Emit the current input character as a character token.
                    else => {},
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#rawtext-state
            .rawtext => |start| {
                if (!self.consume(src)) {
                    // EOF
                    // Emit an end-of-file token.
                    self.state = .eof;
                    return null;
                } else switch (self.current) {
                    // U+003C LESS-THAN SIGN (<)
                    // Switch to the RAWTEXT less-than sign state.
                    '<' => self.state = .{
                        .rawtext_less_than_sign = .{
                            .data_start = start,
                            .tag_start = self.idx - 1,
                            .name_start = 0, // not known yet
                        },
                    },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Emit a U+FFFD REPLACEMENT CHARACTER character token.
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
                        };
                    },
                    // Anything else
                    // Emit the current input character as a character token.
                    else => {},
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-state
            .script_data => |start| {
                if (!self.consume(src)) {
                    // EOF
                    // Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .text = .{
                                .start = start,
                                .end = self.idx,
                            },
                        },
                    };
                }
                switch (self.current) {
                    // U+003C LESS-THAN SIGN (<)
                    // Switch to the script data less-than sign state.
                    '<' => self.state = .{
                        .script_data_less_than_sign = .{
                            .data_start = start,
                            .tag_start = self.idx - 1,
                        },
                    },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Emit a U+FFFD REPLACEMENT CHARACTER character token.
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
                        };
                    },
                    // Anything else
                    // Emit the current input character as a character token.
                    else => {
                        // Since we don't emit single chars,
                        // we will instead emit a text token
                        // when appropriate.
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#plaintext-state
            .plaintext => {
                // Entering this state would have to be triggered by the
                // parser, but we never do it as we consider plaintext a
                // deprecated and unsupported tag (ie we emit an error
                // and treat it like a normal tag to contiue parsing).
                unreachable;
                // if (!self.consume(src)) {
                //     // EOF
                //     // Emit an end-of-file token.
                //     self.state = .eof;
                //     return .{
                //         .token = .{
                //             .parse_error = .{
                //                 .tag = .deprecated_and_unsupported,
                //                 .span = .{ .start = start, .end = self.idx },
                //             },
                //         },
                //     };
                // } else switch (self.current) {
                //     // U+0000 NULL
                //     // This is an unexpected-null-character parse error. Emit a U+FFFD REPLACEMENT CHARACTER character token.
                //     0 => {
                //         self.state = .data;
                //         return .{
                //             .token = .{
                //                 .parse_error = .{
                //                     .tag = .unexpected_null_character,
                //                     .span = .{
                //                         .start = self.idx - 1,
                //                         .end = self.idx,
                //                     },
                //                 },
                //             },
                //         };
                //     },
                //     // Anything else
                //     // Emit the current input character as a character token.
                //     else => {},
                // }
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
                    '?' => {
                        self.idx -= 1;
                        self.state = .{ .bogus_comment = self.idx };
                    },
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
                } else switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Switch to the before attribute name state.
                    '\t', '\n', '\r', form_feed, ' ' => {
                        var tag = state;
                        tag.name.end = self.idx - 1;
                        self.state = .{ .before_attribute_name = tag };

                        if (self.return_attrs) {
                            return .{ .token = .{ .tag_name = tag.name } };
                        }
                    },
                    // U+002F SOLIDUS (/)
                    // Switch to the self-closing start tag state.
                    '/' => {
                        var tag = state;
                        tag.name.end = self.idx - 1;
                        self.state = .{
                            .self_closing_start_tag = tag,
                        };
                    },
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

            // https://html.spec.whatwg.org/multipage/parsing.html#rcdata-less-than-sign-state
            .rcdata_less_than_sign => |state| {
                if (!self.consume(src)) {
                    self.idx -= 1;
                    self.state = .{ .rcdata = state.data_start };
                } else switch (self.current) {
                    // U+002F SOLIDUS (/)
                    // Set the temporary buffer to the empty string. Switch to the RCDATA end tag open state.
                    '/' => self.state = .{ .rcdata_end_tag_open = state },
                    // Anything else
                    // Emit a U+003C LESS-THAN SIGN character token. Reconsume in the RCDATA state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .rcdata = state.data_start };
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#rcdata-end-tag-open-state
            .rcdata_end_tag_open => |state| {
                if (!self.consume(src)) {
                    self.idx -= 1;
                    self.state = .{ .rcdata = state.data_start };
                } else switch (self.current) {
                    // ASCII alpha
                    // Create a new end tag token, set its tag name to the empty string. Reconsume in the RCDATA end tag name state.
                    'a'...'z', 'A'...'Z' => {
                        var new = state;
                        new.name_start = self.idx - 1;
                        self.state = .{ .rcdata_end_tag_name = new };
                    },
                    // Anything else
                    // Emit a U+003C LESS-THAN SIGN character token and a U+002F SOLIDUS character token. Reconsume in the RCDATA state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .rcdata = state.data_start };
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#rcdata-end-tag-name-state
            .rcdata_end_tag_name => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .rcdata = state.data_start };
                } else switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // If the current end tag token is an appropriate end tag token, then switch to the before attribute name state. Otherwise, treat it as per the "anything else" entry below.
                    '\t', '\n', '\r', form_feed, ' ' => {
                        const tag: Token.Tag = .{
                            .kind = .end,
                            .span = .{
                                .start = state.tag_start,
                                .end = 0, // not yet known
                            },
                            .name = .{
                                .start = state.name_start,
                                .end = self.idx - 1,
                            },
                        };
                        const is_appropriate = std.ascii.eqlIgnoreCase(
                            self.last_start_tag_name,
                            tag.name.slice(src),
                        );
                        if (is_appropriate) {
                            self.state = .{ .before_attribute_name = tag };
                            if (trimmedText(
                                state.data_start,
                                state.tag_start,
                                src,
                            )) |txt| {
                                return .{ .token = .{ .text = txt } };
                            }
                        } else {
                            self.idx -= 1;
                            self.state = .{ .rcdata = state.data_start };
                        }
                    },
                    // U+002F SOLIDUS (/)
                    // If the current end tag token is an appropriate end tag token, then switch to the self-closing start tag state. Otherwise, treat it as per the "anything else" entry below.
                    '/' => {
                        const tag: Token.Tag = .{
                            .kind = .end,
                            .span = .{
                                .start = state.tag_start,
                                .end = 0, // not yet known
                            },
                            .name = .{
                                .start = state.name_start,
                                .end = self.idx - 1,
                            },
                        };
                        const is_appropriate = std.ascii.eqlIgnoreCase(
                            self.last_start_tag_name,
                            tag.name.slice(src),
                        );
                        if (is_appropriate) {
                            self.state = .{ .before_attribute_name = tag };

                            const err: Token = .{
                                .parse_error = .{
                                    .tag = .end_tag_with_trailing_solidus,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            };

                            if (trimmedText(
                                state.data_start,
                                state.tag_start,
                                src,
                            )) |txt| {
                                return .{
                                    .token = .{ .text = txt },
                                    .deferred = err,
                                };
                            } else {
                                return .{ .token = err };
                            }
                        } else {
                            self.idx -= 1;
                            self.state = .{ .rcdata = state.data_start };
                        }
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // If the current end tag token is an appropriate end tag token, then switch to the data state and emit the current tag token. Otherwise, treat it as per the "anything else" entry below.
                    '>' => {
                        const tag: Token.Tag = .{
                            .kind = .end,
                            .span = .{
                                .start = state.tag_start,
                                .end = self.idx,
                            },
                            .name = .{
                                .start = state.name_start,
                                .end = self.idx - 1,
                            },
                        };
                        const is_appropriate = std.ascii.eqlIgnoreCase(
                            self.last_start_tag_name,
                            tag.name.slice(src),
                        );
                        if (is_appropriate) {
                            self.state = .data;
                            if (trimmedText(
                                state.data_start,
                                state.tag_start,
                                src,
                            )) |txt| {
                                return .{
                                    .token = .{ .text = txt },
                                    .deferred = .{ .tag = tag },
                                };
                            } else {
                                return .{ .token = .{ .tag = tag } };
                            }
                        } else {
                            self.idx -= 1;
                            self.state = .{ .rcdata = state.data_start };
                        }
                    },

                    // ASCII upper alpha
                    // Append the lowercase version of the current input character (add 0x0020 to the character's code point) to the current tag token's tag name. Append the current input character to the temporary buffer.
                    // ASCII lower alpha
                    // Append the current input character to the current tag token's tag name. Append the current input character to the temporary buffer.
                    'a'...'z', 'A'...'Z' => {},

                    // Anything else
                    // Emit a U+003C LESS-THAN SIGN character token, a U+002F SOLIDUS character token, and a character token for each of the characters in the temporary buffer (in the order they were added to the buffer). Reconsume in the RCDATA state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .rcdata = state.data_start };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#rawtext-less-than-sign-state
            .rawtext_less_than_sign => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .rawtext = state.data_start };
                } else switch (self.current) {
                    // U+002F SOLIDUS (/)
                    // Set the temporary buffer to the empty string. Switch to the RAWTEXT end tag open state.
                    '/' => self.state = .{ .rawtext_end_tag_open = state },

                    // Anything else
                    // Emit a U+003C LESS-THAN SIGN character token. Reconsume in the RAWTEXT state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .rawtext = state.data_start };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#rawtext-end-tag-open-state
            .rawtext_end_tag_open => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .rawtext = state.data_start };
                } else switch (self.current) {
                    // ASCII alpha
                    // Create a new end tag token, set its tag name to the empty string. Reconsume in the RAWTEXT end tag name state.
                    'a'...'z', 'A'...'Z' => {
                        self.idx -= 1;
                        var new = state;
                        new.name_start = self.idx;
                        self.state = .{ .rawtext_end_tag_name = new };
                    },
                    // Anything else
                    // Emit a U+003C LESS-THAN SIGN character token and a U+002F SOLIDUS character token. Reconsume in the RAWTEXT state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .rawtext = state.data_start };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#rawtext-end-tag-name-state
            .rawtext_end_tag_name => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .rawtext = state.data_start };
                } else switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // If the current end tag token is an appropriate end tag token, then switch to the before attribute name state. Otherwise, treat it as per the "anything else" entry below.
                    '\t', '\n', '\r', form_feed, ' ' => {
                        const tag: Token.Tag = .{
                            .kind = .end,
                            .span = .{
                                .start = state.tag_start,
                                .end = 0, // not yet known
                            },
                            .name = .{
                                .start = state.name_start,
                                .end = self.idx - 1,
                            },
                        };
                        const is_appropriate = std.ascii.eqlIgnoreCase(
                            self.last_start_tag_name,
                            tag.name.slice(src),
                        );
                        if (is_appropriate) {
                            self.state = .{ .before_attribute_name = tag };
                            if (trimmedText(
                                state.data_start,
                                state.tag_start,
                                src,
                            )) |txt| {
                                return .{ .token = .{ .text = txt } };
                            }
                        } else {
                            self.idx -= 1;
                            self.state = .{ .rawtext = state.data_start };
                        }
                    },

                    // U+002F SOLIDUS (/)
                    // If the current end tag token is an appropriate end tag token, then switch to the self-closing start tag state. Otherwise, treat it as per the "anything else" entry below.
                    '/' => {
                        // What? A self-closing end tag?
                        // The spec is impicitly relying on how their
                        // state-changing side effects are supposed to combine.
                        // It's unclear if we are meant to trust the leading or
                        // the trailing slash.
                        // Let's just report an error, but for convenience,
                        // we're also going to change state to before_attribute_name
                        const tag: Token.Tag = .{
                            .kind = .end,
                            .span = .{
                                .start = state.tag_start,
                                .end = 0, // not yet known
                            },
                            .name = .{
                                .start = state.name_start,
                                .end = self.idx - 1,
                            },
                        };
                        const is_appropriate = std.ascii.eqlIgnoreCase(
                            self.last_start_tag_name,
                            tag.name.slice(src),
                        );
                        if (is_appropriate) {
                            self.state = .{ .self_closing_start_tag = tag };

                            const err: Token = .{
                                .parse_error = .{
                                    .tag = .end_tag_with_trailing_solidus,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            };

                            if (trimmedText(
                                state.data_start,
                                state.tag_start,
                                src,
                            )) |txt| {
                                return .{
                                    .token = .{ .text = txt },
                                    .deferred = err,
                                };
                            } else {
                                return .{ .token = err };
                            }
                        } else {
                            self.idx -= 1;
                            self.state = .{ .rawtext = state.data_start };
                        }
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // If the current end tag token is an appropriate end tag token, then switch to the data state and emit the current tag token. Otherwise, treat it as per the "anything else" entry below.
                    '>' => {
                        const tag: Token.Tag = .{
                            .kind = .end,
                            .span = .{
                                .start = state.tag_start,
                                .end = self.idx,
                            },
                            .name = .{
                                .start = state.name_start,
                                .end = self.idx - 1,
                            },
                        };
                        const is_appropriate = std.ascii.eqlIgnoreCase(
                            self.last_start_tag_name,
                            tag.name.slice(src),
                        );
                        if (is_appropriate) {
                            self.state = .data;
                            if (trimmedText(
                                state.data_start,
                                state.tag_start,
                                src,
                            )) |txt| {
                                return .{
                                    .token = .{ .text = txt },
                                    .deferred = .{ .tag = tag },
                                };
                            } else {
                                return .{ .token = .{ .tag = tag } };
                            }
                        } else {
                            self.idx -= 1;
                            self.state = .{ .rawtext = state.data_start };
                        }
                    },
                    // ASCII upper alpha
                    // Append the lowercase version of the current input character (add 0x0020 to the character's code point) to the current tag token's tag name. Append the current input character to the temporary buffer.
                    // ASCII lower alpha
                    // Append the current input character to the current tag token's tag name. Append the current input character to the temporary buffer.
                    'a'...'z', 'A'...'Z' => {},

                    // Anything else
                    // Emit a U+003C LESS-THAN SIGN character token, a U+002F SOLIDUS character token, and a character token for each of the characters in the temporary buffer (in the order they were added to the buffer). Reconsume in the RAWTEXT state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .rawtext = state.data_start };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-less-than-sign-state
            .script_data_less_than_sign => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .script_data = state.data_start };
                } else switch (self.current) {
                    // U+002F SOLIDUS (/)
                    // Set the temporary buffer to the empty string. Switch to the script data end tag open state.
                    '/' => self.state = .{ .script_data_end_tag_open = state },
                    // U+0021 EXCLAMATION MARK (!)
                    // Switch to the script data escape start state. Emit a U+003C LESS-THAN SIGN character token and a U+0021 EXCLAMATION MARK character token.
                    '!' => self.state = .{ .script_data_escape_start = state },
                    // Anything else
                    // Emit a U+003C LESS-THAN SIGN character token. Reconsume in the script data state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .script_data = state.data_start };
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-end-tag-open-state
            .script_data_end_tag_open => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .script_data = state.data_start };
                } else switch (self.current) {
                    // ASCII alpha
                    // Create a new end tag token, set its tag name to the empty string. Reconsume in the script data end tag name state.
                    'a'...'z', 'A'...'Z' => {
                        self.idx -= 1;
                        var new = state;
                        new.name_start = self.idx;

                        self.state = .{ .script_data_end_tag_name = new };
                    },
                    // Anything else
                    // Emit a U+003C LESS-THAN SIGN character token and a U+002F SOLIDUS character token. Reconsume in the script data state
                    else => {
                        self.idx -= 1;
                        self.state = .{ .script_data = state.data_start };
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-end-tag-name-state
            .script_data_end_tag_name => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .script_data = state.data_start };
                } else switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // If the current end tag token is an appropriate end tag token, then switch to the before attribute name state. Otherwise, treat it as per the "anything else" entry below.
                    '\t', '\n', '\r', form_feed, ' ' => {
                        const tag: Token.Tag = .{
                            .kind = .end,
                            .span = .{
                                .start = state.tag_start,
                                .end = 0, // not yet known
                            },
                            .name = .{
                                .start = state.name_start,
                                .end = self.idx - 1,
                            },
                        };
                        const is_script = std.ascii.eqlIgnoreCase(
                            "script",
                            tag.name.slice(src),
                        );
                        if (is_script) {
                            self.state = .{ .before_attribute_name = tag };
                            if (trimmedText(
                                state.data_start,
                                state.tag_start,
                                src,
                            )) |txt| {
                                return .{ .token = .{ .text = txt } };
                            }
                        } else {
                            self.idx -= 1;
                            self.state = .{ .script_data = state.data_start };
                        }
                    },
                    // U+002F SOLIDUS (/)
                    // If the current end tag token is an appropriate end tag token, then switch to the self-closing start tag state. Otherwise, treat it as per the "anything else" entry below.
                    '/' => {
                        // What? A self-closing end tag?
                        // The spec is impicitly relying on how their
                        // state-changing side effects are supposed to combine.
                        // It's unclear if we are meant to trust the leading or
                        // the trailing slash.
                        // Let's just report an error, but for convenience,
                        // we're also going to change state to before_attribute_name
                        const tag: Token.Tag = .{
                            .kind = .end,
                            .span = .{
                                .start = state.tag_start,
                                .end = 0, // not yet known
                            },
                            .name = .{
                                .start = state.name_start,
                                .end = self.idx - 1,
                            },
                        };
                        const is_script = std.ascii.eqlIgnoreCase(
                            "script",
                            tag.name.slice(src),
                        );
                        if (is_script) {
                            self.state = .{ .before_attribute_name = tag };

                            const err: Token = .{
                                .parse_error = .{
                                    .tag = .end_tag_with_trailing_solidus,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            };

                            if (trimmedText(
                                state.data_start,
                                state.tag_start,
                                src,
                            )) |txt| {
                                return .{
                                    .token = .{ .text = txt },
                                    .deferred = err,
                                };
                            } else {
                                return .{ .token = err };
                            }
                        } else {
                            self.idx -= 1;
                            self.state = .{ .script_data = state.data_start };
                        }
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // If the current end tag token is an appropriate end tag token, then switch to the data state and emit the current tag token. Otherwise, treat it as per the "anything else" entry below.
                    // NOTE: An appropriate end tag token is an end tag token whose tag name matches the tag name of the last start tag to have been emitted from this tokenizer, if any. If no start tag has been emitted from this tokenizer, then no end tag token is appropriate.
                    '>' => {
                        const tag: Token.Tag = .{
                            .kind = .end,
                            .span = .{
                                .start = state.tag_start,
                                .end = self.idx,
                            },
                            .name = .{
                                .start = state.name_start,
                                .end = self.idx - 1,
                            },
                        };
                        const is_script = std.ascii.eqlIgnoreCase(
                            "script",
                            tag.name.slice(src),
                        );
                        if (is_script) {
                            self.state = .data;
                            if (trimmedText(
                                state.data_start,
                                state.tag_start,
                                src,
                            )) |txt| {
                                return .{
                                    .token = .{ .text = txt },
                                    .deferred = .{ .tag = tag },
                                };
                            } else {
                                return .{ .token = .{ .tag = tag } };
                            }
                        } else {
                            self.idx -= 1;
                            self.state = .{ .script_data = state.data_start };
                        }
                    },
                    // ASCII upper alpha
                    // Append the lowercase version of the current input character (add 0x0020 to the character's code point) to the current tag token's tag name. Append the current input character to the temporary buffer.
                    // ASCII lower alpha
                    // Append the current input character to the current tag token's tag name. Append the current input character to the temporary buffer.
                    'a'...'z', 'A'...'Z' => {},
                    // Anything else
                    // Emit a U+003C LESS-THAN SIGN character token, a U+002F SOLIDUS character token, and a character token for each of the characters in the temporary buffer (in the order they were added to the buffer). Reconsume in the script data state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .script_data = state.data_start };
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-escape-start-state
            .script_data_escape_start => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .script_data = state.data_start };
                } else switch (self.current) {
                    // U+002D HYPHEN-MINUS (-)
                    // Switch to the script data escape start dash state. Emit a U+002D HYPHEN-MINUS character token.
                    '-' => self.state = .{
                        .script_data_escape_start_dash = state,
                    },
                    // Anything else
                    // Reconsume in the script data state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .script_data = state.data_start };
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-escape-start-dash-state
            .script_data_escape_start_dash => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .script_data = state.data_start };
                } else switch (self.current) {
                    // U+002D HYPHEN-MINUS (-)
                    // Switch to the script data escaped dash dash state. Emit a U+002D HYPHEN-MINUS character token.
                    '-' => self.state = .{
                        .script_data_escaped_dash_dash = state,
                    },
                    // Anything else
                    // Reconsume in the script data state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .script_data = state.data_start };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-escaped-state
            .script_data_escaped => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-script-html-comment-like-text parse error. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_script_html_comment_like_text,
                                .span = .{
                                    .start = state.tag_start,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                } else switch (self.current) {
                    // U+002D HYPHEN-MINUS (-)
                    // Switch to the script data escaped dash state. Emit a U+002D HYPHEN-MINUS character token.
                    '-' => self.state = .{
                        .script_data_escaped_dash = state,
                    },
                    // U+003C LESS-THAN SIGN (<)
                    // Switch to the script data escaped less-than sign state.
                    '<' => self.state = .{
                        .script_data_escaped_less_than_sign = state,
                    },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Emit a U+FFFD REPLACEMENT CHARACTER character token.
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
                        };
                    },
                    // Anything else
                    // Emit the current input character as a character token.
                    else => {},
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-escaped-dash-state
            .script_data_escaped_dash => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-script-html-comment-like-text parse error. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_script_html_comment_like_text,
                                .span = .{
                                    .start = state.tag_start,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                } else switch (self.current) {
                    // U+002D HYPHEN-MINUS (-)
                    // Switch to the script data escaped dash dash state. Emit a U+002D HYPHEN-MINUS character token.
                    '-' => self.state = .{
                        .script_data_escaped_dash_dash = state,
                    },
                    // U+003C LESS-THAN SIGN (<)
                    // Switch to the script data escaped less-than sign state.
                    '<' => self.state = .{
                        .script_data_escaped_less_than_sign = state,
                    },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Switch to the script data escaped state. Emit a U+FFFD REPLACEMENT CHARACTER character token.
                    0 => {
                        self.state = .{ .script_data_escaped = state };
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
                    // Anything else
                    // Switch to the script data escaped state. Emit the current input character as a character token.
                    else => self.state = .{ .script_data_escaped = state },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-escaped-dash-dash-state
            .script_data_escaped_dash_dash => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-script-html-comment-like-text parse error. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_script_html_comment_like_text,
                                .span = .{
                                    .start = state.tag_start,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                } else switch (self.current) {
                    // U+002D HYPHEN-MINUS (-)
                    // Emit a U+002D HYPHEN-MINUS character token.
                    '-' => {},
                    // U+003C LESS-THAN SIGN (<)
                    // Switch to the script data escaped less-than sign state.
                    '<' => self.state = .{
                        .script_data_escaped_less_than_sign = state,
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the script data state. Emit a U+003E GREATER-THAN SIGN character token.
                    '>' => self.state = .{ .script_data = state.data_start },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Switch to the script data escaped state. Emit a U+FFFD REPLACEMENT CHARACTER character token.
                    0 => {
                        self.state = .{ .script_data_escaped = state };
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
                    // Anything else
                    // Switch to the script data escaped state. Emit the current input character as a character token.
                    else => self.state = .{ .script_data = state.data_start },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-escaped-less-than-sign-state
            .script_data_escaped_less_than_sign => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .script_data_escaped = state };
                } else switch (self.current) {
                    // U+002F SOLIDUS (/)
                    // Set the temporary buffer to the empty string. Switch to the script data escaped end tag open state.
                    '/' => self.state = .{
                        .script_data_escaped_end_tag_open = state,
                    },
                    // ASCII alpha
                    // Set the temporary buffer to the empty string. Emit a U+003C LESS-THAN SIGN character token. Reconsume in the script data double escape start state.
                    'a'...'z', 'A'...'Z' => {
                        self.idx -= 1;
                        @panic("TODO");
                    },
                    // Anything else
                    // Emit a U+003C LESS-THAN SIGN character token. Reconsume in the script data escaped state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .script_data_escaped = state };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-escaped-end-tag-open-state
            .script_data_escaped_end_tag_open => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .script_data_escaped = state };
                } else switch (self.current) {
                    // ASCII alpha
                    // Create a new end tag token, set its tag name to the empty string. Reconsume in the script data escaped end tag name state.
                    'a'...'z', 'A'...'Z' => {
                        self.idx -= 1;
                        @panic("TODO");
                    },
                    // Anything else
                    // Emit a U+003C LESS-THAN SIGN character token and a U+002F SOLIDUS character token. Reconsume in the script data escaped state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .script_data_escaped = state };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-escaped-end-tag-name-state
            .script_data_escaped_end_tag_name => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .script_data_escaped = state };
                } else switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // If the current end tag token is an appropriate end tag token, then switch to the before attribute name state. Otherwise, treat it as per the "anything else" entry below.
                    '\t', '\n', '\r', form_feed, ' ' => {
                        const tag: Token.Tag = .{
                            .kind = .end,
                            .span = .{
                                .start = state.tag_start,
                                .end = 0, // not yet known
                            },
                            .name = .{
                                .start = state.name_start,
                                .end = self.idx - 1,
                            },
                        };
                        const is_script = std.ascii.eqlIgnoreCase(
                            "script",
                            tag.name.slice(src),
                        );
                        if (is_script) {
                            self.state = .{ .before_attribute_name = tag };
                            if (trimmedText(
                                state.data_start,
                                state.tag_start,
                                src,
                            )) |txt| {
                                return .{ .token = .{ .text = txt } };
                            }
                        } else {
                            self.idx -= 1;
                            self.state = .{ .script_data_escaped = state };
                        }
                    },
                    // U+002F SOLIDUS (/)
                    // If the current end tag token is an appropriate end tag token, then switch to the self-closing start tag state. Otherwise, treat it as per the "anything else" entry below.
                    '/' => {
                        const tag: Token.Tag = .{
                            .kind = .end,
                            .span = .{
                                .start = state.tag_start,
                                .end = 0, // not yet known
                            },
                            .name = .{
                                .start = state.name_start,
                                .end = self.idx - 1,
                            },
                        };
                        const is_script = std.ascii.eqlIgnoreCase(
                            "script",
                            tag.name.slice(src),
                        );
                        if (is_script) {
                            self.state = .{ .before_attribute_name = tag };

                            const err: Token = .{
                                .parse_error = .{
                                    .tag = .end_tag_with_trailing_solidus,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            };

                            if (trimmedText(
                                state.data_start,
                                state.tag_start,
                                src,
                            )) |txt| {
                                return .{
                                    .token = .{ .text = txt },
                                    .deferred = err,
                                };
                            } else {
                                return .{ .token = err };
                            }
                        } else {
                            self.idx -= 1;
                            self.state = .{
                                .script_data_escaped = state,
                            };
                        }
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // If the current end tag token is an appropriate end tag token, then switch to the data state and emit the current tag token. Otherwise, treat it as per the "anything else" entry below.
                    '>' => {
                        const tag: Token.Tag = .{
                            .kind = .end,
                            .span = .{
                                .start = state.tag_start,
                                .end = self.idx,
                            },
                            .name = .{
                                .start = state.name_start,
                                .end = self.idx - 1,
                            },
                        };
                        const is_script = std.ascii.eqlIgnoreCase(
                            "script",
                            tag.name.slice(src),
                        );
                        if (is_script) {
                            self.state = .data;
                            if (trimmedText(
                                state.data_start,
                                state.tag_start,
                                src,
                            )) |txt| {
                                return .{
                                    .token = .{ .text = txt },
                                    .deferred = .{ .tag = tag },
                                };
                            } else {
                                return .{ .token = .{ .tag = tag } };
                            }
                        } else {
                            self.idx -= 1;
                            self.state = .{ .script_data = state.data_start };
                        }
                    },

                    // ASCII upper alpha
                    // Append the lowercase version of the current input character (add 0x0020 to the character's code point) to the current tag token's tag name. Append the current input character to the temporary buffer.
                    // ASCII lower alpha
                    // Append the current input character to the current tag token's tag name. Append the current input character to the temporary buffer.
                    'a'...'z', 'A'...'Z' => {},

                    // Anything else
                    // Emit a U+003C LESS-THAN SIGN character token, a U+002F SOLIDUS character token, and a character token for each of the characters in the temporary buffer (in the order they were added to the buffer). Reconsume in the script data escaped state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .script_data_escaped = state };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-double-escape-start-state
            .script_data_double_escape_start => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .script_data_escaped = state };
                } else switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // U+002F SOLIDUS (/)
                    // U+003E GREATER-THAN SIGN (>)
                    // If the temporary buffer is the string "script", then switch to the script data double escaped state. Otherwise, switch to the script data escaped state. Emit the current input character as a character token.
                    '\t', '\n', '\r', form_feed, ' ', '/', '>' => {
                        const name: Span = .{
                            .start = state.name_start,
                            .end = self.idx - 1,
                        };
                        const is_script = std.ascii.eqlIgnoreCase(
                            "script",
                            name.slice(src),
                        );
                        if (is_script) {
                            self.state = .{
                                .script_data_double_escaped = state,
                            };
                        } else {
                            self.state = .{
                                .script_data_escaped = state,
                            };
                        }
                    },
                    // ASCII upper alpha
                    // Append the lowercase version of the current input character (add 0x0020 to the character's code point) to the temporary buffer. Emit the current input character as a character token.
                    // ASCII lower alpha
                    // Append the current input character to the temporary buffer. Emit the current input character as a character token.
                    'a'...'z', 'A'...'Z' => {},

                    // Anything else
                    // Reconsume in the script data escaped state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .script_data_escaped = state };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-double-escaped-state
            .script_data_double_escaped => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-script-html-comment-like-text parse error. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_script_html_comment_like_text,
                                .span = .{
                                    .start = state.tag_start,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                } else switch (self.current) {
                    // U+002D HYPHEN-MINUS (-)
                    // Switch to the script data double escaped dash state. Emit a U+002D HYPHEN-MINUS character token.
                    '-' => self.state = .{
                        .script_data_double_escaped_dash = state,
                    },
                    // U+003C LESS-THAN SIGN (<)
                    // Switch to the script data double escaped less-than sign state. Emit a U+003C LESS-THAN SIGN character token.
                    '<' => self.state = .{
                        .script_data_double_escaped_less_than_sign = state,
                    },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Emit a U+FFFD REPLACEMENT CHARACTER character token.
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
                        };
                    },
                    // Anything else
                    // Emit the current input character as a character token.
                    else => {},
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-double-escaped-dash-state
            .script_data_double_escaped_dash => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-script-html-comment-like-text parse error. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_script_html_comment_like_text,
                                .span = .{
                                    .start = state.tag_start,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                } else switch (self.current) {
                    // U+002D HYPHEN-MINUS (-)
                    // Switch to the script data double escaped dash dash state. Emit a U+002D HYPHEN-MINUS character token.
                    '-' => self.state = .{
                        .script_data_double_escaped_dash_dash = state,
                    },
                    // U+003C LESS-THAN SIGN (<)
                    // Switch to the script data double escaped less-than sign state. Emit a U+003C LESS-THAN SIGN character token.
                    '<' => self.state = .{
                        .script_data_double_escaped_less_than_sign = state,
                    },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Switch to the script data double escaped state. Emit a U+FFFD REPLACEMENT CHARACTER character token.
                    0 => {
                        self.state = .{ .script_data_double_escaped = state };
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
                    // Anything else
                    // Switch to the script data double escaped state. Emit the current input character as a character token.
                    else => self.state = .{
                        .script_data_double_escaped = state,
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-double-escaped-dash-dash-state
            .script_data_double_escaped_dash_dash => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-script-html-comment-like-text parse error. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_script_html_comment_like_text,
                                .span = .{
                                    .start = state.tag_start,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                } else switch (self.current) {
                    // U+002D HYPHEN-MINUS (-)
                    // Emit a U+002D HYPHEN-MINUS character token.
                    '-' => {},
                    // U+003C LESS-THAN SIGN (<)
                    // Switch to the script data double escaped less-than sign state. Emit a U+003C LESS-THAN SIGN character token.
                    '<' => self.state = .{
                        .script_data_double_escaped_less_than_sign = state,
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the script data state. Emit a U+003E GREATER-THAN SIGN character token.
                    '>' => self.state = .{ .script_data = state.data_start },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Switch to the script data double escaped state. Emit a U+FFFD REPLACEMENT CHARACTER character token.
                    0 => {
                        self.state = .{ .script_data_double_escaped = state };
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
                    // Anything else
                    // Switch to the script data double escaped state. Emit the current input character as a character token.
                    else => self.state = .{
                        .script_data_double_escaped = state,
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-double-escaped-less-than-sign-state
            .script_data_double_escaped_less_than_sign => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .script_data_double_escaped = state };
                } else switch (self.current) {
                    // U+002F SOLIDUS (/)
                    // Set the temporary buffer to the empty string. Switch to the script data double escape end state. Emit a U+002F SOLIDUS character token.
                    '/' => self.state = .{
                        .script_data_double_escape_end = state,
                    },
                    // Anything else
                    // Reconsume in the script data double escaped state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .script_data_double_escaped = state };
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#script-data-double-escape-end-state
            .script_data_double_escape_end => |state| {
                if (!self.consume(src)) {
                    self.state = .{ .script_data_double_escaped = state };
                } else switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // U+002F SOLIDUS (/)
                    // U+003E GREATER-THAN SIGN (>)
                    // If the temporary buffer is the string "script", then switch to the script data escaped state. Otherwise, switch to the script data double escaped state. Emit the current input character as a character token.
                    '\t', '\n', '\r', form_feed, ' ', '/', '>' => {
                        const name: Span = .{
                            .start = state.name_start,
                            .end = self.idx - 1,
                        };
                        const is_script = std.ascii.eqlIgnoreCase(
                            "script",
                            name.slice(src),
                        );
                        if (is_script) {
                            self.state = .{
                                .script_data_escaped = state,
                            };
                        } else {
                            self.state = .{
                                .script_data_double_escaped = state,
                            };
                        }
                    },

                    // ASCII upper alpha
                    // Append the lowercase version of the current input character (add 0x0020 to the character's code point) to the temporary buffer. Emit the current input character as a character token.
                    // ASCII lower alpha
                    // Append the current input character to the temporary buffer. Emit the current input character as a character token.
                    'a'...'z', 'A'...'Z' => {},

                    // Anything else
                    // Reconsume in the script data double escaped state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .script_data_double_escaped = state };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#before-attribute-name-state
            .before_attribute_name => |state| {
                // See EOF case from below
                if (!self.consume(src)) {
                    self.state = .data;
                    var tag = state;
                    tag.span.end = self.idx;
                    return .{ .token = .{ .tag = tag } };
                    // self.idx -= 1;
                    // self.state = .{
                    //     .after_attribute_name = .{
                    //         .tag = state,
                    //         .name = .{
                    //             .start = self.idx,
                    //             .end = self.idx + 1,
                    //         },
                    //     },
                    // };
                } else switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Ignore the character.
                    '\t', '\n', '\r', form_feed, ' ' => {},

                    // U+002F SOLIDUS (/)
                    // U+003E GREATER-THAN SIGN (>)
                    // EOF
                    // Reconsume in the after attribute name state.
                    //
                    // NOTE: handled differently
                    '/', '>' => {
                        self.state = .data;
                        var tag = state;
                        tag.span.end = self.idx;
                        return .{ .token = .{ .tag = tag } };
                        // self.idx -= 1;
                        // self.state = .{
                        //     .after_attribute_name = .{
                        //         .tag = state,
                        //         .name = .{
                        //             .start = self.idx - 2,
                        //             .end = self.idx,
                        //         },
                        //     },
                        // };
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
                    self.state = .{
                        .after_attribute_name = .{
                            .tag = state.tag,
                            .name = .{
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
                    '\t', '\n', '\r', form_feed, ' ', '/', '>' => {
                        self.idx -= 1;
                        self.state = .{
                            .after_attribute_name = .{
                                .tag = state.tag,
                                .name = .{
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
                            .name = .{
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
                    '\t', '\n', '\r', form_feed, ' ' => {},
                    // U+002F SOLIDUS (/)
                    // Switch to the self-closing start tag state.
                    '/' => {
                        var tag = state.tag;
                        tag.attr_count += 1;
                        self.state = .{ .self_closing_start_tag = tag };
                        if (self.return_attrs) {
                            return .{
                                .token = .{
                                    .attr = .{
                                        .name = state.name,
                                        .value = null,
                                    },
                                },
                            };
                        }
                    },
                    // U+003D EQUALS SIGN (=)
                    // Switch to the before attribute value state.
                    '=' => self.state = .{
                        .before_attribute_value = .{
                            .tag = state.tag,
                            .name = state.name,
                            .equal_sign = self.idx - 1,
                        },
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the data state. Emit the current tag token.
                    '>' => {
                        var tag = state.tag;
                        tag.span.end = self.idx;
                        tag.attr_count += 1;

                        self.state = .data;
                        if (self.return_attrs) {
                            return .{
                                .token = .{
                                    .attr = .{
                                        .name = state.name,
                                        .value = null,
                                    },
                                },
                            };
                        }

                        return .{ .token = .{ .tag = tag } };
                    },
                    // Anything else
                    // Start a new attribute in the current tag token. Set that attribute name and value to the empty string. Reconsume in the attribute name state.
                    else => {
                        self.idx -= 1;

                        var tag = state.tag;
                        tag.attr_count += 1;

                        self.state = .{
                            .attribute_name = .{
                                .tag = tag,
                                .name_start = self.idx,
                            },
                        };

                        if (self.return_attrs) {
                            return .{
                                .token = .{
                                    .attr = .{
                                        .name = state.name,
                                        .value = null,
                                    },
                                },
                            };
                        }
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#before-attribute-value-state
            .before_attribute_value => |state| {
                if (!self.consume(src)) {
                    self.state = .{
                        .attribute_value_unquoted = .{
                            .tag = state.tag,
                            .name = state.name,
                            .value_start = self.idx,
                        },
                    };
                } else switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Ignore the character.
                    '\t', '\n', '\r', form_feed, ' ' => {},
                    // U+0022 QUOTATION MARK (")
                    // Switch to the attribute value (double-quoted) state.
                    '"' => self.state = .{
                        .attribute_value = .{
                            .tag = state.tag,
                            .name = state.name,
                            .quote = .double,
                            .value_start = self.idx,
                        },
                    },
                    // U+0027 APOSTROPHE (')
                    // Switch to the attribute value (single-quoted) state.
                    '\'' => self.state = .{
                        .attribute_value = .{
                            .tag = state.tag,
                            .name = state.name,
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
                                .name = state.name,
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
                            var tag = state.tag;
                            tag.attr_count += 1;

                            self.state = .{
                                .after_attribute_value = .{
                                    .tag = tag,
                                    .attr_value_end = self.idx,
                                },
                            };
                            if (self.return_attrs) {
                                return .{
                                    .token = .{
                                        .attr = .{
                                            .name = state.name,
                                            .value = .{
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
                            var tag = state.tag;
                            tag.attr_count += 1;

                            self.state = .{
                                .after_attribute_value = .{
                                    .tag = tag,
                                    .attr_value_end = self.idx,
                                },
                            };
                            if (self.return_attrs) {
                                return .{
                                    .token = .{
                                        .attr = .{
                                            .name = state.name,
                                            .value = .{
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
                    '&' => {
                        self.state = .{ .character_reference = .{
                            .ampersand = self.idx - 1,
                            .return_state = .{ .attribute_value = state },
                        } };
                    },

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
                    '\t', '\n', '\r', form_feed, ' ' => {
                        var tag = state.tag;
                        tag.attr_count += 1;

                        self.state = .{ .before_attribute_name = tag };
                        if (self.return_attrs) {
                            return .{
                                .token = .{
                                    .attr = .{
                                        .name = state.name,
                                        .value = .{
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
                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the data state. Emit the current tag token.
                    '>' => {
                        var tag = state.tag;
                        tag.span.end = self.idx;
                        tag.attr_count += 1;

                        self.state = .data;

                        if (self.return_attrs) {
                            return .{
                                .token = .{
                                    .attr = .{
                                        .name = state.name,
                                        .value = .{
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
                    '&' => {
                        self.state = .{
                            .character_reference = .{
                                .ampersand = self.idx - 1,
                                .return_state = .{ .attribute_value_unquoted = state },
                            },
                        };
                    },

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
                    '\t', '\n', '\r', form_feed, ' ' => self.state = .{
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
                    '/' => {
                        self.state = .{
                            .self_closing_start_tag = state.tag,
                        };
                    },
                    // Anything else
                    // This is a missing-whitespace-between-attributes parse error. Reconsume in the before attribute name state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .before_attribute_name = state.tag };
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

            // https://html.spec.whatwg.org/multipage/parsing.html#self-closing-start-tag-state
            .self_closing_start_tag => |state| {
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
                } else switch (self.current) {
                    // U+003E GREATER-THAN SIGN (>)
                    // Set the self-closing flag of the current tag token. Switch to the data state. Emit the current tag token.
                    '>' => {
                        self.state = .data;

                        var tag = state;
                        tag.span.end = self.idx;
                        tag.kind = switch (tag.kind) {
                            .start => .start_self,
                            .end => .end_self,
                            else => unreachable,
                        };

                        if (self.return_attrs) {
                            const deferred: Token = if (tag.kind == .end_self) .{
                                .parse_error = .{
                                    .tag = .end_tag_with_trailing_solidus,
                                    .span = tag.span,
                                },
                            } else .{ .tag = tag };
                            return .{
                                .token = .{ .tag_name = tag.name },
                                .deferred = deferred,
                            };
                        }

                        return if (tag.kind == .end_self) .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .end_tag_with_trailing_solidus,
                                    .span = tag.span,
                                },
                            },
                            .deferred = .{ .tag = tag },
                        } else .{ .token = .{ .tag = tag } };
                    },
                    // Anything else
                    // This is an unexpected-solidus-in-tag parse error. Reconsume in the before attribute name state.
                    else => {
                        self.state = .{ .before_attribute_name = state };
                        self.idx -= 1;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .unexpected_solidus_in_tag,
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

            // https://html.spec.whatwg.org/multipage/parsing.html#bogus-comment-state
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

            // https://html.spec.whatwg.org/multipage/parsing.html#markup-declaration-open-state
            .markup_declaration_open => |lbracket| {
                if (self.nextCharsAre("--", src)) {
                    // Two U+002D HYPHEN-MINUS characters (-)
                    // Consume those two characters, create a comment token whose data is the empty string, and switch to the comment start state.
                    self.idx += 2;
                    self.state = .{ .comment_start = lbracket };
                } else if (self.nextCharsAreIgnoreCase("DOCTYPE", src)) {
                    // ASCII case-insensitive match for the word "DOCTYPE"
                    // Consume those characters and switch to the DOCTYPE state.
                    self.idx += @intCast("DOCTYPE".len);
                    self.state = .{ .doctype = lbracket };
                } else if (self.nextCharsAre("[CDATA[", src)) {
                    // The string "[CDATA[" (the five uppercase letters "CDATA" with a U+005B LEFT SQUARE BRACKET character before and after)
                    // Consume those characters. If there is an adjusted current node and it is not an element in the HTML namespace, then switch to the CDATA section state. Otherwise, this is a cdata-in-html-content parse error. Create a comment token whose data is the "[CDATA[" string. Switch to the bogus comment state.
                    // NOTE: since we don't implement the AST building step
                    //       according to the HTML spec, we don't report this
                    //       error either since we don't have fully
                    //       spec-compliant knowledge about the "adjusted
                    //       current node".
                    self.idx += @intCast("[CDATA[".len);
                    self.state = .{ .cdata_section = lbracket };
                } else {
                    // Anything else
                    // This is an incorrectly-opened-comment parse error. Create a comment token whose data is the empty string. Switch to the bogus comment state (don't consume anything in the current state).
                    self.state = .{ .bogus_comment = self.idx - 1 };
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .incorrectly_opened_comment,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#character-reference-state
            .character_reference => |state| {
                std.debug.assert(self.current == '&');
                // Set the temporary buffer to the empty string. Append a U+0026 AMPERSAND (&) character to the temporary buffer.
                // Consume the next input character:
                if (!self.consume(src)) {
                    self.state = state.getReturnState();
                } else switch (self.current) {
                    // ASCII alphanumeric
                    // Reconsume in the named character reference state.
                    'a'...'z', 'A'...'Z', '0'...'9' => {
                        self.idx -= 1;
                        self.state = .{ .named_character_reference = state };
                    },
                    // U+0023 NUMBER SIGN (#)
                    // Append the current input character to the temporary buffer. Switch to the numeric character reference state.
                    '#' => {
                        self.state = .{ .numeric_character_reference = .{
                            .code = 0,
                            .ref = state,
                        } };
                    },
                    // Anything else
                    // Flush code points consumed as a character reference. Reconsume in the return state.
                    else => {
                        self.idx -= 1;
                        self.state = state.getReturnState();
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#named-character-reference-state
            .named_character_reference => |state| {
                // Consume the maximum number of characters possible, where the consumed characters are one of the identifiers in the first column of the named character references table. Append each character to the temporary buffer when it's consumed.
                var matcher = named_character_references.Matcher{};
                var pending_count: usize = 0;
                var ends_with_semicolon: bool = false;
                var found_match: bool = false;
                while (true) {
                    if (!self.consume(src)) {
                        break;
                    }
                    pending_count += 1;
                    if (!matcher.char(self.current)) break;
                    if (matcher.matched()) {
                        found_match = true;
                        ends_with_semicolon = self.current == ';';
                        pending_count = 0;
                    }
                }

                // If there is a match
                if (found_match) {
                    // Rewind the idx to the end of the longest match found
                    while (pending_count > 0) : (pending_count -= 1) {
                        self.idx -= 1;
                    }

                    // From the spec:
                    //
                    // > If the character reference was consumed as part of an attribute, and the last character matched is not a U+003B SEMICOLON character (;),
                    // > and the next input character is either a U+003D EQUALS SIGN character (=) or an ASCII alphanumeric, then, for historical reasons,
                    // > flush code points consumed as a character reference and switch to the return state.
                    //
                    // This tokenizer implementation is not concerned with historical reasons, and therefore
                    // does not suppress the missing semicolon error.

                    // Switch to the return state.
                    self.state = state.getReturnState();

                    // If the last character matched is not a U+003B SEMICOLON character (;), then this is a missing-semicolon-after-character-reference parse error.
                    if (!ends_with_semicolon) {
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_semicolon_after_character_reference,
                                    .span = .{
                                        .start = state.ampersand,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    }
                } else {
                    self.state = .{
                        .ambiguous_ampersand = state,
                    };
                }
            },

            .ambiguous_ampersand => |state| {
                // Consume the next input character:
                if (!self.consume(src)) {
                    self.state = state.getReturnState();
                } else switch (self.current) {
                    // ASCII alphanumeric
                    // If the character reference was consumed as part of an attribute, then append the current input character to the current attribute's value. Otherwise, emit the current input character as a character token.
                    'a'...'z', 'A'...'Z', '0'...'9' => {},
                    // U+003B SEMICOLON (;)
                    // This is an unknown-named-character-reference parse error. Reconsume in the return state.
                    ';' => {
                        self.idx -= 1;
                        self.state = state.getReturnState();
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .unknown_named_character_reference,
                                    .span = .{
                                        .start = state.ampersand,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                    // Anything else
                    // Reconsume in the return state.
                    else => {
                        self.idx -= 1;
                        self.state = state.getReturnState();
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#numeric-character-reference-state
            .numeric_character_reference => |state| {
                // Set the character reference code to zero (0).
                self.state.numeric_character_reference.code = 0;

                // Consume the next input character:
                if (!self.consume(src)) {
                    self.state = .{ .decimal_character_reference_start = state };
                } else switch (self.current) {
                    // U+0078 LATIN SMALL LETTER X
                    // U+0058 LATIN CAPITAL LETTER X
                    // Append the current input character to the temporary buffer. Switch to the hexadecimal character reference start state.
                    'x', 'X' => {
                        self.state = .{ .hexadecimal_character_reference_start = state };
                    },
                    // Anything else
                    // Reconsume in the decimal character reference start state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .decimal_character_reference_start = state };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#hexadecimal-character-reference-start-state
            .hexadecimal_character_reference_start => |state| {
                // Consume the next input character:
                if (!self.consume(src)) {
                    self.state = state.ref.getReturnState();
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .absence_of_digits_in_numeric_character_reference,
                                .span = .{
                                    .start = state.ref.ampersand,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                } else switch (self.current) {
                    // ASCII hex digit
                    // Reconsume in the hexadecimal character reference state.
                    '0'...'9', 'a'...'f', 'A'...'F' => {
                        self.idx -= 1;
                        self.state = .{ .hexadecimal_character_reference = state };
                    },
                    // Anything else
                    // Reconsume in the decimal character reference start state.
                    else => {
                        self.idx -= 1;
                        self.state = state.ref.getReturnState();
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .absence_of_digits_in_numeric_character_reference,
                                    .span = .{
                                        .start = state.ref.ampersand,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#decimal-character-reference-start-state
            .decimal_character_reference_start => |state| {
                // Consume the next input character:
                if (!self.consume(src)) {
                    self.state = state.ref.getReturnState();
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .absence_of_digits_in_numeric_character_reference,
                                .span = .{
                                    .start = state.ref.ampersand,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                } else switch (self.current) {
                    // SCII digit
                    // Reconsume in the hexadecimal character reference state.
                    '0'...'9' => {
                        self.idx -= 1;
                        self.state = .{ .decimal_character_reference = state };
                    },
                    // Anything else
                    // Reconsume in the decimal character reference start state.
                    else => {
                        self.idx -= 1;
                        self.state = state.ref.getReturnState();
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .absence_of_digits_in_numeric_character_reference,
                                    .span = .{
                                        .start = state.ref.ampersand,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#hexadecimal-character-reference-state
            .hexadecimal_character_reference => |state| {
                // Consume the next input character:
                if (!self.consume(src)) {
                    self.state = .{ .numeric_character_reference_end = state };
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .missing_semicolon_after_character_reference,
                                .span = .{
                                    .start = state.ref.ampersand,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                } else switch (self.current) {
                    // ASCII hex digit
                    // Multiply the character reference code by 16. Add a numeric version of the current input character to the character reference code.
                    '0'...'9', 'a'...'f', 'A'...'F' => {
                        const value = std.fmt.charToDigit(self.current, 16) catch unreachable;
                        self.state.hexadecimal_character_reference.code = std.math.lossyCast(u21, @as(u32, self.state.hexadecimal_character_reference.code) * 16 + value);
                    },
                    // U+003B SEMICOLON
                    // Switch to the numeric character reference end state.
                    ';' => {
                        self.state = .{ .numeric_character_reference_end = state };
                    },
                    // Anything else
                    // This is a missing-semicolon-after-character-reference parse error. Reconsume in the numeric character reference end state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .numeric_character_reference_end = state };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_semicolon_after_character_reference,
                                    .span = .{
                                        .start = state.ref.ampersand,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#decimal-character-reference-state
            .decimal_character_reference => |state| {
                // Consume the next input character:
                if (!self.consume(src)) {
                    self.state = .{ .numeric_character_reference_end = state };
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .missing_semicolon_after_character_reference,
                                .span = .{
                                    .start = state.ref.ampersand,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                } else switch (self.current) {
                    // ASCII digit
                    // Multiply the character reference code by 10. Add a numeric version of the current input character to the character reference code.
                    '0'...'9' => {
                        const value = std.fmt.charToDigit(self.current, 10) catch unreachable;
                        self.state.decimal_character_reference.code = std.math.lossyCast(u21, @as(u32, self.state.decimal_character_reference.code) * 10 + value);
                    },
                    // U+003B SEMICOLON
                    // Switch to the numeric character reference end state.
                    ';' => {
                        self.state = .{ .numeric_character_reference_end = state };
                    },
                    // Anything else
                    // This is a missing-semicolon-after-character-reference parse error. Reconsume in the numeric character reference end state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .numeric_character_reference_end = state };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_semicolon_after_character_reference,
                                    .span = .{
                                        .start = state.ref.ampersand,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#numeric-character-reference-end-state
            .numeric_character_reference_end => |state| {
                const code = state.code;
                var parse_error: ?TokenError = null;
                // Check the character reference code:
                // If the number is 0x00, then this is a null-character-reference parse error. Set the character reference code to 0xFFFD.
                if (code == 0) {
                    parse_error = .null_character_reference;
                }
                // If the number is greater than 0x10FFFF, then this is a character-reference-outside-unicode-range parse error. Set the character reference code to 0xFFFD.
                else if (code > 0x10FFFF) {
                    parse_error = .character_reference_outside_unicode_range;
                }
                // If the number is a surrogate, then this is a surrogate-character-reference parse error. Set the character reference code to 0xFFFD.
                else if (std.unicode.isSurrogateCodepoint(code)) {
                    parse_error = .surrogate_character_reference;
                }
                // If the number is a noncharacter, then this is a noncharacter-character-reference parse error.
                else if (isNonCharacter(code)) {
                    parse_error = .noncharacter_character_reference;
                }
                // If the number is 0x0D, or a control that's not ASCII whitespace, then this is a control-character-reference parse error.
                else if (code == 0x0D or (code <= 0xFF and isControl(@intCast(code)) and !isAsciiWhitespace(@intCast(code)))) {
                    parse_error = .control_character_reference;
                }

                // Switch to the return state.
                self.state = state.ref.getReturnState();
                if (parse_error) |tag| {
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = tag,
                                .span = .{
                                    .start = state.ref.ampersand,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-start-state
            .comment_start => |comment_start| {
                if (!self.consume(src)) {
                    self.state = .{ .comment = comment_start };
                } else switch (self.current) {
                    // U+002D HYPHEN-MINUS (-)
                    // Switch to the comment start dash state.
                    '-' => self.state = .{
                        .comment_start_dash = comment_start,
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // This is an abrupt-closing-of-empty-comment parse error. Switch to the data state. Emit the current comment token.
                    '>' => {
                        self.state = .data;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .abrupt_closing_of_empty_comment,
                                    .span = .{
                                        .start = comment_start,
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
                    },
                    // Anything else
                    // Reconsume in the comment state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .comment = comment_start };
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#comment-start-dash-state
            .comment_start_dash => |comment_start| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-comment parse error. Emit the current comment token. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_comment,
                                .span = .{
                                    .start = comment_start,
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
                    // U+002D HYPHEN-MINUS (-)
                    // Switch to the comment end state.
                    '-' => self.state = .{ .comment_end = comment_start },
                    // U+003E GREATER-THAN SIGN (>)
                    // This is an abrupt-closing-of-empty-comment parse error. Switch to the data state. Emit the current comment token.
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
                            .deferred = .{
                                .comment = .{
                                    .start = comment_start,
                                    .end = self.idx,
                                },
                            },
                        };
                    },
                    // Anything else
                    // Append a U+002D HYPHEN-MINUS character (-) to the comment token's data. Reconsume in the comment state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .comment = comment_start };
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#comment-state
            .comment => |comment_start| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-comment parse error. Emit the current comment token. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_comment,
                                .span = .{
                                    .start = comment_start,
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
                    // U+003C LESS-THAN SIGN (<)
                    // Append the current input character to the comment token's data. Switch to the comment less-than sign state.
                    '<' => self.state = .{
                        .comment_less_than_sign = comment_start,
                    },
                    // U+002D HYPHEN-MINUS (-)
                    // Switch to the comment end dash state.
                    '-' => self.state = .{
                        .comment_end_dash = comment_start,
                    },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the comment token's data.
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
                        };
                    },
                    // Anything else
                    // Append the current input character to the comment token's data.
                    else => {},
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-less-than-sign-state
            .comment_less_than_sign => |comment_start| {
                if (!self.consume(src)) {
                    self.state = .{ .comment = comment_start };
                }
                switch (self.current) {
                    // U+0021 EXCLAMATION MARK (!)
                    // Append the current input character to the comment token's data. Switch to the comment less-than sign bang state.
                    '!' => self.state = .{
                        .comment_less_than_sign_bang = comment_start,
                    },
                    // U+003C LESS-THAN SIGN (<)
                    // Append the current input character to the comment token's data.
                    '<' => {},
                    // Anything else
                    // Reconsume in the comment state.
                    else => self.state = .{ .comment = comment_start },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-less-than-sign-bang-state
            .comment_less_than_sign_bang => |comment_start| {
                if (!self.consume(src)) {
                    self.state = .{ .comment = comment_start };
                }
                switch (self.current) {
                    // U+002D HYPHEN-MINUS (-)
                    // Switch to the comment less-than sign bang dash state.
                    '-' => self.state = .{
                        .comment_less_than_sign_bang_dash = comment_start,
                    },

                    // Anything else
                    // Reconsume in the comment state.
                    else => self.state = .{ .comment = comment_start },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-less-than-sign-bang-dash-state
            .comment_less_than_sign_bang_dash => |comment_start| {
                if (!self.consume(src)) {
                    self.state = .{ .comment_end_dash = comment_start };
                }
                switch (self.current) {
                    // U+002D HYPHEN-MINUS (-)
                    // Switch to the comment less-than sign bang dash dash state.
                    '-' => switch (self.state) {
                        else => unreachable,
                        .comment_less_than_sign_bang => {
                            self.state = .{
                                .comment_less_than_sign_bang_dash = comment_start,
                            };
                        },
                        .comment_less_than_sign_bang_dash => {
                            self.state = .{
                                .comment_less_than_sign_bang_dash_dash = comment_start,
                            };
                        },
                    },

                    // Anything else
                    // Reconsume in the comment end dash state.
                    else => self.state = .{ .comment_end_dash = comment_start },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#comment-less-than-sign-bang-dash-dash-state
            .comment_less_than_sign_bang_dash_dash,
            => |comment_start| {
                if (!self.consume(src)) {
                    self.state = .{ .comment_end = comment_start };
                }
                switch (self.current) {
                    // U+003E GREATER-THAN SIGN (>)
                    // EOF
                    // Reconsume in the comment end state.
                    '-' => {
                        self.idx -= 1;
                        self.state = .{ .comment_end = comment_start };
                    },

                    // Anything else
                    // This is a nested-comment parse error. Reconsume in the comment end state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .comment_end = comment_start };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .nested_comment,
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
            // https://html.spec.whatwg.org/multipage/parsing.html#comment-end-dash-state
            .comment_end_dash => |comment_start| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-comment parse error. Emit the current comment token. Emit an end-of-file token.
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
                    // U+002D HYPHEN-MINUS (-)
                    // Switch to the comment end state.
                    '-' => self.state = .{ .comment_end = comment_start },
                    // Anything else
                    // Append a U+002D HYPHEN-MINUS character (-) to the comment token's data. Reconsume in the comment state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .comment = comment_start };
                    },
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#comment-end-state
            .comment_end => |comment_start| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-comment parse error. Emit the current comment token. Emit an end-of-file token.
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
                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the data state. Emit the current comment token.
                    '>' => {
                        self.state = .data;
                        return .{
                            .token = .{
                                .comment = .{
                                    .start = comment_start,
                                    .end = self.idx,
                                },
                            },
                        };
                    },
                    // U+0021 EXCLAMATION MARK (!)
                    // Switch to the comment end bang state.
                    '!' => self.state = .{ .comment_end_bang = comment_start },
                    // U+002D HYPHEN-MINUS (-)
                    // Append a U+002D HYPHEN-MINUS character (-) to the comment token's data.
                    '-' => {},
                    // Anything else
                    // Append two U+002D HYPHEN-MINUS characters (-) to the comment token's data. Reconsume in the comment state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .comment = comment_start };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#comment-end-bang-state
            .comment_end_bang => |comment_start| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-comment parse error. Emit the current comment token. Emit an end-of-file token.
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
                    // U+002D HYPHEN-MINUS (-)
                    // Append two U+002D HYPHEN-MINUS characters (-) and a U+0021 EXCLAMATION MARK character (!) to the comment token's data. Switch to the comment end dash state.
                    '-' => self.state = .{ .comment_end_dash = comment_start },
                    // U+003E GREATER-THAN SIGN (>)
                    // This is an incorrectly-closed-comment parse error. Switch to the data state. Emit the current comment token.
                    '>' => {
                        self.state = .data;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .incorrectly_closed_comment,
                                    .span = .{
                                        .start = comment_start,
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
                    },
                    // Anything else
                    // Append two U+002D HYPHEN-MINUS characters (-) and a U+0021 EXCLAMATION MARK character (!) to the comment token's data. Reconsume in the comment state.
                    else => self.state = .{ .comment = comment_start },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#doctype-state
            .doctype => |lbracket| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-doctype parse error. Create a new DOCTYPE token. Set its force-quirks flag to on. Emit the current token. Emit an end-of-file token.
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
                                .force_quirks = true,
                                .name = null,
                                .span = .{
                                    .start = lbracket,
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
                    // Switch to the before DOCTYPE name state.
                    '\t', '\n', '\r', form_feed, ' ' => self.state = .{
                        .before_doctype_name = lbracket,
                    },

                    // U+003E GREATER-THAN SIGN (>)
                    // Reconsume in the before DOCTYPE name state.
                    '>' => {
                        self.idx -= 1;
                        self.state = .{ .before_doctype_name = lbracket };
                    },

                    // Anything else
                    // This is a missing-whitespace-before-doctype-name parse error. Reconsume in the before DOCTYPE name state.
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

            // https://html.spec.whatwg.org/multipage/parsing.html#before-doctype-name-state
            .before_doctype_name => |lbracket| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-doctype parse error. Create a new DOCTYPE token. Set its force-quirks flag to on. Emit the current token. Emit an end-of-file token.
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
                                .span = .{
                                    .start = lbracket,
                                    .end = self.idx,
                                },
                                .force_quirks = true,
                                .name = null,
                            },
                        },
                    };
                }
                switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Ignore the character.
                    '\t', '\n', '\r', form_feed, ' ' => {},
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Create a new DOCTYPE token. Set the token's name to a U+FFFD REPLACEMENT CHARACTER character. Switch to the DOCTYPE name state.
                    0 => {
                        self.state = .{
                            .doctype_name = .{
                                .lbracket = lbracket,
                                .name_start = self.idx - 1,
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
                    // U+003E GREATER-THAN SIGN (>)
                    // This is a missing-doctype-name parse error. Create a new DOCTYPE token. Set its force-quirks flag to on. Switch to the data state. Emit the current token.
                    '>' => {
                        self.idx -= 1;
                        self.state = .data;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_doctype_name,
                                    .span = .{
                                        .start = lbracket,
                                        .end = self.idx + 1,
                                    },
                                },
                            },
                            .deferred = .{
                                .doctype = .{
                                    .span = .{
                                        .start = lbracket,
                                        .end = self.idx + 1,
                                    },
                                    .force_quirks = true,
                                    .name = null,
                                },
                            },
                        };
                    },
                    // ASCII upper alpha
                    // Create a new DOCTYPE token. Set the token's name to the lowercase version of the current input character (add 0x0020 to the character's code point). Switch to the DOCTYPE name state.
                    // Anything else
                    // Create a new DOCTYPE token. Set the token's name to the current input character. Switch to the DOCTYPE name state.
                    else => {
                        self.state = .{
                            .doctype_name = .{
                                .lbracket = lbracket,
                                .name_start = self.idx - 1,
                            },
                        };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#doctype-name-state
            .doctype_name => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
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
                                .span = .{
                                    .start = state.lbracket,
                                    .end = self.idx + 1,
                                },
                                .force_quirks = true,
                                .name = null,
                            },
                        },
                    };
                }
                switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Switch to the after DOCTYPE name state.
                    '\t', '\n', '\r', form_feed, ' ' => {
                        self.state = .{
                            .after_doctype_name = .{
                                .lbracket = state.lbracket,
                                .name = .{
                                    .start = state.name_start,
                                    .end = self.idx - 1,
                                },
                            },
                        };
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the data state. Emit the current DOCTYPE token.
                    '>' => {
                        self.state = .data;
                        return .{
                            .token = .{
                                .doctype = .{
                                    .span = .{
                                        .start = state.lbracket,
                                        .end = self.idx,
                                    },
                                    .name = .{
                                        .start = state.name_start,
                                        .end = self.idx - 1,
                                    },
                                    .force_quirks = false,
                                },
                            },
                        };
                    },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current DOCTYPE token's name.
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
                    // Append the lowercase version of the current input character (add 0x0020 to the character's code point) to the current DOCTYPE token's name.
                    // Anything else
                    // Append the current input character to the current DOCTYPE token's name.
                    else => {},
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#after-doctype-name-state
            .after_doctype_name => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
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
                                .span = .{
                                    .start = state.lbracket,
                                    .end = self.idx,
                                },
                                .name = state.name,
                                .force_quirks = true,
                            },
                        },
                    };
                }
                switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Ignore the character.
                    '\t', '\n', '\r', form_feed, ' ' => {},
                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the data state. Emit the current DOCTYPE token.
                    '>' => {
                        self.state = .data;
                        return .{
                            .token = .{
                                .doctype = .{
                                    .span = .{
                                        .start = state.lbracket,
                                        .end = self.idx,
                                    },
                                    .name = state.name,
                                    .force_quirks = false,
                                },
                            },
                        };
                    },

                    // Anything else
                    else => {
                        self.idx -= 1;
                        if (self.nextCharsAreIgnoreCase("PUBLIC", src)) {
                            // If the six characters starting from the current input character are an ASCII case-insensitive match for the word "PUBLIC", then consume those characters and switch to the after DOCTYPE public keyword state.
                            self.state = .{
                                .after_doctype_public_kw = .{
                                    .span = .{
                                        .start = state.lbracket,
                                        .end = 0,
                                    },
                                    .name = state.name,
                                    .extra = .{
                                        .start = self.idx,
                                        .end = 0,
                                    },
                                    .force_quirks = false,
                                },
                            };

                            self.idx += @intCast("PUBLIC".len);
                        } else if (self.nextCharsAreIgnoreCase("SYSTEM", src)) {
                            // Otherwise, if the six characters starting from the current input character are an ASCII case-insensitive match for the word "SYSTEM", then consume those characters and switch to the after DOCTYPE system keyword state.
                            self.state = .{
                                .after_doctype_system_kw = .{
                                    .span = .{
                                        .start = state.lbracket,
                                        .end = 0,
                                    },
                                    .name = state.name,
                                    .extra = .{
                                        .start = self.idx - 1,
                                        .end = 0,
                                    },
                                    .force_quirks = false,
                                },
                            };
                            self.idx += @intCast("SYSTEM".len);
                        } else {
                            // Otherwise, this is an invalid-character-sequence-after-doctype-name parse error. Set the current DOCTYPE token's force-quirks flag to on. Reconsume in the bogus DOCTYPE state.
                            self.idx -= 1;
                            self.state = .{
                                .bogus_doctype = .{
                                    .span = .{
                                        .start = state.lbracket,
                                        .end = 0,
                                    },
                                    .name = state.name,
                                    .extra = .{
                                        .start = self.idx - 1,
                                        .end = 0,
                                    },
                                    .force_quirks = true,
                                },
                            };
                            return .{
                                .token = .{
                                    .parse_error = .{
                                        .tag = .invalid_character_sequence_after_doctype_name,
                                        .span = .{
                                            .start = self.idx,
                                            .end = self.idx + 1,
                                        },
                                    },
                                },
                            };
                        }
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#after-doctype-public-keyword-state
            .after_doctype_public_kw => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
                    self.state = .eof;
                    var tag = state;
                    tag.force_quirks = true;
                    tag.span.end = self.idx;
                    tag.extra.end = self.idx;
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
                        .deferred = .{ .doctype = tag },
                    };
                }
                switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Switch to the before DOCTYPE public identifier state.
                    '\t', '\n', '\r', form_feed, ' ' => {
                        self.state = .{
                            .before_doctype_public_identifier = state,
                        };
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // This is a missing-doctype-public-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Switch to the data state. Emit the current DOCTYPE token.
                    '>' => {
                        self.state = .data;
                        var tag = state;
                        tag.force_quirks = true;
                        tag.span.end = self.idx;
                        tag.extra.end = self.idx - 1;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_doctype_public_identifier,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                            .deferred = .{ .doctype = tag },
                        };
                    },
                    // U+0022 QUOTATION MARK (")
                    // This is a missing-whitespace-after-doctype-public-keyword parse error. Set the current DOCTYPE token's public identifier to the empty string (not missing), then switch to the DOCTYPE public identifier (double-quoted) state.
                    '"' => {
                        self.state = .{
                            .doctype_public_identifier_double = state,
                        };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_whitespace_after_doctype_public_keyword,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                    // U+0027 APOSTROPHE (')
                    // This is a missing-whitespace-after-doctype-public-keyword parse error. Set the current DOCTYPE token's public identifier to the empty string (not missing), then switch to the DOCTYPE public identifier (single-quoted) state.
                    '\'' => {
                        self.state = .{
                            .doctype_public_identifier_single = state,
                        };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_whitespace_after_doctype_public_keyword,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },

                    // Anything else
                    // This is a missing-quote-before-doctype-public-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Reconsume in the bogus DOCTYPE state.
                    else => {
                        self.idx -= 1;
                        var tag = state;
                        tag.force_quirks = true;
                        self.state = .{ .bogus_doctype = tag };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_quote_before_doctype_public_identifier,
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

            // https://html.spec.whatwg.org/multipage/parsing.html#before-doctype-public-identifier-state
            .before_doctype_public_identifier => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
                    var tag = state;
                    tag.force_quirks = true;
                    tag.span.end = self.idx;
                    tag.extra.end = self.idx;

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
                        .deferred = .{ .doctype = tag },
                    };
                }
                switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Ignore the character.
                    '\t', '\n', '\r', form_feed, ' ' => {},

                    // U+0022 QUOTATION MARK (")
                    // Set the current DOCTYPE token's public identifier to the empty string (not missing), then switch to the DOCTYPE public identifier (double-quoted) state.
                    '"' => {
                        self.state = .{
                            .doctype_public_identifier_double = state,
                        };
                    },
                    // U+0027 APOSTROPHE (')
                    // Set the current DOCTYPE token's public identifier to the empty string (not missing), then switch to the DOCTYPE public identifier (single-quoted) state.
                    '\'' => {
                        self.state = .{
                            .doctype_public_identifier_single = state,
                        };
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // This is a missing-doctype-public-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Switch to the data state. Emit the current DOCTYPE token.
                    '>' => {
                        var tag = state;
                        tag.force_quirks = true;
                        tag.span.end = self.idx;
                        tag.extra.end = self.idx - 1;

                        self.state = .data;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_doctype_public_identifier,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                            .deferred = .{ .doctype = tag },
                        };
                    },
                    // Anything else
                    // This is a missing-quote-before-doctype-public-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Reconsume in the bogus DOCTYPE state.
                    else => {
                        var tag = state;
                        tag.force_quirks = true;

                        self.idx -= 1;
                        self.state = .{ .bogus_doctype = tag };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_quote_before_doctype_public_identifier,
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
            // https://html.spec.whatwg.org/multipage/parsing.html#doctype-public-identifier-(double-quoted)-state
            // https://html.spec.whatwg.org/multipage/parsing.html#doctype-public-identifier-(single-quoted)-state
            .doctype_public_identifier_double,
            .doctype_public_identifier_single,
            => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
                    var tag = state;
                    tag.force_quirks = true;
                    tag.span.end = self.idx;
                    tag.extra.end = self.idx;

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
                        .deferred = .{ .doctype = tag },
                    };
                }
                switch (self.current) {
                    // U+0022 QUOTATION MARK (")
                    // Switch to the after DOCTYPE public identifier state.
                    // U+0027 APOSTROPHE (')
                    // Switch to the after DOCTYPE public identifier state.
                    '"', '\'' => {
                        const double = self.current == '"' and self.state == .doctype_public_identifier_double;
                        const single = self.current == '\'' and self.state == .doctype_public_identifier_single;
                        if (single or double) {
                            self.state = .{
                                .after_doctype_public_identifier = state,
                            };
                        }
                    },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current DOCTYPE token's public identifier.
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
                    // This is an abrupt-doctype-public-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Switch to the data state. Emit the current DOCTYPE token.
                    '>' => {
                        var tag = state;
                        tag.force_quirks = true;
                        tag.span.end = self.idx;
                        tag.extra.end = self.idx - 1;

                        self.state = .data;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .abrupt_doctype_public_identifier,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                            .deferred = .{ .doctype = tag },
                        };
                    },

                    // Anything else
                    // Append the current input character to the current DOCTYPE token's public identifier.
                    else => {},
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#after-doctype-public-identifier-state
            .after_doctype_public_identifier => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
                    var tag = state;
                    tag.force_quirks = true;
                    tag.span.end = self.idx;
                    tag.extra.end = self.idx;

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
                        .deferred = .{ .doctype = tag },
                    };
                }
                switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Switch to the between DOCTYPE public and system identifiers state.
                    '\t', '\n', '\r', form_feed, ' ' => {
                        self.state = .{
                            .beteen_doctype_public_and_system_identifiers = state,
                        };
                    },
                    // U+0022 QUOTATION MARK (")
                    // This is a missing-whitespace-between-doctype-public-and-system-identifiers parse error. Set the current DOCTYPE token's system identifier to the empty string (not missing), then switch to the DOCTYPE system identifier (double-quoted) state.
                    '"' => {
                        self.state = .{
                            .doctype_system_identifier_double = state,
                        };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_whitespace_between_doctype_public_and_system_identifiers,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                    // U+0027 APOSTROPHE (')
                    // This is a missing-whitespace-between-doctype-public-and-system-identifiers parse error. Set the current DOCTYPE token's system identifier to the empty string (not missing), then switch to the DOCTYPE system identifier (single-quoted) state.
                    '\'' => {
                        self.state = .{
                            .doctype_system_identifier_single = state,
                        };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_whitespace_between_doctype_public_and_system_identifiers,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },

                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the data state. Emit the current DOCTYPE token.
                    '>' => {
                        self.state = .data;
                        var tag = state;
                        tag.span.end = self.idx;
                        tag.extra.end = self.idx - 1;
                        return .{ .token = .{ .doctype = tag } };
                    },

                    // Anything else
                    // This is a missing-quote-before-doctype-system-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Reconsume in the bogus DOCTYPE state.
                    else => {
                        var tag = state;
                        tag.force_quirks = true;

                        self.idx -= 1;
                        self.state = .{ .bogus_doctype = tag };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_quote_before_doctype_system_identifier,
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
            // https://html.spec.whatwg.org/multipage/parsing.html#between-doctype-public-and-system-identifiers-state
            .beteen_doctype_public_and_system_identifiers => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
                    var tag = state;
                    tag.force_quirks = true;
                    tag.span.end = self.idx;
                    tag.extra.end = self.idx;

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
                        .deferred = .{ .doctype = tag },
                    };
                }
                switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Ignore the character.
                    '\t', '\n', '\r', form_feed, ' ' => {},
                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the data state. Emit the current DOCTYPE token.
                    '>' => {
                        self.state = .data;
                        var tag = state;
                        tag.span.end = self.idx;
                        tag.extra.end = self.idx - 1;
                        return .{ .token = .{ .doctype = tag } };
                    },
                    // U+0022 QUOTATION MARK (")
                    // Set the current DOCTYPE token's system identifier to the empty string (not missing), then switch to the DOCTYPE system identifier (double-quoted) state.
                    '"' => {
                        self.state = .{
                            .doctype_system_identifier_double = state,
                        };
                    },
                    // U+0027 APOSTROPHE (')
                    // Set the current DOCTYPE token's system identifier to the empty string (not missing), then switch to the DOCTYPE system identifier (single-quoted) state.
                    '\'' => {
                        self.state = .{
                            .doctype_system_identifier_single = state,
                        };
                    },

                    // Anything else
                    // This is a missing-quote-before-doctype-system-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Reconsume in the bogus DOCTYPE state.
                    else => {
                        self.idx -= 1;
                        self.state = .{
                            .bogus_doctype = state,
                        };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_quote_before_doctype_system_identifier,
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

            // https://html.spec.whatwg.org/multipage/parsing.html#after-doctype-system-keyword-state
            .after_doctype_system_kw => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
                    var tag = state;
                    tag.force_quirks = true;
                    tag.span.end = self.idx;
                    tag.extra.end = self.idx;

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
                        .deferred = .{ .doctype = tag },
                    };
                }
                switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Switch to the before DOCTYPE system identifier state.
                    '\t', '\n', '\r', form_feed, ' ' => {
                        self.state = .{
                            .before_doctype_system_identifier = state,
                        };
                    },
                    // U+0022 QUOTATION MARK (")
                    // This is a missing-whitespace-after-doctype-system-keyword parse error. Set the current DOCTYPE token's system identifier to the empty string (not missing), then switch to the DOCTYPE system identifier (double-quoted) state.
                    '"' => {
                        self.state = .{
                            .doctype_system_identifier_double = state,
                        };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_whitespace_after_doctype_system_keyword,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                    // U+0027 APOSTROPHE (')
                    // This is a missing-whitespace-after-doctype-system-keyword parse error. Set the current DOCTYPE token's system identifier to the empty string (not missing), then switch to the DOCTYPE system identifier (single-quoted) state.
                    '\'' => {
                        self.state = .{
                            .doctype_public_identifier_single = state,
                        };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_whitespace_after_doctype_system_keyword,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                        };
                    },
                    // U+003E GREATER-THAN SIGN (>)
                    // This is a missing-doctype-system-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Switch to the data state. Emit the current DOCTYPE token.
                    '>' => {
                        var tag = state;
                        tag.force_quirks = true;
                        tag.span.end = self.idx;
                        tag.extra.end = self.idx - 1;

                        self.state = .data;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_doctype_system_identifier,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                            .deferred = .{ .doctype = tag },
                        };
                    },
                    // Anything else
                    // This is a missing-quote-before-doctype-system-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Reconsume in the bogus DOCTYPE state.
                    else => {
                        var tag = state;
                        tag.force_quirks = true;

                        self.idx -= 1;
                        self.state = .{ .bogus_doctype = tag };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_quote_before_doctype_system_identifier,
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

            // https://html.spec.whatwg.org/multipage/parsing.html#before-doctype-system-identifier-state
            .before_doctype_system_identifier => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
                    var tag = state;
                    tag.force_quirks = true;
                    tag.span.end = self.idx;
                    tag.extra.end = self.idx;

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
                        .deferred = .{ .doctype = tag },
                    };
                }
                switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Ignore the character.
                    '\t', '\n', '\r', form_feed, ' ' => {},

                    // U+0022 QUOTATION MARK (")
                    // Set the current DOCTYPE token's system identifier to the empty string (not missing), then switch to the DOCTYPE system identifier (double-quoted) state.
                    '"' => {
                        self.state = .{
                            .doctype_system_identifier_double = state,
                        };
                    },
                    // U+0027 APOSTROPHE (')
                    // Set the current DOCTYPE token's system identifier to the empty string (not missing), then switch to the DOCTYPE system identifier (single-quoted) state.
                    '\'' => {
                        self.state = .{
                            .doctype_system_identifier_single = state,
                        };
                    },

                    // U+003E GREATER-THAN SIGN (>)
                    // This is a missing-doctype-system-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Switch to the data state. Emit the current DOCTYPE token.
                    '>' => {
                        var tag = state;
                        tag.force_quirks = true;
                        tag.span.end = self.idx;
                        tag.extra.end = self.idx - 1;

                        self.state = .data;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_doctype_system_identifier,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                            .deferred = .{ .doctype = tag },
                        };
                    },
                    // Anything else
                    // This is a missing-quote-before-doctype-system-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Reconsume in the bogus DOCTYPE state.
                    else => {
                        var tag = state;
                        tag.force_quirks = true;
                        self.state = .{
                            .bogus_doctype = tag,
                        };
                        self.idx -= 1;

                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .missing_quote_before_doctype_system_identifier,
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
            // https://html.spec.whatwg.org/multipage/parsing.html#doctype-system-identifier-(double-quoted)-state
            // https://html.spec.whatwg.org/multipage/parsing.html#doctype-system-identifier-(double-quoted)-state
            .doctype_system_identifier_double,
            .doctype_system_identifier_single,
            => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
                    var tag = state;
                    tag.force_quirks = true;
                    tag.span.end = self.idx;
                    tag.extra.end = self.idx;

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
                        .deferred = .{ .doctype = tag },
                    };
                }
                switch (self.current) {
                    // U+0022 QUOTATION MARK (")
                    // Switch to the after DOCTYPE system identifier state.
                    // U+0027 APOSTROPHE (')
                    // Switch to the after DOCTYPE system identifier state.
                    '"', '\'' => {
                        const double = self.current == '"' and self.state == .doctype_system_identifier_double;
                        const single = self.current == '\'' and self.state == .doctype_system_identifier_single;
                        if (single or double) {
                            self.state = .{
                                .after_doctype_system_identifier = state,
                            };
                        }
                    },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current DOCTYPE token's public identifier.
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
                    // This is an abrupt-doctype-system-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Switch to the data state. Emit the current DOCTYPE token.
                    '>' => {
                        var tag = state;
                        tag.force_quirks = true;
                        tag.span.end = self.idx;
                        tag.extra.end = self.idx - 1;

                        self.state = .data;
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .abrupt_doctype_system_identifier,
                                    .span = .{
                                        .start = self.idx - 1,
                                        .end = self.idx,
                                    },
                                },
                            },
                            .deferred = .{ .doctype = tag },
                        };
                    },

                    // Anything else
                    // Append the current input character to the current DOCTYPE token's system identifier.
                    else => {},
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#after-doctype-system-identifier-state
            .after_doctype_system_identifier => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
                    var tag = state;
                    tag.force_quirks = true;
                    tag.span.end = self.idx;
                    tag.extra.end = self.idx;

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
                        .deferred = .{ .doctype = tag },
                    };
                }
                switch (self.current) {
                    // U+0009 CHARACTER TABULATION (tab)
                    // U+000A LINE FEED (LF)
                    // U+000C FORM FEED (FF)
                    // U+0020 SPACE
                    // Ignore the character.
                    '\t', '\n', '\r', form_feed, ' ' => {},

                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the data state. Emit the current DOCTYPE token.
                    '>' => {
                        var tag = state;
                        tag.span.end = self.idx;
                        tag.extra.end = self.idx - 1;

                        self.state = .data;
                        return .{ .token = .{ .doctype = tag } };
                    },
                    // Anything else
                    // This is an unexpected-character-after-doctype-system-identifier parse error. Reconsume in the bogus DOCTYPE state. (This does not set the current DOCTYPE token's force-quirks flag to on.)
                    else => {
                        self.idx -= 1;
                        self.state = .{ .bogus_doctype = state };
                        return .{
                            .token = .{
                                .parse_error = .{
                                    .tag = .unexpected_character_after_doctype_system_identifier,
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

            // https://html.spec.whatwg.org/multipage/parsing.html#bogus-doctype-state
            .bogus_doctype => |state| {
                if (!self.consume(src)) {
                    // EOF
                    // Emit the DOCTYPE token. Emit an end-of-file token.
                    self.state = .eof;
                    var tag = state;
                    tag.span.end = self.idx;
                    tag.extra.end = self.idx;
                    return .{
                        .token = .{ .doctype = tag },
                    };
                }
                switch (self.current) {
                    // U+003E GREATER-THAN SIGN (>)
                    // Switch to the data state. Emit the DOCTYPE token.
                    '>' => {
                        self.state = .data;
                        var tag = state;
                        tag.span.end = self.idx;
                        tag.extra.end = self.idx - 1;
                        return .{
                            .token = .{ .doctype = tag },
                        };
                    },
                    // U+0000 NULL
                    // This is an unexpected-null-character parse error. Ignore the character.
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
                        };
                    },

                    // Anything else
                    // Ignore the character.
                    else => {},
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#cdata-section-state
            .cdata_section => |lbracket| {
                if (!self.consume(src)) {
                    // EOF
                    // This is an eof-in-cdata parse error. Emit an end-of-file token.
                    self.state = .eof;
                    return .{
                        .token = .{
                            .parse_error = .{
                                .tag = .eof_in_cdata,
                                .span = .{
                                    .start = lbracket,
                                    .end = self.idx,
                                },
                            },
                        },
                    };
                }
                switch (self.current) {
                    // U+005D RIGHT SQUARE BRACKET (])
                    // Switch to the CDATA section bracket state.
                    ']' => self.state = .{
                        .cdata_section_bracket = lbracket,
                    },
                    // Anything else
                    // Emit the current input character as a character token.
                    else => {},
                }
            },
            // https://html.spec.whatwg.org/multipage/parsing.html#cdata-section-bracket-state
            .cdata_section_bracket => |lbracket| {
                if (!self.consume(src)) {
                    self.state = .{ .cdata_section = lbracket };
                }
                switch (self.current) {
                    // U+005D RIGHT SQUARE BRACKET (])
                    // Switch to the CDATA section end state.
                    ']' => self.state = .{ .cdata_section_end = lbracket },
                    // Anything else
                    // Emit a U+005D RIGHT SQUARE BRACKET character token. Reconsume in the CDATA section state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .cdata_section = lbracket };
                    },
                }
            },

            // https://html.spec.whatwg.org/multipage/parsing.html#cdata-section-end-state
            .cdata_section_end => |lbracket| {
                if (!self.consume(src)) {
                    self.state = .{ .cdata_section = lbracket };
                }
                switch (self.current) {
                    // U+005D RIGHT SQUARE BRACKET (])
                    // Emit a U+005D RIGHT SQUARE BRACKET character token.
                    ']' => {},
                    // U+003E GREATER-THAN SIGN character
                    // Switch to the data state.
                    '>' => {
                        self.state = .data;
                        return .{
                            .token = .{
                                .comment = .{
                                    .start = lbracket,
                                    .end = self.idx,
                                },
                            },
                        };
                    },
                    // Anything else
                    // Emit two U+005D RIGHT SQUARE BRACKET character tokens. Reconsume in the CDATA section state.
                    else => {
                        self.idx -= 1;
                        self.state = .{ .cdata_section = lbracket };
                    },
                }
            },

            .eof => return null,
        }
    }
}

pub fn gotoScriptData(self: *Tokenizer) void {
    self.state = .{ .script_data = self.idx };
    self.last_start_tag_name = "script";
}

pub fn gotoRcData(self: *Tokenizer, tag_name: []const u8) void {
    self.state = .{ .rcdata = self.idx };
    self.last_start_tag_name = tag_name;
}

pub fn gotoRawText(self: *Tokenizer, tag_name: []const u8) void {
    self.state = .{ .rawtext = self.idx };
    self.last_start_tag_name = tag_name;
}

pub fn gotoPlainText(self: *Tokenizer) void {
    self.state = .{ .plaintext = self.idx };
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
// https://infra.spec.whatwg.org/#noncharacter
fn isNonCharacter(c: u21) bool {
    return switch (c) {
        // zig fmt: off
        '\u{FDD0}'...'\u{FDEF}',
        '\u{FFFE}', '\u{FFFF}', '\u{1FFFE}', '\u{1FFFF}', '\u{2FFFE}', '\u{2FFFF}', '\u{3FFFE}',
        '\u{3FFFF}', '\u{4FFFE}', '\u{4FFFF}', '\u{5FFFE}', '\u{5FFFF}', '\u{6FFFE}', '\u{6FFFF}',
        '\u{7FFFE}', '\u{7FFFF}', '\u{8FFFE}', '\u{8FFFF}', '\u{9FFFE}', '\u{9FFFF}', '\u{AFFFE}',
        '\u{AFFFF}', '\u{BFFFE}', '\u{BFFFF}', '\u{CFFFF}', '\u{DFFFE}', '\u{DFFFF}', '\u{EFFFE}',
        '\u{EFFFF}', '\u{FFFFE}', '\u{FFFFF}', '\u{10FFFE}', '\u{10FFFF}',
        // zig fmt: on
        => true,
        else => false,
    };
}
// https://infra.spec.whatwg.org/#control
fn isControl(c: u8) bool {
    // A control is a C0 control or a code point in the range U+007F DELETE to U+009F APPLICATION PROGRAM COMMAND, inclusive.
    // A C0 control is a code point in the range U+0000 NULL to U+001F INFORMATION SEPARATOR ONE, inclusive.
    return (c >= 0 and c <= 0x1F) or (c >= 0x7F and c <= 0x9F);
}
// https://infra.spec.whatwg.org/#ascii-whitespace
fn isAsciiWhitespace(c: u8) bool {
    return switch (c) {
        // ASCII whitespace is U+0009 TAB, U+000A LF, U+000C FF, U+000D CR, or U+0020 SPACE.
        '\t', '\n', form_feed, '\r', ' ' => true,
        else => false,
    };
}

const tl = std.log.scoped(.trim);

fn trimmedText(start: u32, end: u32, src: []const u8) ?Span {
    var text_span: Span = .{ .start = start, .end = end };

    tl.debug("span: {any}, txt: '{s}'", .{
        text_span,
        text_span.slice(src),
    });

    while (text_span.start < end and
        std.ascii.isWhitespace(src[text_span.start]))
    {
        text_span.start += 1;
    }

    while (text_span.end > text_span.start and
        std.ascii.isWhitespace(src[text_span.end - 1]))
    {
        text_span.end -= 1;
    }

    tl.debug("end span: {any}, txt: '{s}'", .{
        text_span,
        text_span.slice(src),
    });

    if (text_span.start == text_span.end) {
        return null;
    }

    return text_span;
}

test "script single/double escape weirdness" {
    // TODO: Get this test passing
    if (true) return error.SkipZigTest;

    // case from https://stackoverflow.com/questions/23727025/script-double-escaped-state
    const case =
        \\<script>
        \\<!--script data escaped-->
        \\</script>    
        \\
        \\<script>
        \\<!--<script>script data double escaped</script>-->
        \\</script>
    ;

    // TODO: fix also the expected results!

    var tokenizer: Tokenizer = .{};
    var t = tokenizer.next(case);
    errdefer std.debug.print("t = {any}\n", .{t});

    // first half
    {
        try std.testing.expect(t != null);
        try std.testing.expect(t.? == .tag);
        try std.testing.expect(t.?.tag.kind == .start);
    }
    {
        t = tokenizer.next(case);
        try std.testing.expect(t != null);
        try std.testing.expect(t.? == .text);
    }
    {
        t = tokenizer.next(case);
        try std.testing.expect(t != null);
        try std.testing.expect(t.? == .tag);
        try std.testing.expect(t.?.tag.kind == .end);
    }

    // Second half

    {
        try std.testing.expect(t != null);
        try std.testing.expect(t.? == .tag);
        try std.testing.expect(t.?.tag.kind == .start);
    }
    {
        t = tokenizer.next(case);
        try std.testing.expect(t != null);
        try std.testing.expect(t.? == .text);
    }
    {
        t = tokenizer.next(case);
        try std.testing.expect(t != null);
        try std.testing.expect(t.? == .tag);
        try std.testing.expect(t.?.tag.kind == .end);
    }

    t = tokenizer.next(case);
    try std.testing.expect(t == null);
}

test "character references" {
    // Named character references
    try testTokenize("&", &.{
        .{ .text = .{ .start = 0, .end = 1 } },
    });
    try testTokenize("&foo", &.{
        .{ .text = .{ .start = 0, .end = 4 } },
    });
    try testTokenize("&foo;", &.{
        .{ .parse_error = .{
            .tag = .unknown_named_character_reference,
            .span = .{ .start = 0, .end = 4 },
        } },
        .{ .text = .{ .start = 0, .end = 5 } },
    });
    try testTokenize("&foofoofoofoofoofoofoofoofoo;", &.{
        .{ .parse_error = .{
            .tag = .unknown_named_character_reference,
            .span = .{ .start = 0, .end = 28 },
        } },
        .{ .text = .{ .start = 0, .end = 29 } },
    });
    try testTokenize("&noti", &.{
        .{ .parse_error = .{
            .tag = .missing_semicolon_after_character_reference,
            .span = .{ .start = 0, .end = 4 },
        } },
        .{ .text = .{ .start = 0, .end = 5 } },
    });
    // Example from https://html.spec.whatwg.org/multipage/parsing.html#named-character-reference-state
    // `&not` is valid, `&noti` could still match `&notin;` among others,
    // but `&notit;` is not a named character reference, so we get
    // a missing semicolon error for `&not`
    try testTokenize("&notit;", &.{
        .{ .parse_error = .{
            .tag = .missing_semicolon_after_character_reference,
            .span = .{ .start = 0, .end = 4 },
        } },
        .{ .text = .{ .start = 0, .end = 7 } },
    });
    try testTokenize("hello &notin;", &.{
        .{ .text = .{ .start = 0, .end = 13 } },
    });
    try testTokenize("hello&notin;", &.{
        .{ .text = .{ .start = 0, .end = 12 } },
    });
    try testTokenize("hello &foo bar", &.{
        .{ .text = .{ .start = 0, .end = 14 } },
    });
    try testTokenize("hello&foo", &.{
        .{ .text = .{ .start = 0, .end = 9 } },
    });

    // Numeric character references
    try testTokenize("&#123; &#x123;", &.{
        .{ .text = .{ .start = 0, .end = 14 } },
    });
    try testTokenize("&#", &.{
        .{ .parse_error = .{
            .tag = .absence_of_digits_in_numeric_character_reference,
            .span = .{ .start = 0, .end = 2 },
        } },
        .{ .text = .{ .start = 0, .end = 2 } },
    });
    try testTokenize("&#x10FFFF", &.{
        .{ .parse_error = .{
            .tag = .missing_semicolon_after_character_reference,
            .span = .{ .start = 0, .end = 9 },
        } },
        .{ .parse_error = .{
            .tag = .noncharacter_character_reference,
            .span = .{ .start = 0, .end = 9 },
        } },
        .{ .text = .{ .start = 0, .end = 9 } },
    });
    try testTokenize("&#x110000", &.{
        .{ .parse_error = .{
            .tag = .missing_semicolon_after_character_reference,
            .span = .{ .start = 0, .end = 9 },
        } },
        .{ .parse_error = .{
            .tag = .character_reference_outside_unicode_range,
            .span = .{ .start = 0, .end = 9 },
        } },
        .{ .text = .{ .start = 0, .end = 9 } },
    });
    try testTokenize("&#xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;", &.{
        .{ .parse_error = .{
            .tag = .character_reference_outside_unicode_range,
            .span = .{ .start = 0, .end = 37 },
        } },
        .{ .text = .{ .start = 0, .end = 37 } },
    });
    try testTokenize("&#0;", &.{
        .{ .parse_error = .{
            .tag = .null_character_reference,
            .span = .{ .start = 0, .end = 4 },
        } },
        .{ .text = .{ .start = 0, .end = 4 } },
    });
    try testTokenize("&#x0D;", &.{
        .{ .parse_error = .{
            .tag = .control_character_reference,
            .span = .{ .start = 0, .end = 6 },
        } },
        .{ .text = .{ .start = 0, .end = 6 } },
    });
    try testTokenize("&#x9F;", &.{
        .{ .parse_error = .{
            .tag = .control_character_reference,
            .span = .{ .start = 0, .end = 6 },
        } },
        .{ .text = .{ .start = 0, .end = 6 } },
    });
    try testTokenize("&#xDF00;", &.{
        .{ .parse_error = .{
            .tag = .surrogate_character_reference,
            .span = .{ .start = 0, .end = 8 },
        } },
        .{ .text = .{ .start = 0, .end = 8 } },
    });
    try testTokenize("&#xFFFF;", &.{
        .{ .parse_error = .{
            .tag = .noncharacter_character_reference,
            .span = .{ .start = 0, .end = 8 },
        } },
        .{ .text = .{ .start = 0, .end = 8 } },
    });

    // double quoted attribute
    try testTokenize("<span foo=\"&not\">", &.{
        .{ .parse_error = .{
            .tag = .missing_semicolon_after_character_reference,
            .span = .{ .start = 11, .end = 15 },
        } },
        .{ .tag = .{
            .span = .{ .start = 0, .end = 17 },
            .name = .{ .start = 1, .end = 5 },
            .attr_count = 1,
            .kind = .start,
        } },
    });
    try testTokenize("<span foo=\"&notit;\">", &.{
        .{ .parse_error = .{
            .tag = .missing_semicolon_after_character_reference,
            .span = .{ .start = 11, .end = 15 },
        } },
        .{ .tag = .{
            .span = .{ .start = 0, .end = 20 },
            .name = .{ .start = 1, .end = 5 },
            .attr_count = 1,
            .kind = .start,
        } },
    });

    // single quoted attribute
    try testTokenize("<span foo='&not'>", &.{
        .{ .parse_error = .{
            .tag = .missing_semicolon_after_character_reference,
            .span = .{ .start = 11, .end = 15 },
        } },
        .{ .tag = .{
            .span = .{ .start = 0, .end = 17 },
            .name = .{ .start = 1, .end = 5 },
            .attr_count = 1,
            .kind = .start,
        } },
    });
    try testTokenize("<span foo='&notit;'>", &.{
        .{ .parse_error = .{
            .tag = .missing_semicolon_after_character_reference,
            .span = .{ .start = 11, .end = 15 },
        } },
        .{ .tag = .{
            .span = .{ .start = 0, .end = 20 },
            .name = .{ .start = 1, .end = 5 },
            .attr_count = 1,
            .kind = .start,
        } },
    });

    // unquoted attribute
    try testTokenize("<span foo=&not>", &.{
        .{ .parse_error = .{
            .tag = .missing_semicolon_after_character_reference,
            .span = .{ .start = 10, .end = 14 },
        } },
        .{ .tag = .{
            .span = .{ .start = 0, .end = 15 },
            .name = .{ .start = 1, .end = 5 },
            .attr_count = 1,
            .kind = .start,
        } },
    });
    try testTokenize("<span foo=&notit;>", &.{
        .{ .parse_error = .{
            .tag = .missing_semicolon_after_character_reference,
            .span = .{ .start = 10, .end = 14 },
        } },
        .{ .tag = .{
            .span = .{ .start = 0, .end = 18 },
            .name = .{ .start = 1, .end = 5 },
            .attr_count = 1,
            .kind = .start,
        } },
    });
}

test "rcdata character references" {
    var tokenizer: Tokenizer = .{ .language = .html };
    tokenizer.gotoRcData("title");

    try testTokenizeWithState(&tokenizer, "&notit;</title>", &.{
        .{ .parse_error = .{
            .tag = .missing_semicolon_after_character_reference,
            .span = .{ .start = 0, .end = 4 },
        } },
        .{ .text = .{ .start = 0, .end = 7 } },
        .{ .tag = .{
            .span = .{ .start = 7, .end = 15 },
            .name = .{ .start = 9, .end = 14 },
            .kind = .end,
        } },
    });
}

fn testTokenizeWithState(tokenizer: *Tokenizer, src: []const u8, expected_tokens: []const Token) !void {
    for (expected_tokens, 0..) |expected_token, i| {
        const t = tokenizer.next(src);
        std.testing.expectEqual(expected_token, t) catch |e| {
            std.debug.print("unexpected token at index {}\nexpected: {any}\nactual: {any}\n", .{ i, expected_token, t });
            return e;
        };
    }

    const t = tokenizer.next(src);
    try std.testing.expect(t == null);
}

fn testTokenize(src: []const u8, expected_tokens: []const Token) !void {
    var tokenizer: Tokenizer = .{ .language = .html };
    return testTokenizeWithState(&tokenizer, src, expected_tokens);
}
