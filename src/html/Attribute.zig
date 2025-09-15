const Attribute = @This();

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Ast = @import("Ast.zig");
const Tokenizer = @import("Tokenizer.zig");
const root = @import("../root.zig");
const Language = root.Language;
const Span = root.Span;
const log = std.log.scoped(.attribute);
const language_tag = @import("language_tag.zig");

rule: Rule,
desc: []const u8,
// required: bool = false,
// only_under: []const Ast.Kind = &.{},

pub const StringIgnoreCaseContext = struct {
    pub fn hash(self: @This(), s: []const u8) u64 {
        _ = self;
        var h = std.hash.Wyhash.init(0);
        for (s) |byte| h.update((&std.ascii.toLower(byte))[0..1]);
        return h.final();
    }

    pub fn eql(self: @This(), a: []const u8, b: []const u8) bool {
        _ = self;
        return std.ascii.eqlIgnoreCase(a, b);
    }
};

pub const VoidSet = std.HashMapUnmanaged(
    []const u8,
    void,
    StringIgnoreCaseContext,
    std.hash_map.default_max_load_percentage,
);

pub const Set = std.StaticStringMapWithEql(
    u32,
    std.static_string_map.eqlAsciiIgnoreCase,
);

pub const Map = std.StaticStringMapWithEql(
    u32,
    std.static_string_map.eqlAsciiIgnoreCase,
);

pub const Rule = union(enum) {
    /// This rule is checked manually in code that builds the tree or that performs
    /// element validation. It's an error for such attribute to end up being
    /// validated through normal means.
    manual,

    /// Presence of the attribute indicates true value, absence indicates
    /// false value, so no actual explicit value is allowed.
    bool,

    /// All values are fine, including no value at all
    any,

    /// All non-empty values, ignoring whitespace
    not_empty,

    /// Used by fields that accept an ID, cannot be empty or contain whitespace
    id,

    /// Class
    class,

    /// CORS
    cors,

    /// MIME
    mime,

    /// BCP 47 language tag
    lang,

    /// Not negative integer
    non_neg_int: struct {
        min: usize = 0,
        max: usize = std.math.maxInt(usize),
    },

    /// E.g. "#foo"
    hash_name_ref,

    /// An entry in a static list of options
    list: List,

    /// A valid url. Value decides if emtpy string is allowed or not.
    url: enum { empty, not_empty },

    /// Custom validation
    custom: *const fn (
        gpa: Allocator,
        errors: *std.ArrayListUnmanaged(Ast.Error),
        src: []const u8,
        node_idx: u32,
        attr: Tokenizer.Attr,
    ) error{OutOfMemory}!void,

    pub const ValueRejection = struct {
        reason: []const u8 = "",
        offset: ?u32 = null,
    };

    pub const List = struct {
        /// Used for searching
        set: Set,
        completions: []const Ast.Completion,
        extra: Extra,
        count: Count = .one,

        pub const Count = enum { one, many, many_unique, many_unique_comma };
        pub const Extra = union(enum) {
            manual,
            none,
            not_empty,
            missing,
            missing_or_empty,
            custom: *const fn (value: []const u8) ?ValueRejection,
        };

        pub inline fn comptimeIndex(list: *const List, comptime name: []const u8) usize {
            return comptime list.set.getIndex(name) orelse @compileError(
                "unable to find '" ++ name ++ "'",
            );
        }

        pub inline fn init(extra: Extra, count: Count, cpls: []const Ast.Completion) @This() {
            assert(cpls.len > 0);
            return .{
                .count = count,
                .extra = extra,
                .set = blk: {
                    @setEvalBranchQuota(4000);
                    var kvs: []const struct { []const u8, u32 } = &.{};
                    for (cpls, 0..) |c, idx| {
                        if (c.value != null) continue;
                        kvs = kvs ++ .{
                            .{ c.label, @as(u32, @intCast(idx)) },
                        };
                    }
                    break :blk .initComptime(kvs);
                },
                .completions = cpls,
            };
        }

        pub const Match = union(enum) {
            none,
            empty,
            list: u32,
            custom,
        };
        pub fn match(
            list: List,
            gpa: Allocator,
            errors: *std.ArrayList(Ast.Error),
            node_idx: u32,
            offset: u32,
            item: []const u8,
        ) !Match {
            assert(list.extra != .manual);

            if (list.set.getIndex(item)) |idx| {
                return .{ .list = @intCast(idx) };
            }

            switch (list.extra) {
                .missing, .manual => unreachable,
                .none => {},
                .not_empty => if (item.len > 0) return .custom,
                .missing_or_empty => return if (item.len > 0) .custom else .empty,
                .custom => {
                    if (list.extra.custom(item)) |rejection| {
                        try errors.append(gpa, .{
                            .tag = .{
                                .invalid_attr_value = .{
                                    .reason = rejection.reason,
                                },
                            },
                            .main_location = if (rejection.offset) |o| .{
                                .start = offset + o,
                                .end = offset + o + 1,
                            } else .{
                                .start = offset,
                                .end = @intCast(offset + item.len),
                            },
                            .node_idx = node_idx,
                        });
                        return .none;
                    }
                    return .custom;
                },
            }

            try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{},
                },
                .main_location = .{
                    .start = offset,
                    .end = @intCast(offset + item.len),
                },
                .node_idx = node_idx,
            });

            return .none;
        }
    };

    const cors_list: List = .init(.missing_or_empty, .one, &.{
        .{
            .label = "anonymous",
            .desc =
            \\Sends a cross-origin request without a credential. In other
            \\words, it sends the `Origin:` HTTP header without a cookie,
            \\X.509 certificate, or performing HTTP Basic authentication.
            \\If the server does not give credentials to the origin
            \\site (by not setting the `Access-Control-Allow-Origin:`
            \\HTTP header), the resource will be tainted, and its usage
            \\restricted.
            ,
        },
        .{
            .label = "use-credentials",
            .desc =
            \\Sends a cross-origin request with a credential. In other
            \\words, it sends the `Origin:` HTTP header with a cookie, a
            \\certificate, or performing HTTP Basic authentication. If the
            \\server does not give credentials to the origin site (through
            \\`Access-Control-Allow-Credentials:` HTTP header), the resource
            \\will be tainted and its usage restricted.
            ,
        },
    });

    pub fn validate(
        rule: Rule,
        gpa: Allocator,
        errors: *std.ArrayListUnmanaged(Ast.Error),
        src: []const u8,
        node_idx: u32,
        attr: Tokenizer.Attr,
    ) !void {
        rule: switch (rule) {
            .manual => unreachable,
            .any => {},
            .bool => {
                if (attr.value) |value| {
                    try errors.append(gpa, .{
                        .tag = .boolean_attr,
                        .main_location = value.span,
                        .node_idx = node_idx,
                    });
                }
            },
            .mime => return validateMime(gpa, errors, src, node_idx, attr),
            .cors => continue :rule .{ .list = cors_list },
            .lang => {
                const value = attr.value orelse return;
                const value_slice = value.span.slice(src);
                if (validateLanguageTag(value_slice)) |rejection| return errors.append(gpa, .{
                    .tag = .{
                        .invalid_attr_value = .{ .reason = rejection.reason },
                    },
                    .main_location = .{
                        .start = value.span.start + rejection.offset,
                        .end = value.span.start + rejection.offset + rejection.length,
                    },
                    .node_idx = node_idx,
                });
            },
            .not_empty => {
                const value = attr.value orelse return errors.append(gpa, .{
                    .tag = .missing_attr_value,
                    .main_location = attr.name,
                    .node_idx = node_idx,
                });
                const value_slice = value.span.slice(src);
                const content = std.mem.trim(u8, value_slice, &std.ascii.whitespace);
                if (content.len == 0) return errors.append(gpa, .{
                    .tag = .missing_attr_value,
                    .main_location = attr.name,
                    .node_idx = node_idx,
                });
            },
            .id => {
                const value = attr.value orelse return errors.append(gpa, .{
                    .tag = .missing_attr_value,
                    .main_location = attr.name,
                    .node_idx = node_idx,
                });

                const value_slice = value.span.slice(src);
                if (value_slice.len == 0) return errors.append(gpa, .{
                    .tag = .missing_attr_value,
                    .main_location = attr.name,
                    .node_idx = node_idx,
                });

                if (std.mem.indexOfAny(u8, value_slice, &std.ascii.whitespace)) |pos| {
                    return errors.append(gpa, .{
                        .tag = .{
                            .invalid_attr_value = .{
                                .reason = "whitespace not allowed",
                            },
                        },
                        .main_location = .{
                            .start = @intCast(value.span.start + pos),
                            .end = @intCast(value.span.start + pos + 1),
                        },
                        .node_idx = node_idx,
                    });
                }
            },
            .class => {
                const value = attr.value orelse return;
                const value_slice = value.span.slice(src);
                var it = std.mem.tokenizeAny(u8, value_slice, &std.ascii.whitespace);

                var seen_classes: std.StringHashMapUnmanaged(Span) = .empty;
                defer seen_classes.deinit(gpa);

                while (it.next()) |c| {
                    const span: Span = .{
                        .start = @intCast(value.span.start + it.index - c.len),
                        .end = @intCast(value.span.start + it.index),
                    };
                    const gop = try seen_classes.getOrPut(gpa, c);
                    if (gop.found_existing) {
                        try errors.append(gpa, .{
                            .tag = .{ .duplicate_class = gop.value_ptr.* },
                            .main_location = span,
                            .node_idx = node_idx,
                        });
                    } else gop.value_ptr.* = span;
                }
            },
            // .number => {
            //     const value = attr.value orelse return errors.append(gpa, .{
            //         .tag = .missing_attr_value,
            //         .main_location = attr.name,
            //         .node_idx = node_idx,
            //     });
            //     const value_slice = value.span.slice(src);
            //     const digits = std.mem.trim(u8, value_slice, &std.ascii.whitespace);
            //     if (digits.len == 0) return errors.append(gpa, .{
            //         .tag = .missing_attr_value,
            //         .main_location = attr.name,
            //         .node_idx = node_idx,
            //     });
            //     _ = std.fmt.parseInt(i64, digits, 10) catch {
            //         _ = std.fmt.parseFloat(f32, digits) catch return errors.append(gpa, .{
            //             .tag = .{
            //                 .invalid_attr_value = .{
            //                     .reason = "not a valid number",
            //                 },
            //             },
            //             .main_location = value.span,
            //             .node_idx = node_idx,
            //         });
            //     };
            // },
            .non_neg_int => |limits| {
                const value = attr.value orelse return errors.append(gpa, .{
                    .tag = .missing_attr_value,
                    .main_location = attr.name,
                    .node_idx = node_idx,
                });

                const value_slice = value.span.slice(src);
                const digits = std.mem.trim(u8, value_slice, &std.ascii.whitespace);
                if (std.fmt.parseInt(i64, digits, 10)) |num| {
                    if (num < limits.min or num > limits.max) return errors.append(gpa, .{
                        .tag = .{
                            .int_out_of_bounds = .{
                                .min = limits.min,
                                .max = limits.max,
                            },
                        },
                        .main_location = value.span,
                        .node_idx = node_idx,
                    });
                } else |_| return errors.append(gpa, .{
                    .tag = .{
                        .invalid_attr_value = .{
                            .reason = "invalid non-negative integer",
                        },
                    },
                    .main_location = value.span,
                    .node_idx = node_idx,
                });
            },
            .hash_name_ref => {
                const value = attr.value orelse return errors.append(gpa, .{
                    .tag = .missing_attr_value,
                    .main_location = attr.name,
                    .node_idx = node_idx,
                });
                const slice = value.span.slice(src);
                if (slice.len < 2 or slice[0] != '#') return errors.append(gpa, .{
                    .tag = .{
                        .invalid_attr_value = .{
                            .reason = "invalid hash name reference",
                        },
                    },
                    .main_location = value.span,
                    .node_idx = node_idx,
                });
            },
            .list => |list| {
                const value = attr.value orelse {
                    return switch (list.extra) {
                        .missing,
                        .missing_or_empty,
                        => {},
                        else => errors.append(gpa, .{
                            .tag = .missing_attr_value,
                            .main_location = attr.name,
                            .node_idx = node_idx,
                        }),
                    };
                };

                var seen_items: VoidSet = .{};
                defer seen_items.deinit(gpa);

                const value_slice = value.span.slice(src);
                switch (list.count) {
                    .one => {
                        _ = try list.match(
                            gpa,
                            errors,
                            node_idx,
                            value.span.start,
                            value_slice,
                        );
                        return;
                    },
                    .many, .many_unique => {
                        // TODO make this static

                        var it = std.mem.tokenizeAny(u8, value_slice, &std.ascii.whitespace);
                        while (it.next()) |item| {
                            if (try list.match(
                                gpa,
                                errors,
                                node_idx,
                                @intCast(value.span.start + it.index - item.len),
                                item,
                            ) == .none) continue;

                            if (list.count == .many) continue;

                            const gop = try seen_items.getOrPut(gpa, item);
                            if (gop.found_existing) try errors.append(gpa, .{
                                .tag = .{
                                    .invalid_attr_value = .{
                                        .reason = "duplicate entry",
                                    },
                                },
                                .main_location = .{
                                    .start = @intCast(value.span.start + it.index - item.len),
                                    .end = @intCast(value.span.start + it.index),
                                },
                                .node_idx = node_idx,
                            });
                        }
                    },
                    .many_unique_comma => {
                        var it = std.mem.splitScalar(u8, value_slice, ',');
                        var last_index: u32 = 0;
                        while (it.next()) |item| {
                            defer if (it.index) |i| {
                                last_index = @intCast(i);
                            };

                            if (try list.match(
                                gpa,
                                errors,
                                node_idx,
                                @intCast(value.span.start + last_index),
                                item,
                            ) == .none) continue;
                            const gop = try seen_items.getOrPut(gpa, item);
                            if (gop.found_existing) try errors.append(gpa, .{
                                .tag = .{
                                    .invalid_attr_value = .{
                                        .reason = "duplicate entry",
                                    },
                                },
                                .main_location = .{
                                    .start = value.span.start + last_index,
                                    .end = @intCast(value.span.start + last_index + item.len),
                                },
                                .node_idx = node_idx,
                            });
                        }
                    },
                }
            },
            .url => |empty| {
                const value = attr.value orelse {
                    return errors.append(gpa, .{
                        .tag = .missing_attr_value,
                        .main_location = attr.name,
                        .node_idx = node_idx,
                    });
                };

                const url = std.mem.trim(
                    u8,
                    value.span.slice(src),
                    &std.ascii.whitespace,
                );

                if (url.len == 0) {
                    return switch (empty) {
                        .empty => return,
                        .not_empty => errors.append(gpa, .{
                            .tag = .{
                                .invalid_attr_value = .{
                                    .reason = "cannot be empty",
                                },
                            },
                            .main_location = value.span,
                            .node_idx = node_idx,
                        }),
                    };
                }

                // url.len > 0
                _ = Attribute.parseUri(url) catch {
                    return errors.append(gpa, .{
                        .tag = .{
                            .invalid_attr_value = .{
                                .reason = "invalid URL",
                            },
                        },
                        .main_location = value.span,
                        .node_idx = node_idx,
                    });
                };
            },
            .custom => |custom| try custom(gpa, errors, src, node_idx, attr),
        }
    }
};

