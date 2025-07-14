const Ast = @This();

const std = @import("std");
const builtin = @import("builtin");
const html = @import("html.zig");
const HtmlNode = html.Ast.Node;
const Span = @import("root.zig").Span;
const Writer = std.Io.Writer;

const log = std.log.scoped(.ast);

src: []const u8,
extends_idx: u32,
interface: std.StringArrayHashMapUnmanaged(u32),
blocks: std.StringHashMapUnmanaged(u32),
nodes: []const Node,
errors: []const Error,

const Error = struct {
    kind: union(enum) {
        bad_attr,
        else_must_be_first_attr,
        missing_attribute_value,
        loop_no_value,
        block_cannot_be_inlined,
        block_missing_id,
        already_branching,
        id_under_loop,
        extend_without_template_attr,
        top_level_super,
        super_wants_no_attributes,
        block_with_scripted_id,
        super_parent_element_missing_id,
        template_interface_id_collision,
        missing_template_value,
        unexpected_extend,
        unscripted_attr,
        two_supers_one_id,
        super_under_branching,

        one_branching_attribute_per_element,
        ctx_attrs_must_be_scripted,
        else_with_value,
        no_ifs_after_loop,
        text_and_html_are_mutually_exclusive,
        text_and_html_require_an_empty_element,
        duplicate_block: Span,
    },

    main_location: Span,
};

pub const SpecialAttr = enum {
    @":if",
    @":loop",
    @":else",
    @":text",
    @":html",
};

pub const Node = struct {
    kind: Kind = .element,
    elem_idx: u32,
    depth: u32,
    parent_idx: u32 = 0,
    first_child_idx: u32 = 0,
    next_idx: u32 = 0,

    id_template_parentid: ?html.Tokenizer.Attr = null,
    html_text: ?html.Tokenizer.Attr = null,
    if_loop: ?html.Tokenizer.Attr = null,

    const Kind = enum {
        root,
        extend,
        super,
        ctx,
        block,
        super_block,
        element,
    };

    pub fn elem(node: Node, html_ast: html.Ast) HtmlNode {
        return html_ast.nodes[node.elem_idx];
    }

    pub fn idAttr(node: Node) ?html.Tokenizer.Attr {
        std.debug.assert(switch (node.kind) {
            .block, .super_block, .element => true,
            else => false,
        });

        return node.id_template_parentid;
    }

    pub fn blockId(node: Node) html.Tokenizer.Attr.Value {
        std.debug.assert(node.kind == .block);
        return node.id_template_parentid.?.value.?;
    }

    pub fn templateAttr(node: Node) html.Tokenizer.Attr {
        std.debug.assert(switch (node.kind) {
            .extend => true,
            else => false,
        });
        return node.id_template_parentid.?;
    }
    pub fn templateValue(node: Node) html.Tokenizer.Attr.Value {
        return node.templateAttr().value.?;
    }

    pub fn debugName(node: Node, src: []const u8) []const u8 {
        return node.elem.startTag().name().string(src);
    }

    pub const Block = struct {
        parent_tag_name: Span,
        id_value: html.Tokenizer.Attr.Value,
    };

    pub fn superBlock(node: Node, src: []const u8, html_ast: html.Ast) Block {
        std.debug.assert(node.kind == .super);
        const id_value = node.id_template_parentid.?.value.?;
        const elem_idx = node.elem(html_ast).parent_idx;
        const par = html_ast.nodes[elem_idx];

        const it = par.startTagIterator(src, html_ast.language);

        return .{
            .parent_tag_name = it.name_span,
            .id_value = id_value,
        };
    }

    pub fn debug(
        node: *const Node,
        src: []const u8,
        html_ast: html.Ast,
        ast: Ast,
    ) void {
        std.debug.print("\n\n-- DEBUG --\n", .{});
        var stderr = std.fs.File.stderr().writer(&.{});
        node.debugInternal(
            src,
            html_ast,
            ast,
            &stderr.interface,
            0,
        ) catch unreachable;
    }

    // Allows passing in a writer, useful for tests
    pub fn debugWriter(
        node: *const Node,
        src: []const u8,
        html_ast: html.Ast,
        ast: Ast,
        w: *Writer,
    ) void {
        node.debugInternal(src, html_ast, ast, w, 0) catch unreachable;
    }

    fn hasId(node: Node) ?html.Tokenizer.Attr {
        switch (node.kind) {
            .block, .super_block, .element => return node.idAttr(),
            else => return null,
        }
    }

    fn debugInternal(
        node: Node,
        src: []const u8,
        html_ast: html.Ast,
        ast: Ast,
        w: *Writer,
        lvl: usize,
    ) !void {
        for (0..lvl) |_| try w.print("    ", .{});
        try w.print("({t} {}", .{ node.kind, node.depth });

        if (node.hasId()) |id| {
            try w.print(" #{s}", .{id.value.?.span.slice(src)});
        } else if (node.kind == .extend) {
            try w.print(" {s}", .{node.templateAttr().span().slice(src)});
        } else if (node.kind == .super) {
            try w.print(" ->#{s}", .{
                node.superBlock(src, html_ast).id_value.span.slice(src),
            });
        }

        if (ast.child(node)) |ch| {
            // std.debug.assert( ch.parent == node);
            try w.print("\n", .{});
            try ch.debugInternal(src, html_ast, ast, w, lvl + 1);
            for (0..lvl) |_| try w.print("    ", .{});
        }
        try w.print(")\n", .{});

        if (ast.next(node)) |sibling| {
            // std.debug.assert( sibling.prev == node);
            // std.debug.assert( sibling.parent == node.parent);
            try sibling.debugInternal(src, html_ast, ast, w, lvl);
        }
    }
};

