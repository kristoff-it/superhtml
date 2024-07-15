const std = @import("std");
const super = @import("super");

pub const std_options = .{ .log_level = .err };

pub fn main() !void {
    var gpa_impl: std.heap.GeneralPurposeAllocator(.{}) = .{};
    // this will check for leaks and crash the program if it finds any
    defer std.debug.assert(gpa_impl.deinit() == .ok);
    const gpa = gpa_impl.allocator();

    // Read the data from stdin
    const stdin = std.io.getStdIn();
    const data = try stdin.readToEndAlloc(gpa, std.math.maxInt(usize));
    defer gpa.free(data);

    const ast = try super.html.Ast.init(gpa, data, .html);
    defer ast.deinit(gpa);
}

test "afl++ fuzz cases" {
    const cases: []const []const u8 = &.{
        @embedFile("fuzz/2.html"),
        @embedFile("fuzz/3.html"),
        @embedFile("fuzz/12.html"),
    };

    for (cases) |c| {
        std.debug.print("test: \n\n{s}\n\n", .{c});
        const ast = try super.html.Ast.init(std.testing.allocator, c, .html);
        defer ast.deinit(std.testing.allocator);
        ast.debug(c);
    }
}
