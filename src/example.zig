const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const scripty = @import("scripty");
const superhtml = @import("root.zig"); // In your case this would be @import("superhtml")

/// A SuperHTML VM is created by giving it the Context and Value types that
/// make up the Scripty evaluation context. See `src/example.zig` in
/// https://github.com/kristoff-it/scripty for more details on how that
/// works.
///
/// Note that your Scripty values must have some definitions that are
/// required by SuperHTML, such as Optional (used by ':if') and Iterator
/// (used by ':loop').
const ExampleVM = superhtml.VM(ExampleContext, ExampleValue);

test ExampleVM {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();

    const arena = arena_state.allocator();

    var ctx: ExampleContext = .{
        .version = "v0",
        .page = .{
            .title = "Home",
            .content = "<p>Welcome!</p>",
        },
        .site = .{
            .name = "Example Website",
            .hostname = "example.com",
        },
        ._force_https = true,
    };

    const layout_src =
        \\<a href="$site.link()" :text="$site.name"></a>
    ;

    const layout_html_ast: superhtml.html.Ast = try .init(arena, layout_src, .superhtml, false);
    try std.testing.expectEqual(0, layout_html_ast.errors.len);

    const layout_super_ast: superhtml.Ast = try .init(arena, layout_html_ast, layout_src);
    try std.testing.expectEqual(0, layout_super_ast.errors.len);

    var out_writer: Io.Writer.Allocating = .init(arena);
    var err_writer: Io.Writer.Allocating = .init(arena);

    var vm: ExampleVM = .init(
        arena,
        &ctx,
        "(root)",
        "/root.html",
        layout_src,
        layout_html_ast,
        layout_super_ast,
        false,
        "(page name)",
        &out_writer.writer,
        &err_writer.writer,
    );

    while (true) vm.run() catch |err| switch (err) {
        error.Done => break,
        error.Quota => unreachable, // we are running with infinite quota, see RunOptions
        error.WantSnippet => @panic("unimplemented"),
        error.WantTemplate => unreachable,
        // Fatal errors.
        // IO errors are mapped to oom because we're using allocating writers.
        error.ErrIO, error.OutIO, error.OutOfMemory => std.process.fatal("oom", .{}),
        error.Fatal => {
            std.debug.print("error output: \n{s}\n", .{err_writer.written()});
            std.process.fatal("fatal", .{});
        },
    };

    try std.testing.expectEqualStrings("", err_writer.written());
    try std.testing.expectEqualStrings(
        \\<a href="https://example.com">Example Website</a>
    , out_writer.written());
}

const ExampleContext = struct {
    version: []const u8,
    page: Page,
    site: Site,
    _force_https: bool,

    // Globals specific to SuperHTML
    ctx: superhtml.utils.Ctx(ExampleValue) = .{},
    loop: ?*ExampleValue.Iterator = null,
    @"if": ?*const ExampleValue.Optional = null,

    pub const PassByRef = true;
    pub const dot = scripty.defaultDot(ExampleContext, ExampleValue, false);
    pub const Builtins = struct {};

    pub const Site = struct {
        name: []const u8,
        hostname: []const u8,

        pub const PassByRef = true;
        pub const dot = scripty.defaultDot(Site, ExampleValue, false);

        pub const Builtins = struct {
            pub const link = struct {
                pub fn call(
                    site: *const Site,
                    gpa: Allocator,
                    ctx: *const ExampleContext,
                    args: []const ExampleValue,
                ) !ExampleValue {
                    const bad_arg: ExampleValue = .{ .err = "expected 0 arguments" };
                    if (args.len != 0) return bad_arg;

                    return .{
                        .string = .{
                            .value = try std.fmt.allocPrint(gpa, "http{s}://{s}", .{
                                if (ctx._force_https) "s" else "",
                                site.hostname,
                            }),
                        },
                    };
                }
            };
        };
    };

    pub const Page = struct {
        title: []const u8,
        content: []const u8,

        pub const PassByRef = true;
        pub const dot = scripty.defaultDot(Page, ExampleValue, false);
        pub const Builtins = struct {};
    };
};

