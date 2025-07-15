const std = @import("std");
const super = @import("superhtml");

pub const std_options: std.Options = .{ .log_level = .err };

/// This main function is meant to be used via black box fuzzers
/// and/or to manually weed out test cases that are not valid anymore
/// after fixing bugs.
///
/// See fuzz/afl.zig for the AFL++ specific executable.
pub fn main() !void {
    var gpa_impl: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const gpa = gpa_impl.allocator();

    const stdin = std.io.getStdIn();
    const src = try stdin.readToEndAlloc(gpa, std.math.maxInt(usize));
    defer gpa.free(src);

    const ast = try super.html.Ast.init(gpa, src, .html);
    defer ast.deinit(gpa);

    if (ast.errors.len == 0) {
        var dw: std.Io.Writer.Discarding = .init(&.{});
        try ast.render(src, &dw.writer);
    }
}

test "afl++ fuzz cases" {
    const cases: []const []const u8 = &.{
        @embedFile("fuzz/cases/2.html"),
        @embedFile("fuzz/cases/3.html"),
        @embedFile("fuzz/cases/12.html"),
        @embedFile("fuzz/cases/round2/2.html"),
        @embedFile("fuzz/cases/round2/3.html"),
        @embedFile("fuzz/cases/round3/2.html"),
        @embedFile("fuzz/cases/77.html"),
        @embedFile("fuzz/cases/3-01.html"),
        @embedFile("fuzz/cases/4-01.html"),
        @embedFile("fuzz/cases/5-01.html"),
        @embedFile("fuzz/cases/6-01.html"),
        @embedFile("fuzz/cases/6-02.html"),
    };

    for (cases) |c| {
        // std.debug.print("test: \n\n{s}\n\n", .{c});
        const ast = try super.html.Ast.init(std.testing.allocator, c, .html);
        defer ast.deinit(std.testing.allocator);
        if (ast.errors.len == 0) {
            var dw: std.Io.Writer.Discarding = .init(&.{});
            try ast.render(c, &dw.writer);
        }
        // ast.debug(c);
    }
}