pub fn at(ast: Ast, idx: u32) ?Node {
    if (idx == 0) return null;
    return ast.nodes[idx];
}

pub fn child(ast: Ast, n: Node) ?Node {
    return ast.at(n.first_child_idx);
}

pub fn next(ast: Ast, n: Node) ?Node {
    return ast.at(n.next_idx);
}

pub fn parent(ast: Ast, n: Node) Node {
    std.debug.assert(n.kind != .root);
    return ast.nodes[n.parent_idx];
}

pub fn cursor(ast: Ast, idx: u32) Cursor {
    return Cursor.init(ast, idx);
}

pub fn childrenCount(ast: Ast, node: Node) usize {
    var count: usize = 0;
    var maybe_child = ast.child(node);
    while (maybe_child) |ch| : (maybe_child = ast.next(ch)) count += 1;
    return count;
}

pub fn deinit(ast: Ast, gpa: std.mem.Allocator) void {
    @constCast(&ast).interface.deinit(gpa);
    @constCast(&ast).blocks.deinit(gpa);
    gpa.free(ast.nodes);
    gpa.free(ast.errors);
}

pub fn init(
    gpa: std.mem.Allocator,
    html_ast: html.Ast,
    src: []const u8,
) error{OutOfMemory}!Ast {
    std.debug.assert(
        html_ast.language == .superhtml or
            html_ast.language == .xml,
    );

    var p: Parser = .{
        .src = src,
        .html = html_ast,
    };
    errdefer p.deinit(gpa);

    try p.nodes.append(gpa, .{ .kind = .root, .elem_idx = 0, .depth = 0 });

    var cur = p.html.cursor(0);
    var node_idx: u32 = 0;
    var low_mark: u32 = 1;
    var seen_non_comment_elems = false;
    while (cur.next()) |html_node| {
        const html_node_idx = cur.idx;
        const depth = cur.depth;

        switch (html_node.kind) {
            .element,
            .element_void,
            .element_self_closing,
            => {},
            else => continue,
        }

        defer seen_non_comment_elems = true;

        // Ensure that node always points at a node not more deeply nested
        // than our current html_node.
        if (low_mark > depth) low_mark = depth;

        {
            var node = p.nodes.items[node_idx];
            while (p.parent(node)) |par| {
                if (low_mark > par.depth) break;
                node_idx = node.parent_idx;
                node = par;
            }
        }

        // WARNING: will potentially invalidate pointers to nodes
        const new_node = try p.buildNode(
            gpa,
            html_node_idx,
            depth,
            seen_non_comment_elems,
        ) orelse continue;
        const new_node_idx: u32 = @intCast(p.nodes.items.len - 1);

        // Interface and block mode
        switch (new_node.kind) {
            .root, .super_block => unreachable,
            .super, .element, .ctx => {},
            .extend => {
                // sets block mode
                std.debug.assert(p.extends_idx == 0);
                std.debug.assert(new_node_idx == 1);

                p.extends_idx = new_node_idx;
            },
            .block => {
                const id_value = new_node.blockId();
                const gop = try p.blocks.getOrPut(
                    gpa,
                    id_value.span.slice(src),
                );
                if (gop.found_existing) {
                    const other = p.at(gop.value_ptr.*).?.blockId().span;
                    try p.errors.append(gpa, .{
                        .kind = .{ .duplicate_block = other },
                        .main_location = id_value.span,
                    });
                    // self.reportError(
                    //     id_value.span,
                    //     "duplicate_block",
                    //     "DUPLICATE BLOCK DEFINITION",
                    //     \\When a template extends another, top level elements
                    //     \\are called "blocks" and define the value of a corresponding
                    //     \\<super/> tag in the extended template by having the
                    //     \\same id of the <super/> tag's parent container.
                    //     ,
                    // ) catch {};
                    // try self.diagnostic("note: previous definition:", other);
                }

                gop.value_ptr.* = new_node_idx;
            },
        }

        //ast

        // var html_node = new_node.elem.node;
        // var html_node_depth = new_node.depth;
        // var last_same_depth = true;
        // while (!html_node.eq(node.elem.node)) {
        //     last_same_depth = html_node_depth == node.depth;

        //     if (html_node.prev()) |p| {
        //         html_node = p;
        //         continue;
        //     }

        //     const html_parent = html_node.parent() orelse unreachable;
        //     html_node = html_parent;
        //     html_node_depth -= 1;
        // }

        const node = &p.nodes.items[node_idx];
        if (low_mark <= node.depth) {
            std.debug.assert(p.next(node.*) == null);
            node.next_idx = new_node_idx;
            new_node.parent_idx = node.parent_idx;
        } else {
            if (p.child(node.*)) |c| {
                var sibling = c;
                var sibling_idx = node.first_child_idx;
                while (p.next(sibling)) |n| {
                    sibling_idx = sibling.next_idx;
                    sibling = n;
                }
                sibling.next_idx = new_node_idx;
                new_node.parent_idx = node_idx;
            } else {
                node.first_child_idx = new_node_idx;
                new_node.parent_idx = node_idx;
            }
        }

        node_idx = new_node_idx;
        low_mark = new_node.depth + 1;
    }

    try p.validate(gpa);
    return .{
        .src = src,
        .nodes = try p.nodes.toOwnedSlice(gpa),
        .errors = try p.errors.toOwnedSlice(gpa),
        .interface = p.interface,
        .blocks = p.blocks,
        .extends_idx = p.extends_idx,
    };
}

