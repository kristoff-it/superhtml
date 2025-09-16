const std = @import("std");
const Completion = @import("Ast.zig").Completion;
const Registry = @import("language_tag/parse.zig").Registry;
const registry: Registry = @import("language-tag-registry");

pub const Rejection = struct {
    reason: []const u8,
    offset: u32,
    length: u32,

    pub fn init(bytes: []const u8, subtag: []const u8, reason: []const u8) Rejection {
        return .{
            .reason = reason,
            .offset = @intCast(@intFromPtr(subtag.ptr) - @intFromPtr(bytes.ptr)),
            .length = @intCast(subtag.len),
        };
    }
};

pub fn validate(bytes: []const u8) ?Rejection {
    if (maps.grandfathered.get(bytes)) |data| {
        if (!data.is_deprecated) return null;
    }

    const ParseState = enum {
        language,
        extlang,
        script,
        region,
        variant,
        singleton,
        extension,
        extension_extra,
        privateuse,
        privateuse_extra,
    };
    var parse_state: ParseState = .language;

    var subtags = std.mem.splitScalar(u8, bytes, '-');
    while (subtags.next()) |subtag| state: switch (parse_state) {
        .language => switch (subtag.len) {
            0 => return .init(bytes, subtag, "cannot be empty"),
            1 => return .init(bytes, subtag, "too short"),
            2...8 => {
                if (maps.language.get(subtag)) |data| {
                    if (data.is_deprecated) return .init(bytes, subtag, "deprecated language");
                } else {
                    return .init(bytes, subtag, "unknown language");
                }
                parse_state = .extlang;
            },
            else => return .init(bytes, subtag, "too long"),
        },
        .extlang => switch (subtag.len) {
            3 => {
                if (std.ascii.isDigit(subtag[0])) continue :state .region;
                if (maps.extlang.get(subtag)) |data| {
                    if (data.is_deprecated) return .init(bytes, subtag, "deprecated language extension");
                    for (data.prefixes) |prefix| {
                        if (std.ascii.startsWithIgnoreCase(bytes, prefix)) break;
                    } else {
                        return .init(bytes, subtag, "incompatible language extension");
                    }
                } else {
                    return .init(bytes, subtag, "unknown language extension");
                }
                parse_state = .script;
            },
            else => continue :state .script,
        },
        .script => switch (subtag.len) {
            4 => {
                if (std.ascii.isDigit(subtag[0])) continue :state .variant;
                if (!maps.script.has(subtag)) {
                    return .init(bytes, subtag, "unknown language script");
                }
                parse_state = .region;
            },
            else => continue :state .region,
        },
        .region => switch (subtag.len) {
            2...3 => {
                if (maps.region.get(subtag)) |data| {
                    if (data.is_deprecated) return .init(bytes, subtag, "deprecated language region");
                } else {
                    return .init(bytes, subtag, "unknown language region");
                }
                parse_state = .variant;
            },
            else => continue :state .variant,
        },
        .variant => switch (subtag.len) {
            4...8 => {
                if (maps.variant.get(subtag)) |data| {
                    if (data.is_deprecated) return .init(bytes, subtag, "deprecated language variant");
                    for (data.prefixes) |prefix| {
                        if (std.ascii.startsWithIgnoreCase(bytes, prefix)) break;
                    } else {
                        return .init(bytes, subtag, "incompatible language variant");
                    }
                } else {
                    return .init(bytes, subtag, "unknown language variant");
                }
                parse_state = .variant;
            },
            else => continue :state .singleton,
        },
        .singleton => {
            if (subtag.len != 1) {
                return .init(bytes, subtag, "extension prefix must be a single character");
            }
            parse_state = switch (std.ascii.toLower(subtag[0])) {
                'x' => .privateuse,
                'a'...'w', 'y'...'z', '0'...'9' => .extension,
                else => return .init(bytes, subtag, "extension prefix must be alphanumeric"),
            };
        },
        .extension => switch (subtag.len) {
            2...8 => {
                for (subtag) |char| if (!std.ascii.isAlphanumeric(char)) {
                    return .init(bytes, subtag, "extension must be alphanumeric");
                };
                parse_state = .extension_extra;
            },
            else => return .init(bytes, subtag, "wrong extension length"),
        },
        .extension_extra => switch (subtag.len) {
            2...8 => continue :state .extension,
            else => continue :state .singleton,
        },
        .privateuse => switch (subtag.len) {
            1...8 => {
                for (subtag) |char| if (!std.ascii.isAlphanumeric(char)) {
                    return .init(bytes, subtag, "private use extension must be alphanumeric");
                };
                parse_state = .privateuse_extra;
            },
            else => return .init(bytes, subtag, "wrong private use extension length"),
        },
        .privateuse_extra => switch (subtag.len) {
            1...8 => continue :state .privateuse,
            else => return .init(bytes, subtag, "subtag after private use extension"),
        },
    };
    return null;
}

pub fn completions(value: []const u8) []const Completion {
    if (value.len == 0) {
        return &language_completions;
    }

    if (std.mem.endsWith(u8, value, "-")) {
        return &region_completions;
    }

    return &.{};
}

const Map = std.StaticStringMapWithEql(Registry.Subtag.Data, std.ascii.eqlIgnoreCase);

const maps = struct {
    pub const language = makeMap("language");
    pub const extlang = makeMap("extlang");
    pub const script = makeMap("script");
    pub const region = makeMap("region");
    pub const variant = makeMap("variant");
    pub const grandfathered = makeMap("grandfathered");
};

fn makeMap(comptime kind: []const u8) Map {
    const KV = struct { []const u8, Registry.Subtag.Data };
    const subtags = @field(registry, kind);
    @setEvalBranchQuota(subtags.len * 2);
    var kvs: [subtags.len]KV = undefined;
    for (subtags, &kvs) |subtag, *kv| {
        kv.* = .{ subtag.name, subtag.data };
    }
    return .initComptime(kvs);
}

const language_completions = makeCompletions("language");
const region_completions = makeCompletions("region");

fn makeCompletions(comptime kind: []const u8) [@field(registry, kind).len]Completion {
    const subtags = @field(registry, kind);
    @setEvalBranchQuota(subtags.len * 2);
    var comps: [subtags.len]Completion = undefined;
    for (subtags, &comps) |subtag, *comp| {
        comp.* = .{
            .label = subtag.name,
            .desc = subtag.data.description orelse subtag.name,
        };
    }
    return comps;
}

test "validate: all subtags" {
    const value = "sgn-ase-Latn-US-blasl-a-abcd-x-1234";
    try std.testing.expectEqual(null, validate(value));
}

test "validate: deprecated language" {
    const value = "in";
    try std.testing.expect(validate(value) != null);
}

test "validate: multiple prefixes" {
    const valid_1 = "sgn-ase-blasl";
    const valid_2 = "ase-blasl";
    try std.testing.expectEqual(null, validate(valid_1));
    try std.testing.expectEqual(null, validate(valid_2));

    const invalid = "it-blasl";
    try std.testing.expect(validate(invalid) != null);
}
