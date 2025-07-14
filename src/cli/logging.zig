const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const folders = @import("known_folders");

pub var log_file: ?std.fs.File = switch (builtin.target.os.tag) {
    .linux, .macos => std.fs.File.stderr(),
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
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    if (build_options.enabled_scopes.len > 0) {
        inline for (build_options.enabled_scopes) |es| {
            if (comptime std.mem.eql(u8, es, @tagName(scope))) {
                break;
            }
        } else return;
    }

    const l = log_file orelse return;
    const scope_prefix = "(" ++ @tagName(scope) ++ "): ";
    const prefix = "[" ++ @tagName(level) ++ "] " ++ scope_prefix;

    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();

    var buf: [1024]u8 = undefined;
    var fw = l.writer(&buf);
    const w = &fw.interface;
    w.print(prefix ++ format ++ "\n", args) catch return;
    w.flush() catch return;
}

pub fn setup(gpa: std.mem.Allocator) void {
    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();

    setupInternal(gpa) catch {
        log_file = null;
    };
}

fn setupInternal(gpa: std.mem.Allocator) !void {
    const cache_base = try folders.open(gpa, .cache, .{}) orelse return error.Failure;
    try cache_base.makePath("super");

    const log_path = "superhtml.log";
    const file = try cache_base.createFile(log_path, .{ .truncate = false });
    const end = try file.getEndPos();
    try file.seekTo(end);

    log_file = file;
}
