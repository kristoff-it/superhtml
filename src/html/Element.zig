const Element = @This();

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Language = root.Language;
const Span = root.Span;
const Ast = @import("Ast.zig");
const Error = Ast.Error;
const Kind = Ast.Kind;
const Tokenizer = @import("Tokenizer.zig");
const Attribute = @import("Attribute.zig");

const log = std.log.scoped(.element);

tag: Kind,

/// The static model of this element. Static means the combination of
/// categories and content model that the element has without any change
/// that could be caused by the presence/absence of attributes or nested
/// content.
model: Model,

/// Support information used for computing completions and deriving reasons
/// behind errors caused by non-static model changes.
meta: struct {
    categories_superset: Categories,
    content_reject: Categories = .none,
    extra_reject: Extra = .none,
},

/// Strings used to explain reasons behind errors caused by non-static model
/// changes.
reasons: Reasons = .{},

/// Attribute validation.
attributes: union(enum) {
    static,
    dynamic: *const fn (
        gpa: Allocator,
        errors: *std.ArrayListUnmanaged(Error),
        src: []const u8,
        node_idx: u32,
        parent_content: Categories,
        vait: *Attribute.ValidatingIterator,
    ) error{OutOfMemory}!Model,
},

/// Content validation and completions.
content: union(enum) {
    model,
    simple: Simple,
    custom: struct {
        validate: *const fn (
            gpa: Allocator,
            nodes: []const Ast.Node,
            errors: *std.ArrayListUnmanaged(Ast.Error),
            src: []const u8,
            parent_idx: u32,
        ) error{OutOfMemory}!void,
        completions: *const fn (
            arena: Allocator,
            ast: Ast,
            src: []const u8,
            parent_idx: u32,
            offset: u32, // cursor position
        ) error{OutOfMemory}![]const Ast.Completion,
    },
},

desc: []const u8,

const Simple = struct {
    // Allowed tags that are not part of the allowed categories.
    extra_children: []const Kind = &.{},
    // Frobidden tags that are part of the allowed categories.
    forbidden_children: []const Kind = &.{},
    // Frobidden tags that are part of the allowed categories,
    // applies to all descendants, not just direct children.
    forbidden_descendants: []const Kind = &.{},
    forbidden_descendants_extra: Extra = .none,
};

const Reasons = struct {
    categories: Reasons.Categories = .{},
    const Categories = struct {
        // metadata: []const u8 = "",
        // flow: []const u8 = "",
        // sectioning: []const u8 = "",
        // heading: []const u8 = "",
        // phrasing: []const u8 = "",
        // embedded: []const u8 = "",
        interactive: []const u8 = "",
    };
};

pub const CompletionMode = enum { content, attrs };

pub const Set = std.StaticStringMapWithEql(
    void,
    std.static_string_map.eqlAsciiIgnoreCase,
);

pub const Model = struct {
    categories: Categories,
    content: Categories,
    extra: Extra = .none,
};

pub const Extra = packed struct {
    // checked by `a`
    tabindex: bool = false,

    // set by img elements, used to validate source siblings
    autosizes_allowed: bool = false,

    pub const none: Extra = .{};

    const Tag = @typeInfo(Extra).@"struct".backing_integer.?;

    // TODO: remove once packed struct comparison works
    pub inline fn empty(e: Extra) bool {
        const int: Tag = @bitCast(e);
        return int == 0;
    }

    pub inline fn overlaps(lhs: Extra, rhs: Extra) bool {
        const l: Tag = @bitCast(lhs);
        const r: Tag = @bitCast(rhs);
        return (l & r) != 0;
    }

    pub inline fn intersect(lhs: Extra, rhs: Extra) Extra {
        const l: Tag = @bitCast(lhs);
        const r: Tag = @bitCast(rhs);
        return @bitCast(l & r);
    }
};

