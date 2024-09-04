const std = @import("std");
const builtin = @import("builtin");
const super = @import("super");
const lsp_exe = @import("cli/lsp.zig");

pub fn main() !void {
    const gpa = std.heap.wasm_allocator;
    std.debug.print("yep new build 2", .{});
    try lsp_exe.run(gpa, &.{});
}
