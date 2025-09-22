const std = @import("std");
const builtin = @import("builtin");
const super = @import("super");
const lsp_exe = @import("cli/lsp.zig");

pub fn main() !void {
    const gpa = std.heap.wasm_allocator;

    const args = std.process.argsAlloc(gpa) catch oom();
    defer std.process.argsFree(gpa, args);
    try lsp_exe.run(gpa, args[1..]);
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt, args);
    std.process.exit(1);
}

fn oom() noreturn {
    fatal("oom\n", .{});
}
