const std = @import("std");
const builtin = @import("builtin");
const super = @import("super");
const logging = @import("cli/logging.zig");
const fmt_exe = @import("cli/fmt.zig");
const lsp_exe = @import("cli/lsp.zig");

pub const version = "0.1.4";

pub const known_folders_config = .{
    .xdg_force_default = true,
    .xdg_on_mac = true,
};

pub const std_options: std.Options = .{
    .logFn = logging.logFn,
};

var lsp_mode = false;
pub fn panic(
    msg: []const u8,
    trace: ?*std.builtin.StackTrace,
    ret_addr: ?usize,
) noreturn {
    if (lsp_mode) {
        std.log.err("{s}\n\n{?}", .{ msg, trace });
    } else {
        std.debug.print("{s}\n\n{?}", .{ msg, trace });
    }
    blk: {
        const out = if (!lsp_mode) std.io.getStdErr() else logging.log_file orelse break :blk;
        const w = out.writer();
        if (builtin.strip_debug_info) {
            w.print("Unable to dump stack trace: debug info stripped\n", .{}) catch return;
            break :blk;
        }
        const debug_info = std.debug.getSelfDebugInfo() catch |err| {
            w.print("Unable to dump stack trace: Unable to open debug info: {s}\n", .{@errorName(err)}) catch break :blk;
            break :blk;
        };
        std.debug.writeCurrentStackTrace(w, debug_info, .no_color, ret_addr) catch |err| {
            w.print("Unable to dump stack trace: {s}\n", .{@errorName(err)}) catch break :blk;
            break :blk;
        };
    }
    if (builtin.mode == .Debug) @breakpoint();
    std.process.exit(1);
}

pub const Command = enum { fmt, lsp, help };

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
        .fmt => fmt_exe.run(gpa, args[2..]),
        .lsp => lsp_exe.run(gpa, args[2..]),
        .help => fatalHelp(),
    } catch |err| fatal("unexpected error: {s}\n", .{@errorName(err)});
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt, args);
    std.process.exit(1);
}

fn oom() noreturn {
    fatal("oom\n", .{});
}

fn fatalHelp() noreturn {
    fatal(
        \\Usage: super COMMAND [OPTIONS]
        \\
        \\Commands: 
        // \\  check        Check HTML documents for syntax errors
        \\  fmt          Format HTML documents
        \\  lsp          Start the Super LSP
        \\  help         Show this menu and exit
        \\
        \\General Options:
        \\  --help, -h   Print command specific usage
        \\
        \\
    , .{});
}