pub const Categories = packed struct {
    metadata: bool = false,
    flow: bool = false,
    sectioning: bool = false,
    heading: bool = false,
    phrasing: bool = false,
    embedded: bool = false,
    interactive: bool = false,

    pub const none: Categories = .{};

    pub const transparent: Categories = .all;
    pub const all: Categories = .{
        .metadata = true,
        .flow = true,
        .sectioning = true,
        .heading = true,
        .phrasing = true,
        .embedded = true,
        .interactive = true,
    };

    const Tag = @typeInfo(Categories).@"struct".backing_integer.?;

    // TODO: remove once packed struct comparison works
    pub inline fn empty(cs: Categories) bool {
        const int: Tag = @bitCast(cs);
        return int == 0;
    }

    pub inline fn overlaps(lhs: Categories, rhs: Categories) bool {
        const l: Tag = @bitCast(lhs);
        const r: Tag = @bitCast(rhs);
        return (l & r) != 0;
    }

    pub inline fn intersect(lhs: Categories, rhs: Categories) Categories {
        const l: Tag = @bitCast(lhs);
        const r: Tag = @bitCast(rhs);
        return @bitCast(l & r);
    }

    pub inline fn merge(lhs: Categories, rhs: Categories) Categories {
        const l: Tag = @bitCast(lhs);
        const r: Tag = @bitCast(rhs);
        return @bitCast(l | r);
    }

    pub inline fn has(cs: Categories, cat: std.meta.FieldEnum(Categories)) bool {
        return switch (cat) {
            inline else => |f| @field(cs, @tagName(f)),
        };
    }
};

pub const Rejection = struct {
    reason: []const u8,
    span: Span,
};
pub inline fn modelRejects(
    parent_element: *const Element,
    nodes: []const Ast.Node,
    src: []const u8,
    parent_node: Ast.Node,
    parent_span: Span,
    descendant_element: *const Element,
    descendant_rt_model: Model,
) ?Rejection {
    log.debug("========== modelRejects {t} > {t}", .{
        parent_element.tag,
        descendant_element.tag,
    });

    if (!parent_node.model.content.overlaps(descendant_rt_model.categories)) {
        // Check if the content model of the parent was changed because it's
        // transparent.
        log.debug("========== no content - categories overlap {t} > {t}", .{
            parent_element.tag,
            descendant_element.tag,
        });

        if (!parent_element.model.content.overlaps(descendant_rt_model.categories)) {
            log.debug("========== no static overlap {t} > {t}", .{
                parent_element.tag,
                descendant_element.tag,
            });
            return .{ .reason = "", .span = parent_span };
        }

        log.debug("========== yes static overlap {t} > {t}", .{
            parent_element.tag,
            descendant_element.tag,
        });

        var ancestor_idx = parent_node.parent_idx;
        while (ancestor_idx != 0) {
            const ancestor = nodes[ancestor_idx];
            ancestor_idx = ancestor.parent_idx;

            assert(ancestor.kind.isElement());
            assert(ancestor.kind != .___);
            const element = Element.all.get(ancestor.kind);
            if (!element.model.content.overlaps(descendant_rt_model.categories)) {
                return .{
                    .reason = "",
                    .span = ancestor.startTagIterator(src, .html).name_span,
                };
            }
        }

        log.debug("REACHED UNREACHABLE in modeleRejects", .{});
        unreachable;
    }

    if (parent_element.meta.content_reject.overlaps(descendant_rt_model.categories)) {
        const intersection = parent_element.meta.content_reject.intersect(
            descendant_rt_model.categories,
        );

        inline for (std.meta.fields(Categories)) |f| {
            if (@field(intersection, f.name) and @hasField(Reasons.Categories, f.name)) {
                // if this is not a runtime property, report it as the reason
                if (!@field(descendant_element.model.categories, f.name)) {
                    return .{
                        .reason = @field(descendant_element.reasons.categories, f.name),
                        .span = parent_span,
                    };
                }
            }
        }

        return .{ .reason = "", .span = parent_span };
    }

    if (parent_element.meta.extra_reject.tabindex and descendant_rt_model.extra.tabindex) {
        return .{
            .span = parent_span,
            .reason = "presence of tabindex attribute",
        };
    }

    return null;
}

