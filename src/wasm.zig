const std = @import("std");
const builtin = @import("builtin");
const super = @import("super");
const lsp_exe = @import("cli/lsp.zig");

pub const version = "0.1.4";

pub fn main() !void {
    const gpa = std.heap.wasm_allocator;
    try lsp_exe.run(gpa, &.{});
}