pub const ExampleValue = union(Tag) {
    global: *const ExampleContext,
    site: *const ExampleContext.Site,
    page: *const ExampleContext.Page,
    string: String,
    bool: Bool,
    int: Int,
    float: Float,
    err: []const u8, // error message
    nil,

    // Definitions required by SuperHTML
    ctx: superhtml.utils.Ctx(ExampleValue),
    optional: ?*const Optional, // used by :if
    iterator: *Iterator, // used by :loop
    array: Array,

    pub const Int = struct {
        value: i64,
        pub const PassByRef = false;
        pub const Builtins = struct {};
    };

    pub const Float = struct {
        value: f64,
        pub const PassByRef = false;
        pub const Builtins = struct {};
    };

    pub const String = struct {
        value: []const u8,
        pub const PassByRef = false;
        pub const Builtins = struct {};
    };

    pub const Bool = struct {
        value: bool,

        pub const PassByRef = false;
        pub const Builtins = struct {};
    };

    pub const Tag = enum {
        global,
        site,
        page,
        string,
        bool,
        int,
        float,
        err,
        nil,

        ctx,
        optional,
        iterator,
        array,
    };

    pub fn dot(
        self: ExampleValue,
        gpa: std.mem.Allocator,
        path: []const u8,
    ) error{OutOfMemory}!ExampleValue {
        switch (self) {
            .string,
            .bool,
            .int,
            .float,
            .err,
            .nil,
            .optional,
            => return .{ .err = "primitive value" },
            inline else => |v| return v.dot(gpa, path),
        }
    }

    pub const call = scripty.defaultCall(ExampleValue, ExampleContext);

    pub fn fromStringLiteral(bytes: []const u8) ExampleValue {
        return .{ .string = .{ .value = bytes } };
    }

    pub fn fromNumberLiteral(bytes: []const u8) ExampleValue {
        _ = bytes;
        return .{ .int = .{ .value = 0 } };
    }

    pub fn fromBooleanLiteral(b: bool) ExampleValue {
        return .{ .bool = .{ .value = b } };
    }

    pub fn from(gpa: std.mem.Allocator, value: anytype) !ExampleValue {
        _ = gpa;
        const T = @TypeOf(value);
        switch (T) {
            *ExampleContext, *const ExampleContext => return .{ .global = value },
            ExampleValue => return value,
            *const ExampleContext.Site => return .{ .site = value },
            *const ExampleContext.Page => return .{ .page = value },
            ?*const ExampleValue.Optional => return if (value) |v| .{ .optional = v } else .nil,
            ?*ExampleValue.Iterator => return if (value) |v| .{ .iterator = v } else .nil,
            superhtml.utils.Ctx(ExampleValue) => return .{ .ctx = value },
            []const u8 => return .{ .string = .{ .value = value } },
            usize => return .{ .int = .{ .value = @intCast(value) } },
            bool => return .{ .bool = .{ .value = value } },
            else => @compileError("TODO: add support for " ++ @typeName(T)),
        }
    }

    pub fn renderForError(value: ExampleValue, arena: Allocator, w: *Io.Writer) !void {
        _ = arena;
        switch (value) {
            else => w.print("{any}", .{value}) catch return error.ErrIO,
        }
    }

    pub const Optional = struct {
        value: ExampleValue,

        pub const PassByRef = false;
        pub const Builtins = struct {};
    };

    pub const Iterator = struct {
        it: ExampleValue = undefined,
        idx: usize = 0,
        first: bool = undefined,
        last: bool = undefined,
        len: usize,

        _superhtml_context: superhtml.utils.IteratorContext(ExampleValue, ExampleContext) = .{},
        _impl: Impl,

        pub const Impl = union(enum) {
            value_it: SliceIterator(ExampleValue),

            pub fn len(impl: Impl) usize {
                switch (impl) {
                    inline else => |v| return v.len(),
                }
            }
        };

        pub fn init(gpa: Allocator, impl: Impl) !*Iterator {
            const res = try gpa.create(Iterator);
            res.* = .{ ._impl = impl, .len = impl.len() };
            return res;
        }

        pub fn deinit(iter: *const Iterator, gpa: Allocator) void {
            gpa.destroy(iter);
        }

        pub fn next(iter: *Iterator, gpa: Allocator) !bool {
            switch (iter._impl) {
                inline else => |*v| {
                    const item = try v.next(gpa);
                    iter.it = try ExampleValue.from(gpa, item orelse return false);
                    iter.idx += 1;
                    iter.first = iter.idx == 1;
                    iter.last = iter.idx == iter.len;
                    return true;
                },
            }
        }

        pub fn fromArray(gpa: Allocator, arr: Array) !*Iterator {
            return init(gpa, .{
                .value_it = .{ .items = arr._items },
            });
        }

        pub const dot = scripty.defaultDot(Iterator, ExampleValue, false);
        pub const Builtins = struct {
            pub const up = struct {
                pub fn call(
                    it: *Iterator,
                    _: Allocator,
                    _: *const ExampleContext,
                    args: []const ExampleValue,
                ) !ExampleValue {
                    const bad_arg: ExampleValue = .{ .err = "expected 0 arguments" };
                    if (args.len != 0) return bad_arg;
                    return it._superhtml_context.up();
                }
            };
        };

        fn SliceIterator(comptime Element: type) type {
            return struct {
                idx: usize = 0,
                items: []const Element,

                pub fn len(self: @This()) usize {
                    return self.items.len;
                }

                pub fn next(self: *@This(), gpa: Allocator) !?Element {
                    _ = gpa;
                    if (self.idx == self.items.len) return null;
                    defer self.idx += 1;
                    return self.items[self.idx];
                }
            };
        }
    };

    pub const Array = struct {
        len: usize,
        empty: bool,
        _items: []const ExampleValue,

        pub const dot = scripty.defaultDot(Array, ExampleValue, false);
        pub const Builtins = struct {
            pub const at = struct {
                pub fn call(
                    arr: Array,
                    _: Allocator,
                    _: *const ExampleContext,
                    args: []const ExampleValue,
                ) !ExampleValue {
                    const bad_arg: ExampleValue = .{ .err = "expected 1 integer argument" };
                    if (args.len != 1) return bad_arg;

                    const idx = switch (args[0]) {
                        .int => |i| i.value,
                        else => return bad_arg,
                    };

                    if (idx < 0) return .{ .err = "index value is negative" };
                    if (idx >= arr.len) return .{ .err = "index value exceeds array length" };

                    return arr._items[@intCast(idx)];
                }
            };
        };
    };
};