pub inline fn validateContent(
    element: *const Element,
    gpa: Allocator,
    nodes: []const Ast.Node,
    errors: *std.ArrayListUnmanaged(Ast.Error),
    src: []const u8,
    parent_idx: u32,
) !void {
    assert(parent_idx != 0);

    content: switch (element.content) {
        .custom => |custom| try custom.validate(gpa, nodes, errors, src, parent_idx),
        .model => continue :content .{ .simple = .{} },
        .simple => |simple| {
            const parent = nodes[parent_idx];
            const parent_span = parent.startTagIterator(src, .html).name_span;
            assert(parent.kind.isElement());
            const parent_element = Element.all.get(parent.kind);
            const first_child_idx = nodes[parent_idx].first_child_idx;

            var child_idx = first_child_idx;
            outer: while (child_idx != 0) {
                const child = nodes[child_idx];
                defer child_idx = child.next_idx;

                assert(simple.extra_children.len < 10);
                for (simple.extra_children) |extra| {
                    if (child.kind == extra) continue :outer;
                }

                assert(simple.forbidden_children.len < 10);
                for (simple.forbidden_children) |forbidden| {
                    if (child.kind == forbidden) {
                        try errors.append(gpa, .{
                            .tag = .{
                                .invalid_nesting = .{
                                    .span = parent_span,
                                },
                            },
                            .main_location = child.startTagIterator(src, .html).name_span,
                            .node_idx = child_idx,
                        });
                        continue :outer;
                    }
                }

                if (parent_element.modelRejects(
                    nodes,
                    src,
                    parent,
                    parent_span,
                    &Element.all.get(child.kind),
                    child.model,
                )) |rejection| {
                    try errors.append(gpa, .{
                        .tag = .{
                            .invalid_nesting = .{
                                .span = rejection.span,
                                .reason = rejection.reason,
                            },
                        },
                        .main_location = child.startTagIterator(src, .html).name_span,
                        .node_idx = child_idx,
                    });
                }
                // if (!parent.model.content.overlaps(child.model.categories)) {
                //     // In case of transparent elements, the child might have
                //     // been rejected by an ancestor.

                //     const span: Span = blk: {
                //         var cur_node = parent;
                //         var cur_ele = element;
                //         while (true) {
                //             switch (cur_ele.model) {
                //                 .full => if (cur_ele == element) {
                //                     break :blk parent_span;
                //                 },
                //                 .partial => |partial| {
                //                     if (!partial.content_rejection_subset.overlaps(
                //                         child.model.categories,
                //                     )) {
                //                         assert(cur_node.parent_idx != 0);
                //                         cur_node = nodes[cur_node.parent_idx];
                //                         cur_ele = all.getPtrConst(cur_node.kind);
                //                     }
                //                 },
                //             }

                //             break :blk cur_node.startTagIterator(
                //                 src,
                //                 .html,
                //             ).name_span;
                //         }
                //     };

                //     try errors.append(gpa, .{
                //         .tag = .{
                //             .invalid_nesting = .{
                //                 .span = span,
                //             },
                //         },
                //         .main_location = child.startTagIterator(src, .html).name_span,
                //         .node_idx = child_idx,
                //     });
                // }
            }

            if (simple.forbidden_descendants.len == 0 and
                simple.forbidden_descendants_extra.empty())
            {
                return;
            }

            // check descendants
            if (first_child_idx == 0) return;
            const stop_idx = parent.stop(nodes);

            var next_idx = first_child_idx;
            outer: while (next_idx != stop_idx) {
                assert(next_idx != 0);

                const node_idx = next_idx;
                const node = nodes[node_idx];

                if (node.kind == .___) {
                    next_idx = node.stop(nodes);
                    continue;
                } else if (node.kind == .svg or node.kind == .math) {
                    next_idx = node.stop(nodes);
                } else {
                    next_idx += 1;
                }

                assert(simple.forbidden_descendants.len < 10);
                for (simple.forbidden_descendants) |forbidden| {
                    if (node.kind == forbidden) {
                        try errors.append(gpa, .{
                            .tag = .{
                                .invalid_nesting = .{
                                    .span = parent_span,
                                },
                            },
                            .main_location = node.startTagIterator(src, .html).name_span,
                            .node_idx = node_idx,
                        });
                        continue :outer;
                    }
                }

                if (simple.forbidden_descendants_extra.tabindex and
                    node.model.extra.tabindex)
                {
                    try errors.append(gpa, .{
                        .tag = .{
                            .invalid_nesting = .{
                                .span = parent_span,
                                .reason = "presence of 'tabindex' attribute",
                            },
                        },
                        .main_location = node.startTagIterator(src, .html).name_span,
                        .node_idx = node_idx,
                    });
                    continue :outer;
                }
            }
        },
    }
}