pub fn root(ast: Ast) Node {
    return ast.nodes[0];
}

const Parser = struct {
    src: []const u8,
    html: html.Ast,
    nodes: std.ArrayListUnmanaged(Node) = .{},
    errors: std.ArrayListUnmanaged(Error) = .{},
    extends_idx: u32 = 0,
    interface: std.StringArrayHashMapUnmanaged(u32) = .{},
    blocks: std.StringHashMapUnmanaged(u32) = .{},

    pub fn deinit(p: *Parser, gpa: std.mem.Allocator) void {
        p.nodes.deinit(gpa);
        p.errors.deinit(gpa);
        p.interface.deinit(gpa);
        p.blocks.deinit(gpa);
    }

    fn at(p: Parser, idx: u32) ?Node {
        if (idx == 0) return null;
        return p.nodes.items[idx];
    }

    pub fn parent(p: Parser, node: Node) ?Node {
        return p.at(node.parent_idx);
    }

    pub fn child(p: Parser, node: Node) ?Node {
        return p.at(node.first_child_idx);
    }

    pub fn next(p: Parser, node: Node) ?Node {
        return p.at(node.next_idx);
    }

    fn buildNode(
        p: *Parser,
        gpa: std.mem.Allocator,
        elem_idx: u32,
        depth: u32,
        seen_non_comment_elems: bool,
    ) !?*Node {
        const elem = p.html.nodes[elem_idx];

        const block_mode = p.extends_idx != 0;
        var tmp_result: Node = .{
            .elem_idx = elem_idx,
            .depth = depth,
        };

        std.debug.assert(depth > 0);
        const block_context = block_mode and depth == 1;
        if (block_context) tmp_result.kind = .block;

        var start_it = elem.startTagIterator(p.src, p.html.language);
        const tag_name = start_it.name_span;

        // is it a special tag
        {
            const tag_name_string = tag_name.slice(p.src);
            if (is(tag_name_string, "extend")) {
                tmp_result.kind = switch (tmp_result.kind) {
                    else => unreachable,
                    .element => .extend,
                    .block => blk: {
                        // this is an error, but we're going to let it through
                        // in order to report it as a duplicate extend tag error.
                        break :blk .extend;
                    },
                };

                // validation
                {
                    const parent_isnt_root = elem.parent_idx != 0;

                    if (parent_isnt_root or seen_non_comment_elems) {
                        try p.errors.append(gpa, .{
                            .kind = .unexpected_extend,
                            .main_location = tag_name,
                        });
                        return null;
                        // return p.reportError(
                        //     tag_name,
                        //     "unexpected_extend",
                        //     "UNEXPECTED EXTEND TAG",
                        //     \\The <extend> tag can only be present at the beginning of a
                        //     \\template and it can only be preceded by HTML comments and
                        //     \\whitespace.
                        //     ,
                        // );
                    }

                    const template_attr = start_it.next(p.src) orelse {
                        try p.errors.append(gpa, .{
                            .kind = .extend_without_template_attr,
                            .main_location = tag_name,
                        });
                        return null;
                    };

                    if (!is(template_attr.name.slice(p.src), "template")) {
                        try p.errors.append(gpa, .{
                            .kind = .extend_without_template_attr,
                            .main_location = tag_name,
                        });
                        try p.errors.append(gpa, .{
                            .kind = .bad_attr,
                            .main_location = template_attr.name,
                        });
                        return null;
                    }

                    const template = template_attr.value orelse {
                        try p.errors.append(gpa, .{
                            .kind = .missing_template_value,
                            .main_location = template_attr.name,
                        });
                        return null;
                    };

                    // TODO: more validation about this template value?
                    _ = template;

                    tmp_result.id_template_parentid = template_attr;

                    if (start_it.next(p.src)) |a| {
                        try p.errors.append(gpa, .{
                            .kind = .bad_attr,
                            .main_location = a.name,
                        });
                        return null;
                    }

                    const new_node = try p.nodes.addOne(gpa);
                    new_node.* = tmp_result;
                    return new_node;
                }
            } else if (is(tag_name_string, "super")) {
                tmp_result.kind = switch (tmp_result.kind) {
                    else => unreachable,
                    .element => .super,
                    .block => {
                        try p.errors.append(gpa, .{
                            .kind = .top_level_super,
                            .main_location = tag_name,
                        });
                        return null;
                        // return p.reportError(
                        //     tag_name,
                        //     "bad_super_tag",
                        //     "TOP LEVEL <SUPER/>",
                        //     \\This template extends another template and as such it
                        //     \\must only have block definitions at the top level.
                        //     \\
                        //     \\You *can* use <super/>, but it must be nested in a block.
                        //     \\Using <super/> will make this template extendable in turn.
                        //     ,
                        // );
                    },
                };

                while (start_it.next(p.src)) |a| {
                    try p.errors.append(gpa, .{
                        .kind = .super_wants_no_attributes,
                        .main_location = a.span(),
                    });
                }

                //The immediate parent must have an id
                const pr = p.html.parent(tmp_result.elem(p.html)) orelse {
                    try p.errors.append(gpa, .{
                        .kind = .top_level_super,
                        .main_location = tag_name,
                    });
                    return null;
                };

                var parent_start_it = pr.startTagIterator(p.src, p.html.language);
                while (parent_start_it.next(p.src)) |attr| {
                    if (is(attr.name.slice(p.src), "id")) {
                        const value = attr.value orelse return null;
                        const gop = try p.interface.getOrPut(
                            gpa,
                            value.span.slice(p.src),
                        );
                        if (gop.found_existing) {
                            try p.errors.append(gpa, .{
                                .kind = .template_interface_id_collision,
                                .main_location = value.span,
                            });
                        }

                        tmp_result.id_template_parentid = attr;

                        const new_node = try p.nodes.addOne(gpa);
                        new_node.* = tmp_result;
                        gop.value_ptr.* = @intCast(p.nodes.items.len - 1);
                        return new_node;
                    }
                } else {
                    try p.errors.append(gpa, .{
                        .kind = .super_parent_element_missing_id,
                        .main_location = parent_start_it.name_span,
                    });
                    return null;
                    // p.reportError(
                    //     tag_name,
                    //     "super_block_missing_id",
                    //     "<SUPER/> BLOCK HAS NO ID",
                    //     \\The <super/> tag must exist directly under an element
                    //     \\that specifies an `id` attribute.
                    //     ,
                    // ) catch {};
                    // try p.diagnostic(
                    //     "note: the parent element:",
                    //     parent_start_tag.name_span,
                    // );
                    // return error.Fatal;
                }
            } else if (is(tag_name_string, "ctx")) {
                tmp_result.kind = .ctx;
            }
        }

        std.debug.assert(switch (tmp_result.kind) {
            else => true,
            .root, .extend, .super_block, .super => false,
        });

        var has_attr_text_html = false;
        var has_attr_if = false;
        var has_attr_loop = false;
        var has_attr_else = false;
        var has_attr_scripted = false;
        var has_attr_id = false;
        var last_attr_end = tag_name.end;

        while (start_it.next(p.src)) |attr| : (last_attr_end = attr.span().end) {
            const name = attr.name;
            const name_string = name.slice(p.src);

            const special_attr = std.meta.stringToEnum(SpecialAttr, name_string) orelse {
                const is_id = is(name_string, "id");
                if (is_id) {
                    tmp_result.id_template_parentid = attr;
                    has_attr_id = true;
                }

                // normal attribute
                if (attr.value) |value| {
                    // TODO: implement unescape
                    // const code = try value.unescape(gpa, p.src);
                    const code = value.span.slice(p.src);

                    if (std.mem.startsWith(u8, code, "$")) {
                        has_attr_scripted = true;
                        if (is_id and tmp_result.kind == .block) {
                            try p.errors.append(gpa, .{
                                .kind = .block_with_scripted_id,
                                .main_location = value.span,
                            });
                        }
                    } else {
                        if (tmp_result.kind == .ctx) {
                            try p.errors.append(gpa, .{
                                .kind = .ctx_attrs_must_be_scripted,
                                .main_location = name,
                            });
                        }
                    }
                } else {
                    if (is_id) {
                        try p.errors.append(gpa, .{
                            .kind = .missing_attribute_value,
                            .main_location = name,
                        });
                    }
                    if (tmp_result.kind == .ctx) {
                        try p.errors.append(gpa, .{
                            .kind = .ctx_attrs_must_be_scripted,
                            .main_location = name,
                        });
                    }
                }

                continue;
            };

            if (special_attr == .@":else") {
                has_attr_else = true;

                if (last_attr_end != tag_name.end) {
                    try p.errors.append(gpa, .{
                        .kind = .else_must_be_first_attr,
                        .main_location = name,
                    });
                }

                if (attr.value != null) {
                    try p.errors.append(gpa, .{
                        .kind = .else_with_value,
                        .main_location = name,
                    });
                }
                continue;
            }

            if (attr.value == null) {
                try p.errors.append(gpa, .{
                    .kind = .missing_attribute_value,
                    .main_location = name,
                });
                return null;
            }

            const code = if (attr.value) |v|
                v.span.slice(p.src)
            else blk: {
                try p.errors.append(gpa, .{
                    .kind = .missing_attribute_value,
                    .main_location = name,
                });
                break :blk "";
            };

            if (code.len > 0 and
                std.mem.indexOfScalar(u8, code, '$') == null)
            {
                try p.errors.append(gpa, .{
                    .kind = .unscripted_attr,
                    .main_location = name,
                });
            }

            switch (special_attr) {
                .@":text", .@":html" => {
                    if (has_attr_text_html) {
                        try p.errors.append(gpa, .{
                            .kind = .text_and_html_are_mutually_exclusive,
                            .main_location = attr.name,
                        });
                    }
                    if (elem.first_child_idx != 0) {
                        try p.errors.append(gpa, .{
                            .kind = .text_and_html_require_an_empty_element,
                            .main_location = attr.name,
                        });
                    }
                    has_attr_text_html = true;
                    tmp_result.html_text = attr;
                },
                .@":if" => {
                    if (has_attr_loop) {
                        try p.errors.append(gpa, .{
                            .kind = .one_branching_attribute_per_element,
                            .main_location = attr.name,
                        });
                    }
                    has_attr_if = true;
                    tmp_result.if_loop = attr;
                },
                .@":loop" => {
                    if (has_attr_if) {
                        try p.errors.append(gpa, .{
                            .kind = .one_branching_attribute_per_element,
                            .main_location = attr.name,
                        });
                    }
                    has_attr_loop = true;
                    tmp_result.if_loop = attr;
                },
                .@":else" => unreachable,
            }
        }

        if (tmp_result.kind == .element) {
            if (!has_attr_if and
                !has_attr_loop and
                !has_attr_else and
                !has_attr_text_html and
                !has_attr_scripted)
            {
                return null;
            }
        }

        if (tmp_result.kind == .block and !has_attr_id) {
            try p.errors.append(gpa, .{
                .kind = .block_missing_id,
                .main_location = tag_name,
            });
            return null;
            // const name = tmp_result.elem(p.html).startTag(p.src).name_span;
            // return p.reportError(
            //     name,
            //     "block_missing_id",
            //     "BLOCK MISSING ID ATTRIBUTE",
            //     \\When a template extends another template, all top level
            //     \\elements must specify an `id` that matches with a corresponding
            //     \\super block (i.e. the element parent of a <super/> tag in
            //     \\the extended template).
            //     ,
            // );
        }

        const new_node = try p.nodes.addOne(gpa);
        new_node.* = tmp_result;
        return new_node;
    }

    fn validate(p: *Parser, gpa: std.mem.Allocator) !void {
        var ast: Ast = undefined;
        ast.nodes = p.nodes.items;
        var c = ast.cursor(0);
        while (c.next()) |ev| {
            if (ev.dir == .exit) continue;
            const node = ev.node;
            switch (node.kind) {
                .root => unreachable,
                .ctx => {},
                .element => {
                    // element with an unscripted id cannot be directly under
                    // a loop, as that guarantees that duplicated ids will be
                    // generated. we stop if we find `if` branching because,
                    // even if risky, the user might have handled the situation
                    // properly (eg by only printing the id element on
                    // $loop.first)
                    if (node.idAttr()) |id| blk: {
                        const value = id.value orelse break :blk;
                        if (std.mem.startsWith(u8, value.span.slice(p.src), "$")) {
                            break :blk;
                        }

                        var upper = ast.parent(node);
                        while (upper.kind != .root) : (upper = ast.parent(upper)) {
                            const attr = upper.if_loop orelse continue;
                            if (attr.name.len() == ":if".len) break;
                            try p.errors.append(gpa, .{
                                .kind = .id_under_loop,
                                .main_location = id.name,
                            });
                            // todo: add note location
                            break;
                        }
                    }
                },
                .extend => {
                    // if present, <extend> must be the first tag in the document
                    // (validated on creation)
                },
                .block => {
                    // blocks must have an id
                    // (validated on creation)

                    // blocks must be at depth = 1
                    // (validated on creation)

                    // blocks must not be under branching
                    // (validated by the .super branch)
                },

                .super_block => {
                    // must have an id
                    // (validated on creation)

                    // must have a <super> inside
                    // (validated when creating the <super> node)
                },
                .super => {
                    // <super> must have super_block right above
                    // (validated on creation)

                    // only one <super> per block
                    // we scan downwards to avoid duplicate errors
                    var sibling_idx = node.next_idx;
                    while (sibling_idx != 0) {
                        const sibling = ast.at(sibling_idx).?;
                        sibling_idx = sibling.next_idx;

                        if (sibling.kind == .super) {
                            const p1 = node.elem(p.html).parent_idx;
                            const p2 = sibling.elem(p.html).parent_idx;
                            if (p1 != p2) continue;

                            try p.errors.append(gpa, .{
                                .kind = .two_supers_one_id,
                                .main_location = sibling.elem(p.html).open,
                            });
                            // todo: add note location
                        }
                    }
                    // <super> can't be inside any subtree with branching in it
                    var upper = ast.parent(node);
                    while (upper.kind != .root) : (upper = ast.parent(upper)) {
                        if (upper.if_loop) |attr| {
                            try p.errors.append(gpa, .{
                                .kind = .super_under_branching,
                                .main_location = node.elem(p.html).open,
                            });
                            // todo: add note location
                            _ = attr;

                            // ast.reportError(node.elem(html_ast).open, "<SUPER> UNDER BRANCHING",
                            //     \\The <super> tag is used to define a static template
                            //     \\extension hierarchy, and as such should not be placed
                            //     \\inside of elements that feature branching logic.
                            // ) catch {};
                            // std.debug.print("note: branching happening here:\n", .{});
                            // ast.diagnostic(attr.name);
                            // return error.Reported;
                        }
                    }
                },
            }
        }

        // // nodes under a loop can't have ids
        // log.debug("before", .{});
        // if (node.kind.hasId()) {
        //     log.debug("here", .{});
        //     var maybe_parent = p.parent(node);
        //     while (maybe_parent) |par| : (maybe_parent = p.parent(par)) switch (par.kind.branching()) {
        //         else => {
        //             log.debug("testing '{s}'", .{
        //                 par.elem(p.html).open.slice(p.src),
        //             });
        //             continue;
        //         },
        //         .loop, .inloop => {
        //             try p.errors.append(gpa, .{
        //                 .kind = .id_under_loop,
        //                 .main_location = node.idAttr().name,
        //             });
        //             // p.reportError(
        //             //     node.idAttr().name,
        //             //     "id_under_loop",
        //             //     "ID UNDER LOOP",
        //             //     \\In a valid HTML document all `id` attributes must
        //             //     \\have unique values.
        //             //     \\
        //             //     \\Giving an `id` attribute to elements under a loop
        //             //     \\makes that impossible.
        //             //     ,
        //             // ) catch {};
        //             // try p.diagnostic("note: the loop:\n", p.loopAttr().attr.name);
        //             // return error.Fatal;
        //         },
        //     };
        // }

        // switch (node.kind.branching()) {
        //     else => {},
        //     // `inline-else` must be right after `if`
        //     .@"inline-else" => {
        //         // compute distance
        //         var distance: usize = 1;
        //         var html_node = if (node.prev) |p| blk: {
        //             break :blk if (p.kind.branching() == .@"if") p.elem.node.next() else null;
        //         } else null;

        //         while (html_node) |n| : (html_node = n.next()) {
        //             if (n.eq(node.elem.node)) break;
        //             distance += 1;
        //         } else {
        //             // either the previous node was not an if, or, if it was,
        //             // it did not connect to us.
        //             const name = node.if_else_loop.attr.name();
        //             return self.reportError(name, "LONELY ELSE",
        //                 \\Elements with an `else` attribute must come right after
        //                 \\an element with an `if` attribute. Make sure to nest them
        //                 \\correctly.
        //             );
        //         }
        //         // prev was set and it was an if node (html_node is set)
        //         if (distance > 1) {
        //             const name = node.if_else_loop.attr.name();
        //             self.reportError(name, "STRANDED ELSE",
        //                 \\Elements with an `else` attribute must come right after
        //                 \\an element with an `if` attribute. Make sure to nest them
        //                 \\correctly.
        //             ) catch {};
        //             std.debug.print("\nnote: potentially corresponding if: ", .{});
        //             self.diagnostic(name);

        //             if (distance == 2) {
        //                 std.debug.print("note: inbetween: ", .{});
        //             } else {
        //                 std.debug.print("note: inbetween (plus {} more): ", .{distance - 1});
        //             }
        //             const inbetween = html_node.?.toElement();
        //             const bad = if (inbetween) |e| e.startTag().name() else html_node.?;
        //             self.diagnostic(bad);
        //             return error.Reported;
        //         }
        //     },
        // }
    }
};

