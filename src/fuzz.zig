const builtin = @import("builtin");
const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Reader = std.Io.Reader;
const Element = @import("html/Element.zig");
const Attribute = @import("html/Attribute.zig");
const Ast = @import("html/Ast.zig");

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
        arena: Allocator,
        stack: *std.ArrayList([]const u8),
        smith: *std.testing.Smith,
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
                switch (smith.value(u2)) {
                    0 => try w.writeAll("lorem ipsum"),
                    1 => try w.writeAll(" lorem ipsum"),
                    2 => try w.writeAll("lorem ipsum "),
                    3 => try w.writeAll(" lorem ipsum "),
                }
            },
            .push_elem, .push_self_closing_elem => {
                // const rng = input.takeByte() catch return error.Done;
                const final_space = smith.value(bool);
                const attrs_count = smith.valueRangeAtMost(u8, 0, 64);

                const name = if (smith.boolWeighted(1, 10)) blk: {
                    const tag_idx = smith.valueRangeLessThan(u32, 0, @intCast(tags.len));
                    const name = tags[tag_idx];
                    const kind = Element.elements.values()[tag_idx];
                    const attrs = Attribute.element_attrs.get(kind);
                    try w.print("<{s}", .{name});

                    for (0..attrs_count) |_| {
                        const has_value = smith.value(bool);
                        if (smith.boolWeighted(1, 5)) {
                            if (attrs.list.len > 0 and smith.value(bool)) {
                                // element attr
                                const idx = smith.valueRangeLessThan(u32, 0, @intCast(attrs.list.len));
                                const named_model = attrs.list[idx];
                                try renderAttr(gpa, named_model, has_value, smith, w);
                            } else {
                                // global attr
                                const idx = smith.valueRangeLessThan(u32, 0, @intCast(Attribute.global.list.len));
                                const named_model = Attribute.global.list[idx];
                                try renderAttr(gpa, named_model, has_value, smith, w);
                            }
                        } else {
                            var buf: [64]u8 = undefined;
                            const attr_name = buf[0..smith.slice(&buf)];
                            try renderAttr(gpa, .{
                                .name = attr_name,
                                .model = .{ .rule = .any, .desc = "" },
                            }, has_value, smith, w);
                        }
                    }
                    break :blk name;
                } else blk: {
                    const buf = try arena.alloc(u8, 64);
                    const name = buf[0..smith.slice(buf)];
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
                if (smith.value(bool)) {
                    _ = stack.pop() orelse return error.Done;
                }

                if (smith.value(bool)) {
                    const t = tags[smith.valueRangeLessThan(u32, 0, @intCast(tags.len))];
                    try w.print("</{s}>", .{t});
                    return;
                } else {
                    var buf: [64]u8 = undefined;
                    const name = buf[0..smith.slice(&buf)];
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
    smith: *std.testing.Smith,
    w: *Writer,
) !void {
    _ = gpa;
    try w.print(" {s}", .{named_model.name});
    if (!has_value) return;

    switch (smith.value(u2)) {
        1 => return, // no value
        2 => try w.writeAll("=''"),
        3 => try w.writeAll("='not_empty'"),
        0 => switch (named_model.model.rule) { // apply rule semantically
            else => {
                var buf: [64]u8 = undefined;
                const value = buf[0..smith.slice(&buf)];
                try w.print("=\"{s}\"", .{value});
            },

            .list => |list_rule| {
                const case = list_rule.completions[
                    smith.valueRangeLessThan(
                        u32,
                        0,
                        @intCast(list_rule.completions.len),
                    )
                ];
                try w.print("=\"{s}\"", .{case.label});
            },
            .cors => {
                const case: []const []const u8 = &.{
                    "anonymous", "use-credentials", "arst",
                };

                try w.print("=\"{s}\"", .{case[
                    smith.valueRangeLessThan(
                        u32,
                        0,
                        @intCast(case.len),
                    )
                ]});
            },
            .non_neg_int => {
                const case: []const []const u8 = &.{
                    "0", "1", "2", "-1", "100", "-99", "101", "-101", "-102",
                };

                try w.print("=\"{s}\"", .{case[
                    smith.valueRangeLessThan(
                        u32,
                        0,
                        @intCast(case.len),
                    )
                ]});
            },
        },
    }
}

test "fuzz case" {
    const case_b64 = "";
    const size = try std.base64.standard.Decoder.calcSizeForSlice(case_b64);
    const case = try std.testing.allocator.allocWithOptions(u8, size, null, 0);
    defer std.testing.allocator.free(case);
    try std.base64.standard.Decoder.decode(case, case_b64);

    const ast: Ast = try .init(std.testing.allocator, case, .html, false);
    defer ast.deinit(std.testing.allocator);

    if (!ast.has_syntax_errors) {
        var fmt_out: Io.Writer.Allocating = .init(std.testing.allocator);
        defer fmt_out.deinit();

        try ast.render(case, &fmt_out.writer);
    }
}

test "fuzz" {
    // const log = try Io.Dir.cwd().createFile(std.testing.io, "fuzz.log", .{ .truncate = false });
    // var file_writer = log.writerStreaming(std.testing.io, &.{});

    // try std.testing.fuzz(&file_writer.interface, struct {
    // fn fuzz(l: *Io.Writer, smith: *std.testing.Smith) !void {
    try std.testing.fuzz({}, struct {
        fn fuzz(_: void, smith: *std.testing.Smith) !void {
            var stack: std.ArrayList([]const u8) = .empty;
            defer stack.deinit(std.testing.allocator);

            var case: Io.Writer.Allocating = .init(std.testing.allocator);
            defer case.deinit();

            var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
            defer arena.deinit();

            var newlines: usize = 0;
            while (!smith.eosWeightedSimple(7, 1)) {
                const op = smith.value(Op);
                if (op == .add_newline) newlines += 1;
                if (newlines > 5) return error.Skip;

                op.apply(std.testing.allocator, arena.allocator(), &stack, smith, &case.writer) catch |err| switch (err) {
                    error.Done => break,
                    else => unreachable,
                };
            }

            // try std.base64.standard.Encoder.encodeWriter(l, case.written());
            // try l.print("\n{s}\n---\n\n", .{case.written()});

            const ast: Ast = try .init(std.testing.allocator, case.written(), .html, false);
            defer ast.deinit(std.testing.allocator);

            if (!ast.has_syntax_errors) {
                var fmt_out: Io.Writer.Allocating = .init(std.testing.allocator);
                defer fmt_out.deinit();

                try ast.render(case.written(), &fmt_out.writer);
            }
        }
    }.fuzz, .{});
}
