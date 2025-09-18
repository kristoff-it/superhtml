const builtin = @import("builtin");
const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Reader = std.Io.Reader;
const Element = @import("../html/Element.zig");
const Attribute = @import("../html/Attribute.zig");

const Op = enum(u8) {
    add_newline,
    up,
    push_doctype,
    push_comment,
    push_text,
    push_elem,
    push_self_closing_elem,
    add_or_push_erroneous_end_tag,

    fn apply(
        op: Op,
        gpa: Allocator,
        stack: *std.ArrayList([]const u8),
        input: *Reader,
        w: *Writer,
    ) !void {
        const tags = Element.elements.keys();

        switch (op) {
            .add_newline => try w.writeAll("\n"),
            .up => {
                if (stack.pop()) |tag| {
                    try w.print("</{s}>", .{tag});
                } else return error.Done;
            },
            .push_doctype => try w.writeAll("<!DOCTYPE html>"),
            .push_comment => try w.writeAll("<!-- comment -->"),
            .push_text => {
                const rng = input.takeByte() catch return error.Done;
                if (rng < @trunc(0.25 * 255)) {
                    try w.writeAll("lorem ipsum");
                } else if (rng < @trunc(0.50 * 255)) {
                    try w.writeAll(" lorem ipsum");
                } else if (rng < @trunc(0.75 * 255)) {
                    try w.writeAll("lorem ipsum ");
                } else {
                    try w.writeAll(" lorem ipsum ");
                }
            },
            .push_elem, .push_self_closing_elem => {
                const rng = input.takeByte() catch return error.Done;
                const final_space = rng > @trunc(0.5 * 255);
                const attrs_count = input.takeByte() catch return error.Done;

                const name = if ((rng & 127) < tags.len) blk: {
                    const name = tags[rng & 127];
                    const kind = Element.elements.values()[rng & 127];
                    const attrs = Attribute.element_attrs.get(kind);
                    try w.print("<{s}", .{name});

                    for (0..attrs_count) |_| {
                        const attr_rng = input.takeByte() catch break;
                        if (attr_rng & 0b10000000 != 0) {
                            const has_value = attr_rng & 0b00100000 != 0;
                            const len = input.takeByte() catch break;
                            const attr_name = input.take(len) catch break;
                            try renderAttr(gpa, .{
                                .name = attr_name,
                                .model = .{ .rule = .any, .desc = "" },
                            }, has_value, input, w);
                        } else {
                            if (attrs.list.len > 0 and attr_rng & 0b01000000 != 0) {
                                // element attr
                                const has_value = attr_rng & 0b00100000 != 0;
                                const idx = attr_rng & 0b00011111;
                                const named_model = attrs.list[idx % attrs.list.len];
                                try renderAttr(gpa, named_model, has_value, input, w);
                            } else {
                                // global attr
                                const has_value = attr_rng & 0b00100000 != 0;
                                const idx = attr_rng & 0b00011111; // TODO: need one more bit!
                                const named_model = Attribute.global.list[idx % Attribute.global.list.len];
                                try renderAttr(gpa, named_model, has_value, input, w);
                            }
                        }
                    }
                    break :blk name;
                } else blk: { // 127 - 116
                    const len = input.takeByte() catch return error.Done;
                    const name = input.take(len) catch return error.Done;
                    try w.print("<{s}", .{name});
                    // TODO: attributes?
                    break :blk name;
                };

                if (final_space) try w.writeAll(" ");
                if (op == .push_self_closing_elem) {
                    try w.writeAll("/>");
                } else {
                    try stack.append(gpa, name);
                    try w.writeAll(">");
                }
            },
            .add_or_push_erroneous_end_tag => {
                const rng = input.takeByte() catch return error.Done;

                if (rng > @trunc(0.5 * 255)) {
                    _ = stack.pop() orelse return error.Done;
                }

                if ((rng & 127) < tags.len) {
                    const t = tags[rng & 127];
                    try w.print("</{s}>", .{t});
                    return;
                } else { // 127 - 116
                    const len = input.takeByte() catch return error.Done;
                    const name = input.take(len) catch return error.Done;
                    try w.print("</{s}>", .{name});
                    return;
                }
            },
        }
    }
};

fn renderAttr(
    gpa: Allocator,
    named_model: Attribute.Named,
    has_value: bool,
    input: *Reader,
    w: *Writer,
) !void {
    _ = gpa;
    try w.print(" {s}", .{named_model.name});
    if (!has_value) return;
    switch (named_model.model.rule) {
        else => {
            const len = input.takeByte() catch return;
            const value = input.take(len) catch return;
            try w.print("=\"{s}\"", .{value});
        },
        // .list => {},
    }
}

pub fn generate(gpa: Allocator, input: *Reader, w: *Writer) !void {
    var stack: std.ArrayList([]const u8) = .empty;
    defer stack.deinit(gpa);

    var newlines: usize = 0;
    while (true) {
        const op: Op = @enumFromInt((input.takeByte() catch return) % 8);
        if (op == .add_newline) newlines += 1;
        if (newlines > 10) return error.Skip;
        op.apply(gpa, &stack, input, w) catch |err| switch (err) {
            error.Done => return,
            else => return err,
        };
    }
}
