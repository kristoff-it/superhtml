/// From https://github.com/marler8997/html-css-renderer/blob/master/HtmlTokenizer.zig
///
/// An html5 tokenizer.
/// Implements the state machine described here:
///     https://html.spec.whatwg.org/multipage/parsing.html#tokenization
/// This tokenizer does not perform any processing/allocation, it simply
/// splits the input text into higher-level tokens.
const Tokenizer = @This();

const std = @import("std");

const log = std.log.scoped(.tokenizer);

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

pub const Token = union(enum) {
    doctype: Doctype,
    doctype_rbracket: u32,
    start_tag: struct {
        lbracket: u32, // index of "<"
        name: Span,
        pub fn isVoid(st: @This(), src: []const u8) bool {
            // TODO find all the void tags
            const tags: []const []const u8 = &.{
                "link",
                "meta",
                "br",
            };

            for (tags) |t| {
                if (std.ascii.eqlIgnoreCase(st.name.slice(src), t)) {
                    return true;
                }
            }
            return false;
        }
    },
    start_tag_rbracket: u32,
    end_tag: struct {
        lbracket: u32, // index of "<"
        name: Span,
    },
    end_tag_rbracket: u32,
    start_tag_self_closed: Span,
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
    comment: Span,
    text: Span,
    parse_error: enum {
        unexpected_null_character,
        invalid_first_character_of_tag_name,
        incorrectly_opened_comment,
        missing_end_tag_name,
        eof_before_tag_name,
        eof_in_doctype,
        eof_in_tag,
        eof_in_comment,
        missing_whitespace_before_doctype_name,
        unexpected_character_in_attribute_name,
        missing_attribute_value,
        unexpected_solidus_in_tag,
        abrupt_closing_of_empty_comment,
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
    tag_name: struct {
        is_end: bool,
        start: u32,
        lbracket: u32,
    },
    self_closing_start_tag: void,
    before_attribute_name: void,
    attribute_name: u32,
    before_attribute_value: Span,
    attribute_value: struct {
        quote: enum { double, single },
        name_raw: Span,
        start: u32,
    },
    attribute_value_unquoted: struct {
        name_raw: Span,
        start: u32,
    },
    after_attribute_value: void,
    bogus_comment: void,
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
        std.debug.print("{s} {any}\n", .{ src, self.state });
        switch (self.state) {
            .data => {
                if (!self.consume(src)) return null;
                switch (self.current) {
                    //'&' => {} we don't process character references in the tokenizer
                    '<' => self.state = .{ .tag_open = self.idx - 1 },
                    0 => {
                        return .{
                            .token = .{ .parse_error = .unexpected_null_character },
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
                                .parse_error = .unexpected_null_character,
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
            .tag_open => |tag_open_start| {
                if (!self.consume(src)) {
                    self.state = .eof;
                    return .{
                        .token = .{ .parse_error = .eof_before_tag_name },
                        // .deferred = .{
                        //     .char = .{
                        //         .start = tag_open_start,
                        //         .end = self.idx,
                        //     },
                        // },
                    };
                }
                switch (self.current) {
                    '!' => self.state = .{
                        .markup_declaration_open = tag_open_start,
                    },
                    '/' => self.state = .{ .end_tag_open = tag_open_start },
                    '?' => @panic("TODO: implement '?'"),
                    else => |c| if (isAsciiAlpha(c)) {
                        self.state = .{
                            .tag_name = .{
                                .is_end = false,
                                .start = self.idx - 1,
                                .lbracket = tag_open_start,
                            },
                        };
                    } else {
                        self.state = .data;
                        self.idx -= 1;
                        return .{
                            .token = .{
                                .parse_error = .invalid_first_character_of_tag_name,
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
            .end_tag_open => |tag_open_start| {
                if (!self.consume(src)) {
                    // NOTE: this is implemented differently from the spec so we only need to
                    //       support 1 deferred token, but, should result in the same tokens.
                    self.state = .data;
                    self.idx -= 1;
                    return .{
                        .token = .{ .parse_error = .eof_before_tag_name },
                        // .deferred = .{
                        //     .char = .{
                        //         .start = tag_open_start,
                        //         .end = tag_open_start + 1,
                        //     },
                        // },
                    };
                }
                switch (self.current) {
                    '>' => {
                        self.state = .data;
                        return .{ .token = .{ .parse_error = .missing_end_tag_name } };
                    },
                    else => |c| if (isAsciiAlpha(c)) {
                        self.state = .{
                            .tag_name = .{
                                .is_end = true,
                                .start = self.idx - 1,
                                .lbracket = tag_open_start,
                            },
                        };
                    } else {
                        self.state = .bogus_comment;
                        return .{
                            .token = .{ .parse_error = .invalid_first_character_of_tag_name },
                        };
                    },
                }
            },
            .tag_name => |tag_state| {
                if (!self.consume(src)) {
                    self.state = .eof;
                    return .{ .token = .{ .parse_error = .eof_in_tag } };
                }
                switch (self.current) {
                    '\t', '\n', form_feed, ' ' => {
                        self.state = .before_attribute_name;
                        const name_span = Span{
                            .start = tag_state.start,
                            .end = self.idx - 1,
                        };
                        return if (tag_state.is_end) .{
                            .token = .{
                                .end_tag = .{
                                    .name = name_span,
                                    .lbracket = tag_state.lbracket,
                                },
                            },
                        } else .{
                            .token = .{
                                .start_tag = .{
                                    .name = name_span,
                                    .lbracket = tag_state.lbracket,
                                },
                            },
                        };
                    },
                    '/' => self.state = .self_closing_start_tag,
                    '>' => {
                        self.state = .data;
                        const name_span = Span{
                            .start = tag_state.start,
                            .end = self.idx - 1,
                        };
                        return if (tag_state.is_end) .{
                            .token = .{
                                .end_tag = .{
                                    .name = name_span,
                                    .lbracket = tag_state.lbracket,
                                },
                            },
                            .deferred = .{
                                .end_tag_rbracket = self.idx,
                            },
                        } else .{
                            .token = .{
                                .start_tag = .{
                                    .name = name_span,
                                    .lbracket = tag_state.lbracket,
                                },
                            },
                            .deferred = .{
                                .start_tag_rbracket = self.idx,
                            },
                        };
                    },
                    0 => return .{
                        .token = .{ .parse_error = .unexpected_null_character },
                    },
                    else => {},
                }
            },
            .self_closing_start_tag => {
                if (!self.consume(src)) {
                    self.state = .eof;
                    return .{ .token = .{ .parse_error = .eof_in_tag } };
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
                        self.state = .before_attribute_name;
                        self.idx -= 1;
                        return .{
                            .token = .{ .parse_error = .unexpected_solidus_in_tag },
                        };
                    },
                }
            },
            .before_attribute_name => {
                if (!self.consume(src)) {
                    self.state = .eof;
                    return .{ .token = .{ .parse_error = .eof_in_tag } };
                } else switch (self.current) {
                    '\t', '\n', form_feed, ' ' => {},
                    '/' => {
                        @panic("TODO");
                    },
                    '>' => {
                        self.state = .data;
                        return .{
                            .token = .{
                                .start_tag_rbracket = self.idx,
                            },
                        };
                    },
                    '=' => {
                        // unexpected_equals_sign_before_attribute_name
                        @panic("TODO implement '='");
                    },
                    else => self.state = .{
                        .attribute_name = self.idx - 1,
                    },
                }
            },
            .attribute_name => |start| {
                if (!self.consume(src)) {
                    self.state = .eof;
                    return .{ .token = .{ .parse_error = .eof_in_tag } };
                } else switch (self.current) {
                    '\t', '\n', form_feed, ' ', '/', '>' => {
                        defer {
                            self.idx -= 1;
                            self.state = .before_attribute_name;
                        }
                        return .{
                            .token = .{
                                .attr = .{
                                    .name_raw = .{
                                        .start = start,
                                        .end = self.idx - 1,
                                    },
                                    .value_raw = null,
                                },
                            },
                        };
                    },
                    '=' => self.state = .{
                        .before_attribute_value = .{
                            .start = start,
                            .end = self.idx - 1,
                        },
                    },
                    '"', '\'', '<' => return .{
                        .token = .{
                            .parse_error = .unexpected_character_in_attribute_name,
                        },
                    },
                    else => {},
                }
            },
            .before_attribute_value => |name_span| {
                if (!self.consume(src)) {
                    self.state = .eof;
                    return .{ .token = .{ .parse_error = .eof_in_tag } };
                } else switch (self.current) {
                    '\t', '\n', form_feed, ' ' => {},
                    '"' => self.state = .{
                        .attribute_value = .{
                            .name_raw = name_span,
                            .quote = .double,
                            .start = self.idx,
                        },
                    },
                    '\'' => self.state = .{
                        .attribute_value = .{
                            .name_raw = name_span,
                            .quote = .single,
                            .start = self.idx,
                        },
                    },
                    '>' => {
                        self.state = .data;
                        return .{
                            .token = .{ .parse_error = .missing_attribute_value },
                            .deferred = .{
                                .start_tag_rbracket = self.idx - 1,
                            },
                        };
                    },
                    else => {
                        self.state = .{
                            .attribute_value_unquoted = .{
                                .name_raw = name_span,
                                .start = self.idx,
                            },
                        };
                    },
                }
            },
            .attribute_value => |attr_state| {
                if (!self.consume(src)) {
                    self.state = .eof;
                    // NOTE: spec doesn't say to emit the current tag?
                    return .{ .token = .{ .parse_error = .eof_in_tag } };
                } else switch (self.current) {
                    '"' => switch (attr_state.quote) {
                        .double => {
                            self.state = .after_attribute_value;
                            return .{
                                .token = .{
                                    .attr = .{
                                        .name_raw = attr_state.name_raw,
                                        .value_raw = .{
                                            .quote = .double,
                                            .span = .{
                                                .start = attr_state.start,
                                                .end = self.idx - 1,
                                            },
                                        },
                                    },
                                },
                            };
                        },
                        .single => @panic("TODO"),
                    },
                    '\'' => switch (attr_state.quote) {
                        .double => @panic("TODO"),
                        .single => @panic("TODO"),
                    },
                    // TODO: the spec says the tokenizer should handle "character references" here, but,
                    //       that would require allocation, so, we should probably handle that elsewhere
                    //'&' => return error.NotImpl,
                    0 => return .{
                        .token = .{ .parse_error = .unexpected_null_character },
                    },
                    else => {},
                }
            },
            .attribute_value_unquoted => |attr_state| {
                if (!self.consume(src)) {
                    self.state = .eof;
                    // NOTE: spec doesn't say to emit the current tag?
                    return .{ .token = .{ .parse_error = .eof_in_tag } };
                } else switch (self.current) {
                    '"', '\'' => @panic("TODO"),
                    // TODO: the spec says the tokenizer should handle "character references" here, but,
                    //       that would require allocation, so, we should probably handle that elsewhere
                    //'&' => return error.NotImpl,
                    0 => return .{
                        .token = .{ .parse_error = .unexpected_null_character },
                    },
                    else => {
                        if (std.ascii.isWhitespace(self.current)) {
                            defer {
                                self.idx -= 1;
                                self.state = .after_attribute_value;
                            }
                            return .{
                                .token = .{
                                    .attr = .{
                                        .name_raw = attr_state.name_raw,
                                        .value_raw = .{
                                            .quote = .none,
                                            .span = .{
                                                .start = attr_state.start,
                                                .end = self.idx,
                                            },
                                        },
                                    },
                                },
                            };
                        }
                    },
                }
            },
            .after_attribute_value => {
                if (!self.consume(src)) {
                    self.state = .eof;
                    // NOTE: spec doesn't say to emit the current tag?
                    return .{ .token = .{ .parse_error = .eof_in_tag } };
                } else switch (self.current) {
                    '\t', '\n', form_feed, ' ' => self.state = .before_attribute_name,
                    '>' => {
                        self.state = .data;
                        return .{
                            .token = .{
                                .start_tag_rbracket = self.idx,
                            },
                        };
                    },
                    '/' => self.state = .self_closing_start_tag,
                    else => {
                        // TODO: read the spec and return the correct error
                        return .{
                            .token = .{
                                .parse_error = .unexpected_character_in_attribute_name,
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
                } else if (self.nextCharsAre(DOCTYPE, src)) {
                    self.idx += @intCast(DOCTYPE.len);
                    self.state = .{ .doctype = lbracket };
                } else if (self.nextCharsAre("[CDATA[", src)) {
                    @panic("TODO: implement CDATA");
                } else {
                    self.state = .bogus_comment;
                    return .{ .token = .{ .parse_error = .incorrectly_opened_comment } };
                }
            },
            .character_reference => {
                @panic("TODO: implement character reference");
            },
            .doctype => |lbracket| {
                if (!self.consume(src)) {
                    self.state = .eof;
                    return .{
                        .token = .{ .parse_error = .eof_in_doctype },
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
                                .parse_error = .missing_whitespace_before_doctype_name,
                            },
                        };
                    },
                }
            },
            .before_doctype_name => |lbracket| {
                if (!self.consume(src)) {
                    self.state = .eof;
                    return .{
                        .token = .{ .parse_error = .eof_in_doctype },
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
                            .token = .{ .parse_error = .unexpected_null_character },
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
                            .deferred = .{
                                .doctype_rbracket = self.idx,
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
                        .token = .{ .parse_error = .eof_in_doctype },
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
                            .deferred = .{
                                .doctype_rbracket = self.idx,
                            },
                        };
                    },
                    0 => return .{
                        .token = .{ .parse_error = .unexpected_null_character },
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
                                .parse_error = .abrupt_closing_of_empty_comment,
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
                        .token = .{ .parse_error = .eof_in_comment },
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
                        .token = .{ .parse_error = .eof_in_comment },
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
                        .token = .{ .parse_error = .eof_in_comment },
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
            .bogus_comment => {
                @panic("TODO: implement bogus_comment");
            },
            .eof => return null,
        }
    }
}

fn nextCharsAre(self: Tokenizer, needle: []const u8, src: []const u8) bool {
    return std.mem.startsWith(u8, src[self.idx..], needle);
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
