const std = @import("std");
const builtin = @import("builtin");
const super = @import("super");
const lsp_exe = @import("cli/lsp.zig");

pub const version = "0.1.4";

pub fn main() !void {
    std.debug.print("Yep it werks3", .{});
    // const gpa = std.heap.wasm_allocator;
    // try lsp_exe.run(gpa, &.{});

    const Buf = std.fifo.LinearFifo(u8, .{ .Static = 1024 * 128 });
    var buf = Buf.init();
    try buf.pump(std.io.getStdIn().reader(), std.io.getStdErr().writer());
}
