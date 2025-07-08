const std = @import("std");
const super = @import("superhtml");
const ElementValidationMode = super.html.Ast.ElementValidationMode;

const FileType = enum { html, super };

pub fn run(gpa: std.mem.Allocator, args: []const []const u8) !void {
    const cmd = Command.parse(args);
    var any_error = false;
    switch (cmd.mode) {
        .stdin => {
            var buf = std.ArrayList(u8).init(gpa);
            try std.io.getStdIn().reader().readAllArrayList(&buf, super.max_size);
            const in_bytes = try buf.toOwnedSliceSentinel(0);

            const out_bytes = try fmtHtml(gpa, null, in_bytes);
            try std.io.getStdOut().writeAll(out_bytes);
        },
        .stdin_super => {
            var buf = std.ArrayList(u8).init(gpa);
            try std.io.getStdIn().reader().readAllArrayList(&buf, super.max_size);
            const in_bytes = try buf.toOwnedSliceSentinel(0);

            const out_bytes = try fmtSuper(gpa, null, in_bytes);
            try std.io.getStdOut().writeAll(out_bytes);
        },
        .paths => |paths| {
            // checkFile will reset the arena at the end of each call
            var arena_impl = std.heap.ArenaAllocator.init(gpa);
            for (paths) |path| {
                formatFile(
                    &arena_impl,
                    cmd.check,
                    std.fs.cwd(),
                    path,
                    path,
                    &any_error,
                ) catch |err| switch (err) {
                    error.IsDir, error.AccessDenied => {
                        formatDir(
                            gpa,
                            &arena_impl,
                            cmd.check,
                            path,
                            &any_error,
                        ) catch |dir_err| {
                            std.debug.print("Error walking dir '{s}': {s}\n", .{
                                path,
                                @errorName(dir_err),
                            });
                            std.process.exit(1);
                        };
                    },
                    else => {
                        std.debug.print("Error while accessing '{s}': {s}\n", .{
                            path, @errorName(err),
                        });
                        std.process.exit(1);
                    },
                };
            }
        },
    }

    if (any_error) {
        std.process.exit(1);
    }
}

fn formatDir(
    gpa: std.mem.Allocator,
    arena_impl: *std.heap.ArenaAllocator,
    check: bool,
    path: []const u8,
    any_error: *bool,
) !void {
    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();
    var walker = dir.walk(gpa) catch oom();
    defer walker.deinit();
    while (try walker.next()) |item| {
        switch (item.kind) {
            .file => {
                try formatFile(
                    arena_impl,
                    check,
                    item.dir,
                    item.basename,
                    item.path,
                    any_error,
                );
            },
            else => {},
        }
    }
}

fn formatFile(
    arena_impl: *std.heap.ArenaAllocator,
    check: bool,
    base_dir: std.fs.Dir,
    sub_path: []const u8,
    full_path: []const u8,
    any_error: *bool,
) !void {
    defer _ = arena_impl.reset(.retain_capacity);
    const arena = arena_impl.allocator();

    const file = try base_dir.openFile(sub_path, .{});
    defer file.close();

    const stat = try file.stat();
    if (stat.kind == .directory)
        return error.IsDir;

    const file_type: FileType = blk: {
        const ext = std.fs.path.extension(sub_path);
        if (std.mem.eql(u8, ext, ".html") or
            std.mem.eql(u8, ext, ".htm"))
        {
            break :blk .html;
        }

        if (std.mem.eql(u8, ext, ".shtml")) {
            break :blk .super;
        }
        return;
    };

    var buf = std.ArrayList(u8).init(arena);
    defer buf.deinit();

    try file.reader().readAllArrayList(&buf, super.max_size);

    const in_bytes = try buf.toOwnedSliceSentinel(0);

    const out_bytes = switch (file_type) {
        .html => try fmtHtml(
            arena,
            full_path,
            in_bytes,
        ),
        .super => try fmtSuper(
            arena,
            full_path,
            in_bytes,
        ),
    };

    if (std.mem.eql(u8, out_bytes, in_bytes)) return;

    const stdout = std.io.getStdOut().writer();
    if (check) {
        any_error.* = true;
        try stdout.print("{s}\n", .{full_path});
        return;
    }

    var af = try base_dir.atomicFile(sub_path, .{ .mode = stat.mode });
    defer af.deinit();

    try af.file.writeAll(out_bytes);
    try af.finish();
    try stdout.print("{s}\n", .{full_path});
}

