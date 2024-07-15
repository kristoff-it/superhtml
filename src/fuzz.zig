const std = @import("std");
const super = @import("super");

pub const std_options = .{ .log_level = .err };

var gpa_impl: std.heap.GeneralPurposeAllocator(.{}) = .{};
export fn zig_fuzz_test(buf: [*]u8, len: isize) void {
    const gpa = gpa_impl.allocator();
    const src = buf[0..@intCast(len)];

    const ast = super.html.Ast.init(gpa, src, .html) catch unreachable;
    defer ast.deinit(gpa);

    if (ast.errors.len == 0) {
        try ast.render(src, std.io.null_writer);
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
