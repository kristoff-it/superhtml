const std = @import("std");
const Writer = std.Io.Writer;
const builtin = @import("builtin");
const html = @import("html.zig");
const Span = @import("root.zig").Span;

/// Used to catch programming errors where a function fails to report
/// correctly that an error has occurred.
pub const Fatal = error{
    /// The error has been fully reported.
    Fatal,

    /// There was an error while outputting to the error writer.
    ErrIO,

    /// There war an error while outputting to the out writer.
    OutIO,
};

pub const FatalOOM = error{OutOfMemory} || Fatal;

pub const FatalShow = Fatal || error{
    /// The error has been reported but we should also print the
    /// interface of the template we are extending.
    FatalShowInterface,
};

pub const FatalShowOOM = error{OutOfMemory} || FatalShow;

pub fn report(
    writer: *Writer,
    template_name: []const u8,
    template_path: []const u8,
    bad_node: Span,
    src: []const u8,
    error_code: []const u8,
    comptime title: []const u8,
    comptime msg: []const u8,
) Fatal {
    try header(writer, title, msg);
    try diagnostic(
        writer,
        template_name,
        template_path,
        true,
        error_code,
        bad_node,
        src,
    );
    return error.Fatal;
}

pub fn diagnostic(
    writer: *Writer,
    template_name: []const u8,
    template_path: []const u8,
    bracket_line: bool,
    note_line: []const u8,
    span: Span,
    src: []const u8,
) error{ErrIO}!void {
    const pos = span.range(src);
    const line_off = span.line(src);

    // trim spaces
    const line_trim_left = std.mem.trimLeft(u8, line_off.line, &std.ascii.whitespace);
    const start_trim_left = line_off.start + line_off.line.len - line_trim_left.len;

    const caret_len = span.end - span.start;
    const caret_spaces_len = span.start -| start_trim_left;

    const line_trim = std.mem.trimRight(u8, line_trim_left, &std.ascii.whitespace);

    var buf: [1024]u8 = undefined;

    const highlight = if (caret_len + caret_spaces_len < 1024) blk: {
        const h = buf[0 .. caret_len + caret_spaces_len];
        @memset(h[0..caret_spaces_len], ' ');
        @memset(h[caret_spaces_len..][0..caret_len], '^');
        break :blk h;
    } else "";

    writer.print(
        \\
        \\{s}{s}{s}
        \\({s}) {s}:{}:{}:
        \\    {s}
        \\    {s}
        \\
    , .{
        if (bracket_line) "[" else "",
        note_line,
        if (bracket_line) "]" else "",
        template_name,
        template_path,
        pos.start.row,
        pos.start.col,
        line_trim,
        highlight,
    }) catch return error.ErrIO;
}

pub fn header(
    writer: *Writer,
    comptime title: []const u8,
    comptime msg: []const u8,
) error{ErrIO}!void {
    writer.print(
        \\
        \\---------- {s} ----------
        \\
    , .{title}) catch return error.ErrIO;
    writer.print(msg, .{}) catch return error.ErrIO;
    writer.print("\n", .{}) catch return error.ErrIO;
}

pub fn fatal(
    writer: *Writer,
    comptime fmt: []const u8,
    args: anytype,
) Fatal {
    writer.print(fmt, args) catch return error.ErrIO;
    return error.ErrIO;
}
