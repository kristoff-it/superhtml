const std = @import("std");
const super = @import("superhtml");

const FileType = enum { html, super };

pub fn run(gpa: std.mem.Allocator, args: []const []const u8) !void {
    const cmd = Command.parse(args);
    const options = super.html.Ast.ParseOptions{
        .strict_tags = cmd.strict,
        .self_closing_void = .never,
    };
    var any_error = false;
    switch (cmd.mode) {
        .stdin => {
            var fr = std.fs.File.stdin().reader(&.{});
            var aw: std.Io.Writer.Allocating = .init(gpa);
            _ = try fr.interface.streamRemaining(&aw.writer);
            const in_bytes = try aw.toOwnedSliceSentinel(0);

            try checkHtml(gpa, null, in_bytes, options);
        },
        .stdin_super => {
            var fr = std.fs.File.stdin().reader(&.{});
            var aw: std.Io.Writer.Allocating = .init(gpa);
            _ = try fr.interface.streamRemaining(&aw.writer);
            const in_bytes = try aw.toOwnedSliceSentinel(0);

            try checkSuper(gpa, null, in_bytes, options);
        },
        .paths => |paths| {
            // checkFile will reset the arena at the end of each call
            var arena_impl = std.heap.ArenaAllocator.init(gpa);
            for (paths) |path| {
                checkFile(
                    &arena_impl,
                    std.fs.cwd(),
                    path,
                    path,
                    &any_error,
                    options,
                ) catch |err| switch (err) {
                    error.IsDir, error.AccessDenied => {
                        checkDir(
                            gpa,
                            &arena_impl,
                            path,
                            &any_error,
                            options,
                        ) catch |dir_err| {
                            std.debug.print("Error walking dir '{s}': {t}\n", .{
                                path,
                                dir_err,
                            });
                            std.process.exit(1);
                        };
                    },
                    else => {
                        std.debug.print("Error while accessing '{s}': {t}\n", .{
                            path, err,
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

fn checkDir(
    gpa: std.mem.Allocator,
    arena_impl: *std.heap.ArenaAllocator,
    path: []const u8,
    any_error: *bool,
    options: super.html.Ast.ParseOptions,
) !void {
    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();
    var walker = dir.walk(gpa) catch oom();
    defer walker.deinit();
    while (try walker.next()) |item| {
        switch (item.kind) {
            .file => {
                try checkFile(
                    arena_impl,
                    item.dir,
                    item.basename,
                    item.path,
                    any_error,
                    options,
                );
            },
            else => {},
        }
    }
}

fn checkFile(
    arena_impl: *std.heap.ArenaAllocator,
    base_dir: std.fs.Dir,
    sub_path: []const u8,
    full_path: []const u8,
    any_error: *bool,
    options: super.html.Ast.ParseOptions,
) !void {
    _ = any_error;
    defer _ = arena_impl.reset(.retain_capacity);
    const arena = arena_impl.allocator();

    const in_bytes = try base_dir.readFileAllocOptions(
        arena,
        sub_path,
        super.max_size,
        null,
        .of(u8),
        0,
    );

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

    switch (file_type) {
        .html => try checkHtml(
            arena,
            full_path,
            in_bytes,
            options,
        ),
        .super => try checkSuper(
            arena,
            full_path,
            in_bytes,
            options,
        ),
    }
}

pub fn checkHtml(
    arena: std.mem.Allocator,
    path: ?[]const u8,
    code: [:0]const u8,
    options: super.html.Ast.ParseOptions,
) !void {
    const ast = try super.html.Ast.init(arena, code, .html, options);
    if (ast.errors.len > 0) {
        var stderr = std.fs.File.stderr().writer(&.{});
        try ast.printErrors(code, path, &stderr.interface);
        std.process.exit(1);
    }
}

fn checkSuper(
    arena: std.mem.Allocator,
    path: ?[]const u8,
    code: [:0]const u8,
    options: super.html.Ast.ParseOptions,
) !void {
    const html = try super.html.Ast.init(arena, code, .superhtml, options);
    if (html.errors.len > 0) {
        var stderr = std.fs.File.stderr().writer(&.{});
        try html.printErrors(code, path, &stderr.interface);
        std.process.exit(1);
    }

    const s = try super.Ast.init(arena, html, code);
    if (s.errors.len > 0) {
        var stderr = std.fs.File.stderr().writer(&.{});
        try s.printErrors(code, path, &stderr.interface);
        std.process.exit(1);
    }
}

fn oom() noreturn {
    std.debug.print("Out of memory\n", .{});
    std.process.exit(1);
}

const Command = struct {
    mode: Mode,
    strict: bool,

    const Mode = union(enum) {
        stdin,
        stdin_super,
        paths: []const []const u8,
    };

    fn parse(args: []const []const u8) Command {
        var mode: ?Mode = null;
        var strict: ?bool = null;

        var idx: usize = 0;
        while (idx < args.len) : (idx += 1) {
            const arg = args[idx];
            if (std.mem.eql(u8, arg, "--help") or
                std.mem.eql(u8, arg, "-h"))
            {
                fatalHelp();
            }

            if (std.mem.eql(u8, arg, "--no-strict-tags")) {
                strict = false;
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

        return .{
            .mode = m,
            .strict = strict orelse true,
        };
    }

    fn fatalHelp() noreturn {
        std.debug.print(
            \\Usage: super check PATH [PATH...] [OPTIONS]
            \\
            \\   Checks for syntax errors. If PATH is a directory, it will
            \\   be searched recursively for HTML and SuperHTML files.
            \\     
            \\   Detected extensions:     
            \\        HTML          .html, .htm 
            \\        SuperHTML     .shtml 
            \\
            \\Options:
            \\
            \\   --stdin          Format bytes from stdin and output to stdout.
            \\                    Mutually exclusive with other input arguments.
            \\
            \\   --stdin-super    Same as --stdin but for SuperHTML files.
            \\
            \\  --no-strict-tags  Disable strict checking of tag names in HTML
            \\                    and SuperHTML files. 
            \\
            \\   --help, -h       Prints this help and exits.
            \\
        , .{});

        std.process.exit(1);
    }
};
