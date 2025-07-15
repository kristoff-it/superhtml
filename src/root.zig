const std = @import("std");
const Writer = std.Io.Writer;
const vm = @import("vm.zig");

pub const VM = vm.VM;
pub const Exception = vm.Exception;
pub const html = @import("html.zig");
pub const css = @import("css.zig");
pub const Ast = @import("Ast.zig");

pub const HtmlSafe = struct {
    bytes: []const u8,

    pub fn format(
        self: HtmlSafe,
        out_stream: *Writer,
    ) !void {
        for (self.bytes) |b| {
            switch (b) {
                '&' => try out_stream.writeAll("&amp;"),
                '>' => try out_stream.writeAll("&gt;"),
                '<' => try out_stream.writeAll("&lt;"),
                '\'' => try out_stream.writeAll("&apos;"),
                '\"' => try out_stream.writeAll("&quot;"),
                else => try out_stream.writeByte(b),
            }
        }
    }
};

pub const utils = struct {
    pub fn IteratorContext(comptime Value: type, comptime Template: type) type {
        return struct {
            idx: u32 = undefined,
            tpl: *const VM(Template, Value).Template = undefined,

            pub fn up(lc: @This()) Value {
                return lc.tpl.loopUp(lc.idx);
            }
        };
    }

    pub fn Ctx(comptime Value: type) type {
        return struct {
            _map: *const std.StringHashMapUnmanaged(Value) = undefined,

            pub fn dot(
                ctx: *const @This(),
                _: std.mem.Allocator,
                path: []const u8,
            ) !Value {
                return ctx._map.get(path) orelse .{ .err = "field not found" };
            }
            pub const docs_description =
                \\A special map that contains all the attributes
                \\ defined on `<ctx>` in the current scope.
                \\
                \\You can access the available fields using dot notation.
                \\
                \\Example:
                \\```superhtml
                \\<div>
                \\  <ctx foo="(scripty expr)" bar="(scripty expr)"> 
                \\    <span :text="$ctx.foo"></span>
                \\    <span :text="$ctx.bar"></span>
                \\  </ctx>
                \\</div>
                \\```
            ;
            pub const Builtins = struct {};
        };
    }
};

pub const Language = enum {
    html,
    superhtml,
    xml,

    /// Use to map file extensions to a Language, supports aliases.
    pub fn fromSliceResilient(s: []const u8) ?Language {
        const Alias = enum { html, superhtml, shtml, xml };

        const alias = std.meta.stringToEnum(Alias, s) orelse {
            return null;
        };

        return switch (alias) {
            .superhtml, .shtml => .superhtml,
            .html => .html,
            .xml => .xml,
        };
    }
};
pub const max_size = 4 * 1024 * 1024 * 1024;

const Range = struct {
    start: Pos,
    end: Pos,

    const Pos = struct {
        row: u32,
        col: u32,
    };
};

pub const Line = struct { line: []const u8, start: u32 };

pub const Span = struct {
    start: u32,
    end: u32,

    pub fn len(span: Span) u32 {
        return span.end - span.start;
    }

    pub fn slice(self: Span, src: []const u8) []const u8 {
        return src[self.start..self.end];
    }

    pub fn range(self: Span, code: []const u8) Range {
        var selection: Range = .{
            .start = .{ .row = 0, .col = 0 },
            .end = undefined,
        };

        for (code[0..self.start]) |c| {
            if (c == '\n') {
                selection.start.row += 1;
                selection.start.col = 0;
            } else selection.start.col += 1;
        }

        selection.end = selection.start;
        for (code[self.start..self.end]) |c| {
            if (c == '\n') {
                selection.end.row += 1;
                selection.end.col = 0;
            } else selection.end.col += 1;
        }
        return selection;
    }

    /// Finds the line around a Node. Choose simple nodes
    //  if you don't want unwanted newlines in the middle.
    pub fn line(span: Span, src: []const u8) Line {
        var idx = span.start;
        const s = while (idx > 0) : (idx -= 1) {
            if (src[idx] == '\n') break idx + 1;
        } else 0;

        idx = span.end;
        const e = while (idx < src.len) : (idx += 1) {
            if (src[idx] == '\n') break idx;
        } else src.len - 1;

        return .{ .line = src[s..e], .start = s };
    }

    pub fn getName(span: Span, full_src: []const u8, language: Language) Span {
        var temp_tok: html.Tokenizer = .{
            .language = language,
            .return_attrs = true,
            .idx = span.start,
        };

        const src = full_src[0..span.end];
        return temp_tok.getName(src).?;
    }

    pub fn debug(span: Span, src: []const u8) void {
        std.debug.print("{s}", .{span.slice(src)});
    }
};

test {
    _ = @import("html.zig");
    _ = @import("Ast.zig");
    // _ = @import("template.zig");
}