pub fn printInterfaceAsHtml(
    ast: Ast,
    html_ast: html.Ast,
    path: ?[]const u8,
    out: *Writer,
) !void {
    if (path) |p| {
        try out.print("<extend template=\"{s}\">\n", .{p});
    }
    var it = ast.interface.iterator();
    var at_least_one = false;
    while (it.next()) |kv| {
        at_least_one = true;
        const id = kv.key_ptr.*;
        const parent_idx = kv.value_ptr.*;
        const tag_name = ast.nodes[parent_idx].superBlock(
            ast.src,
            html_ast,
        ).parent_tag_name.slice(ast.src);
        try out.print("<{s} id=\"{s}\"></{s}>\n", .{
            tag_name,
            id,
            tag_name,
        });
    }

    if (!at_least_one) {
        try out.print(
            \\
            \\<!--
            \\The extended template has no interface!
            \\Add <super> tags to it to make it extensible.
            \\-->
            \\
        , .{});
    }
}

pub fn printErrors(
    ast: Ast,
    src: []const u8,
    path: ?[]const u8,
    w: *Writer,
) !void {
    for (ast.errors) |err| {
        const range = err.main_location.range(src);
        try w.print("{s}:{}:{}: {t}\n", .{
            path orelse "<stdin>",
            range.start.row,
            range.start.col,
            err.kind,
        });
    }
}

