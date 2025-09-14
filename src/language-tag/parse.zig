const std = @import("std");
const source = @embedFile("registry.txt");

pub const Registry = struct {
    languages: []const Language,
    extlangs: []const Extlang,
    scripts: []const Script,
    regions: []const Region,
    variants: []const Variant,
    grandfathereds: []const Grandfathered,
};

const Language = struct {
    subtag: []const u8 = "",
    description: []const u8 = "",
    is_deprecated: bool = false,
    preferred: ?[]const u8 = null,
};

const Extlang = struct {
    subtag: []const u8 = "",
    description: []const u8 = "",
    prefix: []const u8 = "",
    is_deprecated: bool = false,
    preferred: ?[]const u8 = null,
};

const Script = struct {
    subtag: []const u8 = "",
    description: []const u8 = "",
};

const Region = struct {
    subtag: []const u8 = "",
    description: []const u8 = "",
    is_deprecated: bool = false,
    preferred: ?[]const u8 = null,
};

const Variant = struct {
    subtag: []const u8 = "",
    description: []const u8 = "",
    prefix: []const u8 = "",
    is_deprecated: bool = false,
    preferred: ?[]const u8 = null,
};

const Grandfathered = struct {
    tag: []const u8 = "",
    description: []const u8 = "",
    is_deprecated: bool = false,
    preferred: ?[]const u8 = null,
};

var languages: std.ArrayList(Language) = .empty;
var extlangs: std.ArrayList(Extlang) = .empty;
var scripts: std.ArrayList(Script) = .empty;
var regions: std.ArrayList(Region) = .empty;
var variants: std.ArrayList(Variant) = .empty;
var grandfathereds: std.ArrayList(Grandfathered) = .empty;

pub fn main() !void {
    var arena_instance: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    const arena = arena_instance.allocator();
    defer arena_instance.deinit();

    var lines = std.mem.splitScalar(u8, source, '\n');
    _ = lines.next(); // skip file date
    _ = lines.next(); // skip first divider

    while (lines.next()) |line| {
        var chunks = std.mem.splitSequence(u8, line, ": ");
        const key = chunks.first();
        const value = chunks.rest();
        std.debug.assert(std.mem.eql(u8, key, "Type"));

        if (std.mem.eql(u8, value, "language")) {
            const language = try parseLanguage(arena, &lines);
            // length is greater in the case of the private-use exception
            if (language.subtag.len == 2 or language.subtag.len == 3) {
                try languages.append(arena, language);
            }
        } else if (std.mem.eql(u8, value, "extlang")) {
            const extlang = try parseExtlang(arena, &lines);
            try extlangs.append(arena, extlang);
        } else if (std.mem.eql(u8, value, "script")) {
            const script = try parseScript(arena, &lines);
            try scripts.append(arena, script);
        } else if (std.mem.eql(u8, value, "region")) {
            const region = try parseRegion(arena, &lines);
            try regions.append(arena, region);
        } else if (std.mem.eql(u8, value, "variant")) {
            const variant = try parseVariant(arena, &lines);
            try variants.append(arena, variant);
        } else if (std.mem.eql(u8, value, "grandfathered")) {
            const grandfathered = try parseGrandfathered(arena, &lines);
            try grandfathereds.append(arena, grandfathered);
        } else if (std.mem.eql(u8, value, "redundant")) {
            skipBlock(&lines);
        } else {
            @panic("unknown subtag type");
        }
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
        .languages = languages.items,
        .extlangs = extlangs.items,
        .scripts = scripts.items,
        .regions = regions.items,
        .variants = variants.items,
        .grandfathereds = grandfathereds.items,
    };
    try std.zon.stringify.serialize(registry, .{}, output);
    try output.flush();
}

fn parseLanguage(arena: std.mem.Allocator, lines: *std.mem.SplitIterator(u8, .scalar)) !Language {
    var language: Language = .{};
    while (lines.next()) |line| {
        if (std.mem.eql(u8, line, "%%")) break;

        var chunks = std.mem.splitSequence(u8, line, ": ");
        const key = chunks.first();
        const value = chunks.rest();

        if (std.mem.eql(u8, key, "Subtag")) {
            language.subtag = value;
        } else if (std.mem.eql(u8, key, "Description")) {
            language.description = try parseMultiline(arena, value, lines);
        } else if (std.mem.eql(u8, key, "Deprecated")) {
            language.is_deprecated = true;
        } else if (std.mem.eql(u8, key, "Preferred-Value")) {
            language.preferred = value;
        } else if (std.mem.eql(u8, key, "Comments")) {
            _ = try parseMultiline(arena, value, lines);
        } else if (std.mem.eql(u8, key, "Added")) {
            // skip
        } else if (std.mem.eql(u8, key, "Scope")) {
            // skip
        } else if (std.mem.eql(u8, key, "Macrolanguage")) {
            // skip
        } else if (std.mem.eql(u8, key, "Suppress-Script")) {
            // skip
        } else {
            @panic("unknown language property");
        }
    }
    return language;
}