pub fn validateMime(
    gpa: Allocator,
    errors: *std.ArrayListUnmanaged(Ast.Error),
    src: []const u8,
    node_idx: u32,
    attr: Tokenizer.Attr,
) !void {
    // https://mimesniff.spec.whatwg.org/#parsing-a-mime-type
    const raw_value = attr.value orelse return errors.append(gpa, .{
        .tag = .missing_attr_value,
        .main_location = attr.name,
        .node_idx = node_idx,
    });

    var seen_params: std.StringHashMapUnmanaged(void) = .empty;
    defer seen_params.deinit(gpa);

    // 1. Remove any leading and trailing HTTP whitespace from input.
    const value, const spaces: u32 = blk: {
        const raw = raw_value.span.slice(src);
        const left = std.mem.trimLeft(u8, raw, &std.ascii.whitespace);
        const left_right = std.mem.trimRight(u8, left, &std.ascii.whitespace);
        break :blk .{ left_right, @intCast(raw.len - left.len) };
    };

    // 2. Let position be a position variable for input, initially pointing at
    // the start of input.
    const slash_idx = blk: {

        // 3. Let type be the result of collecting a sequence of code points that
        // are not U+002F (/) from input, given position.
        // 5. If position is past the end of input, then return failure.
        const slash_idx = std.mem.indexOfScalar(u8, value, '/') orelse {
            return errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "missing '/' in MIME value",
                    },
                },
                .main_location = raw_value.span,
                .node_idx = node_idx,
            });
        };

        const mime_type = value[0..slash_idx];

        // 4. If type is the empty string or does not solely contain HTTP token code
        // points, then return failure.
        if (mime_type.len == 0) return errors.append(gpa, .{
            .tag = .{
                .invalid_attr_value = .{
                    .reason = "emtpy MIME type",
                },
            },
            .main_location = .{
                .start = raw_value.span.start,
                .end = @intCast(raw_value.span.start + spaces + slash_idx),
            },
            .node_idx = node_idx,
        });

        if (validateMimeChars(mime_type)) |rejection| return errors.append(gpa, .{
            .tag = .{
                .invalid_attr_value = .{
                    .reason = rejection.reason,
                },
            },
            .main_location = .{
                .start = raw_value.span.start + spaces + (rejection.offset orelse 0),
                .end = @intCast(raw_value.span.start + spaces + (rejection.offset orelse mime_type.len) + 1),
            },
            .node_idx = node_idx,
        });

        break :blk slash_idx;
    };

    // 6. Advance position by 1. (This skips past U+002F (/).)
    const rest = value[slash_idx + 1 ..];

    // 7. Let subtype be the result of collecting a sequence of code points that
    // are not U+003B (;) from input, given position.
    const semi_idx = std.mem.indexOfScalar(u8, rest, ';') orelse {
        if (std.mem.trim(u8, rest, &std.ascii.whitespace).len != 0) return;
        return errors.append(gpa, .{
            .tag = .{
                .invalid_attr_value = .{
                    .reason = "missing MIME subtype",
                },
            },
            .main_location = .{
                .start = @intCast(raw_value.span.start + slash_idx + 1),
                .end = @intCast(raw_value.span.end),
            },
            .node_idx = node_idx,
        });
    };

    // 8. Remove any trailing HTTP whitespace from subtype.
    const subtype = std.mem.trim(u8, rest[0..semi_idx], &std.ascii.whitespace);

    // 9. If subtype is the empty string or does not solely contain HTTP token code points, then return failure.
    if (subtype.len == 0) return errors.append(gpa, .{
        .tag = .{
            .invalid_attr_value = .{
                .reason = "emtpy MIME subtype",
            },
        },
        .main_location = .{
            .start = @intCast(raw_value.span.start + spaces + slash_idx + 1),
            .end = @intCast(raw_value.span.start + spaces + slash_idx + 1 + semi_idx),
        },
        .node_idx = node_idx,
    });

    if (validateMimeChars(subtype)) |rejection| return errors.append(gpa, .{
        .tag = .{
            .invalid_attr_value = .{
                .reason = rejection.reason,
            },
        },
        .main_location = .{
            .start = @intCast(
                raw_value.span.start + spaces + slash_idx + 1 + (rejection.offset orelse 0),
            ),
            .end = @intCast(
                raw_value.span.start + spaces + slash_idx + 1 + (rejection.offset orelse subtype.len) + 1,
            ),
        },
        .node_idx = node_idx,
    });

    var kvs = rest[semi_idx + 1 ..];

    // 11. While position is not past the end of input:
    var kv_offset: u32 = @intCast(
        raw_value.span.start + spaces + slash_idx + 1 + semi_idx + 1,
    );

    while (true) {
        const sep_idx = std.mem.indexOfAny(u8, kvs, ";=") orelse kvs.len;

        // 2.Collect a sequence of code points that are HTTP whitespace from
        // input given position.
        const param_name = std.mem.trimLeft(u8, kvs[0..sep_idx], &std.ascii.whitespace);

        if (param_name.len == 0) return errors.append(gpa, .{
            .tag = .{
                .invalid_attr_value = .{
                    .reason = "emtpy MIME parameter name",
                },
            },
            .main_location = .{
                .start = kv_offset,
                .end = @intCast(kv_offset + sep_idx),
            },
            .node_idx = node_idx,
        });

        if (validateMimeChars(param_name)) |rejection| return errors.append(gpa, .{
            .tag = .{
                .invalid_attr_value = .{ .reason = rejection.reason },
            },
            .main_location = .{
                .start = @intCast(kv_offset + (rejection.offset orelse 0)),
                .end = @intCast(kv_offset + (rejection.offset orelse subtype.len) + 1),
            },
            .node_idx = node_idx,
        });

        const gop = try seen_params.getOrPut(gpa, param_name);
        if (gop.found_existing) return errors.append(gpa, .{
            .tag = .{
                .invalid_attr_value = .{
                    .reason = "duplicate MIME param name",
                },
            },
            .main_location = .{
                .start = kv_offset,
                .end = @intCast(kv_offset + sep_idx),
            },
            .node_idx = node_idx,
        });

        // 6. If position is past the end of input, then break.
        if (sep_idx == kvs.len) break;

        // 5. If position is not past the end of input, then:
        // 5.2 Advance position by 1. (This skips past U+003D (=).)
        const sep = kvs[sep_idx];
        kv_offset += @intCast(sep_idx + 1);
        kvs = kvs[sep_idx + 1 ..];

        // 5.1 If the code point at position within input is U+003B (;),
        // then continue.
        if (sep == ';') continue;

        // 6. If position is past the end of input, then break.
        if (kvs.len == 0) break;

        // 8. If the code point at position within input is U+0022 ("), then:
        if (kvs[0] == '"') {
            kvs = kvs[1..];
            kv_offset += 1;
            while (true) {
                // 1. Append the result of collecting a sequence of code points
                // that are not U+0022 (") or U+005C (\) from input, given
                // position, to value.
                const quote_or_slash_idx = std.mem.indexOfAny(u8, kvs,
                    \\"\
                ) orelse {
                    // 2. If position is past the end of input, then break.
                    kv_offset += @intCast(kvs.len);
                    kvs = &.{};
                    break;
                };

                // 3. Let quoteOrBackslash be the code point at position within
                // input.
                const quote_or_slash = kvs[quote_or_slash_idx];

                // 4. Advance position by 1.
                kvs = kvs[1..];
                kv_offset += 1;

                // 5. If quoteOrBackslash is U+005C (\), then:
                if (quote_or_slash == '\\') {
                    // 6. If position is past the end of input, then append U+005C
                    //(\) to value and break.
                    if (kvs.len == 0) break;

                    // 7. Append the code point at position within input to value.
                    // 8. Advance position by 1.
                    kvs = kvs[1..];
                    kv_offset += 1;
                } else {
                    // 9. Otherwise:
                    //
                    // 10. Assert: quoteOrBackslash is U+0022 (").
                    //
                    // 11. Break.
                    break;
                }
            }
        }

        const next_semi_idx = std.mem.indexOfScalar(u8, kvs, ';') orelse kvs.len;

        const param_value = kvs[0..next_semi_idx];
        for (param_value, 0..) |c, idx| switch (c) {
            '\t', ' '...'~', 0x80...0xff => {},
            else => return errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "invalid character in MIME param value",
                    },
                },
                .main_location = .{
                    .start = @intCast(kv_offset + idx),
                    .end = @intCast(kv_offset + idx + 1),
                },
                .node_idx = node_idx,
            }),
        };

        if (next_semi_idx == kvs.len) break;
        kv_offset += @intCast(next_semi_idx + 1);
        kvs = kvs[next_semi_idx + 1 ..];
    }
}