pub fn interfaceFormatter(
    ast: Ast,
    html_ast: html.Ast,
    path: ?[]const u8,
) Formatter {
    return .{ .ast = ast, .html = html_ast, .path = path };
}
const Formatter = struct {
    ast: Ast,
    html: html.Ast,
    path: ?[]const u8,

    pub fn format(f: Formatter, out_stream: *Writer) !void {
        try f.ast.printInterfaceAsHtml(f.html, f.path, out_stream);
    }
};

fn is(str1: []const u8, str2: []const u8) bool {
    return std.ascii.eqlIgnoreCase(str1, str2);
}

test "basics" {
    const case =
        \\<div>Hello World!</div>
    ;

    const html_ast = try html.Ast.init(
        std.testing.allocator,
        case,
        .superhtml,
    );
    defer html_ast.deinit(std.testing.allocator);
    const tree = try Ast.init(std.testing.allocator, html_ast, case);
    defer tree.deinit(std.testing.allocator);

    const r = tree.root();
    try std.testing.expectEqual(Node.Kind.root, r.kind);

    errdefer r.debug(case, html_ast, tree);

    try std.testing.expectEqual(0, r.parent_idx);
    try std.testing.expectEqual(0, r.next_idx);
    try std.testing.expectEqual(0, r.first_child_idx);
}

