const std = @import("std");
const Completion = @import("../html/Ast.zig").Completion;
const Registry = @import("language_tag/parse.zig").Registry;
const registry: Registry = @import("language-tag-registry");

const Map = std.StaticStringMapWithEql(Registry.Subtag.Data, std.ascii.eqlIgnoreCase);

pub const maps = struct {
    pub const language = makeMap("language");
    pub const extlang = makeMap("extlang");
    pub const script = makeMap("script");
    pub const region = makeMap("region");
    pub const variant = makeMap("variant");
    pub const grandfathered = makeMap("grandfathered");
};

pub const completions = struct {
    pub const language = makeCompletion("language");
    pub const region = makeCompletion("region");
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

fn makeCompletion(comptime kind: []const u8) [@field(registry, kind).len]Completion {
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
