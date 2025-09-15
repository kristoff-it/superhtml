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
    /// Attribute validation will not be performed when adding the element to
    /// the AST. Used by:
    /// - `<source>`, validated by parent elements
    /// - `<optgroup>`, validated while validating children
    manual,
    static,
    /// Custom attribute validation. Has also access to the incomplete AST to
    /// navigate ancestry when necessary. Any constraint that requires knowledge
    /// of descendants must be evaluated in the content callback.
    /// NOTE: node_idx is not yet present in the AST, to navigate upwards use
    /// parent_idx directly.
    dynamic: *const fn (
        gpa: Allocator,
        errors: *std.ArrayListUnmanaged(Error),
        src: []const u8,
        nodes: []const Ast.Node,
        parent_idx: u32,
        node_idx: u32,
        vait: *Attribute.ValidatingIterator,
    ) error{OutOfMemory}!Model,
},

/// Content validation and completions.
content: union(enum) {
    model,
    anything,
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

pub const Simple = struct {
    // Allowed tags that are not part of the allowed categories.
    extra_children: []const Kind = &.{},
    // Frobidden tags that are part of the allowed categories.
    forbidden_children: []const Kind = &.{},
    // Frobidden tags that are part of the allowed categories,
    // applies to all descendants, not just direct children.
    forbidden_descendants: ?std.EnumSet(Kind) = null,
    forbidden_descendants_extra: Extra = .none,
};

const Reasons = struct {
    categories: Reasons.Categories = .{},
    const Categories = struct {
        // metadata: []const u8 = "",
        flow: Reason = .{},
        // sectioning: []const u8 = "",
        // heading: []const u8 = "",
        phrasing: Reason = .{},
        // embedded: []const u8 = "",
        interactive: Reason = .{},
    };

    const Reason = struct {
        reject: []const u8 = "",
        accept: []const u8 = "",
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
    phrasing: bool = false,
    text: bool = false,
    sectioning: bool = false,
    heading: bool = false,
    interactive: bool = false,
    // embedded: bool = false,

    pub const none: Categories = .{};
    pub const all: Categories = .{
        .metadata = true,
        .flow = true,
        .phrasing = true,
        .text = true,
        .sectioning = true,
        .heading = true,
        .interactive = true,
        // .embedded = true,
    };
    // Just for clarity
    pub const transparent: Categories = .all;

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
        log.debug("========== no content - categories overlap {t} > {t}", .{
            parent_element.tag,
            descendant_element.tag,
        });

        if (!parent_element.model.content.overlaps(descendant_rt_model.categories)) {
            log.debug("========== no static overlap {t} > {t}", .{
                parent_element.tag,
                descendant_element.tag,
            });

            const intersection = parent_node.model.content.intersect(
                descendant_element.meta.categories_superset,
            );

            inline for (std.meta.fields(Categories)) |f| {
                if (@field(intersection, f.name) and @hasField(Reasons.Categories, f.name)) {
                    // if this is not a runtime property, report it as the reason
                    if (!@field(descendant_element.model.categories, f.name)) {
                        return .{
                            .reason = @field(descendant_element.reasons.categories, f.name).accept,
                            .span = parent_span,
                        };
                    }
                }
            }

            return .{ .reason = "", .span = parent_span };
        }

        // Check if the content model of the parent was changed because it's
        // transparent.
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
                        .reason = @field(descendant_element.reasons.categories, f.name).reject,
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
    parent_element: *const Element,
    gpa: Allocator,
    nodes: []const Ast.Node,
    errors: *std.ArrayListUnmanaged(Ast.Error),
    src: []const u8,
    parent_idx: u32,
) !void {
    content: switch (parent_element.content) {
        .anything => {},
        .custom => |custom| try custom.validate(gpa, nodes, errors, src, parent_idx),
        .model => continue :content .{ .simple = .{} },
        .simple => |simple| {
            const parent = nodes[parent_idx];
            const parent_span = parent.startTagIterator(src, .html).name_span;
            assert(parent.kind.isElement());
            assert(parent.kind != .___);
            const first_child_idx = nodes[parent_idx].first_child_idx;

            var child_idx = first_child_idx;
            outer: while (child_idx != 0) {
                const child = nodes[child_idx];
                defer child_idx = child.next_idx;

                switch (child.kind) {
                    else => {},
                    .doctype => continue,
                    .comment => continue,
                    .text => {
                        if (!parent.model.content.flow and
                            !parent.model.content.phrasing and
                            !parent.model.content.text)
                        {
                            try errors.append(gpa, .{
                                .tag = .{
                                    .invalid_nesting = .{
                                        .span = parent_span,
                                    },
                                },
                                .main_location = child.open,
                                .node_idx = child_idx,
                            });
                        }

                        continue;
                    },
                }

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
                        .main_location = child.span(src),
                        .node_idx = child_idx,
                    });
                }
            }

            if (simple.forbidden_descendants == null and
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
                } else if (node.kind == .comment or node.kind == .text) {
                    next_idx += 1;
                    continue;
                } else {
                    next_idx += 1;
                }

                if (simple.forbidden_descendants) |forbidden| {
                    if (forbidden.contains(node.kind)) {
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
                                .reason = "presence of [tabindex]",
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
    nodes: []const Ast.Node,
    parent_idx: u32,
    src: []const u8,
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
        .manual => return element.model,
        .dynamic => |validate| validate(
            gpa,
            errors,
            src,
            nodes,
            parent_idx,
            node_idx,
            &vait,
        ),
        .static => blk: {
            // const max_len = comptime max: {
            //     var max: u32 = 0;
            //     for (Attribute.element_attrs.values[@intFromEnum(Ast.Kind.___) + 1 ..]) |set| {
            //         if (max < set.list.len) max = set.list.len;
            //     }
            //     break :max max;
            // };

            const attrs_set = Attribute.element_attrs.get(element.tag);
            var tabindex = false;

            while (try vait.next(gpa, src)) |attr| {
                const span = attr.name;
                const name = span.slice(src);

                const attr_model = model: {
                    if (attrs_set.index(name)) |idx| {
                        const model = attrs_set.list[idx].model;
                        break :model model;
                    } else if (Attribute.global.index(name)) |idx| {
                        tabindex |= idx == Attribute.global.comptimeIndex("tabindex");
                        break :model Attribute.global.list[idx].model;
                    } else {
                        if (Attribute.isData(name)) continue;
                        try errors.append(gpa, .{
                            .tag = .invalid_attr,
                            .main_location = span,
                            .node_idx = node_idx,
                        });
                    }
                    continue;
                };

                try attr_model.rule.validate(gpa, errors, src, node_idx, attr);
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
    const children = switch (mode) {
        .attrs => blk: {
            var stt = ast.nodes[node_idx].startTagIterator(src, ast.language);
            break :blk try Attribute.completions(
                arena,
                src,
                &stt,
                element.tag,
                offset,
            );
        },
        .content => content: switch (element.content) {
            .custom => |custom| try custom.completions(
                arena,
                ast,
                src,
                node_idx,
                offset,
            ),
            .model => continue :content .{ .simple = .{} },
            .simple => |simple| try simpleCompletions(
                arena,
                &.{},
                ast.nodes[node_idx].model.content,
                element.meta.content_reject,
                simple,
            ),
            .anything => blk: {
                const start: usize = @intFromEnum(Kind.___) + 1;
                const all_elems = all.values[start..];
                const anything: [all_elems.len]Ast.Completion = comptime a: {
                    var anything: [all_elems.len]Ast.Completion = undefined;
                    for (all_elems, &anything) |in, *out| out.* = .{
                        .label = @tagName(in.tag),
                        .desc = in.desc,
                    };
                    break :a anything;
                };

                break :blk &anything;
            },
        },
    };

    var result: std.ArrayList(Ast.Completion) = .empty;

    var ancestor_idx = node_idx;
    while (ancestor_idx != 0) {
        const ancestor = ast.nodes[ancestor_idx];
        if (!ancestor.isClosed()) {
            const name = ancestor.span(src).slice(src);
            const slashed = try std.fmt.allocPrint(arena, "/{s}", .{name});
            try result.append(arena, .{
                .label = slashed,
                .value = if (src[offset -| 1] == '/') name else slashed,
                .desc = "",
            });
            break;
        }
        ancestor_idx = ancestor.parent_idx;
    }

    try result.ensureTotalCapacityPrecise(arena, result.items.len + children.len);
    result.appendSliceAssumeCapacity(children);
    return result.items;
}

pub fn simpleCompletions(
    arena: Allocator,
    prefix: []const Ast.Kind,
    parent_content: Categories,
    parent_reject: Categories,
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

        if (simple.forbidden_descendants) |fd| {
            if (fd.contains(child_kind)) continue :outer;
        }

        if (parent_reject.overlaps(e.model.categories)) continue :outer;

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

pub const elements: KindMap = blk: {
    const fields = std.meta.fields(Ast.Kind)[8..];
    assert(std.mem.eql(u8, fields[0].name, "a"));

    const KV = struct { []const u8, Ast.Kind };
    var keys: []const KV = &.{};
    for (fields) |f| keys = keys ++ &[_]KV{.{
        f.name,
        @enumFromInt(f.value),
    }};

    break :blk .initComptime(keys);
};

const temp: Element = .{
    .tag = .div,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
        },
        .content = .all,
    },
    .meta = .{
        .categories_superset = .{
            .flow = true,
            .phrasing = true,
        },
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
    .root = @import("elements/root.zig").root,
    .doctype = undefined,
    .comment = undefined,
    .text = temp,
    .extend = @import("elements/extend.zig").extend, // done
    .super = temp,
    .ctx = temp,
    .___ = temp,
    .a = @import("elements/a.zig").a, // done
    .abbr = @import("elements/abbr.zig").abbr, // done
    .address = @import("elements/address.zig").address, // done
    .area = @import("elements/area.zig").area, // done
    .article = @import("elements/article.zig").article, // done
    .aside = @import("elements/aside.zig").aside, // done
    .audio = @import("elements/audio_video.zig").audio, // done
    .b = @import("elements/b.zig").b, // done
    .base = @import("elements/base.zig").base, // done
    .bdi = @import("elements/bdi.zig").bdi, // done
    .bdo = @import("elements/bdo.zig").bdo, // done
    .blockquote = @import("elements/blockquote.zig").blockquote, // done
    .body = @import("elements/body.zig").body, // done
    .br = @import("elements/br.zig").br, // done
    .button = @import("elements/button.zig").button, // done
    .canvas = @import("elements/canvas.zig").canvas, // done
    .caption = @import("elements/caption.zig").caption, // done
    .cite = @import("elements/cite.zig").cite, // done
    .code = @import("elements/code.zig").code, // done
    .col = @import("elements/col.zig").col, // done
    .colgroup = @import("elements/colgroup.zig").colgroup, // done
    .data = @import("elements/data.zig").data, // done
    .datalist = @import("elements/datalist.zig").datalist, // done
    .dd = @import("elements/dd.zig").dd, // done
    .del = @import("elements/ins_del.zig").del, // done
    .details = @import("elements/details.zig").details, // done
    .dfn = @import("elements/dfn.zig").dfn, // done
    .dialog = @import("elements/dialog.zig").dialog, // done
    .div = @import("elements/div.zig").div, // done
    .dl = @import("elements/dl.zig").dl, // done
    .dt = @import("elements/dt.zig").dt, // done
    .em = @import("elements/em.zig").em, // done
    .embed = @import("elements/embed.zig").embed, // done
    .fencedframe = @import("elements/fencedframe.zig").fencedframe, // done
    .fieldset = @import("elements/fieldset.zig").fieldset, // done
    .figcaption = @import("elements/figcaption.zig").figcaption, // done
    .figure = @import("elements/figure.zig").figure, // done
    .footer = @import("elements/footer.zig").footer, // done
    .form = @import("elements/form.zig").form, // done
    .h1 = @import("elements/h.zig").h1, // done
    .h2 = @import("elements/h.zig").h2, // done
    .h3 = @import("elements/h.zig").h3, // done
    .h4 = @import("elements/h.zig").h4, // done
    .h5 = @import("elements/h.zig").h5, // done
    .h6 = @import("elements/h.zig").h6, // done
    .head = @import("elements/head.zig").head, // done
    .header = @import("elements/header.zig").header, // done
    .hgroup = @import("elements/hgroup.zig").hgroup, // done
    .hr = @import("elements/hr.zig").hr, // done
    .html = @import("elements/html.zig").html, // done
    .i = @import("elements/i.zig").i, // done
    .iframe = @import("elements/iframe.zig").iframe, // done
    .img = @import("elements/img.zig").img, // done
    .input = @import("elements/input.zig").input, // done
    .ins = @import("elements/ins_del.zig").ins, // done
    .kbd = @import("elements/kbd.zig").kbd, //done
    .label = @import("elements/label.zig").label, //done
    .legend = @import("elements/legend.zig").legend, //done
    .li = @import("elements/li.zig").li, //done
    .link = @import("elements/link.zig").link, // done
    .main = @import("elements/main.zig").main, // done
    .map = @import("elements/map.zig").map, // done
    .math = @import("elements/math.zig").math, // done
    .mark = @import("elements/mark.zig").mark, // done
    .menu = @import("elements/menu.zig").menu, // done
    .meta = @import("elements/meta.zig").meta, // done
    .meter = @import("elements/meter.zig").meter, // done
    .nav = @import("elements/nav.zig").nav, // done
    .noscript = @import("elements/noscript.zig").noscript, // done
    .object = @import("elements/object.zig").object, // done
    .ol = @import("elements/ol.zig").ol, // done
    .optgroup = @import("elements/optgroup.zig").optgroup, // done
    .option = @import("elements/option.zig").option, // done
    .output = @import("elements/output.zig").output, // done
    .p = @import("elements/p.zig").p, // done
    .picture = @import("elements/picture.zig").picture, // done
    .pre = @import("elements/pre.zig").pre, // done
    .progress = @import("elements/progress.zig").progress, // done
    .q = @import("elements/q.zig").q, // done
    .rp = @import("elements/rp.zig").rp, // done
    .rt = @import("elements/rt.zig").rt, // done
    .ruby = @import("elements/ruby.zig").ruby, // done
    .s = @import("elements/s.zig").s, // done
    .samp = @import("elements/samp.zig").samp, // done
    .script = @import("elements/script.zig").script, // done
    .search = @import("elements/search.zig").search, // done
    .section = @import("elements/section.zig").section, // done
    .select = @import("elements/select.zig").select, // done
    .selectedcontent = @import("elements/selectedcontent.zig").selectedcontent, // done
    .slot = @import("elements/slot.zig").slot, // done
    .small = @import("elements/small.zig").small, // done
    .source = @import("elements/source.zig").source, // done
    .span = @import("elements/span.zig").span, // done
    .strong = @import("elements/strong.zig").strong, // done
    .style = @import("elements/style.zig").style, // done
    .sub = @import("elements/sub.zig").sub, // done
    .summary = @import("elements/summary.zig").summary, // done
    .sup = @import("elements/sup.zig").sup, // done
    .svg = @import("elements/svg.zig").svg, // done
    .table = @import("elements/table.zig").table, // done
    .tbody = @import("elements/tbody.zig").tbody, // done
    .td = @import("elements/td.zig").td, // done
    .template = @import("elements/template.zig").template, // done
    .textarea = @import("elements/textarea.zig").textarea, // done
    .tfoot = @import("elements/tfoot.zig").tfoot, // done
    .th = @import("elements/th.zig").th, // done
    .thead = @import("elements/thead.zig").thead, // done
    .time = @import("elements/time.zig").time, // done
    .title = @import("elements/title.zig").title, // done
    .tr = @import("elements/tr.zig").tr, // done
    .track = @import("elements/track.zig").track, // done
    .u = @import("elements/u.zig").u, // done
    .ul = @import("elements/ul.zig").ul, // done
    .@"var" = @import("elements/var.zig").@"var", // done
    .video = @import("elements/audio_video.zig").video, // done
    .wbr = @import("elements/wbr.zig").wbr, // done
});