pub fn validateMimeChars(bytes: []const u8) ?Rule.ValueRejection {
    for (bytes, 0..) |c, idx| switch (c) {
        // zig fmt: off
        '!', '#', '$', '%', '&', '\'', '*',
        '+', '-', '.', '^', '_', '`', '|', '~',
        'a'...'z', '0'...'9', 'A'...'Z' => {},
        // zig fmt: on
        else => return .{
            .reason = "invalid character in MIME value",
            .offset = @intCast(idx),
        },
    };

    return null;
}

const LanguageTagRejection = struct {
    reason: []const u8,
    offset: u32,
    length: u32,

    pub fn init(bytes: []const u8, subtag: []const u8, reason: []const u8) LanguageTagRejection {
        return .{
            .reason = reason,
            .offset = @intCast(@intFromPtr(subtag.ptr) - @intFromPtr(bytes.ptr)),
            .length = @intCast(subtag.len),
        };
    }
};

fn validateLanguageTag(bytes: []const u8) ?LanguageTagRejection {
    if (language_tag.maps.grandfathered.get(bytes)) |data| {
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
        privateuse,
        end,
    };
    var parse_state: ParseState = .language;
    var extlang_count: u8 = 0;

    var subtags = std.mem.splitScalar(u8, bytes, '-');
    while (subtags.next()) |subtag| state: switch (parse_state) {
        .language => switch (subtag.len) {
            0 => return .init(bytes, subtag, "cannot be empty"),
            // ISO 639 code
            2...3 => {
                if (language_tag.maps.language.get(subtag)) |data| {
                    if (data.is_deprecated) return .init(bytes, subtag, "deprecated language");
                } else {
                    return .init(bytes, subtag, "unknown language");
                }
                parse_state = .extlang;
            },
            // reserved for future use
            4 => {
                parse_state = .script;
            },
            // registered language subtag
            5...8 => {
                parse_state = .script;
            },
            else => return .init(bytes, subtag, "wrong language length"),
        },
        .extlang => if (subtag.len == 3) {
            if (std.ascii.isDigit(subtag[0])) continue :state .region;
            if (language_tag.maps.extlang.get(subtag)) |data| {
                if (data.is_deprecated) return .init(bytes, subtag, "deprecated language extension");
            } else {
                return .init(bytes, subtag, "unknown language extension");
            }
            extlang_count += 1;
            if (extlang_count > 3) {
                return .init(bytes, subtag, "more than 3 language extensions");
            }
        } else {
            continue :state .script;
        },
        .script => if (subtag.len == 4) {
            if (std.ascii.isDigit(subtag[0])) continue :state .variant;
            if (!language_tag.maps.script.has(subtag)) {
                return .init(bytes, subtag, "unknown language script");
            }
            parse_state = .region;
        } else {
            continue :state .region;
        },
        .region => switch (subtag.len) {
            // ISO 3166 or UN M.49 code
            2...3 => {
                if (language_tag.maps.region.get(subtag)) |data| {
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
                if (language_tag.maps.variant.get(subtag)) |data| {
                    if (data.is_deprecated) return .init(bytes, subtag, "deprecated language variant");
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
                parse_state = .singleton;
            },
            else => return .init(bytes, subtag, "wrong extension length"),
        },
        .privateuse => switch (subtag.len) {
            1...8 => {
                for (subtag) |char| if (!std.ascii.isAlphanumeric(char)) {
                    return .init(bytes, subtag, "private use extension must be alphanumeric");
                };
                parse_state = .end;
            },
            else => return .init(bytes, subtag, "wrong private use extension length"),
        },
        .end => return .init(bytes, subtag, "subtag after private use extension"),
    };
    return null;
}

pub const ValidatingIterator = struct {
    it: Tokenizer,
    errors: *std.ArrayListUnmanaged(Ast.Error),
    seen_attrs: *std.StringHashMapUnmanaged(Span),
    end: u32,
    node_idx: u32,
    name: Span = undefined,

    /// On initalization will call seen_attrs.clearRetainingCapacity()
    pub fn init(
        errors: *std.ArrayListUnmanaged(Ast.Error),
        seen_attrs: *std.StringHashMapUnmanaged(Span),
        lang: Language,
        tag: Span,
        src: []const u8,
        node_idx: u32,
    ) ValidatingIterator {
        seen_attrs.clearRetainingCapacity();
        var result: ValidatingIterator = .{
            .it = .{
                .language = lang,
                .idx = tag.start,
                .return_attrs = true,
            },
            .errors = errors,
            .seen_attrs = seen_attrs,
            .end = tag.end,
            .node_idx = node_idx,
        };

        result.name = result.it.next(src).?.tag_name;
        return result;
    }

    /// Will add a duplicate_attribute error for each duplicate attribute.
    /// Duplicate attributes will not be returned by this function.
    pub fn next(
        vait: *ValidatingIterator,
        gpa: Allocator,
        src: []const u8,
    ) !?Tokenizer.Attr {
        while (vait.it.next(src[0..vait.end])) |maybe_attr| {
            switch (maybe_attr) {
                else => unreachable,
                .tag_name => {},
                .tag => break,
                .parse_error => {},
                .attr => |attr| {
                    const attr_name = attr.name.slice(src);
                    const gop = try vait.seen_attrs.getOrPut(gpa, attr_name);
                    if (gop.found_existing) {
                        try vait.errors.append(gpa, .{
                            .tag = .{
                                .duplicate_attribute_name = gop.value_ptr.*,
                            },
                            .main_location = .{
                                .start = attr.name.start,
                                .end = attr.name.end,
                            },
                            .node_idx = vait.node_idx,
                        });
                        continue;
                    } else {
                        gop.value_ptr.* = attr.name;
                        return attr;
                    }
                },
            }
        }
        return null;
    }
};

pub fn completions(
    arena: Allocator,
    src: []const u8,
    stt: *Ast.Node.TagIterator,
    element_tag: Ast.Kind,
    offset: u32,
) ![]const Ast.Completion {
    assert(element_tag.isElement());

    const elem_attrs = element_attrs.get(element_tag);
    const total_count = global.list.len + elem_attrs.list.len;

    var seen: std.DynamicBitSetUnmanaged = try .initEmpty(arena, total_count);
    var seen_count: u32 = 0;
    while (stt.next(src)) |attr| {
        log.debug("completions attr: {any}", .{attr});
        const name = attr.name.slice(src);
        const attr_model, const list_idx = blk: {
            if (global.index(name)) |idx| {
                const gl = global.list[idx];
                break :blk .{ gl.model, elem_attrs.list.len + idx };
            }

            if (elem_attrs.index(name)) |idx| {
                const ea = elem_attrs.list[idx];
                break :blk .{ ea.model, idx };
            }

            continue;
        };

        if (attr.value) |v| {
            log.debug("offset = {} v.span = {any}", .{ offset, v.span });
            if (offset >= v.span.start and
                offset <= v.span.end)
            {
                // <div attribute="">
                //                ^
                // <div attribute="  ">
                //                ^^^
                const value_content = std.mem.trim(
                    u8,
                    v.span.slice(src),
                    &std.ascii.whitespace,
                );

                switch (attr_model.rule) {
                    .cors => if (value_content.len == 0) {
                        return Rule.cors_list.completions;
                    },
                    .lang => {
                        if (value_content.len == 0) {
                            return &language_tag.completions.language;
                        }
                    },
                    .list => |l| {
                        if (value_content.len == 0) {
                            return l.completions;
                        }

                        if (l.count != .one) {
                            log.debug("in", .{});
                            var delimiter_idx = offset;
                            while (delimiter_idx < src.len) : (delimiter_idx += 1) {
                                if (std.mem.indexOfScalar(
                                    u8,
                                    &std.ascii.whitespace,
                                    src[delimiter_idx],
                                ) == null) break;
                            }

                            if (src[delimiter_idx] == '"' or src[delimiter_idx] == '\'') {
                                var items = try arena.alloc(
                                    Ast.Completion,
                                    l.completions.len,
                                );
                                var seen_items = try arena.alloc(
                                    bool,
                                    l.completions.len,
                                );
                                defer arena.free(seen_items);
                                @memset(seen_items, false);
                                var it = std.mem.tokenizeAny(
                                    u8,
                                    value_content,
                                    &std.ascii.whitespace,
                                );
                                while (it.next()) |item| {
                                    if (l.set.get(item)) |item_idx| {
                                        seen_items[item_idx] = true;
                                    }
                                }

                                var idx: usize = 0;
                                for (seen_items, 0..) |iseen, sidx| {
                                    if (iseen) continue;
                                    items[idx] = l.completions[sidx];
                                    idx += 1;
                                }

                                return items[0..idx];
                            }
                        }

                        log.debug("here", .{});
                    },
                    else => return &.{},
                }
            } else if (offset >= attr.name.end and
                offset < v.span.start)
            {
                // <div attribute= anotherattribute>
                //               ^
                if (src[offset - 1] == '=') {
                    return switch (attr_model.rule) {
                        .cors => Rule.cors_list.completions,
                        .list => |l| l.completions,
                        else => &.{},
                    };
                }
            }
        } else {
            // Are we in this case?
            // <div attribute=  >
            //               ^
            const next_start = blk: {
                var stt1 = stt.*;
                const next = stt1.next(src);
                if (next) |n| break :blk n.name.start;
                break :blk stt1.end;
            };

            if (offset > attr.name.end and
                offset < next_start)
            {
                var idx = offset - 1;
                while (idx > 0) : (idx -= 1) {
                    switch (src[idx]) {
                        else => break,
                        ' ', '\t', '\n', '\r' => continue,
                        '=' => return switch (attr_model.rule) {
                            .cors => Rule.cors_list.completions,
                            .list => |l| l.completions,
                            else => &.{},
                        },
                    }
                }
            }
        }

        if (!seen.isSet(list_idx)) {
            seen.set(list_idx);
            seen_count += 1;
        }
    }

    const items = try arena.alloc(Ast.Completion, total_count - seen_count + 1);
    var items_idx: u32 = 0;
    var it = seen.iterator(.{ .kind = .unset });
    while (it.next()) |seen_idx| : (items_idx += 1) {
        const item = if (seen_idx < elem_attrs.list.len)
            elem_attrs.list[seen_idx]
        else
            global.list[seen_idx - elem_attrs.list.len];

        items[items_idx] = .{
            .label = item.name,
            .desc = item.model.desc,
        };
    }

    items[items_idx] = .{
        .label = "Data Attribute",
        .desc = "A data attribute",
        .value = "data-",
    };

    items_idx += 1;
    assert(items_idx == items.len);
    return items;
}

const empty_set: *const AttributeSet = &.{
    .list = &.{},
    .map = .initComptime(.{}),
};

const Named = struct { name: []const u8, model: Attribute };
pub const AttributeSet = struct {
    list: []const Named,
    map: Map,

    pub fn init(list: []const Named) AttributeSet {
        @setEvalBranchQuota(4000);
        var kvs: [list.len]struct { []const u8, u32 } = undefined;
        for (list, &kvs, 0..) |entry, *kv, idx| kv.* = .{
            entry.name,
            idx,
        };

        return .{
            .list = list,
            .map = .initComptime(kvs),
        };
    }

    pub fn get(as: AttributeSet, name: []const u8) ?Attribute {
        return as.list[as.map.get(name) orelse return null].model;
    }

    pub fn index(as: AttributeSet, name: []const u8) ?u32 {
        return as.map.get(name) orelse return null;
    }
    pub fn has(as: AttributeSet, name: []const u8) bool {
        return as.map.has(name);
    }

    pub inline fn comptimeIndex(as: AttributeSet, name: []const u8) u32 {
        @setEvalBranchQuota(4000);
        inline for (as.list, 0..) |named, idx| {
            if (named.name.ptr == name.ptr) return idx;
        }

        @compileError("failed to resolve index for '" ++ name ++ "'");
    }
};

pub const element_attrs: std.EnumArray(Ast.Kind, *const AttributeSet) = .init(.{
    .root = undefined,
    .doctype = undefined,
    .comment = undefined,
    .text = undefined,
    .extend = &@import("elements/extend.zig").attributes,
    .super = undefined,
    .ctx = undefined,
    .___ = undefined,
    .a = &@import("elements/a.zig").attributes,
    .abbr = empty_set,
    .address = empty_set,
    .area = &@import("elements/area.zig").attributes,
    .article = empty_set,
    .aside = empty_set,
    .audio = &@import("elements/audio_video.zig").attributes,
    .b = empty_set,
    .base = &@import("elements/base.zig").attributes,
    .bdi = empty_set,
    .bdo = empty_set,
    .blockquote = &@import("elements/blockquote.zig").attributes,
    .body = &@import("elements/body.zig").attributes,
    .br = empty_set,
    .button = &@import("elements/button.zig").attributes,
    .canvas = &@import("elements/canvas.zig").attributes,
    .caption = empty_set,
    .cite = empty_set,
    .code = empty_set,
    .col = &@import("elements/col.zig").attributes,
    .colgroup = &@import("elements/colgroup.zig").attributes,
    .data = &@import("elements/data.zig").attributes,
    .datalist = empty_set,
    .dd = empty_set,
    .del = &@import("elements/ins_del.zig").attributes,
    .details = &@import("elements/details.zig").attributes,
    .dfn = empty_set,
    .dialog = &@import("elements/dialog.zig").attributes,
    .div = empty_set,
    .dl = empty_set,
    .dt = empty_set,
    .em = empty_set, // done
    .embed = &@import("elements/embed.zig").attributes,
    .fencedframe = &@import("elements/fencedframe.zig").attributes,
    .fieldset = &@import("elements/fieldset.zig").attributes,
    .figcaption = empty_set,
    .figure = empty_set,
    .footer = empty_set,
    .form = &@import("elements/form.zig").attributes,
    .h1 = empty_set,
    .h2 = empty_set,
    .h3 = empty_set,
    .h4 = empty_set,
    .h5 = empty_set,
    .h6 = empty_set,
    .head = empty_set,
    .header = empty_set,
    .hgroup = empty_set,
    .hr = empty_set,
    .html = empty_set,
    .i = empty_set, // done
    .iframe = &@import("elements/iframe.zig").attributes,
    .img = &@import("elements/img.zig").attributes,
    .input = &@import("elements/input.zig").attributes,
    .ins = &@import("elements/ins_del.zig").attributes,
    .kbd = empty_set,
    .label = &@import("elements/label.zig").attributes,
    .legend = empty_set,
    .li = &@import("elements/li.zig").attributes,
    .link = &@import("elements/link.zig").attributes,
    .main = empty_set, // done
    .map = &@import("elements/map.zig").attributes,
    .math = empty_set,
    .mark = empty_set,
    .menu = empty_set,
    .meta = &@import("elements/meta.zig").attributes,
    .meter = &@import("elements/meter.zig").attributes,
    .nav = empty_set,
    .noscript = empty_set,
    .object = &@import("elements/object.zig").attributes,
    .ol = &@import("elements/ol.zig").attributes,
    .optgroup = &@import("elements/optgroup.zig").attributes,
    .option = &@import("elements/option.zig").attributes,
    .output = &@import("elements/output.zig").attributes,
    .p = empty_set,
    .picture = empty_set,
    .pre = empty_set,
    .progress = &@import("elements/progress.zig").attributes,
    .q = &@import("elements/q.zig").attributes,
    .rp = empty_set,
    .rt = empty_set,
    .ruby = empty_set,
    .s = empty_set,
    .samp = empty_set,
    .script = &@import("elements/script.zig").attributes,
    .search = empty_set,
    .section = empty_set,
    .select = &@import("elements/select.zig").attributes,
    .selectedcontent = empty_set,
    .slot = &@import("elements/slot.zig").attributes,
    .small = empty_set,
    .source = &@import("elements/source.zig").attributes,
    .span = empty_set,
    .strong = empty_set,
    .style = &@import("elements/style.zig").attributes,
    .sub = empty_set,
    .summary = empty_set,
    .sup = empty_set,
    .svg = empty_set,
    .table = empty_set,
    .tbody = empty_set,
    .td = &@import("elements/td.zig").attributes,
    .template = &@import("elements/template.zig").attributes,
    .textarea = &@import("elements/textarea.zig").attributes,
    .tfoot = empty_set,
    .th = &@import("elements/th.zig").attributes,
    .thead = empty_set,
    .time = &@import("elements/time.zig").attributes,
    .title = empty_set,
    .tr = empty_set,
    .track = &@import("elements/track.zig").attributes,
    .u = empty_set,
    .ul = empty_set,
    .@"var" = empty_set,
    .video = &@import("elements/audio_video.zig").attributes,
    .wbr = empty_set,
});

const temp: Attribute = .{
    .rule = .any,
    .desc = "#temp global attribute#",
};

pub fn isData(name: []const u8) bool {
    if (name.len < "data-*".len) return false;
    return std.ascii.eqlIgnoreCase("data-", name[0.."data-".len]);
}

pub const global: AttributeSet = .init(&.{
    .{
        .name = "id",
        .model = .{
            .rule = .id,
            .desc = "The `id` global attribute defines an identifier (ID) that must be unique within the entire document.",
        },
    },
    .{
        .name = "class",
        .model = .{
            .rule = .class,
            .desc = "The `class` global attribute is a list of the classes of the element, separated by ASCII whitespace.",
        },
    },
    .{
        .name = "slot",
        .model = .{
            .rule = .not_empty,
            .desc = "The `slot` global attribute assigns a slot in a shadow DOM shadow tree to an element: An element with a `slot` attribute is assigned to the slot created by the `<slot>` element whose `name` attribute's value matches that `slot` attribute's value. You can have multiple elements assigned to the same slot by using the same slot name. Elements without a slot attribute are assigned to the unnamed slot, if one exists.",
        },
    },

    // https://html.spec.whatwg.org/multipage/interaction.html#the-accesskey-attribute
    .{
        .name = "accesskey",
        .model = .{
            .rule = .{
                .custom = accesskey,
            },
            .desc =
            \\The accesskey global attribute provides a hint for generating a
            \\keyboard shortcut for the current element. The attribute value must
            \\consist of a single printable character (which includes accented and
            \\other characters that can be generated by the keyboard).
            \\
            \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Global_attributes/accesskey)
            \\- [HTML Spec](https://html.spec.whatwg.org/multipage/interaction.html#the-accesskey-attribute)
            ,
        },
    },

    // https://html.spec.whatwg.org/multipage/interaction.html#attr-autocapitalize
    .{
        .name = "autocapitalize",
        .model = .{
            .rule = .{
                .list = .init(.none, .one, &.{
                    .{
                        .label = "sentences",
                        .desc =
                        \\The first letter of each sentence should default to a capital letter; all other letters should default to lowercase.
                        ,
                    },
                    .{
                        .label = "words",
                        .desc =
                        \\The first letter of each word should default to a capital letter; all other letters should default to lowercase.
                        ,
                    },
                    .{
                        .label = "characters",
                        .desc =
                        \\All letters should default to uppercase.
                        ,
                    },
                    .{
                        .label = "none",
                        .desc =
                        \\No autocapitalization should be applied (all letters should default to lowercase).
                        ,
                    },
                    .{
                        .label = "on",
                        .desc =
                        \\Same as `sentences`.
                        ,
                    },
                    .{
                        .label = "off",
                        .desc =
                        \\Same as `none`.
                        ,
                    },
                }),
            },
            .desc = "The `autocapitalize` global attribute is an enumerated attribute that controls whether inputted text is automatically capitalized and, if so, in what manner.",
        },
    },

    // https://html.spec.whatwg.org/multipage/interaction.html#attr-autocorrect
    .{
        .name = "autocorrect",
        .model = .{
            .desc = "The autocorrect global attribute is an enumerated attribute that controls whether autocorrection of editable text is enabled for spelling and/or punctuation errors.",
            .rule = .{
                .list = .init(.missing_or_empty, .one, &.{
                    .{
                        .label = "on",
                        .desc = "Enable automatic correction of spelling and punctuation errors.",
                    },
                    .{
                        .label = "off",
                        .desc = "Disable automatic correction of editable text.",
                    },
                }),
            },
        },
    },

    // https://html.spec.whatwg.org/multipage/interaction.html#attr-fe-autofocus
    .{
        .name = "autofocus",
        .model = .{
            .desc = "The `autofocus` global attribute is a Boolean attribute indicating that an element should be focused on page load, or when the `<dialog>` that it is part of is displayed.",
            .rule = .{
                .list = .init(.missing_or_empty, .one, &.{
                    .{
                        .label = "on",
                        .desc = "Enable automatic correction of spelling and punctuation errors.",
                    },
                    .{
                        .label = "off",
                        .desc = "Disable automatic correction of editable text.",
                    },
                }),
            },
        },
    },

    // https://html.spec.whatwg.org/multipage/interaction.html#attr-contenteditable
    .{
        .name = "contenteditable",
        .model = .{
            .desc = "The `contenteditable` global attribute is an enumerated attribute indicating if the element should be editable by the user. If so, the browser modifies its widget to allow editing.",
            .rule = .{
                .list = .init(.missing_or_empty, .one, &.{
                    .{
                        .label = "true",
                        .desc = "Indicates that the element is editable.",
                    },
                    .{
                        .label = "false",
                        .desc = "Indicates that the element is not editable.",
                    },
                    .{
                        .label = "plaintext-only",
                        .desc = "Indicates that the element's raw text is editable, but rich text formatting is disabled.",
                    },
                }),
            },
        },
    },

    // https://html.spec.whatwg.org/multipage/dom.html#attr-dir
    .{
        .name = "dir",
        .model = .{
            .desc = "The `dir` global attribute is an enumerated attribute that indicates the directionality of the element's text.",
            .rule = .{
                .list = .init(.none, .one, &.{
                    .{
                        .label = "ltr",
                        .desc = "Left-to-right, to be used for languages that are written from the left to the right.",
                    },
                    .{
                        .label = "rtl",
                        .desc = "Right-to-left, to be used for languages that are written from the right to the left.",
                    },
                    .{
                        .label = "auto",
                        .desc = "To be used when the directionality is unknown. It uses a basic algorithm as it parses the characters inside the element until it finds a character with a strong directionality, then applies that directionality to the whole element.",
                    },
                }),
            },
        },
    },

    // https://html.spec.whatwg.org/multipage/dnd.html#attr-draggable
    .{
        .name = "draggable",
        .model = .{
            .desc = "The `draggable` global attribute is an enumerated attribute that indicates whether the element can be dragged, either with native browser behavior or the HTML Drag and Drop API.",
            .rule = .{
                .list = .init(.none, .one, &.{
                    .{
                        .label = "true",
                        .desc = "The element can be dragged.",
                    },
                    .{
                        .label = "false",
                        .desc = "The element cannot be dragged.",
                    },
                }),
            },
        },
    },

    // https://html.spec.whatwg.org/multipage/interaction.html#attr-enterkeyhint
    .{
        .name = "enterkeyhint",
        .model = .{
            .desc = "The `enterkeyhint` global attribute is an enumerated attribute defining what action label (or icon) to present for the enter key on virtual keyboards.",
            .rule = .{
                .list = .init(.none, .one, &.{
                    .{
                        .label = "enter",
                        .desc = "",
                    },
                    .{
                        .label = "done",
                        .desc = "",
                    },
                    .{
                        .label = "go",
                        .desc = "",
                    },
                    .{
                        .label = "next",
                        .desc = "",
                    },
                    .{
                        .label = "previous",
                        .desc = "",
                    },
                    .{
                        .label = "search",
                        .desc = "",
                    },
                    .{
                        .label = "send",
                        .desc = "",
                    },
                }),
            },
        },
    },

    // https://html.spec.whatwg.org/multipage/interaction.html#the-hidden-attribute
    .{
        .name = "hidden",
        .model = .{
            .desc = "The `hidden` global attribute is an enumerated attribute indicating that the browser should not render the contents of the element. For example, it can be used to hide elements of the page that can't be used until the login process has been completed.",
            .rule = .{
                .list = .init(.missing_or_empty, .one, &.{
                    .{
                        .label = "hidden",
                        .desc = "",
                    },
                    .{
                        .label = "until-found",
                        .desc = "",
                    },
                }),
            },
        },
    },

    // https://html.spec.whatwg.org/multipage/interaction.html#the-inert-attribute
    .{
        .name = "inert",
        .model = .{
            .rule = .bool,
            .desc =
            \\The `inert` global attribute is a Boolean attribute
            \\indicating that the element and all of its flat tree
            \\descendants become inert. Modal `<dialog>`s generated with
            \\`showModal()` escape inertness, meaning that they don't
            \\inherit inertness from their ancestors, but can only be
            \\made inert by having the inert attribute explicitly set
            \\on themselves.
            \\
            \\Specifically, inert does the following:
            \\
            \\- Prevents the `click` event from being fired when the user
            \\  clicks on the element.
            \\- Prevents the `focus` event from being raised by preventing
            \\  the element from gaining focus.
            \\- Prevents any contents of the element from being
            \\  found/matched during any use of the browser's find-in-page
            \\  feature.
            \\- Prevents users from selecting text within the element —
            \\  akin to using the CSS property `user-select` to disable text
            \\  selection.
            \\- Prevents users from editing any contents of the element
            \\  that are otherwise editable.
            \\- Hides the element and its content from assistive
            \\  technologies by excluding them from the accessibility tree.
            ,
        },
    },

    .{
        .name = "inputmode",
        .model = .{
            .desc = "The `inputmode` global attribute is an enumerated attribute that hints at the type of data that might be entered by the user while editing the element or its contents. This allows a browser to display an appropriate virtual keyboard.",
            .rule = .{
                .list = .init(.none, .one, &.{
                    .{
                        .label = "none",
                        .desc = "No virtual keyboard. For when the page implements its own keyboard input control.",
                    },
                    .{
                        .label = "text",
                        .desc = "Standard input keyboard for the user's current locale.",
                    },
                    .{
                        .label = "decimal",
                        .desc = "Fractional numeric input keyboard containing the digits and decimal separator for the user's locale (typically . or ,). Devices may or may not show a minus key (-).",
                    },
                    .{
                        .label = "numeric",
                        .desc = "Numeric input keyboard, but only requires the digits 0–9. Devices may or may not show a minus key.",
                    },
                    .{
                        .label = "tel",
                        .desc = "A telephone keypad input, including the digits 0–9, the asterisk (*), and the pound (#) key. Inputs that require a telephone number should typically use `<input type=\"tel\">` instead.",
                    },
                    .{
                        .label = "search",
                        .desc = "A virtual keyboard optimized for search input. For instance, the return/submit key may be labeled \"Search\", along with possible other optimizations. Inputs that require a search query should typically use `<input type=\"search\">` instead.",
                    },
                    .{
                        .label = "email",
                        .desc = "A virtual keyboard optimized for entering email addresses. Typically includes the @ character as well as other optimizations. Inputs that require email addresses should typically use `<input type=\"email\">` instead.",
                    },
                    .{
                        .label = "url",
                        .desc = "A keypad optimized for entering URLs. This may have the / key more prominent, for example. Enhanced features could include history access and so on. Inputs that require a URL should typically use `<input type=\"url\">` instead.",
                    },
                }),
            },
        },
    },
    .{
        .name = "itemid",
        .model = .{
            .rule = .{ .url = .not_empty },
            .desc = "The `itemid` global attribute provides microdata in the form of a unique, global identifier of an item.",
        },
    },
    .{
        .name = "itemprop",
        .model = .{
            .rule = .any,
            .desc = "The `itemprop` global attribute is used to add properties to an item. Every HTML element can have an itemprop attribute specified, and an itemprop consists of a name-value pair. ",
        },
    },
    .{
        .name = "itemref",
        .model = .{
            .rule = .any,
            .desc = "Properties that are not descendants of an element with the itemscope attribute can be associated with an item using the global attribute itemref.",
        },
    },
    .{
        .name = "itemscope",
        .model = .{
            .rule = .any,
            .desc = "itemscope is a boolean global attribute that defines the scope of associated metadata. Specifying the itemscope attribute for an element creates a new item, which results in a number of name-value pairs that are associated with the element.",
        },
    },
    .{
        .name = "itemtype",
        .model = .{
            .rule = .any,
            .desc = "The global attribute itemtype specifies the URL of the vocabulary that will be used to define itemprop's (item properties) in the data structure.",
        },
    },
    .{
        .name = "lang",
        .model = .{
            .rule = .not_empty,
            .desc = "The `lang` global attribute helps define the language of an element: the language that non-editable elements are written in, or the language that the editable elements should be written in by the user. The attribute contains a single BCP 47 language tag.",
        },
    },
    .{
        .name = "nonce",
        .model = .{
            .rule = .any,
            .desc = "The `nonce` global attribute is a content attribute defining a cryptographic nonce ('number used once') which can be used by Content Security Policy to determine whether or not a given fetch will be allowed to proceed for a given element.",
        },
    },
    .{
        .name = "popover",
        .model = .{
            .desc = "The `popover` global attribute is used to designate an element as a popover element.",
            .rule = .{
                .list = .init(.missing_or_empty, .one, &.{
                    .{
                        .label = "auto",
                        .desc = "auto popovers can be 'light dismissed' — this means that you can hide the popover by clicking outside it or pressing the Esc key. Showing an auto popover will generally close other auto popovers that are already displayed, unless they are nested.",
                    },
                    .{
                        .label = "manual",
                        .desc = "manual popovers cannot be 'light dismissed' and are not automatically closed. Popovers must explicitly be displayed and closed using declarative show/hide/toggle buttons or JavaScript. Multiple independent manual popovers can be shown simultaneously.",
                    },
                    .{
                        .label = "hint",
                        .desc = "hint popovers do not close auto popovers when they are displayed, but will close other hint popovers. They can be light dismissed and will respond to close requests.",
                    },
                }),
            },
        },
    },
    .{
        .name = "spellcheck",
        .model = .{
            .desc = "The `spellcheck` global attribute is an enumerated attribute that defines whether the element may be checked for spelling errors.",
            .rule = .{
                .list = .init(.missing_or_empty, .one, &.{
                    .{
                        .label = "true",
                        .desc = "Indicates that the element should be, if possible, checked for spelling errors.",
                    },
                    .{
                        .label = "false",
                        .desc = "Indicates that the element should not be checked for spelling errors.",
                    },
                }),
            },
        },
    },
    .{
        .name = "style",
        .model = .{
            .desc = "The `style` global attribute contains CSS styling declarations to be applied to the element. Note that it is recommended for styles to be defined in a separate file or files. This attribute and the `<style>` element have mainly the purpose of allowing for quick styling, for example for testing purposes.",
            .rule = .any,
        },
    },
    .{
        .name = "tabindex",
        .model = .{
            .desc = "The `tabindex` global attribute allows developers to make HTML elements focusable, allow or prevent them from being sequentially focusable (usually with the Tab key, hence the name) and determine their relative ordering for sequential focus navigation.",
            .rule = .{ .custom = struct {
                fn custom(
                    gpa: Allocator,
                    errors: *std.ArrayListUnmanaged(Ast.Error),
                    src: []const u8,
                    node_idx: u32,
                    attr: Tokenizer.Attr,
                ) error{OutOfMemory}!void {
                    const value = attr.value orelse return errors.append(gpa, .{
                        .tag = .missing_attr_value,
                        .main_location = attr.name,
                        .node_idx = node_idx,
                    });
                    const digits = std.mem.trim(
                        u8,
                        value.span.slice(src),
                        &std.ascii.whitespace,
                    );
                    _ = std.fmt.parseInt(i64, digits, 10) catch {
                        try errors.append(gpa, .{
                            .tag = .{
                                .invalid_attr_value = .{
                                    .reason = "not a valid integer number",
                                },
                            },
                            .main_location = value.span,
                            .node_idx = node_idx,
                        });
                    };
                }
            }.custom },
        },
    },
    .{
        .name = "title",
        .model = .{
            .rule = .any,
            .desc = "The `title` global attribute contains text representing advisory information related to the element it belongs to.",
        },
    },
    .{
        .name = "translate",
        .model = .{
            .desc = "The `translate` global attribute is an enumerated attribute that is used to specify whether an element's translatable attribute values and its Text node children should be translated when the page is localized, or whether to leave them unchanged.",
            .rule = .{
                .list = .init(.missing_or_empty, .one, &.{
                    .{
                        .label = "yes",
                        .desc = "Indicates that the element should be translated when the page is localized.",
                    },
                    .{
                        .label = "no",
                        .desc = "Indicates that the element must not be translated.",
                    },
                }),
            },
        },
    },
    .{
        .name = "writingsuggestions",
        .model = .{
            .desc = "The `writingsuggestions` global attribute is an enumerated attribute indicating if browser-provided writing suggestions should be enabled under the scope of the element or not.",
            .rule = .{
                .list = .init(.missing_or_empty, .one, &.{
                    .{ .label = "true", .desc = "" },
                    .{ .label = "false", .desc = "" },
                }),
            },
        },
    },
    .{
        .name = "onauxclick",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onbeforeinput",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onbeforematch",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onbeforetoggle",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onblur",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "oncancel",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "oncanplay",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "oncanplaythrough",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onchange",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onclick",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onclose",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "oncommand",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "oncontextlost",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "oncontextmenu",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "oncontextrestored",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "oncopy",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "oncuechange",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "oncut",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "ondblclick",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "ondrag",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "ondragend",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "ondragenter",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "ondragleave",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "ondragover",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "ondragstart",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "ondrop",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "ondurationchange",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onemptied",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onended",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onerror",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onfocus",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onformdata",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "oninput",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "oninvalid",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onkeydown",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onkeypress",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onkeyup",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onload",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onloadeddata",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onloadedmetadata",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onloadstart",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onmousedown",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onmouseenter",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onmouseleave",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onmousemove",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onmouseout",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onmouseover",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onmouseup",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onpaste",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onpause",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onplay",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onplaying",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onprogress",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onratechange",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onreset",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onresize",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onscroll",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onscrollend",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onsecuritypolicyviolation",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onseeked",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onseeking",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onselect",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onslotchange",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onstalled",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onsubmit",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onsuspend",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "ontimeupdate",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "ontoggle",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onvolumechange",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onwaiting",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
    .{
        .name = "onwheel",
        .model = .{
            .rule = .any,
            .desc = "",
        },
    },
});

pub fn accesskey(
    gpa: Allocator,
    errors: *std.ArrayListUnmanaged(Ast.Error),
    src: []const u8,
    node_idx: u32,
    attr: Tokenizer.Attr,
) !void {
    const value = attr.value orelse {
        return errors.append(gpa, .{
            .tag = .missing_attr_value,
            .main_location = attr.name,
            .node_idx = node_idx,
        });
    };

    var seen_toks: std.StringHashMapUnmanaged(Span) = .empty;
    defer seen_toks.deinit(gpa);

    var it = std.mem.tokenizeAny(u8, value.span.slice(src), &std.ascii.whitespace);
    while (it.next()) |tok| {
        const span: Span = .{
            .start = @intCast(it.index - tok.len + value.span.start),
            .end = @intCast(it.index + value.span.start),
        };

        const count = std.unicode.utf8CountCodepoints(tok) catch {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "token must be valid unicode",
                    },
                },
                .main_location = span,
                .node_idx = node_idx,
            });
            continue;
        };

        if (count != 1) {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "token must be a single codepoint",
                    },
                },
                .main_location = span,
                .node_idx = node_idx,
            });
            continue;
        }

        const gop = try seen_toks.getOrPut(gpa, tok);
        if (gop.found_existing) {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "duplicate token",
                    },
                },
                .main_location = span,
                .node_idx = node_idx,
            });
            continue;
        }
        gop.value_ptr.* = span;
    }
}

