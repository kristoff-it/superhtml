const std = @import("std");
const Reader = std.Io.Reader;
const html = @import("generator/html.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    const args = try init.minimal.args.toSlice(init.arena.allocator());

    var bufout: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(io, &bufout);

    if (args.len > 2) @panic("wrong number of arguments");
    if (args.len == 1) {
        var bufin: [4096]u8 = undefined;
        var in = std.Io.File.stdin().reader(io, &bufin);
        try html.generate(gpa, &in.interface, &out.interface);
    } else {
        var in: Reader = .fixed(args[1]);
        try html.generate(gpa, &in, &out.interface);
    }

    try out.interface.flush();
}
