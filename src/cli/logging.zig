const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const folders = @import("known_folders");

pub var log_file: ?std.Io.File = switch (builtin.target.os.tag) {
    .linux, .macos => std.Io.File.stderr(),
    else => null,
};

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
    // if (builtin.mode == .Debug) switch (scope) {
    if (true) switch (scope) {
        .root, .element, .super_lsp, .@"html/ast" => {},
        else => return,
    } else inline for (build_options.enabled_scopes) |es| {
        if (comptime std.mem.eql(u8, es, @tagName(scope))) {
            break;
        }
    } else return;

    const l = log_file orelse return;
    const scope_prefix = "(" ++ @tagName(scope) ++ "): ";
    const prefix = "[" ++ @tagName(level) ++ "] " ++ scope_prefix;

    var lock_buf: [64]u8 = undefined;
    _ = std.debug.lockStderr(&lock_buf);
    defer std.debug.unlockStderr();

    var buf: [1024]u8 = undefined;
    var fw = l.writerStreaming(std.Options.debug_io, &buf);
    const w = &fw.interface;
    w.print(prefix ++ format ++ "\n", args) catch return;
    w.flush() catch return;
}

pub fn setup(gpa: std.mem.Allocator, io: std.Io, environ: *std.process.Environ.Map) void {
    var lock_buf: [64]u8 = undefined;
    _ = std.debug.lockStderr(&lock_buf);
    defer std.debug.unlockStderr();

    setupInternal(gpa, io, environ) catch {
        log_file = null;
    };
}

fn setupInternal(gpa: std.mem.Allocator, io: std.Io, environ: *std.process.Environ.Map) !void {
    var cache_base = try folders.open(io, gpa, environ.*, .cache, .{}) orelse return error.Failure;
    errdefer cache_base.close(io);

    const log_path = "superhtml.log";
    const file = try cache_base.createFile(io, log_path, .{ .truncate = false });
    errdefer file.close(io);

    const end = (try file.stat(io)).size;
    var writer = file.writerStreaming(io, &.{});
    try writer.seekTo(end);

    log_file = file;
}
