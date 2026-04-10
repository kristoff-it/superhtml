const std = @import("std");
const builtin = @import("builtin");
const lsp_exe = @import("cli/lsp.zig");

pub fn main() !void {
    const gpa = std.heap.wasm_allocator;
    const args = std.process.argsAlloc(gpa) catch std.process.fatal("oom", .{});
    defer std.process.argsFree(gpa, args);
    try lsp_exe.run(gpa, args[1..]);
}