test "text/html - errors" {
    const cases =
        \\<div :text></div>
        \\<div :text="$page.content()" :else></div>
        \\<div :text="$page.content()" :if></div>
        \\<div :text="$page.content()" :loop></div>
        \\<div :text="$page.content()" :text></div>
        \\<div :text="$page.content()" :html></div>
        \\<div :html="$page.content()" :html></div>
        \\<div :html="$page.content()" :text></div>
        \\<div :text="not scripted"></div>
        \\<div :html="not scripted"></div>
    ;

    var it = std.mem.tokenizeScalar(u8, cases, '\n');
    while (it.next()) |case| {
        const html_ast = try html.Ast.init(
            std.testing.allocator,
            case,
            .superhtml,
        );
        defer html_ast.deinit(std.testing.allocator);
        const tree = try Ast.init(std.testing.allocator, html_ast, case);
        defer tree.deinit(std.testing.allocator);

        errdefer std.debug.print("--- CASE ---\n{s}\n", .{case});
        try std.testing.expect(tree.errors.len > 0);
    }
}

test "siblings" {
    const case =
        \\<div>
        \\  Hello World!
        \\  <span :if="$foo"></span>
        \\  <p :text="$bar"></p>
        \\</div>
    ;
    errdefer std.debug.print("--- CASE ---\n{s}\n", .{case});

    const html_ast = try html.Ast.init(
        std.testing.allocator,
        case,
        .superhtml,
    );
    defer html_ast.deinit(std.testing.allocator);
    const tree = try Ast.init(std.testing.allocator, html_ast, case);
    defer tree.deinit(std.testing.allocator);

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    tree.root().debugWriter(case, html_ast, tree, &out.writer);

    const ex =
        \\(root 0
        \\    (element 2)
        \\    (element 2)
        \\)
        \\
    ;
    try std.testing.expectEqualStrings(ex, out.getWritten());
}

