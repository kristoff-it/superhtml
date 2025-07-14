const std = @import("std");
const super = @import("superhtml");

const FileType = enum { html, super };

pub fn run(gpa: std.mem.Allocator, args: []const []const u8) !void {
    const cmd = Command.parse(args);
    switch (cmd.mode) {
        .stdin => {
            var fr = std.fs.File.stdin().reader(&.{});
            var aw: std.Io.Writer.Allocating = .init(gpa);
            _ = try fr.interface.streamRemaining(&aw.writer);
            const in_bytes = try aw.toOwnedSliceSentinel(0);
            const out_bytes = try renderInterface(gpa, null, in_bytes);
            try std.fs.File.stdout().writeAll(out_bytes);
        },
        .path => |path| {
            var arena_impl = std.heap.ArenaAllocator.init(gpa);
            const out_bytes = printInterfaceFromFile(
                &arena_impl,
                std.fs.cwd(),
                path,
                path,
            ) catch |err| switch (err) {
                error.IsDir => {
                    std.debug.print("error: '{s}' is a directory\n\n", .{
                        path,
                    });
                    std.process.exit(1);
                },
                else => {
                    std.debug.print("error while accessing '{s}': {}\n\n", .{
                        path,
                        err,
                    });
                    std.process.exit(1);
                },
            };

            try std.fs.File.stdout().writeAll(out_bytes);
        },
    }
}

fn printInterfaceFromFile(
    arena_impl: *std.heap.ArenaAllocator,
    base_dir: std.fs.Dir,
    sub_path: []const u8,
    full_path: []const u8,
) ![]const u8 {
    defer _ = arena_impl.reset(.retain_capacity);
    const arena = arena_impl.allocator();

    const in_bytes = try base_dir.readFileAllocOptions(
        arena,
        sub_path,
        1024 * 1024 * 4,
        null,
        .of(u8),
        0,
    );

    return renderInterface(arena, full_path, in_bytes);
}

fn renderInterface(
    arena: std.mem.Allocator,
    path: ?[]const u8,
    code: [:0]const u8,
) ![]const u8 {
    const html_ast = try super.html.Ast.init(arena, code, .superhtml);
    if (html_ast.errors.len > 0) {
        var ew = std.fs.File.stderr().writer(&.{});
        try html_ast.printErrors(code, path, &ew.interface);
        std.process.exit(1);
    }

    const s = try super.Ast.init(arena, html_ast, code);
    if (s.errors.len > 0) {
        var ew = std.fs.File.stderr().writer(&.{});
        try s.printErrors(code, path, &ew.interface);
        std.process.exit(1);
    }

    return std.fmt.allocPrint(arena, "{f}", .{
        s.interfaceFormatter(html_ast, path),
    });
}

fn oom() noreturn {
    std.debug.print("Out of memory\n", .{});
    std.process.exit(1);
}

const Command = struct {
    mode: Mode,

    const Mode = union(enum) {
        stdin,
        path: []const u8,
    };

    fn parse(args: []const []const u8) Command {
        var mode: ?Mode = null;

        var idx: usize = 0;
        while (idx < args.len) : (idx += 1) {
            const arg = args[idx];
            if (std.mem.eql(u8, arg, "--help") or
                std.mem.eql(u8, arg, "-h"))
            {
                fatalHelp();
            }

            if (std.mem.startsWith(u8, arg, "-")) {
                if (std.mem.eql(u8, arg, "--stdin") or
                    std.mem.eql(u8, arg, "-"))
                {
                    if (mode != null) {
                        std.debug.print("unexpected flag: '{s}'\n", .{arg});
                        std.process.exit(1);
                    }

                    mode = .stdin;
                } else {
                    std.debug.print("unexpected flag: '{s}'\n", .{arg});
                    std.process.exit(1);
                }
            } else {
                if (mode != null) {
                    std.debug.print(
                        "unexpected path argument: '{s}'...\n",
                        .{args[idx]},
                    );
                    std.process.exit(1);
                }

                mode = .{ .path = args[idx] };
            }
        }

        const m = mode orelse {
            std.debug.print("missing argument\n\n", .{});
            fatalHelp();
        };

        return .{ .mode = m };
    }

    fn fatalHelp() noreturn {
        std.debug.print(
            \\Usage: super i [FILE] [OPTIONS]
            \\
            \\   Prints a SuperHTML template's interface.
            \\
            \\Options:
            \\
            \\   --stdin          Read the template from stdin instead of 
            \\                    reading from a file.
            \\
            \\   --help, -h       Prints this help and exits.
        , .{});

        std.process.exit(1);
    }
};