pub const common = struct {
    pub const fetchpriority: Attribute = .{
        .desc = "Provides a hint of the relative priority to use when fetching a resource of a particular type.",
        .rule = .{
            .list = .init(.none, .one, &.{
                .{
                    .label = "high",
                    .desc = "Fetch the resource at a high priority relative to other resources of the same type.",
                },
                .{
                    .label = "low",
                    .desc = "Fetch the resource at a low priority relative to other resources of the same type.",
                },
                .{
                    .label = "auto",
                    .desc = "Don't set a preference for the fetch priority. This is the default. It is used if no value or an invalid value is set.",
                },
            }),
        },
    };
    pub const alt: Attribute = .{
        .rule = .any,
        .desc =
        \\Defines text that can replace the image in the page.
        \\
        \\Setting this attribute to an empty string (`alt=""`) indicates
        \\that this image is not a key part of the content (it's
        \\decoration or a tracking pixel), and that non-visual browsers
        \\may omit it from rendering. Visual browsers will also hide the
        \\broken image icon if the alt attribute is empty and the image
        \\failed to display.
        \\
        \\This attribute is also used when copying and pasting the image
        \\to text, or saving a linked image to a bookmark.
        ,
    };

    pub const target: Attribute = .{
        .rule = .{
            .list = .init(.{ .custom = checkNavigableName }, .one, &.{
                .{
                    .label = "_self",
                    .desc = "The current browsing context. (Default)",
                },
                .{
                    .label = "_blank",
                    .desc =
                    \\Usually a new tab, but users can configure
                    \\browsers to open a new window instead.
                    \\
                    \\When set on `<a>` elements, it implicitly
                    \\provides the same rel behavior as
                    \\setting rel="noopener" which does not set
                    \\`window.opener`.
                    ,
                },
                .{
                    .label = "_parent",
                    .desc = "The parent browsing context of the current one. If no parent, behaves as `_self`.",
                },
                .{
                    .label = "_top",
                    .desc =
                    \\The topmost browsing context. To be
                    \\specific, this means the "highest" context
                    \\that's an ancestor of the current one. If no
                    \\ancestors, behaves as `_self`.
                    ,
                },
                .{
                    .label = "_unfencedTop",
                    .desc =
                    \\Allows embedded fenced frames to navigate
                    \\the top-level frame (i.e., traversing
                    \\beyond the root of the fenced frame, unlike
                    \\other reserved destinations). Note that the
                    \\navigation will still succeed if this is
                    \\used outside of a fenced frame context, but
                    \\it will not act like a reserved keyword.
                    ,
                },
                .{
                    .label = "Navigable Name",
                    .value = "myIframe",
                    .desc =
                    \\The value given to the `name` attribute of an `<iframe>`
                    \\element, a tab or a window.
                    ,
                },
            }),
        },
        .desc =
        \\Where to display the linked URL, as the name for a browsing
        \\context (a tab, window, or `<iframe>`).
        \\
        \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/a#target)
        \\- [HTML Spec](https://html.spec.whatwg.org/multipage/links.html#attr-hyperlink-target)
        ,
    };

    pub const download: Attribute = .{
        .rule = .any,
        .desc =
        \\Causes the browser to treat the linked URL as a
        \\download. Can be used with or without a filename value.
        \\
        \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/a#download)
        \\- [HTML Spec](https://html.spec.whatwg.org/multipage/links.html#attr-hyperlink-download)
        ,
    };

    pub const ping: Attribute = .{
        .rule = .any, // we purposely do not validate this crappy attribute
        .desc =
        \\A space-separated list of URLs. When the link is
        \\followed, the browser will send POST requests with the
        \\body PING to the URLs. Typically for tracking.
        \\
        \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/a#ping)
        \\- [HTML Spec](https://html.spec.whatwg.org/multipage/links.html#attr-hyperlink-ping)
        ,
    };

    pub const rel: Attribute = .{
        .rule = .{
            .list = .init(.none, .many_unique, &.{
                .{
                    .label = "nofollow",
                    .desc = "Indicates that the current document's original author or publisher does not endorse the referenced document.",
                },
                .{
                    .label = "noreferrer",
                    .desc = "No `Referer` header will be included. Additionally, has the same effect as `noopener`.",
                },
                .{
                    .label = "noopener",
                    .desc = "Creates a top-level browsing context that is not an auxiliary browsing context if the hyperlink would create either of those, to begin with (i.e., has an appropriate target attribute value).",
                },
                .{
                    .label = "opener",
                    .desc = "Creates an auxiliary browsing context if the hyperlink would otherwise create a top-level browsing context that is not an auxiliary browsing context (i.e., has \"_blank\" as target attribute value).",
                },
                .{
                    .label = "alternate",
                    .desc = "Alternate representations of the current document.",
                },
                .{
                    .label = "author",
                    .desc = "Author of the current document or article.",
                },
                .{
                    .label = "bookmark",
                    .desc = "Permalink for the nearest ancestor section.",
                },
                .{
                    .label = "help",
                    .desc = "Link to context-sensitive help.",
                },
                .{
                    .label = "license",
                    .desc = "Indicates that the main content of the current document is covered by the copyright license described by the referenced document.",
                },
                .{
                    .label = "me",
                    .desc = "Indicates that the current document represents the person who owns the linked content.",
                },
                .{
                    .label = "next",
                    .desc = "Indicates that the current document is a part of a series and that the next document in the series is the referenced document.",
                },
                .{
                    .label = "prev",
                    .desc = "Indicates that the current document is a part of a series and that the previous document in the series is the referenced document.",
                },
                .{
                    .label = "privacy-policy",
                    .desc = "Gives a link to a information about the data collection and usage practices that apply to the current document.",
                },
                .{
                    .label = "search",
                    .desc = "Gives a link to a resource that can be used to search through the current document and its related pages.",
                },
                .{
                    .label = "tag",
                    .desc = "Gives a tag (identified by the given address) that applies to the current document.",
                },
                .{
                    .label = "prev",
                    .desc = "Indicates that the current document is a part of a series and that the previous document in the series is the referenced document.",
                },
                .{
                    .label = "terms-of-service",
                    .desc = "Link to the agreement, or terms of service, between the document's provider and users who wish to use the document.",
                },
            }),
        },
        .desc = "The relationship of the linked URL as space-separated link types.",
    };
    pub const @"type": Attribute = .{
        .rule = .mime,
        .desc = "Hints at the linked URL's format with a MIME type.",
    };
    pub const referrerpolicy: Attribute = .{
        .rule = .{
            .list = .init(.missing_or_empty, .one, &.{
                .{
                    .label = "no-referrer",
                    .desc = "The Referer header will not be sent",
                },
                .{
                    .label = "no-referrer-when-downgrade",
                    .desc = "The Referer header will not be sent to origins without TLS (HTTPS).",
                },
                .{
                    .label = "origin",
                    .desc = "The sent referrer will be limited to the origin of the referring page: its scheme, host, and port.",
                },
                .{
                    .label = "same-origin",
                    .desc = "A referrer will be sent for same origin, but cross-origin requests will contain no referrer information.",
                },
                .{
                    .label = "strict-origin",
                    .desc = "Only send the origin of the document as the referrer when the protocol security level stays the same (HTTPS→HTTPS), but don't send it to a less secure destination (HTTPS→HTTP).",
                },
                .{
                    .label = "strict-origin-when-cross-origin",
                    .desc = "Send a full URL when performing a same-origin request, only send the origin when the protocol security level stays the same (HTTPS→HTTPS), and send no header to a less secure destination (HTTPS→HTTP",
                },
                .{
                    .label = "origin-when-cross-origin",
                    .desc = "The referrer sent to other origins will be limited to the scheme, the host, and the port. Navigations on the same origin will still include the path",
                },
                .{
                    .label = "unsafe-url",
                    .desc = "The referrer will include the origin and the path (but not the fragment, password, or username). This value is unsafe, because it leaks origins and paths from TLS-protected resources to insecure origins.",
                },
            }),
        },
        .desc = "A string indicating which referrer to use when fetching the resource.",
    };
};

// A valid navigable target name is any string with at least one character that
// does not contain both an ASCII tab or newline and a U+003C (<), and it does
// not start with a U+005F (_). (Names starting with a U+005F (_) are reserved
// for special keywords.)
// A valid navigable target name or keyword is any string that is either a valid
// navigable target name or that is an ASCII case-insensitive match for one of:
// _blank, _self, _parent, or _top.

fn checkNavigableName(value: []const u8) ?Attribute.Rule.ValueRejection {
    if (value.len == 0) return .{};

    if (value[0] == '_') return .{
        .reason = "reserved for special keywords, did you mistype?",
        .offset = 0,
    };

    if (std.mem.indexOfAny(u8, value, "\t\n<")) |idx| return .{
        .reason = "invalid character in navigable target name",
        .offset = @intCast(idx),
    };

    return null;
}

pub fn parseUri(src: []const u8) !std.Uri {
    const end = for (src, 0..) |byte, i| {
        if (!isSchemeChar(byte)) break i;
    } else src.len;
    // After the scheme, a ':' must appear.
    if (end >= src.len or src[end] != ':') {
        return std.Uri.parseAfterScheme("", src);
    } else {
        return std.Uri.parseAfterScheme(src[0..end], src[end + 1 ..]);
    }
}
fn isSchemeChar(c: u8) bool {
    return switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9', '+', '-', '.' => true,
        else => false,
    };
}
