const std = @import("std");
const super = @import("superhtml");
const builtin = @import("builtin");

pub const std_options: std.Options = .{ .log_level = .err };

pub export fn zig_fuzz_init() void {}

pub export fn zig_fuzz_test(buf: [*]u8, len: isize) void {
    var gpa_impl: std.heap.DebugAllocator(.{}) = .{};
    defer std.debug.assert(gpa_impl.deinit() == .ok);

    const gpa = gpa_impl.allocator();

    const src = buf[0..@intCast(len)];
    // const src = blk: {
    //     const input = buf[0..@intCast(len)];
    //     if (std.mem.indexOf(u8, input, "</script>") != null) return;
    //     break :blk std.fmt.allocPrint(gpa, "<script>{s}</script>", .{input}) catch unreachable;
    // };
    // defer gpa.free(src);

    const html_ast = super.html.Ast.init(gpa, src, .superhtml, false) catch unreachable;
    defer html_ast.deinit(gpa);

    // if (html_ast.errors.len == 0) {
    //     const super_ast = super.Ast.init(gpa, html_ast, src) catch unreachable;
    //     defer super_ast.deinit(gpa);
    // }

    if (html_ast.errors.len == 0) {
        var out: std.Io.Writer.Allocating = .init(gpa);
        defer out.deinit();

        html_ast.render(src, &out.writer) catch unreachable;

        eqlIgnoreWhitespace(src, out.written());

        var full_circle: std.Io.Writer.Allocating = .init(gpa);
        defer full_circle.deinit();

        const html_ast1 = super.html.Ast.init(gpa, out.written(), .superhtml, false) catch unreachable;
        defer html_ast1.deinit(gpa);

        if (html_ast1.errors.len > 0) {
            std.debug.panic("---- orig ----\n{s}[end]\n\n---- round1 ---\n{s}[end]\n", .{
                src,
                out.written(),
            });
        }

        html_ast1.render(out.written(), &full_circle.writer) catch unreachable;

        const ok = std.mem.eql(u8, out.written(), full_circle.written());
        if (!ok) {
            std.debug.panic("---- orig ----\n{s}[end]\n\n---- round1 ---\n{s}[end]\n---- round2 ----\n{s}[end]\n", .{
                src,
                out.written(),
                full_circle.written(),
            });
        }

        const super_ast = super.Ast.init(gpa, html_ast, src) catch unreachable;
        defer super_ast.deinit(gpa);
    }
}

export fn zig_fuzz_test_astgen(buf: [*]u8, len: isize) void {
    var gpa_impl: std.heap.DebugAllocator(.{}) = .{};
    const gpa = gpa_impl.allocator();
    const astgen_src = buf[0..@intCast(len)];

    const clamp: u32 = @min(20, astgen_src.len);
    const src = astgen.build(gpa, astgen_src[0..clamp]) catch unreachable;
    defer gpa.free(src);

    const html_ast = super.html.Ast.init(gpa, src, .superhtml, false) catch unreachable;
    defer html_ast.deinit(gpa);

    std.debug.assert(html_ast.errors.len == 0);

    const super_ast = super.Ast.init(gpa, html_ast, src) catch unreachable;
    defer super_ast.deinit(gpa);

    // if (html_ast.errors.len == 0) {
    //     var out = std.ArrayList(u8).init(gpa);
    //     defer out.deinit();
    //     html_ast.render(src, out.writer()) catch unreachable;

    //     eqlIgnoreWhitespace(src, out.items);

    //     var full_circle = std.ArrayList(u8).init(gpa);
    //     defer full_circle.deinit();
    //     html_ast.render(out.items, full_circle.writer()) catch unreachable;

    //     std.debug.assert(std.mem.eql(u8, out.items, full_circle.items));

    //     const super_ast = super.Ast.init(gpa, html_ast, src) catch unreachable;
    //     defer super_ast.deinit(gpa);
    // }
}

fn eqlIgnoreWhitespace(a: []const u8, b: []const u8) void {
    var i: u32 = 0;
    var j: u32 = 0;

    outer: while (i < a.len) : (i += 1) {
        const a_byte = a[i];
        if (std.ascii.isWhitespace(a_byte)) continue;
        while (j < b.len) : (j += 1) {
            const b_byte = b[j];
            if (std.ascii.isWhitespace(b_byte)) continue;

            if (std.ascii.toUpper(a_byte) != std.ascii.toUpper(b_byte)) {
                std.debug.print("---- orig ---\n{s}\n---- round1 ----\n{s}\n", .{ a, b });
                const a_span: super.Loc = .{ .start = i, .end = i + 1 };
                const b_span: super.Loc = .{ .start = j, .end = j + 1 };
                std.debug.panic("mismatch! {c} != {c} \na = {any}\nb={any}\n", .{
                    a_byte,
                    b_byte,
                    a_span.range(a),
                    b_span.range(b),
                });
            }

            j += 1;
            continue :outer;
        }
    }
}

pub const astgen = struct {
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
        attrs: super.Loc = .{ .start = 0, .end = 0 },
        kind: Tag = .none,
        whitespace: bool = false,

        pub const Tag = enum { none, div, super, extend, br, comment, text };

        pub fn commit(
            e: *Element,
            w: anytype,
            gpa: std.mem.Allocator,
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
                    .div => ends.append(gpa, e.kind) catch unreachable,
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
                const op: Op = @fromBackingInt(@intCast(src[idx]));
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
                    const op_next: Op = @fromBackingInt(@intCast(src[idx]));
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
        var out: std.Io.Writer.Allocating = .init(gpa);
        var ends: std.ArrayList(Element.Tag) = .empty;
        const w = &out.writer;
        var current: Element = .{};

        buildInternal(w, gpa, src, &ends, &current) catch |err| switch (err) {
            error.Break => {},
            else => unreachable,
        };

        current.commit(w, gpa, src, &ends) catch |err| switch (err) {
            error.Break => {},
            else => unreachable,
        };

        while (ends.pop()) |kind|
            try w.print("</{s}>", .{@tagName(kind)});

        return out.written();
    }
    pub fn buildInternal(
        w: anytype,
        gpa: std.mem.Allocator,
        src: []const u8,
        ends: *std.ArrayList(Element.Tag),
        current: *Element,
    ) !void {
        for (src, 0..) |c, i| {
            const idx: u32 = @intCast(i);
            const op: Op = @fromBackingInt(@intCast(c));
            switch (op) {
                // add <extend> attribute
                .n => {
                    try current.commit(w, gpa, src, ends);
                    current.kind = .extend;
                },
                // add <extend> attribute and give it a template attribute
                .N => {
                    try current.commit(w, gpa, src, ends);
                    current.kind = .extend;
                    current.attrs = .{ .start = idx, .end = idx + 1 };
                },
                // add new element, enter it
                .e => {
                    try current.commit(w, gpa, src, ends);
                    current.kind = .div;
                },
                // add a new non-semantic void element
                .E => {
                    try current.commit(w, gpa, src, ends);
                    current.kind = .br;
                },
                // add <super> element
                .s => {
                    try current.commit(w, gpa, src, ends);
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
                    try current.commit(w, gpa, src, ends);
                    current.kind = .text;
                },
                // add comment
                .c => {
                    try current.commit(w, gpa, src, ends);
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
                    try current.commit(w, gpa, src, ends);
                    if (ends.pop()) |kind|
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
};
