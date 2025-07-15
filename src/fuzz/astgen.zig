const std = @import("std");
const Writer = std.Io.Writer;

const builtin = @import("builtin");
const super = @import("superhtml");

const Op = enum(u8) {
    // add <extend> element
    n = 'n',
    // add <extend> element and give it a template attribute
    N = 'N',
    // add <super> element
    s = 's',
    // add text node
    t = 't',
    // add comment node
    c = 'c',
    // add new element, enter it
    e = 'e',
    // add a new non-semantic void element
    E = 'E',
    // add an id attribute
    // (break if any 'u', 'c', or 't' was sent after the last 'e' or 'E')
    // (break if another attribute of the same kind was already added)
    i = 'i',
    // add non-semantic attribute to selected node
    // (break if any 'u', 'c', or 't' was sent after the last 'e' or 'E')
    a = 'a',
    // add loop attribute
    // (break if any 'u', 'c', or 't' was sent after the last 'e' or 'E')
    // (break if another attribute of the same kind was already added)
    l = 'l',
    // add an inline-loop attribute
    // (break if any 'u', 'c', or 't' was sent after the last 'e' or 'E')
    // (break if another attribute of the same kind was already added)
    L = 'L',
    // add an if attribute
    // (break if any 'u', 'c', or 't' was sent after the last 'e' or 'E')
    // (break if another attribute of the same kind was already added)
    f = 'f',
    // add an inline-if attribute
    // (break if any 'u', 'c', or 't' was sent after the last 'e' or 'E')
    // (break if another attribute of the same kind was already added)
    F = 'F',
    // add a var attribute
    // (break if any 'u', 'c', or 't' was sent after the last 'e' or 'E')
    // (break if another attribute of the same kind was already added)
    v = 'v',
    // add an empty attribute value
    // (break when not put in front of an attribute Op)
    x = 'x',
    // add a static non-scripted attribute value
    // (break when not put in front of an attribute Op)
    X = 'X',
    // add a scripted attribute value
    // (break when not put in front of an attribute Op)
    y = 'y',
    // add a unique non-scripted attribute value
    // (break when not put in front of an attribute Op)
    Y = 'Y',
    // select the parent element of the current element
    // (break when a top-level element is already selected)
    u = 'u',
    // add whitespace
    // (consecutive 'w' on the same element will cause a break)
    w = 'w',

    // noop
    _,
};

const Element = struct {
    // a span of Ops that describes a list of attrs
    attrs: super.Span = .{ .start = 0, .end = 0 },
    kind: Tag = .none,
    whitespace: bool = false,

    pub const Tag = enum { none, div, super, extend, br, comment, text };

    pub fn commit(
        e: *Element,
        w: *Writer,
        src: []const u8,
        ends: *std.ArrayList(Tag),
    ) !void {
        switch (e.kind) {
            .comment => {
                if (e.whitespace) try w.writeAll("\n");
                try w.writeAll("<!-- -->");
                e.* = .{};
                return;
            },
            .text => {
                if (e.whitespace) try w.writeAll("\n");
                try w.writeAll("X");
                e.* = .{};
                return;
            },
            .none => {
                e.* = .{};
                return;
            },
            .div, .super, .extend, .br => {
                if (e.whitespace) try w.writeAll("\n");
            },
        }

        try w.print("<{s}", .{@tagName(e.kind)});
        defer {
            w.writeAll(">") catch unreachable;
            switch (e.kind) {
                .div => ends.append(e.kind) catch unreachable,
                .super, .br, .extend, .none, .text, .comment => {},
            }
            e.* = .{};
        }

        var has_id = false;
        var has_loop = false;
        var has_inl_loop = false;
        var has_if = false;
        var has_inl_if = false;
        var has_var = false;
        var idx = e.attrs.start;
        while (idx < e.attrs.end) : (idx += 1) {
            var attribute_was_added = true;
            const op: Op = @enumFromInt(src[idx]);
            switch (op) {
                .N => {
                    try w.writeAll(" template='x'");
                    attribute_was_added = false;
                },
                .a => try w.print(" a{}", .{idx}),
                .i => if (!has_id) {
                    try w.writeAll(" id");
                    has_id = true;
                } else {
                    return error.Break;
                },
                .l => if (!has_loop) {
                    try w.writeAll(" loop");
                    has_loop = true;
                } else {
                    return error.Break;
                },
                .L => if (!has_inl_loop) {
                    try w.writeAll(" inline-loop");
                    has_inl_loop = true;
                } else {
                    return error.Break;
                },
                .f => if (!has_if) {
                    try w.writeAll(" if");
                    has_if = true;
                } else {
                    return error.Break;
                },
                .F => if (!has_inl_if) {
                    try w.writeAll(" inline-if");
                    has_inl_if = true;
                } else {
                    return error.Break;
                },
                .v => if (!has_var) {
                    try w.writeAll(" var");
                    has_var = true;
                } else {
                    return error.Break;
                },
                .w => attribute_was_added = false,
                else => {
                    return error.Break;
                },
            }

            if (attribute_was_added and idx < e.attrs.end - 1) {
                idx += 1;
                const op_next: Op = @enumFromInt(src[idx]);
                switch (op_next) {
                    .x => try w.writeAll("=''"),
                    .X => try w.writeAll("='x'"),
                    .y => try w.writeAll("='$'"),
                    .Y => try w.print("='{}'", .{idx}),
                    else => idx -= 1,
                }
            }
        }
    }
};

