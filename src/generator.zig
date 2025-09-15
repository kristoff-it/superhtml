const std = @import("std");
const Reader = std.Io.Reader;
const html = @import("generator/html.zig");

pub fn main() !void {
    const gpa = std.heap.smp_allocator;

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    var bufout: [4096]u8 = undefined;
    var out = std.fs.File.stdout().writer(&bufout);

    if (args.len > 2) @panic("wrong number of arguments");
    if (args.len == 1) {
        var bufin: [4096]u8 = undefined;
        var in = std.fs.File.stdin().reader(&bufin);
        try html.generate(gpa, &in.interface, &out.interface);
    } else {
        var in: Reader = .fixed(args[1]);
        try html.generate(gpa, &in, &out.interface);
    }

    try out.interface.flush();
}
