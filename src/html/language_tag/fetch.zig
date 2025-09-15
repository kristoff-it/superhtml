const std = @import("std");

pub fn main() !void {
    var arena_instance: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    const arena = arena_instance.allocator();
    defer arena_instance.deinit();

    var args = try std.process.argsWithAllocator(arena);
    std.debug.assert(args.skip());

    const file = file: {
        const output_path = args.next() orelse break :file std.fs.File.stdout();
        break :file try std.fs.cwd().createFile(output_path, .{});
    };
    var buffer: [1024]u8 = undefined;
    var writer = file.writer(&buffer);
    const output = &writer.interface;

    var client: std.http.Client = .{ .allocator = arena };
    _ = try client.fetch(.{
        .location = .{ .url = "https://www.iana.org/assignments/language-subtag-registry/language-subtag-registry" },
        .response_writer = output,
    });

    try output.flush();
}
