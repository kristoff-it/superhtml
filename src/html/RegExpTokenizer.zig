const RegExpTokenizer = @This();
const named_character_references = @import("named_character_references.zig");

const std = @import("std");
const assert = std.debug.assert;
const root = @import("../root.zig");
const Span = root.Span;

const log = std.log.scoped(.regExpTokenizer);

const State = union(enum) {
    data,
    eof,
};

const Token = union(enum) {
    regexpToken,
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
            .eof => return null,
            else => {
                std.debug.print("token: {c}\n", .{self.current});
                if (!self.consume(src)) {
                    self.state = .eof;
                }
            },
        }
    }
}

test "test next and consume" {
    var tokenizer: RegExpTokenizer = .{};

    const src = "(?:foo)deedoo";

    var got_eof = false;

    while (tokenizer.next(src)) |_| {} else {
        got_eof = true;
    }

    try std.testing.expectEqual(true, got_eof);
}