pub fn fmtHtml(
    arena: std.mem.Allocator,
    path: ?[]const u8,
    code: [:0]const u8,
) ![]const u8 {
    const ast = try super.html.Ast.init(
        arena,
        code,
        .html,
        ElementValidationMode.off,
    );
    if (ast.errors.len > 0) {
        try ast.printErrors(code, path, std.io.getStdErr().writer());
        std.process.exit(1);
    }

    return std.fmt.allocPrint(arena, "{}", .{ast.formatter(code)});
}

fn fmtSuper(
    arena: std.mem.Allocator,
    path: ?[]const u8,
    code: [:0]const u8,
) ![]const u8 {
    const ast = try super.html.Ast.init(
        arena,
        code,
        .superhtml,
        ElementValidationMode.off,
    );
    if (ast.errors.len > 0) {
        try ast.printErrors(code, path, std.io.getStdErr().writer());
        std.process.exit(1);
    }

    return std.fmt.allocPrint(arena, "{}", .{ast.formatter(code)});
}

fn oom() noreturn {
    std.debug.print("Out of memory\n", .{});
    std.process.exit(1);
}

const Command = struct {
    check: bool,
    mode: Mode,

    const Mode = union(enum) {
        stdin,
        stdin_super,
        paths: []const []const u8,
    };

    fn parse(args: []const []const u8) Command {
        var check: bool = false;
        var mode: ?Mode = null;

        var idx: usize = 0;
        while (idx < args.len) : (idx += 1) {
            const arg = args[idx];
            if (std.mem.eql(u8, arg, "--help") or
                std.mem.eql(u8, arg, "-h"))
            {
                fatalHelp();
            }

            if (std.mem.eql(u8, arg, "--check")) {
                if (check) {
                    std.debug.print("error: duplicate '--check' flag\n\n", .{});
                    std.process.exit(1);
                }

                check = true;
                continue;
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
                } else if (std.mem.eql(u8, arg, "--stdin-super")) {
                    if (mode != null) {
                        std.debug.print("unexpected flag: '{s}'\n", .{arg});
                        std.process.exit(1);
                    }

                    mode = .stdin_super;
                } else {
                    std.debug.print("unexpected flag: '{s}'\n", .{arg});
                    std.process.exit(1);
                }
            } else {
                const paths_start = idx;
                while (idx < args.len) : (idx += 1) {
                    if (std.mem.startsWith(u8, args[idx], "-")) {
                        break;
                    }
                }
                idx -= 1;

                if (mode != null) {
                    std.debug.print(
                        "unexpected path argument(s): '{s}'...\n",
                        .{args[paths_start]},
                    );
                    std.process.exit(1);
                }

                const paths = args[paths_start .. idx + 1];
                mode = .{ .paths = paths };
            }
        }

        const m = mode orelse {
            std.debug.print("missing argument(s)\n\n", .{});
            fatalHelp();
        };

        return .{ .check = check, .mode = m };
    }

    fn fatalHelp() noreturn {
        std.debug.print(
            \\Usage: super fmt PATH [PATH...] [OPTIONS]
            \\
            \\   Formats input paths inplace. If PATH is a directory, it will
            \\   be searched recursively for HTML and SuperHTML files.
            \\     
            \\   Detected extensions:     
            \\        HTML          .html, .htm 
            \\        SuperHTML     .shtml 
            \\
            \\Options:
            \\
            \\   --stdin            Format bytes from stdin and output to stdout.
            \\                      Mutually exclusive with other input arguments.
            \\
            \\   --stdin-super      Same as --stdin but for SuperHTML files.
            \\
            \\   --check            List non-conforming files and exit with an
            \\                      error if the list is not empty.
            \\
            \\   --help, -h         Prints this help and exits.
        , .{});

        std.process.exit(1);
    }
};
