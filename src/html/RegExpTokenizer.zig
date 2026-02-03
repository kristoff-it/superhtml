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
    character: u32,

    group_open: struct {
        kind: enum { regular, non_capturing },
        span: Span,
    },

    group_close: u32,

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
        std.debug.print("token {d}: {c}\n", .{ self.idx, self.current });
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