fn parseExtlang(arena: std.mem.Allocator, lines: *std.mem.SplitIterator(u8, .scalar)) !Extlang {
    var extlang: Extlang = .{};
    while (lines.next()) |line| {
        if (std.mem.eql(u8, line, "%%")) break;

        var chunks = std.mem.splitSequence(u8, line, ": ");
        const key = chunks.first();
        const value = chunks.rest();

        if (std.mem.eql(u8, key, "Subtag")) {
            extlang.subtag = value;
        } else if (std.mem.eql(u8, key, "Description")) {
            extlang.description = try parseMultiline(arena, value, lines);
        } else if (std.mem.eql(u8, key, "Prefix")) {
            extlang.prefix = value;
        } else if (std.mem.eql(u8, key, "Deprecated")) {
            extlang.is_deprecated = true;
        } else if (std.mem.eql(u8, key, "Preferred-Value")) {
            extlang.preferred = value;
        } else if (std.mem.eql(u8, key, "Added")) {
            // skip
        } else if (std.mem.eql(u8, key, "Macrolanguage")) {
            // skip
        } else {
            @panic("unknown extlang property");
        }
    }
    return extlang;
}

fn parseScript(arena: std.mem.Allocator, lines: *std.mem.SplitIterator(u8, .scalar)) !Script {
    var script: Script = .{};
    while (lines.next()) |line| {
        if (std.mem.eql(u8, line, "%%")) break;

        var chunks = std.mem.splitSequence(u8, line, ": ");
        const key = chunks.first();
        const value = chunks.rest();

        if (std.mem.eql(u8, key, "Subtag")) {
            script.subtag = value;
        } else if (std.mem.eql(u8, key, "Description")) {
            script.description = try parseMultiline(arena, value, lines);
        } else if (std.mem.eql(u8, key, "Comments")) {
            _ = try parseMultiline(arena, value, lines);
        } else if (std.mem.eql(u8, key, "Added")) {
            // skip
        } else {
            @panic("unknown extlang property");
        }
    }
    return script;
}

fn parseRegion(arena: std.mem.Allocator, lines: *std.mem.SplitIterator(u8, .scalar)) !Region {
    var region: Region = .{};
    while (lines.next()) |line| {
        if (std.mem.eql(u8, line, "%%")) break;

        var chunks = std.mem.splitSequence(u8, line, ": ");
        const key = chunks.first();
        const value = chunks.rest();

        if (std.mem.eql(u8, key, "Subtag")) {
            region.subtag = value;
        } else if (std.mem.eql(u8, key, "Description")) {
            region.description = try parseMultiline(arena, value, lines);
        } else if (std.mem.eql(u8, key, "Deprecated")) {
            region.is_deprecated = true;
        } else if (std.mem.eql(u8, key, "Preferred-Value")) {
            region.preferred = value;
        } else if (std.mem.eql(u8, key, "Comments")) {
            _ = try parseMultiline(arena, value, lines);
        } else if (std.mem.eql(u8, key, "Added")) {
            // skip
        } else {
            @panic("unknown region property");
        }
    }
    return region;
}

fn parseVariant(arena: std.mem.Allocator, lines: *std.mem.SplitIterator(u8, .scalar)) !Variant {
    var variant: Variant = .{};
    while (lines.next()) |line| {
        if (std.mem.eql(u8, line, "%%")) break;

        var chunks = std.mem.splitSequence(u8, line, ": ");
        const key = chunks.first();
        const value = chunks.rest();

        if (std.mem.eql(u8, key, "Subtag")) {
            variant.subtag = value;
        } else if (std.mem.eql(u8, key, "Description")) {
            variant.description = try parseMultiline(arena, value, lines);
        } else if (std.mem.eql(u8, key, "Prefix")) {
            variant.prefix = value;
        } else if (std.mem.eql(u8, key, "Deprecated")) {
            variant.is_deprecated = true;
        } else if (std.mem.eql(u8, key, "Preferred-Value")) {
            variant.preferred = value;
        } else if (std.mem.eql(u8, key, "Comments")) {
            _ = try parseMultiline(arena, value, lines);
        } else if (std.mem.eql(u8, key, "Added")) {
            // skip
        } else {
            @panic("unknown variant property");
        }
    }
    return variant;
}

fn parseGrandfathered(arena: std.mem.Allocator, lines: *std.mem.SplitIterator(u8, .scalar)) !Grandfathered {
    var grandfathered: Grandfathered = .{};
    while (lines.next()) |line| {
        if (std.mem.eql(u8, line, "%%")) break;

        var chunks = std.mem.splitSequence(u8, line, ": ");
        const key = chunks.first();
        const value = chunks.rest();

        if (std.mem.eql(u8, key, "Tag")) {
            grandfathered.tag = value;
        } else if (std.mem.eql(u8, key, "Description")) {
            grandfathered.description = try parseMultiline(arena, value, lines);
        } else if (std.mem.eql(u8, key, "Deprecated")) {
            grandfathered.is_deprecated = true;
        } else if (std.mem.eql(u8, key, "Preferred-Value")) {
            grandfathered.preferred = value;
        } else if (std.mem.eql(u8, key, "Comments")) {
            _ = try parseMultiline(arena, value, lines);
        } else if (std.mem.eql(u8, key, "Added")) {
            // skip
        } else {
            @panic("unknown grandfathered property");
        }
    }
    return grandfathered;
}

fn parseMultiline(arena: std.mem.Allocator, first: []const u8, lines: *std.mem.SplitIterator(u8, .scalar)) ![]const u8 {
    var bytes: std.ArrayList(u8) = .empty;
    try bytes.appendSlice(arena, first);
    while (lines.peek()) |line| {
        if (!std.mem.startsWith(u8, line, "  ")) break;
        // keep one of the two spances to join the lines
        try bytes.appendSlice(arena, line[1..]);
        _ = lines.next();
    }
    return bytes.items;
}

fn skipBlock(lines: *std.mem.SplitIterator(u8, .scalar)) void {
    while (lines.next()) |line| {
        if (std.mem.eql(u8, line, "%%")) break;
    }
}
