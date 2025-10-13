const builtin = @import("builtin");
const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const super = @import("superhtml");

var bufout: [4096]u8 = undefined;
var buferr: [4096]u8 = undefined;

var syntax_errors = false;
pub fn run(gpa: Allocator, args: []const []const u8) !noreturn {
    // Prints html errors found in the document
    var stderr_writer = std.fs.File.stderr().writerStreaming(&buferr);
    const stderr = &stderr_writer.interface;

    // Prints file paths of files that were modified on disk
    var stdout_writer = std.fs.File.stdout().writerStreaming(&bufout);
    const stdout = &stdout_writer.interface;

    const cmd = Command.parse(args);
    switch (cmd.mode) {
        .stdin => |lang| {
            var fr = std.fs.File.stdin().reader(&.{});
            var aw: Writer.Allocating = .init(gpa);
            _ = try fr.interface.streamRemaining(&aw.writer);
            const in_bytes = try aw.toOwnedSliceSentinel(0);

            if (try fmt(gpa, stderr, null, in_bytes, lang, cmd.syntax_only)) |fmt_src| {
                try std.fs.File.stdout().writeAll(fmt_src);
            }
        },
        .paths => |paths| {
            // checkFile will reset the arena at the end of each call
            var arena_impl = std.heap.ArenaAllocator.init(gpa);
            for (paths) |path| {
                formatFile(
                    &arena_impl,
                    stdout,
                    stderr,
                    cmd.check,
                    std.fs.cwd(),
                    path,
                    path,
                    cmd.syntax_only,
                ) catch |err| switch (err) {
                    error.IsDir, error.AccessDenied => formatDir(
                        gpa,
                        &arena_impl,
                        stdout,
                        stderr,
                        cmd.check,
                        path,
                        cmd.syntax_only,
                    ) catch |dir_err| {
                        std.debug.print("error walking dir '{s}': {s}\n", .{
                            path,
                            @errorName(dir_err),
                        });
                        std.process.exit(1);
                    },
                    else => {
                        std.debug.print("error while accessing '{s}': {s}\n", .{
                            path, @errorName(err),
                        });
                        std.process.exit(1);
                    },
                };
            }
        },
    }

    try stdout.flush();
    try stderr.flush();
    std.process.exit(@intFromBool(syntax_errors));
}

fn formatDir(
    gpa: std.mem.Allocator,
    arena_impl: *std.heap.ArenaAllocator,
    stdout: *Writer,
    stderr: *Writer,
    check: bool,
    path: []const u8,
    syntax_only: bool,
) !void {
    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();

    var walker = dir.walk(gpa) catch oom();
    defer walker.deinit();

    while (try walker.next()) |item| {
        switch (item.kind) {
            .file => try formatFile(
                arena_impl,
                stdout,
                stderr,
                check,
                item.dir,
                item.basename,
                item.path,
                syntax_only,
            ),
            else => {},
        }
    }
}

fn formatFile(
    arena_impl: *std.heap.ArenaAllocator,
    stdout: *Writer,
    stderr: *Writer,
    check: bool,
    base_dir: std.fs.Dir,
    sub_path: []const u8,
    full_path: []const u8,
    syntax_only: bool,
) !void {
    defer _ = arena_impl.reset(.retain_capacity);
    const arena = arena_impl.allocator();

    const in_bytes = if (builtin.zig_version.minor == 15) try base_dir.readFileAllocOptions(
        arena,
        sub_path,
        super.max_size,
        null,
        .of(u8),
        0,
    ) else try base_dir.readFileAllocOptions(
        sub_path,
        arena,
        .limited(super.max_size),
        .of(u8),
        0,
    );

    const language: super.Language = blk: {
        const ext = std.fs.path.extension(sub_path);
        if (std.mem.eql(u8, ext, ".html") or
            std.mem.eql(u8, ext, ".htm"))
        {
            break :blk .html;
        }

        if (std.mem.eql(u8, ext, ".shtml")) {
            break :blk .superhtml;
        }

        // Unkown file, skip it
        return;
    };

    if (try fmt(arena, stderr, full_path, in_bytes, language, syntax_only)) |fmt_src| {
        if (std.mem.eql(u8, fmt_src, in_bytes)) return;
        if (check) {
            syntax_errors = true;
            try stdout.print("{s}\n", .{full_path});
            return;
        }

        var af = try base_dir.atomicFile(sub_path, .{ .write_buffer = &.{} });
        defer af.deinit();

        try af.file_writer.interface.writeAll(fmt_src);
        try af.finish();
        try stdout.print("{s}\n", .{full_path});
    } else if (check) {
        syntax_errors = true;
        try stdout.print("{s}\n", .{full_path});
        return;
    }
}