test "nesting" {
    const case =
        \\<div :loop="$page.authors">
        \\  Hello World!
        \\  <span :if="$foo"></span>
        \\  <p :text="$bar"></p>
        \\</div>
    ;
    errdefer std.debug.print("--- CASE ---\n{s}\n", .{case});

    const html_ast = try html.Ast.init(
        std.testing.allocator,
        case,
        .superhtml,
    );
    defer html_ast.deinit(std.testing.allocator);
    const tree = try Ast.init(std.testing.allocator, html_ast, case);
    defer tree.deinit(std.testing.allocator);

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    tree.root().debugWriter(case, html_ast, tree, &out.writer);

    const ex =
        \\(root 0
        \\    (element 1
        \\        (element 2)
        \\        (element 2)
        \\    )
        \\)
        \\
    ;
    try std.testing.expectEqualStrings(ex, out.getWritten());
}

test "deeper nesting" {
    const case =
        \\<div :loop="$page.authors">
        \\  Hello World!
        \\  <span :if="$foo"></span>
        \\  <div><p :text="$bar"></p></div>
        \\</div>
    ;
    errdefer std.debug.print("--- CASE ---\n{s}\n", .{case});

    const html_ast = try html.Ast.init(
        std.testing.allocator,
        case,
        .superhtml,
    );
    defer html_ast.deinit(std.testing.allocator);
    const tree = try Ast.init(std.testing.allocator, html_ast, case);
    defer tree.deinit(std.testing.allocator);

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    tree.root().debugWriter(case, html_ast, tree, &out.writer);

    const ex =
        \\(root 0
        \\    (element 1
        \\        (element 2)
        \\        (element 3)
        \\    )
        \\)
        \\
    ;
    try std.testing.expectEqualStrings(ex, out.getWritten());
}