pub inline fn validateAttrs(
    element: *const Element,
    gpa: Allocator,
    lang: Language,
    errors: *std.ArrayListUnmanaged(Error),
    seen_attrs: *std.StringHashMapUnmanaged(Span),
    src: []const u8,
    parent_kind: Ast.Kind,
    parent_content: Categories,
    tag: Span,
    node_idx: u32,
) error{OutOfMemory}!Model {
    var vait: Attribute.ValidatingIterator = .init(
        errors,
        seen_attrs,
        lang,
        tag,
        src,
        node_idx,
    );

    return switch (element.attributes) {
        .dynamic => |validate| validate(gpa, errors, src, node_idx, parent_content, &vait),
        .static => blk: {
            const max_len = comptime max: {
                var max: u32 = 0;
                for (Attribute.element_attrs.values[@intFromEnum(Ast.Kind.___) + 1 ..]) |set| {
                    if (max < set.list.len) max = set.list.len;
                }
                break :max max;
            };

            const attrs_set = Attribute.element_attrs.get(element.tag);
            var seen_required: std.StaticBitSet(max_len) = .initEmpty();
            var tabindex = false;

            outer: while (try vait.next(gpa, src)) |attr| {
                const span = attr.name;
                const name = span.slice(src);

                const attr_model = model: {
                    if (attrs_set.index(name)) |idx| {
                        const model = attrs_set.list[idx].model;

                        if (model.only_under.len > 0) {
                            for (model.only_under) |ou| {
                                if (ou == parent_kind) break;
                            } else {
                                try errors.append(gpa, .{
                                    .tag = .{ .invalid_attr_nesting = parent_kind },
                                    .main_location = span,
                                    .node_idx = node_idx,
                                });
                                continue :outer;
                            }
                        }

                        if (model.required) seen_required.set(idx);

                        break :model model;
                    } else if (Attribute.global.index(name)) |idx| {
                        tabindex |= idx == Attribute.global.comptimeIndex("tabindex");
                        break :model Attribute.global.list[idx].model;
                    } else try errors.append(gpa, .{
                        .tag = .invalid_attr,
                        .main_location = span,
                        .node_idx = node_idx,
                    });
                    continue;
                };

                try attr_model.rule.validate(gpa, errors, src, node_idx, attr);
            }

            for (attrs_set.list, 0..) |named, idx| {
                if (named.model.required and !seen_required.isSet(idx)) {
                    if (named.model.only_under.len > 0) match: {
                        for (named.model.only_under) |ou| {
                            if (ou == parent_kind) break :match;
                        } else continue;
                    }

                    try errors.append(gpa, .{
                        .tag = .{
                            .missing_required_attr = named.name,
                        },
                        .main_location = vait.name,
                        .node_idx = node_idx,
                    });
                }
            }

            break :blk .{
                .content = element.model.content,
                .categories = element.model.categories,
                .extra = .{
                    .tabindex = tabindex,
                },
            };
        },
    };
}

pub inline fn completions(
    element: *const Element,
    arena: Allocator,
    ast: Ast,
    src: []const u8,
    node_idx: u32,
    offset: u32,
    mode: CompletionMode,
) ![]const Ast.Completion {
    switch (mode) {
        .attrs => {
            var stt = ast.nodes[node_idx].startTagIterator(src, ast.language);
            return Attribute.completions(
                arena,
                src,
                &stt,
                element.tag,
                offset,
            );
        },
        .content => content: switch (element.content) {
            .custom => |custom| return custom.completions(
                arena,
                ast,
                src,
                node_idx,
                offset,
            ),
            .model => continue :content .{ .simple = .{} },
            .simple => |simple| return simpleCompletions(
                arena,
                &.{},
                ast.nodes[node_idx].model.content,
                simple,
            ),
        },
    }
}

pub fn simpleCompletions(
    arena: Allocator,
    prefix: []const Ast.Kind,
    parent_content: Categories,
    simple: Simple,
) ![]const Ast.Completion {
    var list: std.ArrayListUnmanaged(Ast.Completion) = .empty;
    try list.ensureTotalCapacity(
        arena,
        all.values.len - @intFromEnum(Kind.___),
    );

    for (prefix) |p| list.appendAssumeCapacity(.{
        .label = @tagName(p),
        .desc = all.get(p).desc,
    });

    const start: usize = @intFromEnum(Kind.___) + 1;
    outer: for (all.values[start..], start..) |e, idx| {
        const child_kind: Kind = @enumFromInt(idx);

        for (prefix) |p| {
            if (p == child_kind) continue :outer;
        }

        for (simple.forbidden_children) |fc| {
            if (fc == child_kind) continue :outer;
        }

        for (simple.forbidden_descendants) |fd| {
            if (fd == child_kind) continue :outer;
        }

        const child_cs = e.meta.categories_superset;
        if (parent_content.overlaps(child_cs)) {
            list.appendAssumeCapacity(.{
                .label = @tagName(child_kind),
                .desc = e.desc,
            });
            continue :outer;
        }

        for (simple.extra_children) |ec| {
            if (ec == child_kind) {
                list.appendAssumeCapacity(.{
                    .label = @tagName(child_kind),
                    .desc = e.desc,
                });
                continue :outer;
            }
        }
    }

    return list.items;
}

const KindMap = std.StaticStringMapWithEql(
    Ast.Kind,
    std.static_string_map.eqlAsciiIgnoreCase,
);

