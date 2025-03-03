const std = @import("std");
const super = @import("superhtml");
const astgen = @import("astgen.zig");

pub const std_options: std.Options = .{ .log_level = .err };

export fn zig_fuzz_init() void {}

export fn zig_fuzz_test(buf: [*]u8, len: isize) void {
    var gpa_impl: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer std.debug.assert(gpa_impl.deinit() == .ok);

    const gpa = gpa_impl.allocator();
    const src = buf[0..@intCast(len)];

    const html_ast = super.html.Ast.init(gpa, src, .superhtml) catch unreachable;
    defer html_ast.deinit(gpa);

    // if (html_ast.errors.len == 0) {
    //     const super_ast = super.Ast.init(gpa, html_ast, src) catch unreachable;
    //     defer super_ast.deinit(gpa);
    // }

    if (html_ast.errors.len == 0) {
        var out = std.ArrayList(u8).init(gpa);
        defer out.deinit();
        html_ast.render(src, out.writer()) catch unreachable;

        eqlIgnoreWhitespace(src, out.items);

        var full_circle = std.ArrayList(u8).init(gpa);
        defer full_circle.deinit();
        html_ast.render(out.items, full_circle.writer()) catch unreachable;

        std.debug.assert(std.mem.eql(u8, out.items, full_circle.items));

        const super_ast = super.Ast.init(gpa, html_ast, src) catch unreachable;
        defer super_ast.deinit(gpa);
    }
}

export fn zig_fuzz_test_astgen(buf: [*]u8, len: isize) void {
    var gpa_impl: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const gpa = gpa_impl.allocator();
    const astgen_src = buf[0..@intCast(len)];

    const clamp: u32 = @min(20, astgen_src.len);
    const src = astgen.build(gpa, astgen_src[0..clamp]) catch unreachable;
    defer gpa.free(src);

    const html_ast = super.html.Ast.init(gpa, src, .superhtml) catch unreachable;
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

    while (i < a.len) : (i += 1) {
        const a_byte = a[i];
        if (std.ascii.isWhitespace(a_byte)) continue;
        while (j < b.len) : (j += 1) {
            const b_byte = b[j];
            if (std.ascii.isWhitespace(b_byte)) continue;

            if (a_byte != b_byte) {
                const a_span: super.Span = .{ .start = i, .end = i + 1 };
                const b_span: super.Span = .{ .start = j, .end = j + 1 };
                std.debug.panic("mismatch! {c} != {c} \na = {any}\nb={any}\n", .{
                    a_byte,
                    b_byte,
                    a_span.range(a),
                    b_span.range(b),
                });
            }
        }
    }
}

test "afl++ fuzz cases" {
    const cases: []const []const u8 = &.{
        @embedFile("fuzz/2.html"),
        @embedFile("fuzz/3.html"),
        @embedFile("fuzz/12.html"),
        @embedFile("fuzz/round2/2.html"),
        @embedFile("fuzz/round2/3.html"),
        @embedFile("fuzz/round3/2.html"),
        @embedFile("fuzz/77.html"),
        @embedFile("fuzz/3-01.html"),
        @embedFile("fuzz/4-01.html"),
        @embedFile("fuzz/5-01.html"),
    };

    for (cases) |c| {
        // std.debug.print("test: \n\n{s}\n\n", .{c});
        const ast = try super.html.Ast.init(std.testing.allocator, c, .html);
        defer ast.deinit(std.testing.allocator);
        if (ast.errors.len == 0) {
            try ast.render(c, std.io.null_writer);
        }
        // ast.debug(c);
    }
}