test "complex example" {
    const case =
        \\<div :if="$page.authors">
        \\  Hello World!
        \\  <span :if="$foo"></span>
        \\  <span :else>
        \\    <p :loop="foo" id="p-loop">
        \\      <span :text="$bar"></span>
        \\    </p>
        \\  </span>
        \\  <div><p id="last" :text="$bar"></p></div>
        \\</div>
    ;
    errdefer std.debug.print("--- CASE ---\n{s}\n", .{case});

    const html_ast = try html.Ast.init(
        std.testing.allocator,
        case,
        .superhtml,
    );
    defer html_ast.deinit(std.testing.allocator);
    const tree = try Ast.init(std.testing.allocator, html_ast, case);
    defer tree.deinit(std.testing.allocator);

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    const r = tree.root();
    r.debugWriter(case, html_ast, tree, &out.writer);

    const cex: usize = 3;
    try std.testing.expectEqual(cex, tree.childrenCount(tree.child(r).?));

    const ex =
        \\(root 0
        \\    (element 1
        \\        (element 2)
        \\        (element 2
        \\            (element 3 #p-loop
        \\                (element 4)
        \\            )
        \\        )
        \\        (element 3 #last)
        \\    )
        \\)
        \\
    ;
    try std.testing.expectEqualStrings(ex, out.getWritten());
}

test "if-else-loop errors" {
    const cases =
        \\<div :if></div>
        \\<div :if="arst"></div>
        \\<div :else="$foo"></div>
        \\<div :else="bar"></div>
        \\<div :else :if="bar"></div>
    ;

    var it = std.mem.tokenizeScalar(u8, cases, '\n');
    while (it.next()) |case| {
        const html_ast = try html.Ast.init(
            std.testing.allocator,
            case,
            .superhtml,
        );
        defer html_ast.deinit(std.testing.allocator);
        const tree = try Ast.init(std.testing.allocator, html_ast, case);
        defer tree.deinit(std.testing.allocator);

        errdefer std.debug.print("--- CASE ---\n{s}\n", .{case});
        try std.testing.expect(tree.errors.len > 0);
    }
}

test "super" {
    const case =
        \\<div :if="$page.authors">
        \\  Hello World!
        \\  <span>
        \\    <p :loop="$page.authors" id="p-loop">
        \\      <span :text="$loop.it.name"></span>
        \\      <super>
        \\    </p>
        \\  </span>
        \\  <div><p id="last" :text="$bar"></p></div>
        \\</div>
    ;
    errdefer std.debug.print("--- CASE ---\n{s}\n", .{case});

    const html_ast = try html.Ast.init(
        std.testing.allocator,
        case,
        .superhtml,
    );
    defer html_ast.deinit(std.testing.allocator);
    const tree = try Ast.init(std.testing.allocator, html_ast, case);
    defer tree.deinit(std.testing.allocator);

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    const r = tree.root();
    r.debugWriter(case, html_ast, tree, &out.writer);

    const ex =
        \\(root 0
        \\    (element 1
        \\        (element 3 #p-loop
        \\            (element 4)
        \\            (super 4 ->#p-loop)
        \\        )
        \\        (element 3 #last)
        \\    )
        \\)
        \\
    ;
    try std.testing.expectEqualStrings(ex, out.getWritten());

    const cex: usize = 2;
    try std.testing.expectEqual(cex, tree.childrenCount(tree.child(r).?));
}
// TODO: get rid of this once stack traces on arm64 work again
// fn assert(loc: std.builtin.SourceLocation, condition: bool) void {
//     if (!condition) {
//         std.debug.print("assertion error in {s} at {s}:{}:{}\n", .{
//             loc.fn_name,
//             loc.file,
//             loc.line,
//             loc.column,
//         });
//         std.process.exit(1);
//     }
// }

pub const Cursor = struct {
    cur: ?Event = null,
    ast: Ast,
    start_idx: u32,

    pub const Event = struct {
        dir: Dir,
        node: Node,
        idx: u32,
        pub const Dir = enum { enter, exit };
    };

    pub fn init(ast: Ast, idx: u32) Cursor {
        return .{
            .ast = ast,
            .start_idx = idx,
            .cur = .{
                .node = ast.nodes[idx],
                .idx = idx,
                .dir = .enter,
            },
        };
    }

    pub fn move(c: *Cursor, idx: u32) void {
        c.cur = .{
            .node = c.ast.nodes[idx],
            .idx = idx,
            .dir = .enter,
        };
    }

    pub fn current(c: Cursor) ?Event {
        return c.cur;
    }

    pub fn next(c: *Cursor) ?Event {
        const cur = c.cur orelse return null;
        switch (cur.dir) {
            .enter => {
                const ch = c.ast.child(cur.node) orelse {
                    c.cur.?.dir = .exit;
                    return c.cur;
                };

                c.cur.?.node = ch;
                c.cur.?.idx = cur.node.first_child_idx;
                return c.cur;
            },
            .exit => {
                if (c.start_idx == cur.idx) {
                    c.cur = null;
                    return null;
                }

                const n = c.ast.next(cur.node) orelse {
                    const _parent = c.ast.parent(cur.node);
                    c.cur.?.node = _parent;
                    c.cur.?.idx = cur.node.parent_idx;
                    return c.cur;
                };

                c.cur.?.node = n;
                c.cur.?.idx = cur.node.next_idx;
                c.cur.?.dir = .enter;
                return c.cur;
            },
        }
    }
};