pub fn build(gpa: std.mem.Allocator, src: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).init(gpa);
    var ends = std.ArrayList(Element.Tag).init(gpa);
    const w = out.writer();
    var current: Element = .{};

    buildInternal(w, src, &ends, &current) catch |err| switch (err) {
        error.Break => {},
        else => unreachable,
    };

    current.commit(w, src, &ends) catch |err| switch (err) {
        error.Break => {},
        else => unreachable,
    };

    while (ends.popOrNull()) |kind|
        try w.print("</{s}>", .{@tagName(kind)});

    return out.items;
}
pub fn buildInternal(
    w: *Writer,
    src: []const u8,
    ends: *std.ArrayList(Element.Tag),
    current: *Element,
) !void {
    for (src, 0..) |c, i| {
        const idx: u32 = @intCast(i);
        const op: Op = @enumFromInt(c);
        switch (op) {
            // add <extend> attribute
            .n => {
                try current.commit(w, src, ends);
                current.kind = .extend;
            },
            // add <extend> attribute and give it a template attribute
            .N => {
                try current.commit(w, src, ends);
                current.kind = .extend;
                current.attrs = .{ .start = idx, .end = idx + 1 };
            },
            // add new element, enter it
            .e => {
                try current.commit(w, src, ends);
                current.kind = .div;
            },
            // add a new non-semantic void element
            .E => {
                try current.commit(w, src, ends);
                current.kind = .br;
            },
            // add <super> element
            .s => {
                try current.commit(w, src, ends);
                current.kind = .super;
            },
            // add <super> element into the current element and give id
            // attribute to the parent if needed
            // (noop if any 'u', 'c', or 't' was sent after the last 'e' or 'E')
            // .S => switch (current.kind) {
            //     .none, .comment, .text => continue,
            //     .div, .super, .extend, .br => {
            //         if (current.attrs.end == 0) {
            //             current.attrs = .{ .start = idx, .end = idx + 1 };
            //         } else {
            //             current.attrs.end = idx + 1;
            //         }
            //         try current.commit(w, src, ends);
            //         current.kind = .super;
            //     },
            // },
            // add text element
            .t => {
                try current.commit(w, src, ends);
                current.kind = .text;
            },
            // add comment
            .c => {
                try current.commit(w, src, ends);
                current.kind = .comment;
            },
            // attributes
            // (noop if any 'u', 'c', or 't' was sent after the last 'e' or 'E')
            .a, .l, .L, .f, .F, .v, .i, .x, .X, .y, .Y => switch (current.kind) {
                .none, .comment, .text => break,
                .div, .super, .extend, .br => {
                    if (current.attrs.end == 0) {
                        current.attrs = .{ .start = idx, .end = idx + 1 };
                    } else {
                        current.attrs.end = idx + 1;
                    }
                },
            },
            // select the parent element of the current element
            // (noop when a top-level element is already selected)
            .u => {
                try current.commit(w, src, ends);
                if (ends.popOrNull()) |kind|
                    try w.print("</{s}>", .{@tagName(kind)})
                else
                    break;
            },
            // add whitespace
            // (consecutive 'w' on the same element are noops)
            .w => {
                if (current.whitespace) break;
                current.whitespace = true;
            },

            // early return to avoid keeping "dead bytes"
            // in the active set of bytes, ideally improving
            // fuzzer performance
            else => break,
        }
    }
}

pub fn main() !void {
    var gpa_impl: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const gpa = gpa_impl.allocator();

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    if (args.len != 2) @panic("wrong number of arguments");
    const src = args[1];

    const out = try build(gpa, src);
    try std.io.getStdOut().writeAll(out);
}
