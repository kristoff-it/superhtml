const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const builtin = @import("builtin");
const build_options = @import("build_options");
const folders = @import("known_folders");

var buf: [1024]u8 = undefined;

pub var log_writer: Io.File.Writer = undefined;

// const enabled_scopes = blk: {
//     const len = build_options.enabled_scopes.len;
//     const scopes: [len]@Type(.EnumLiteral) = undefined;
//     for (build_options.enabled_scopes, &scopes) |s, *e| {
//         e.* = @Type()
//     }
// };

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    if (builtin.mode == .Debug) switch (scope) {
        // if (true) switch (scope) {
        .root, .element, .super_lsp, .@"html/ast" => {},
        else => return,
    } else inline for (build_options.enabled_scopes) |es| {
        if (comptime std.mem.eql(u8, es, @tagName(scope))) {
            break;
        }
    } else return;

    const scope_prefix = "(" ++ @tagName(scope) ++ "): ";
    const prefix = "[" ++ @tagName(level) ++ "] " ++ scope_prefix;

    _ = std.debug.lockStderr(&.{});
    defer std.debug.unlockStderr();

    const w = &log_writer.interface;
    w.print(prefix ++ format ++ "\n", args) catch return;
    w.flush() catch return;
}

pub fn setup(io: Io, gpa: Allocator, environ: *std.process.Environ.Map) void {
    _ = std.debug.lockStderr(&.{});
    defer std.debug.unlockStderr();

    setupInternal(io, gpa, environ) catch {
        log_writer = Io.File.stderr().writerStreaming(io, &.{});
    };
}

fn setupInternal(io: Io, gpa: Allocator, environ: *std.process.Environ.Map) !void {
    var cache_base = try folders.open(io, gpa, environ.*, .cache, .{}) orelse return error.Failure;
    errdefer cache_base.close(io);

    const log_path = "superhtml.log";
    const file = try cache_base.createFile(io, log_path, .{ .truncate = false });
    errdefer file.close(io);

    log_writer = file.writerStreaming(io, &buf);

    // const end = try file.length(io);
    // try file.seekTo(io, end);
}
