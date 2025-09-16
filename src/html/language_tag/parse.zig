const std = @import("std");
const source = @embedFile("registry.txt");

pub const Registry = struct {
    language: []const Subtag,
    extlang: []const Subtag,
    script: []const Subtag,
    region: []const Subtag,
    variant: []const Subtag,
    grandfathered: []const Subtag,
    redundant: []const Subtag,

    pub const Subtag = struct {
        name: []const u8,
        data: Data,

        pub const Data = struct {
            description: ?[]const u8 = null,
            prefixes: []const []const u8,
            is_deprecated: bool = false,
        };
    };
};

const Parser = struct {
    lines: std.mem.SplitIterator(u8, .scalar),

    pub fn init(bytes: []const u8) Parser {
        var lines = std.mem.splitScalar(u8, bytes, '\n');
        _ = lines.next(); // skip file date
        _ = lines.next(); // skip first divider
        return .{ .lines = lines };
    }

    pub const Result = struct {
        kind: Kind,
        subtag: Registry.Subtag,

        pub const Kind = enum {
            language,
            extlang,
            script,
            region,
            variant,
            grandfathered,
            redundant,
        };
    };

    pub inline fn next(parser: *Parser, arena: std.mem.Allocator) !?Result {
        var kind: ?Result.Kind = null;
        var name: ?[]const u8 = null;
        var description: ?[]const u8 = null;
        var prefixes: std.ArrayList([]const u8) = .empty;
        var is_deprecated: bool = false;

        while (parser.lines.next()) |line| {
            if (line.len == 0 or std.mem.eql(u8, line, "%%")) {
                return .{
                    .kind = kind.?,
                    .subtag = .{
                        .name = name.?,
                        .data = .{
                            .description = description,
                            .prefixes = prefixes.items,
                            .is_deprecated = is_deprecated,
                        },
                    },
                };
            }

            var chunks = std.mem.splitSequence(u8, line, ": ");
            const key = chunks.first();
            const value = chunks.rest();

            if (std.mem.eql(u8, key, "Type")) {
                kind = std.meta.stringToEnum(Result.Kind, value) orelse {
                    @panic("unknown subtag type");
                };
            } else if (std.mem.eql(u8, key, "Subtag") or std.mem.eql(u8, key, "Tag")) {
                name = value;
            } else if (std.mem.eql(u8, key, "Description")) {
                var buffer: std.ArrayList(u8) = .empty;
                try buffer.appendSlice(arena, value);
                while (parser.lines.peek()) |subline| {
                    if (!std.mem.startsWith(u8, subline, "  ")) break;
                    // keep one of the two spances to join the lines
                    try buffer.appendSlice(arena, subline[1..]);
                    _ = parser.lines.next();
                }
                description = buffer.items;
            } else if (std.mem.eql(u8, key, "Prefix")) {
                try prefixes.append(arena, value);
            } else if (std.mem.eql(u8, key, "Deprecated")) {
                is_deprecated = true;
            } else if (std.mem.eql(u8, key, "Comments")) {
                while (parser.lines.peek()) |subline| {
                    if (!std.mem.startsWith(u8, subline, "  ")) break;
                    _ = parser.lines.next();
                }
            } else if (std.mem.eql(u8, key, "Preferred-Value")) {
                // skip
            } else if (std.mem.eql(u8, key, "Added")) {
                // skip
            } else if (std.mem.eql(u8, key, "Scope")) {
                // skip
            } else if (std.mem.eql(u8, key, "Macrolanguage")) {
                // skip
            } else if (std.mem.eql(u8, key, "Suppress-Script")) {
                // skip
            } else {
                @panic("unknown subtag property");
            }
        }

        return null;
    }
};

pub fn main() !void {
    var arena_instance: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    const arena = arena_instance.allocator();
    defer arena_instance.deinit();

    var language: std.ArrayList(Registry.Subtag) = .empty;
    var extlang: std.ArrayList(Registry.Subtag) = .empty;
    var script: std.ArrayList(Registry.Subtag) = .empty;
    var region: std.ArrayList(Registry.Subtag) = .empty;
    var variant: std.ArrayList(Registry.Subtag) = .empty;
    var grandfathered: std.ArrayList(Registry.Subtag) = .empty;
    var redundant: std.ArrayList(Registry.Subtag) = .empty;

    var parser: Parser = .init(source);
    while (try parser.next(arena)) |result| {
        const list = switch (result.kind) {
            .language => &language,
            .extlang => &extlang,
            .script => &script,
            .region => &region,
            .variant => &variant,
            .grandfathered => &grandfathered,
            .redundant => &redundant,
        };
        try list.append(arena, result.subtag);
    }

    var args = try std.process.argsWithAllocator(arena);
    std.debug.assert(args.skip());

    const file = file: {
        const output_path = args.next() orelse break :file std.fs.File.stdout();
        break :file try std.fs.cwd().createFile(output_path, .{});
    };
    var buffer: [1024]u8 = undefined;
    var writer = file.writer(&buffer);
    const output = &writer.interface;

    const registry: Registry = .{
        .language = language.items,
        .extlang = extlang.items,
        .script = script.items,
        .region = region.items,
        .variant = variant.items,
        .grandfathered = grandfathered.items,
        .redundant = redundant.items,
    };
    try std.zon.stringify.serialize(registry, .{}, output);
    try output.flush();
}
