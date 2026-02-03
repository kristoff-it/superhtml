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
    eof,
};

const TokenError = enum {
    generic_error,

    //
    unclosed_capture_group,
};

const Token = union(enum) {
    character: u8,

    group_open: struct {
        kind: enum { regular, non_capturing },
        span: Span,
    },

    parse_error: struct {
        tag: TokenError,
        span: Span,
    },
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
        switch (self.state) {
            .data => {
                std.debug.print("token {d}: {c}\n", .{ self.idx, self.current });
                if (!self.consume(src)) {
                    self.state = .eof;
                } else switch (self.current) {
                    '(' => {
                        self.state = .{
                            .parens_open = self.idx - 1,
                        };
                    },
                    'x' => {
                        return .{
                            .parse_error = .{
                                .tag = .generic_error,
                                .span = .{
                                    .start = self.idx - 1,
                                    .end = self.idx,
                                },
                            },
                        };
                    },
                    else => {
                        return .{
                            .character = self.current,
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
                                .span = .{ .start = start, .end = self.idx },
                            },
                        };
                    },
                }
            },
            .eof => return null,
        }
    }
}

test "regexp-scan" {
    var tokenizer: RegExpTokenizer = .{};

    const src = "(?foo)dxedoo";

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
        .{ .character = 'f' },
        .{ .character = 'o' },
        .{ .character = 'o' },
        .{ .character = ')' },
        .{ .character = 'd' },
        .{
            .parse_error = .{
                .tag = .generic_error,
                .span = .{
                    .start = 7,
                    .end = 8,
                },
            },
        },
        .{ .character = 'e' },
        .{ .character = 'd' },
        .{ .character = 'o' },
        .{ .character = 'o' },
    };

    try std.testing.expectEqualSlices(Token, expected, tokens.items);
}
