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

rule: Rule,
desc: []const u8,
required: bool = false,
only_under: []const Ast.Kind = &.{},

pub const Set = std.StaticStringMapWithEql(
    void,
    std.static_string_map.eqlAsciiIgnoreCase,
);

pub const Map = std.StaticStringMapWithEql(
    u32,
    std.static_string_map.eqlAsciiIgnoreCase,
);

pub const Rule = union(enum) {
    /// Presence of the attribute indicates true value, absence indicates
    /// false value, so no actual explicit value is allowed.
    bool,

    /// All values are fine, including no value at all
    any,

    /// All non-empty values, ignoring whitespace
    not_empty,

    /// CORS
    cors,

    /// MIME
    mime,

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

        pub const Extra = union(enum) {
            none,
            missing,
            missing_or_empty,
            custom: *const fn (value: []const u8) ?ValueRejection,
        };

        pub inline fn init(extra: Extra, cpls: []const Ast.Completion) @This() {
            assert(cpls.len > 0);
            return .{
                .extra = extra,
                .set = blk: {
                    var kvs: [cpls.len]struct { []const u8 } = undefined;
                    for (cpls, 0..) |c, idx| kvs[idx] = .{c.label};
                    break :blk .initComptime(kvs);
                },
                .completions = cpls,
            };
        }
    };

    const cors_list: List = .init(.missing_or_empty, &.{
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

                const value_slice = value.span.slice(src);
                if (value_slice.len == 0 and list.extra == .missing_or_empty) return;
                if (!list.set.has(value_slice)) {
                    if (list.extra == .custom) {
                        if (list.extra.custom(value_slice)) |rejection| {
                            return errors.append(gpa, .{
                                .tag = .{
                                    .invalid_attr_value = .{
                                        .reason = rejection.reason,
                                    },
                                },
                                .main_location = if (rejection.offset) |o| .{
                                    .start = value.span.start + o,
                                    .end = value.span.start + o + 1,
                                } else value.span,
                                .node_idx = node_idx,
                            });
                        }
                    } else return errors.append(gpa, .{
                        .tag = .{
                            .invalid_attr_value = .{},
                        },
                        .main_location = value.span,
                        .node_idx = node_idx,
                    });
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
                _ = std.Uri.parse(url) catch {
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
            else => @panic("TODO"),
        }
    }
};

fn validateMime(
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

        if (validateMimeChars(
            mime_type,
            node_idx,
            raw_value.span.start + spaces,
        )) |err| return errors.append(gpa, err);

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

    if (validateMimeChars(
        subtype,
        node_idx,
        @intCast(raw_value.span.start + spaces + slash_idx + 1),
    )) |err| return errors.append(gpa, err);

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

        if (validateMimeChars(
            param_name,
            node_idx,
            kv_offset,
        )) |err| return errors.append(gpa, err);

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

fn validateMimeChars(bytes: []const u8, node_idx: u32, offset: u32) ?Ast.Error {
    for (bytes, 0..) |c, idx| switch (c) {
        // zig fmt: off
        '!', '#', '$', '%', '&', '\'', '*',
        '+', '-', '.', '^', '_', '`', '|', '~',
        'a'...'z', '0'...'9', 'A'...'Z' => {},
        // zig fmt: on
        else => return .{
            .tag = .{
                .invalid_attr_value = .{
                    .reason = "invalid character in MIME value",
                },
            },
            .main_location = .{
                .start = @intCast(offset + idx),
                .end = @intCast(offset + idx + 1),
            },
            .node_idx = node_idx,
        },
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
    assert(offset > 0);
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
                if (value_content.len == 0) {
                    return switch (attr_model.rule) {
                        .cors => Rule.cors_list.completions,
                        .list => |l| l.completions,
                        else => &.{},
                    };
                }

                return &.{};
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

    const items = try arena.alloc(Ast.Completion, total_count - seen_count);
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

    assert(items_idx == items.len);
    return items;
}

const temp_set: *const AttributeSet = &.{
    .list = &.{},
    .map = .initComptime(.{}),
};
const empty_set: *const AttributeSet = &.{
    .list = &.{},
    .map = .initComptime(.{}),
};

const Named = struct { name: []const u8, model: Attribute };
pub const AttributeSet = struct {
    list: []const Named,
    map: Map,

    pub fn init(list: []const Named) AttributeSet {
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

    pub inline fn comptimeIndex(as: AttributeSet, name: []const u8) u32 {
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
    .extend = undefined,
    .super = undefined,
    .ctx = undefined,
    .___ = undefined,
    .a = &@import("elements/a.zig").attributes,
    .abbr = temp_set,
    .address = temp_set,
    .area = temp_set,
    .article = temp_set,
    .aside = temp_set,
    .audio = &@import("elements/audio_video.zig").attributes,
    .b = empty_set,
    .base = temp_set,
    .bdi = temp_set,
    .bdo = temp_set,
    .blockquote = temp_set,
    .body = temp_set,
    .br = temp_set,
    .button = &@import("elements/button.zig").attributes,
    .canvas = temp_set,
    .caption = temp_set,
    .cite = temp_set,
    .code = temp_set,
    .col = temp_set,
    .colgroup = temp_set,
    .data = temp_set,
    .datalist = temp_set,
    .dd = temp_set,
    .del = temp_set,
    .details = temp_set,
    .dfn = empty_set, // done
    .dialog = temp_set,
    .div = temp_set,
    .dl = temp_set,
    .dt = temp_set,
    .em = empty_set, // done
    .embed = temp_set,
    .fencedframe = temp_set,
    .fieldset = temp_set,
    .figcaption = temp_set,
    .figure = temp_set,
    .footer = temp_set,
    .form = temp_set,
    .h1 = temp_set,
    .h2 = temp_set,
    .h3 = temp_set,
    .h4 = temp_set,
    .h5 = temp_set,
    .h6 = temp_set,
    .head = temp_set,
    .header = temp_set,
    .hgroup = temp_set,
    .hr = temp_set,
    .html = empty_set,
    .i = empty_set, // done
    .iframe = temp_set,
    .img = temp_set,
    .input = temp_set,
    .ins = temp_set,
    .kbd = temp_set,
    .label = temp_set,
    .legend = temp_set,
    .li = temp_set,
    .link = temp_set,
    .main = empty_set, // done
    .map = temp_set,
    .math = temp_set,
    .mark = temp_set,
    .menu = temp_set,
    .meta = temp_set,
    .meter = temp_set,
    .nav = temp_set,
    .noscript = temp_set,
    .object = temp_set,
    .ol = temp_set,
    .optgroup = temp_set,
    .option = temp_set,
    .output = temp_set,
    .p = empty_set,
    .picture = temp_set,
    .pre = temp_set,
    .progress = temp_set,
    .q = temp_set,
    .rp = temp_set,
    .rt = temp_set,
    .ruby = temp_set,
    .s = temp_set,
    .samp = temp_set,
    .script = temp_set,
    .search = temp_set,
    .section = temp_set,
    .select = temp_set,
    .selectedcontent = temp_set,
    .slot = temp_set,
    .small = temp_set,
    .source = &@import("elements/source.zig").attributes,
    .span = temp_set,
    .strong = temp_set,
    .style = temp_set,
    .sub = temp_set,
    .summary = temp_set,
    .sup = temp_set,
    .svg = temp_set,
    .table = temp_set,
    .tbody = temp_set,
    .td = temp_set,
    .template = temp_set,
    .textarea = temp_set,
    .tfoot = temp_set,
    .th = temp_set,
    .thead = temp_set,
    .time = temp_set,
    .title = temp_set,
    .tr = temp_set,
    .track = temp_set,
    .u = empty_set,
    .ul = temp_set,
    .@"var" = temp_set,
    .video = &@import("elements/audio_video.zig").attributes,
    .wbr = temp_set,
});

const temp: Attribute = .{
    .rule = .any,
    .desc = "#temp global attribute#",
};

pub const global: AttributeSet = .init(&.{
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
                .list = .init(.none, &.{
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
            .desc = "TODO",
        },
    },

    .{ .name = "autocorrect", .model = temp },

    // https://html.spec.whatwg.org/multipage/interaction.html#attr-fe-autofocus
    .{
        .name = "autofocus",
        .model = .{
            .rule = .bool,
            .desc = "TODO",
        },
    },

    .{ .name = "contenteditable", .model = temp },
    .{ .name = "dir", .model = temp },
    .{ .name = "draggable", .model = temp },
    .{ .name = "enterkeyhint", .model = temp },
    .{ .name = "hidden", .model = temp },
    .{ .name = "inert", .model = temp },
    .{ .name = "inputmode", .model = temp },
    .{ .name = "is", .model = temp },
    .{ .name = "itemid", .model = temp },
    .{ .name = "itemprop", .model = temp },
    .{ .name = "itemref", .model = temp },
    .{ .name = "itemscope", .model = temp },
    .{ .name = "itemtype", .model = temp },
    .{ .name = "lang", .model = temp },
    .{ .name = "nonce", .model = temp },
    .{ .name = "popover", .model = temp },
    .{ .name = "spellcheck", .model = temp },
    .{ .name = "style", .model = temp },
    .{ .name = "tabindex", .model = temp },
    .{ .name = "title", .model = temp },
    .{ .name = "translate", .model = temp },
    .{ .name = "writingsuggestions", .model = temp },
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