pub fn fmt(
    arena: std.mem.Allocator,
    stderr: *Writer,
    path: ?[]const u8,
    src: [:0]const u8,
    language: super.Language,
    syntax_only: bool,
) !?[]const u8 {
    const html_ast = try super.html.Ast.init(arena, src, language, syntax_only);
    if (html_ast.errors.len > 0) {
        try html_ast.printErrors(src, path, stderr);
        if (html_ast.has_syntax_errors) {
            syntax_errors = true;
            return null;
        }
    } else if (language == .superhtml) {
        const super_ast = try super.Ast.init(arena, html_ast, src);
        if (super_ast.errors.len > 0) {
            try html_ast.printErrors(src, path, stderr);
        }
    }

    return try std.fmt.allocPrint(arena, "{f}", .{
        html_ast.formatter(src),
    });
}

fn oom() noreturn {
    std.debug.print("Out of memory\n", .{});
    std.process.exit(1);
}

const Command = struct {
    check: bool,
    mode: Mode,
    syntax_only: bool,

    const Mode = union(enum) {
        stdin: super.Language,
        paths: []const []const u8,
    };

    fn parse(args: []const []const u8) Command {
        var check: bool = false;
        var mode: ?Mode = null;
        var syntax_only: ?bool = null;

        var idx: usize = 0;
        while (idx < args.len) : (idx += 1) {
            const arg = args[idx];
            if (std.mem.eql(u8, arg, "--help") or
                std.mem.eql(u8, arg, "-h"))
            {
                fatalHelp();
            }

            if (std.mem.eql(u8, arg, "--check")) {
                check = true;
                continue;
            }

            if (std.mem.eql(u8, arg, "--syntax-only")) {
                syntax_only = true;
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

                    mode = .{ .stdin = .html };
                } else if (std.mem.eql(u8, arg, "--stdin-super")) {
                    if (mode != null) {
                        std.debug.print("unexpected flag: '{s}'\n", .{arg});
                        std.process.exit(1);
                    }

                    mode = .{ .stdin = .superhtml };
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
            .check = check,
            .mode = m,
            .syntax_only = syntax_only orelse false,
        };
    }

    fn fatalHelp() noreturn {
        std.debug.print(
            \\Usage: superhtml fmt PATH [PATH...] [OPTIONS]
            \\
            \\   Formats input paths inplace. If PATH is a directory, it will
            \\   be searched recursively for HTML and SuperHTML files.
            \\   HTML errors will be printed to stderr but will only cause a
            \\   non-zero exit code if they prevent formatting (i.e. syntax
            \\   errors).
            \\     
            \\   Detected extensions:     
            \\        HTML          .html, .htm 
            \\        SuperHTML     .shtml 
            \\
            \\Options:
            \\
            \\   --stdin          Format bytes from stdin and output to stdout.
            \\                    Mutually exclusive with other input arguments.
            \\   --stdin-super    Same as --stdin but for SuperHTML files.
            \\   --check          List non-conforming files to stdout and exit 
            \\                    with an error if the list is not empty.
            \\                    Does not modify files on disk.
            \\   --syntax-only    Disable HTML element and attribute validation.
            \\   --help, -h       Prints this help and exits.
            \\
        , .{});

        std.process.exit(1);
    }
};
