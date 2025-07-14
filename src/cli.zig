const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const known = @import("known_folders");
const super = @import("super");
const logging = @import("cli/logging.zig");
const interface_exe = @import("cli/interface.zig");
const check_exe = @import("cli/check.zig");
const fmt_exe = @import("cli/fmt.zig");
const lsp_exe = @import("cli/lsp.zig");

pub const known_folders_config = known.KnownFolderConfig{
    .xdg_force_default = true,
    .xdg_on_mac = true,
};

pub const std_options: std.Options = .{
    .log_level = if (build_options.verbose_logging)
        .debug
    else
        std.log.default_level,
    .logFn = logging.logFn,
};

var lsp_mode = false;

pub fn panic(
    msg: []const u8,
    trace: ?*std.builtin.StackTrace,
    ret_addr: ?usize,
) noreturn {
    if (lsp_mode) {
        std.log.err("{s}\n\n{?f}", .{ msg, trace });
    } else {
        std.debug.print("{s}\n\n{?f}", .{ msg, trace });
    }
    blk: {
        const out: std.fs.File = if (!lsp_mode) std.fs.File.stderr() else logging.log_file orelse break :blk;
        var writer = out.writer(&.{});
        const w = &writer.interface;
        if (builtin.strip_debug_info) {
            w.print("Unable to dump stack trace: debug info stripped\n", .{}) catch return;
            break :blk;
        }
        const debug_info = std.debug.getSelfDebugInfo() catch |err| {
            w.print("Unable to dump stack trace: Unable to open debug info: {s}\n", .{@errorName(err)}) catch break :blk;
            break :blk;
        };
        std.debug.writeCurrentStackTrace(w, debug_info, .no_color, ret_addr) catch |err| {
            w.print("Unable to dump stack trace: {t}\n", .{err}) catch break :blk;
            break :blk;
        };
    }
    if (builtin.mode == .Debug) @breakpoint();
    std.process.exit(1);
}

pub const Command = enum {
    check,
    interface,
    i, // alias for interface
    fmt,
    lsp,
    help,
    version,
};

pub fn main() !void {
    var gpa_impl: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const gpa = gpa_impl.allocator();

    logging.setup(gpa);

    const args = std.process.argsAlloc(gpa) catch oom();
    defer std.process.argsFree(gpa, args);

    if (args.len < 2) fatalHelp();

    const cmd = std.meta.stringToEnum(Command, args[1]) orelse {
        std.debug.print("unrecognized subcommand: '{s}'\n\n", .{args[1]});
        fatalHelp();
    };

    if (cmd == .lsp) lsp_mode = true;

    _ = switch (cmd) {
        .check => check_exe.run(gpa, args[2..]),
        .interface, .i => interface_exe.run(gpa, args[2..]),
        .fmt => fmt_exe.run(gpa, args[2..]),
        .lsp => lsp_exe.run(gpa, args[2..]),
        .help => fatalHelp(),
        .version => printVersion(),
    } catch |err| fatal("unexpected error: {t}\n", .{err});
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt, args);
    std.process.exit(1);
}

fn oom() noreturn {
    fatal("oom\n", .{});
}

fn printVersion() noreturn {
    std.debug.print("{s}\n", .{build_options.version});
    std.process.exit(0);
}

fn fatalHelp() noreturn {
    fatal(
        \\Usage: superhtml COMMAND [OPTIONS]
        \\
        \\Commands:
        \\  check         Check documents for syntax errors
        \\  interface, i  Print a SuperHTML template's interface
        \\  fmt           Format documents
        \\  lsp           Start the Super LSP
        \\  help          Show this menu and exit
        \\  version       Print Super's version and exit
        \\
        \\General Options:
        \\  --help, -h   Print command specific usage
        \\
        \\
    , .{});
}