pub const kinds: KindMap = blk: {
    const KV = struct { []const u8, Ast.Kind };
    var keys: []const KV = &.{};
    for (std.meta.fields(Ast.Kind)) |f| {
        keys = keys ++ &[_]KV{.{ f.name, @enumFromInt(f.value) }};
    }

    break :blk .initComptime(keys);
};

const temp: Element = .{
    .tag = .div,
    .model = .{
        .content = .all,
        .categories = .all,
    },
    .meta = .{
        .categories_superset = .all,
        .content_reject = .none,
        .extra_reject = .none,
    },
    .attributes = .static,
    .content = .{
        .simple = .{},
    },
    .desc = "#temporary element description#",
};

pub const all: std.EnumArray(Ast.Kind, Element) = .init(.{
    .root = temp,
    .doctype = temp,
    .comment = temp,
    .text = temp,
    .extend = temp,
    .super = temp,
    .ctx = temp,
    .___ = temp,
    .a = @import("elements/a.zig").a,
    .abbr = temp,
    .address = temp,
    .area = temp,
    .article = temp,
    .aside = temp,
    .audio = @import("elements/audio_video.zig").audio, // done
    .b = @import("elements/b.zig").b, // done
    .base = temp,
    .bdi = temp,
    .bdo = temp,
    .blockquote = temp,
    .body = temp,
    .br = temp,
    .button = @import("elements/button.zig").button,
    .canvas = temp,
    .caption = temp,
    .cite = temp,
    .code = temp,
    .col = temp,
    .colgroup = temp,
    .data = temp,
    .datalist = temp,
    .dd = temp,
    .del = temp,
    .details = temp,
    .dfn = @import("elements/dfn.zig").dfn, // done
    .dialog = temp,
    .div = temp,
    .dl = temp,
    .dt = temp,
    .em = @import("elements/em.zig").em, // done
    .embed = temp,
    .fencedframe = temp,
    .fieldset = temp,
    .figcaption = temp,
    .figure = temp,
    .footer = temp,
    .form = temp,
    .h1 = temp,
    .h2 = temp,
    .h3 = temp,
    .h4 = temp,
    .h5 = temp,
    .h6 = temp,
    .head = temp,
    .header = temp,
    .hgroup = temp,
    .hr = temp,
    .html = @import("elements/html.zig").html,
    .i = @import("elements/i.zig").i, // done
    .iframe = temp,
    .img = temp,
    .input = temp,
    .ins = temp,
    .kbd = temp,
    .label = temp,
    .legend = temp,
    .li = temp,
    .link = temp,
    .main = @import("elements/main.zig").main, // done
    .map = temp,
    .math = temp,
    .mark = temp,
    .menu = temp,
    .meta = temp,
    .meter = temp,
    .nav = temp,
    .noscript = temp,
    .object = temp,
    .ol = temp,
    .optgroup = temp,
    .option = temp,
    .output = temp,
    .p = @import("elements/p.zig").p, // done
    .picture = @import("elements/picture.zig").picture,
    .pre = temp,
    .progress = temp,
    .q = temp,
    .rp = temp,
    .rt = temp,
    .ruby = temp,
    .s = temp,
    .samp = temp,
    .script = temp,
    .search = temp,
    .section = temp,
    .select = .{
        .tag = .select,
        .model = .{
            .content = .all,
            .categories = .all,
        },
        .meta = .{
            .categories_superset = .all,
        },
        .attributes = .static,
        .content = .{
            .simple = .{},
        },
        .desc = "#temporary element description#",
    },
    .selectedcontent = .{
        .tag = .selectedcontent,
        .model = .{
            .content = .all,
            .categories = .{
                .phrasing = true,
            },
        },
        .meta = .{
            .categories_superset = .all,
        },
        .attributes = .static,
        .content = .{
            .simple = .{},
        },
        .desc = "#temporary element description#",
    },
    .slot = temp,
    .small = temp,
    .source = @import("elements/source.zig").source, // done
    .span = temp,
    .strong = temp,
    .style = temp,
    .sub = temp,
    .summary = temp,
    .sup = temp,
    .svg = temp,
    .table = temp,
    .tbody = temp,
    .td = temp,
    .template = temp,
    .textarea = temp,
    .tfoot = temp,
    .th = temp,
    .thead = temp,
    .time = temp,
    .title = temp,
    .tr = temp,
    .track = temp,
    .u = @import("elements/u.zig").u, // done
    .ul = temp,
    .@"var" = temp,
    .video = @import("elements/audio_video.zig").video, // done
    .wbr = temp,
});
