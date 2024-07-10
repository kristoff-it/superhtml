const Ast = @This();

const std = @import("std");
const html = @import("html.zig");
const HtmlNode = html.Ast.Node;
const Span = @import("root.zig").Span;
const errors = @import("errors.zig");
const ErrWriter = errors.ErrWriter;

const log = std.log.scoped(.ast);

src: []const u8,
extends_idx: u32 = 0,
interface: std.StringArrayHashMapUnmanaged(u32),
blocks: std.StringHashMapUnmanaged(u32),
nodes: []const Node,
errors: []const Error,
scripted_attrs: []const Node.ScriptedAttr,

const Error = struct {
    kind: union(enum) {
        bad_attr,
        late_else,
        late_loop,
        var_no_value,
        loop_no_value,
        block_missing_id,
        extend_without_template_attr,
        missing_template_value,
        unexpected_extend,
        unscripted_var,
        duplicate_block: Span,
    },

    main_location: Span,
};

pub const Node = struct {
    kind: Kind = .element,
    elem_idx: u32,
    depth: u32,
    parent_idx: u32 = 0,
    first_child_idx: u32 = 0,
    next_idx: u32 = 0,

    // parent: ?*Node = null,
    // child: ?*Node = null,
    // next: ?*Node = null,
    // prev: ?*Node = null,

    // Evaluation
    id_template_parentid: html.Tokenizer.Attr = undefined,
    if_else_loop: ScriptedAttr = undefined,
    var_ctx: ScriptedAttr = undefined,
    scripted_attrs_span: ScriptedAttrsSpan = .{ .start = 0, .end = 0 },

    const ScriptedAttrsSpan = struct {
        start: u32,
        end: u32,

        pub fn slice(
            span: ScriptedAttrsSpan,
            attrs: []const ScriptedAttr,
        ) []const ScriptedAttr {
            return attrs[span.start..span.end];
        }
    };

    const ScriptedAttr = struct {
        attr: html.Tokenizer.Attr,
        code: html.Tokenizer.Attr.Value.UnescapedSlice,
        eval: ?[]const u8 = null,
    };

    pub fn elem(node: Node, html_ast: html.Ast) HtmlNode {
        return html_ast.nodes[node.elem_idx];
    }

    pub fn idAttr(node: Node) html.Tokenizer.Attr {
        assert(@src(), node.kind.hasId());
        return node.id_template_parentid;
    }
    pub fn idValue(node: Node) html.Tokenizer.Attr.Value {
        return node.idAttr().value.?;
    }

    pub fn templateAttr(node: Node) html.Tokenizer.Attr {
        assert(@src(), node.kind == .extend);
        return node.id_template_parentid;
    }
    pub fn templateValue(node: Node) html.Tokenizer.Attr.Value {
        return node.templateAttr().value().?;
    }

    pub fn branchingAttr(node: Node) ScriptedAttr {
        assert(@src(), node.kind.branching() != .none);
        return node.if_else_loop;
    }
    pub fn loopAttr(node: Node) ScriptedAttr {
        assert(@src(), node.kind.branching() == .loop or node.kind.branching() == .inloop);
        return node.if_else_loop;
    }
    pub fn loopValue(node: Node) html.Tokenizer.Attr.Value {
        return node.loopAttr().attr.value().?;
    }
    pub fn ifAttr(node: Node) ScriptedAttr {
        assert(@src(), node.kind.branching() == .@"if");
        return node.if_else_loop;
    }
    pub fn ifValue(node: Node) html.Tokenizer.Attr.Value {
        return node.ifAttr().attr.value().?;
    }
    pub fn elseAttr(node: Node) ScriptedAttr {
        assert(@src(), node.kind.branching() == .@"else");
        return node.if_else_loop;
    }
    pub fn varAttr(node: Node) ScriptedAttr {
        assert(@src(), node.kind.output() == .@"var");
        return node.var_ctx;
    }
    pub fn varValue(node: Node) html.Tokenizer.Attr.Value {
        return node.varAttr().attr.value().?;
    }

    pub fn debugName(node: Node, src: []const u8) []const u8 {
        return node.elem.startTag().name().string(src);
    }

    const Kind = enum {
        root,
        extend,
        super,

        block,
        block_var,
        block_ctx,
        block_if,
        block_if_var,
        block_if_ctx,
        block_loop,
        block_loop_var,
        block_loop_ctx,

        super_block,
        super_block_ctx,
        // TODO: enable these types once we implement super attributes
        //super_block_if,
        //super_block_if_ctx,
        //super_block_loop,
        //super_block_loop_ctx,

        element,
        element_var,
        element_ctx,
        element_if,
        element_if_var,
        element_if_ctx,
        element_else,
        element_else_var,
        element_else_ctx,
        element_loop,
        element_loop_var,
        element_loop_ctx,
        element_inloop,
        element_inloop_var,
        element_inloop_ctx,
        element_id,
        element_id_var,
        element_id_ctx,
        element_id_if,
        element_id_if_var,
        element_id_if_ctx,
        element_id_else,
        element_id_else_var,
        element_id_else_ctx,
        element_id_loop,
        element_id_loop_var,
        element_id_loop_ctx,
        element_id_inloop,
        element_id_inloop_var,
        element_id_inloop_ctx,

        pub const Branching = enum { none, loop, inloop, @"if", @"else" };
        pub fn branching(kind: Kind) Branching {
            return switch (kind) {
                .block_loop,
                .block_loop_var,
                .block_loop_ctx,
                .element_loop,
                .element_loop_var,
                .element_loop_ctx,
                .element_id_loop,
                .element_id_loop_var,
                .element_id_loop_ctx,
                => .loop,
                .element_inloop,
                .element_inloop_var,
                .element_inloop_ctx,
                .element_id_inloop,
                .element_id_inloop_var,
                .element_id_inloop_ctx,
                => .inloop,
                .block_if,
                .block_if_var,
                .block_if_ctx,
                .element_if,
                .element_if_var,
                .element_if_ctx,
                .element_id_if,
                .element_id_if_var,
                .element_id_if_ctx,
                => .@"if",
                .element_else,
                .element_else_var,
                .element_else_ctx,
                .element_id_else,
                .element_id_else_var,
                .element_id_else_ctx,
                => .@"else",
                .root,
                .extend,
                .block,
                .block_var,
                .block_ctx,
                .super_block,
                .super_block_ctx,
                .super,
                .element,
                .element_var,
                .element_ctx,
                .element_id,
                .element_id_var,
                .element_id_ctx,
                => .none,
            };
        }

        pub const Output = enum { none, @"var", ctx };
        pub fn output(kind: Kind) Output {
            return switch (kind) {
                .block_var,
                .block_if_var,
                .block_loop_var,
                .element_var,
                .element_if_var,
                .element_else_var,
                .element_loop_var,
                .element_inloop_var,
                .element_id_var,
                .element_id_if_var,
                .element_id_else_var,
                .element_id_loop_var,
                .element_id_inloop_var,
                => .@"var",
                .block_ctx,
                .block_if_ctx,
                .block_loop_ctx,
                .super_block_ctx,
                .element_ctx,
                .element_if_ctx,
                .element_else_ctx,
                .element_loop_ctx,
                .element_inloop_ctx,
                .element_id_ctx,
                .element_id_if_ctx,
                .element_id_else_ctx,
                .element_id_loop_ctx,
                .element_id_inloop_ctx,
                => .ctx,
                .root,
                .extend,
                .super,
                .super_block,
                .block,
                .block_if,
                .block_loop,
                .element,
                .element_if,
                .element_else,
                .element_loop,
                .element_inloop,
                .element_id,
                .element_id_if,
                .element_id_else,
                .element_id_loop,
                .element_id_inloop,
                => .none,
            };
        }

        const Role = enum { root, extend, block, super_block, super, element };
        pub fn role(kind: Kind) Role {
            return switch (kind) {
                .root => .root,
                .extend => .extend,
                .block,
                .block_var,
                .block_ctx,
                .block_if,
                .block_if_var,
                .block_if_ctx,
                .block_loop,
                .block_loop_var,
                .block_loop_ctx,
                => .block,
                .super => .super,
                .super_block,
                .super_block_ctx,
                => .super_block,
                .element,
                .element_var,
                .element_ctx,
                .element_if,
                .element_if_var,
                .element_if_ctx,
                .element_else,
                .element_else_var,
                .element_else_ctx,
                .element_loop,
                .element_loop_var,
                .element_loop_ctx,
                .element_inloop,
                .element_inloop_var,
                .element_inloop_ctx,
                .element_id,
                .element_id_var,
                .element_id_ctx,
                .element_id_if,
                .element_id_if_var,
                .element_id_if_ctx,
                .element_id_else,
                .element_id_else_var,
                .element_id_else_ctx,
                .element_id_loop,
                .element_id_loop_var,
                .element_id_loop_ctx,
                .element_id_inloop,
                .element_id_inloop_var,
                .element_id_inloop_ctx,
                => .element,
            };
        }
        pub fn hasId(kind: Kind) bool {
            return switch (kind) {
                else => false,
                .block,
                .block_var,
                .block_ctx,
                .block_if,
                .block_if_var,
                .block_if_ctx,
                .block_loop,
                .block_loop_var,
                .block_loop_ctx,
                .super_block,
                .super_block_ctx,
                .element_id,
                .element_id_var,
                .element_id_ctx,
                .element_id_if,
                .element_id_if_var,
                .element_id_if_ctx,
                .element_id_else,
                .element_id_else_var,
                .element_id_else_ctx,
                .element_id_loop,
                .element_id_loop_ctx,
                .element_id_inloop,
                .element_id_inloop_ctx,
                => true,
            };
        }
    };

    pub const SuperBlock = struct {
        elem: HtmlNode,
        id_value: html.Tokenizer.Attr.Value,
    };

    pub fn superBlock(node: Node, html_ast: html.Ast) SuperBlock {
        assert(@src(), node.kind.role() == .super);
        const id_value = node.id_template_parentid.value.?;

        return .{
            // TODO: review this weird navigation pattern
            .elem = html_ast.parent(node.elem(html_ast)).?,
            .id_value = id_value,
        };
    }

    pub fn cursor(node: *const Node) SuperCursor {
        return SuperCursor.init(node);
    }

    pub fn debug(
        node: *const Node,
        src: []const u8,
        html_ast: html.Ast,
        ast: Ast,
    ) void {
        std.debug.print("\n\n-- DEBUG --\n", .{});
        node.debugInternal(
            src,
            html_ast,
            ast,
            std.io.getStdErr().writer(),
            0,
        ) catch unreachable;
    }

    // Allows passing in a writer, useful for tests
    pub fn debugWriter(
        node: *const Node,
        src: []const u8,
        html_ast: html.Ast,
        ast: Ast,
        w: anytype,
    ) void {
        node.debugInternal(src, html_ast, ast, w, 0) catch unreachable;
    }

    fn debugInternal(
        node: Node,
        src: []const u8,
        html_ast: html.Ast,
        ast: Ast,
        w: anytype,
        lvl: usize,
    ) !void {
        for (0..lvl) |_| try w.print("    ", .{});
        try w.print("({s} {}", .{ @tagName(node.kind), node.depth });

        if (node.kind.hasId()) {
            try w.print(" #{s}", .{node.idValue().span.slice(src)});
        } else if (node.kind == .extend) {
            try w.print(" {s}", .{node.templateAttr().span().slice(src)});
        } else if (node.kind == .super) {
            try w.print(" ->#{s}", .{
                node.superBlock(html_ast).id_value.span.slice(src),
            });
        }

        if (ast.child(node)) |ch| {
            // assert(@src(), ch.parent == node);
            try w.print("\n", .{});
            try ch.debugInternal(src, html_ast, ast, w, lvl + 1);
            for (0..lvl) |_| try w.print("    ", .{});
        }
        try w.print(")\n", .{});

        if (ast.next(node)) |sibling| {
            // assert(@src(), sibling.prev == node);
            // assert(@src(), sibling.parent == node.parent);
            try sibling.debugInternal(src, html_ast, ast, w, lvl);
        }
    }
};

pub fn scripted_attrs(ast: Ast, node: Node) []Node.ScriptedAttr {
    const span = node.scripted_attrs_span;
    return ast.scripted_attrs[span.start..span.end];
}

fn at(ast: Ast, idx: u32) ?Node {
    if (idx == 0) return null;
    return ast.nodes[idx];
}

pub fn child(ast: Ast, n: Node) ?Node {
    return ast.at(n.first_child_idx);
}

pub fn next(ast: Ast, n: Node) ?Node {
    return ast.at(n.next_idx);
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
    gpa.free(ast.scripted_attrs);
}

pub fn init(
    gpa: std.mem.Allocator,
    html_ast: html.Ast,
    src: []const u8,
) error{OutOfMemory}!Ast {
    std.debug.assert(html_ast.language == .superhtml);

    var p: Parser = .{
        .src = src,
        .html = html_ast,
    };
    errdefer p.deinit(gpa);

    try p.nodes.append(gpa, .{ .kind = .root, .elem_idx = 0, .depth = 0 });

    var cursor = p.html.cursor(0);

    var node_idx: u32 = 0;
    var low_mark: u32 = 1;
    var seen_non_comment_elems = false;
    while (cursor.next()) |html_node| {
        const html_node_idx = cursor.idx;
        const depth = cursor.depth;

        switch (html_node.tag) {
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
            while (p.parent(node)) |parent| {
                if (low_mark > parent.depth) break;
                node_idx = node.parent_idx;
                node = parent;
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

        // Iterface and block mode
        switch (new_node.kind.role()) {
            .root, .super_block => unreachable,
            .super, .element => {},
            .extend => {
                // sets block mode
                assert(@src(), p.extends_idx == 0);
                p.extends_idx = new_node_idx;
            },
            .block => {
                const id_value = new_node.idValue();
                const gop = try p.blocks.getOrPut(
                    gpa,
                    id_value.span.slice(src),
                );
                if (gop.found_existing) {
                    const other = p.at(gop.value_ptr.*).?.idValue().span;
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
            assert(@src(), p.next(node.*) == null);
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

        try p.validateNodeInTree(new_node.*);

        node_idx = new_node_idx;
        low_mark = new_node.depth + 1;
    }

    return .{
        .src = src,
        .nodes = try p.nodes.toOwnedSlice(gpa),
        .errors = try p.errors.toOwnedSlice(gpa),
        .scripted_attrs = try p.scripted_attrs.toOwnedSlice(gpa),
        .interface = p.interface,
        .blocks = p.blocks,
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
    scripted_attrs: std.ArrayListUnmanaged(Node.ScriptedAttr) = .{},
    extends_idx: u32 = 0,
    interface: std.StringArrayHashMapUnmanaged(u32) = .{},
    blocks: std.StringHashMapUnmanaged(u32) = .{},

    pub fn deinit(p: *Parser, gpa: std.mem.Allocator) void {
        p.nodes.deinit(gpa);
        p.errors.deinit(gpa);
        p.scripted_attrs.deinit(gpa);
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
        // id_map: std.StringHashMapUnmanaged(Span),
    ) !?*Node {
        const elem = p.html.nodes[elem_idx];

        const block_mode = p.extends_idx != 0;
        var tmp_result: Node = .{
            .elem_idx = elem_idx,
            .depth = depth,
        };

        assert(@src(), depth > 0);
        const block_context = block_mode and depth == 1;
        if (block_context) tmp_result.kind = .block;

        var start_tag = elem.startTag(p.src, .superhtml);
        const tag_name = start_tag.name_span;

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
                        //     \\template and it can only be preceeded by HTML comments and
                        //     \\whitespace.
                        //     ,
                        // );
                    }

                    const template_attr = start_tag.next(p.src) orelse {
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

                    if (start_tag.next(p.src)) |a| {
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
                        @panic("TODO");
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

                if (start_tag.next(p.src)) |a| {
                    _ = a;
                    @panic("TODO: explain that super can't have attrs");
                }

                //The immediate parent must have an id
                const pr = p.html.parent(tmp_result.elem(p.html)).?;

                var parent_start_tag = pr.startTag(p.src, .superhtml);
                while (parent_start_tag.next(p.src)) |attr| {
                    if (is(attr.name.slice(p.src), "id")) {
                        // We can assert that the value is present because
                        // the parent element has already been validated.
                        const value = attr.value.?;
                        const gop = try p.interface.getOrPut(
                            gpa,
                            value.span.slice(p.src),
                        );
                        if (gop.found_existing) {
                            @panic("TODO: explain that the interface of this template has a collision");
                        }

                        tmp_result.id_template_parentid = attr;

                        const new_node = try p.nodes.addOne(gpa);
                        new_node.* = tmp_result;
                        gop.value_ptr.* = @intCast(p.nodes.items.len - 1);
                        return new_node;
                    }
                } else {
                    @panic("TODO");
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
            }
        }

        // programming errors
        switch (tmp_result.kind.role()) {
            else => {},
            .root, .extend, .super_block, .super => unreachable,
        }

        var attrs_seen = std.StringHashMap(Span).init(gpa);
        defer attrs_seen.deinit();

        var last_attr_end = tag_name.end;
        var scripted_attrs_span: Node.ScriptedAttrsSpan = .{
            .start = @intCast(p.scripted_attrs.items.len),
            .end = @intCast(p.scripted_attrs.items.len),
        };
        while (start_tag.next(p.src)) |attr| : (last_attr_end = attr.span().end) {
            const name = attr.name;
            const name_string = name.slice(p.src);

            if (is(name_string, "id")) {
                tmp_result.kind = switch (tmp_result.kind) {
                    .element => .element_id,
                    .element_var => .element_id_var,
                    .element_ctx => .element_id_ctx,
                    .element_if => .element_id_if,
                    .element_if_var => .element_id_if_var,
                    .element_if_ctx => .element_id_if_ctx,
                    .element_else => .element_id_else,
                    .element_else_var => .element_id_else_var,
                    .element_else_ctx => .element_id_else_ctx,
                    .element_loop => .element_id_loop,
                    .element_loop_var => .element_id_loop_var,
                    .element_loop_ctx => .element_id_loop_ctx,
                    .element_inloop => .element_id_inloop,
                    .element_inloop_var => .element_id_inloop_var,
                    .element_inloop_ctx => .element_id_inloop_ctx,

                    // no state transition
                    .block,
                    .block_var,
                    .block_ctx,
                    .block_if,
                    .block_if_var,
                    .block_if_ctx,
                    .block_loop,
                    .block_loop_var,
                    .block_loop_ctx,
                    => |s| s,

                    .root,
                    .extend,
                    .super,
                    // never discovered yet
                    .super_block,
                    .super_block_ctx,
                    // duplicate detection
                    .element_id,
                    .element_id_var,
                    .element_id_ctx,
                    .element_id_if,
                    .element_id_if_var,
                    .element_id_if_ctx,
                    .element_id_else,
                    .element_id_else_var,
                    .element_id_else_ctx,
                    .element_id_loop,
                    .element_id_loop_var,
                    .element_id_loop_ctx,
                    .element_id_inloop,
                    .element_id_inloop_var,
                    .element_id_inloop_ctx,
                    => unreachable,
                };

                const value = attr.value orelse {
                    // TODO: check if this is a general HTML error
                    //       in which case it's the HTML parser's
                    //       responsibility to check for it.
                    @panic("TODO: explain that id must have a value");
                };

                // TODO: implement value.unescape
                const maybe_code = value.span.slice(p.src);

                if (std.mem.indexOfScalar(u8, maybe_code, '$') != null) {
                    switch (tmp_result.kind.role()) {
                        .root, .extend, .super_block, .super => unreachable,
                        .block => @panic("TODO: explain blocks can't have scripted id attrs"),
                        .element => {},
                    }
                } else {
                    // we can only statically analyze non-scripted ids

                    // TODO: implement this in a way that can account for branching

                    // const id_str = value.unquote(self.html);
                    // const gop = id_map.getOrPut(gpa, id_str) catch oom();
                    // if (gop.found_existing) {
                    //     return errors.report(
                    //         template_name,
                    //         template_path,
                    //         attr.node,
                    //         self.html,
                    //         "DUPLICATE ID",
                    //         \\TODO: explain
                    //         ,
                    //     );
                    // }
                }

                tmp_result.id_template_parentid = attr;

                continue;
            }
            if (is(name_string, "debug")) {
                log.debug("\nfound debug attribute", .{});
                log.debug("\n{s}\n", .{name.slice(p.src)});
                name.debug(p.src);
                log.debug("\n", .{});

                @panic("debug attr found, aborting");
                // return Ast.fatal("debug attribute found, aborting", .{});
            }

            // var
            if (is(name_string, "var")) {
                // TODO: triage this error message

                // if (attr.node.next() != null) {
                //     return p.reportError(
                //         name,
                //         "var_must_be_last",
                //         "MISPLACED VAR ATTRIBUTE",
                //         \\An element that prints the content of a variable must place
                //         \\the `var` attribute at the very end of the opening tag.
                //         ,
                //     );
                // }

                tmp_result.kind = switch (tmp_result.kind) {
                    .block => .block_var,
                    .block_if => .block_if_var,
                    .block_loop => .block_loop_var,
                    .element => .element_var,
                    .element_if => .element_if_var,
                    .element_else => .element_else_var,
                    .element_loop => .element_loop_var,
                    .element_inloop => .element_inloop_var,
                    .element_id => .element_id_var,
                    .element_id_if => .element_id_if_var,
                    .element_id_else => .element_id_else_var,
                    .element_id_loop => .element_id_loop_var,
                    .element_id_inloop => .element_id_inloop_var,

                    .block_ctx,
                    .block_if_ctx,
                    .block_loop_var,
                    .block_loop_ctx,
                    .element_ctx,
                    .element_if_ctx,
                    .element_else_ctx,
                    .element_loop_ctx,
                    .element_inloop_ctx,
                    .element_id_ctx,
                    .element_id_if_ctx,
                    .element_id_else_ctx,
                    .element_id_loop_ctx,
                    .element_id_inloop_ctx,
                    => {
                        @panic("TODO: explain that a tag combination is wrong");
                    },

                    .root,
                    .extend,
                    .super,
                    // never discorvered yet
                    .super_block,
                    .super_block_ctx,
                    => unreachable,

                    // duplicate attr
                    .block_var,
                    .block_if_var,
                    .element_var,
                    .element_if_var,
                    .element_else_var,
                    .element_loop_var,
                    .element_inloop_var,
                    .element_id_var,
                    .element_id_if_var,
                    .element_id_else_var,
                    .element_id_loop_var,
                    .element_id_inloop_var,
                    => tmp_result.kind, // do nothing
                };

                //TODO: implement unescape
                // const code = try value.unescape(gpa, p.src);
                const code = if (attr.value) |v|
                    v.span.slice(p.src)
                else blk: {

                    // return p.reportError(
                    //     name,
                    //     "var_no_value",
                    //     "VAR MISSING VALUE",
                    //     \\A `var` attribute requires a value that scripts what
                    //     \\to put in the relative element's body.
                    //     ,
                    // );
                    try p.errors.append(gpa, .{
                        .kind = .var_no_value,
                        .main_location = name,
                    });
                    break :blk "";
                };

                // TODO: typecheck the expression
                if (code.len > 0 and
                    std.mem.indexOfScalar(u8, code, '$') == null)
                {
                    try p.errors.append(gpa, .{
                        .kind = .unscripted_var,
                        .main_location = name,
                    });

                    // return p.reportError(
                    //     name,
                    //     "unscripted_var",
                    //     "UNSCRIPTED VAR",
                    //     \\A `var` attribute requires a value that scripts what
                    //     \\to put in the relative element's body.
                    //     ,
                    // );
                }
                tmp_result.var_ctx = .{
                    .attr = attr,
                    .code = .{
                        .slice = code,
                    },
                };

                continue;
            }

            // template outside of <extend/>
            if (is(name_string, "template")) {
                @panic("TODO: explain that `template` can only go in extend tags");
            }

            // if
            if (is(name_string, "if")) {
                tmp_result.kind = switch (tmp_result.kind) {
                    .block => .block_if,
                    .block_var => .block_if_var,
                    .block_ctx => .block_if_ctx,
                    .element => .element_if,
                    .element_var => .element_if_var,
                    .element_ctx => .element_if_ctx,
                    .element_id => .element_id_if,
                    .element_id_var => .element_id_if_var,
                    .element_id_ctx => .element_id_if_ctx,

                    .block_if,
                    .block_if_var,
                    .block_if_ctx,
                    .block_loop,
                    .block_loop_var,
                    .block_loop_ctx,
                    .element_else,
                    .element_else_var,
                    .element_else_ctx,
                    .element_loop,
                    .element_loop_var,
                    .element_loop_ctx,
                    .element_inloop,
                    .element_inloop_var,
                    .element_inloop_ctx,
                    .element_id_else,
                    .element_id_else_var,
                    .element_id_else_ctx,
                    .element_id_loop,
                    .element_id_loop_var,
                    .element_id_loop_ctx,
                    .element_id_inloop,
                    .element_id_inloop_var,
                    .element_id_inloop_ctx,
                    => blk: {
                        try p.errors.append(gpa, .{
                            .kind = .bad_attr,
                            .main_location = name,
                        });
                        break :blk tmp_result.kind;
                        // p.reportError(
                        //     name,
                        //     "bad_attr",
                        //     "ALREADY BRANCHING",
                        //     \\Elements can't have multiple branching attributes defined
                        //     \\at the same time.
                        //     ,
                        // ) catch {};
                        // try p.diagnostic(
                        //     "note: this is the previous branching attribute:",
                        //     tmp_result.branchingAttr().attr.name,
                        // );
                        // return error.Fatal;
                    },

                    .root,
                    .extend,
                    .super,
                    // never discovered yet
                    .super_block,
                    .super_block_ctx,
                    // duplicate attribute
                    .element_if,
                    .element_if_var,
                    .element_if_ctx,
                    .element_id_if,
                    .element_id_if_var,
                    .element_id_if_ctx,
                    => unreachable,
                };

                if (last_attr_end != tag_name.end) {
                    try p.errors.append(gpa, .{
                        .kind = .bad_attr,
                        .main_location = name,
                    });
                    // return p.reportError(
                    //     name,
                    //     "bad_attr",
                    //     "IF ATTRIBUTE MUST COME FIRST",
                    //     \\When giving an 'if' attribute to an element, you must always place it
                    //     \\first in the attribute list.
                    //     ,
                    // );
                }

                const code = if (attr.value) |v|
                    v.span.slice(p.src)
                else blk: {
                    try p.errors.append(gpa, .{
                        .kind = .bad_attr,
                        .main_location = name,
                    });
                    // return p.reportError(
                    //     name,
                    //     "bad_attr",
                    //     "IF ATTRIBUTE WIHTOUT VALUE",
                    //     \\When giving an `if` attribute to an element, you must always
                    //     \\also provide a condition in the form of a value.
                    //     ,
                    // );
                    break :blk "";
                };

                // TODO: implement unescape
                // const code = try value.unescape(gpa, p.src);

                // TODO: typecheck the expression
                tmp_result.if_else_loop = .{
                    .attr = attr,
                    .code = .{
                        .slice = code,
                    },
                };

                continue;
            }

            // else
            if (is(name_string, "else")) {
                tmp_result.kind = switch (tmp_result.kind) {
                    .element => .element_else,
                    .element_var => .element_else_var,
                    .element_ctx => .element_else_ctx,
                    .element_id => .element_id_else,
                    .element_id_var => .element_id_else_var,
                    .element_id_ctx => .element_id_else_ctx,

                    .block,
                    .block_var,
                    .block_ctx,
                    .block_if,
                    .block_if_var,
                    .block_if_ctx,
                    .block_loop,
                    .block_loop_var,
                    .block_loop_ctx,
                    .element_if,
                    .element_if_var,
                    .element_if_ctx,
                    .element_else,
                    .element_else_var,
                    .element_else_ctx,
                    .element_loop,
                    .element_loop_var,
                    .element_loop_ctx,
                    .element_inloop,
                    .element_inloop_var,
                    .element_inloop_ctx,
                    .element_id_if,
                    .element_id_if_var,
                    .element_id_if_ctx,
                    .element_id_else,
                    .element_id_else_var,
                    .element_id_else_ctx,
                    .element_id_loop,
                    .element_id_loop_var,
                    .element_id_loop_ctx,
                    .element_id_inloop,
                    .element_id_inloop_var,
                    .element_id_inloop_ctx,
                    => {
                        @panic("TODO: explain why these blocks can't have an else attr");
                    },

                    .root,
                    .extend,
                    .super,
                    // never discovered yet
                    .super_block,
                    .super_block_ctx,
                    => unreachable,
                };

                if (last_attr_end != tag_name.end) {
                    try p.errors.append(gpa, .{
                        .kind = .late_else,
                        .main_location = name,
                    });
                    // @panic("TODO: explain that else must be the first attr");
                }
                if (attr.value) |v| {
                    try p.errors.append(gpa, .{
                        .kind = .bad_attr,
                        .main_location = v.span,
                    });
                    // return p.reportError(
                    //     v.span,
                    //     "bad_attr",
                    //     "ELSE ATTRIBUTE WITH VALUE",
                    //     "`else` attributes cannot have a value.",
                    // );
                }

                tmp_result.if_else_loop = .{ .attr = attr, .code = .{} };

                continue;
            }

            // loop
            if (is(name_string, "loop")) {
                if (last_attr_end != tag_name.end) {
                    try p.errors.append(gpa, .{
                        .kind = .late_loop,
                        .main_location = name,
                    });
                    // @panic("TODO: explain that loop must be the first attr");
                }

                tmp_result.kind = switch (tmp_result.kind) {
                    .block => .block_loop,
                    .block_var => .block_loop_var,
                    .block_ctx => .block_loop_ctx,
                    .element => .element_loop,
                    .element_var => .element_loop_var,
                    .element_ctx => .element_loop_ctx,
                    .element_id => .element_id_loop,
                    .element_id_var => .element_id_loop_var,
                    .element_id_ctx => .element_id_loop_ctx,

                    .block_if,
                    .block_if_var,
                    .block_if_ctx,
                    .block_loop,
                    .block_loop_var,
                    .block_loop_ctx,
                    .element_if,
                    .element_if_var,
                    .element_if_ctx,
                    .element_else,
                    .element_else_var,
                    .element_else_ctx,
                    .element_loop,
                    .element_loop_var,
                    .element_loop_ctx,
                    .element_inloop,
                    .element_inloop_var,
                    .element_inloop_ctx,
                    .element_id_if,
                    .element_id_if_var,
                    .element_id_if_ctx,
                    .element_id_else,
                    .element_id_else_var,
                    .element_id_else_ctx,
                    .element_id_loop,
                    .element_id_loop_var,
                    .element_id_loop_ctx,
                    .element_id_inloop,
                    .element_id_inloop_var,
                    .element_id_inloop_ctx,
                    => {
                        // TODO: some of these cases should be unreachable
                        @panic("TODO: explain why these blocks can't have an loop attr");
                    },

                    .root,
                    .extend,
                    .super,
                    // never discovered yet
                    .super_block,
                    .super_block_ctx,
                    => unreachable,
                };

                const code = if (attr.value) |v|
                    v.span.slice(p.src)
                else blk: {
                    try p.errors.append(gpa, .{
                        .kind = .loop_no_value,
                        .main_location = name,
                    });
                    // @panic("TODO: explain that loop must have a value");
                    break :blk "";
                };

                // TODO: implement unescape
                // const code = try value.unescape(gpa, p.src);

                // TODO: typecheck the expression
                tmp_result.if_else_loop = .{
                    .attr = attr,
                    .code = .{
                        .slice = code,
                    },
                };

                continue;
            }

            // inline-loop
            if (is(name_string, "inline-loop")) {
                if (last_attr_end != tag_name.end) {
                    @panic("TODO: explain that loop must be the first attr");
                }

                tmp_result.kind = switch (tmp_result.kind) {
                    .element => .element_inloop,
                    .element_var => .element_inloop_var,
                    .element_ctx => .element_inloop_ctx,
                    .element_id => .element_id_inloop,
                    .element_id_var => .element_id_inloop_var,
                    .element_id_ctx => .element_id_inloop_ctx,

                    .block_if,
                    .block_if_var,
                    .block_if_ctx,
                    .block_loop,
                    .block_loop_var,
                    .block_loop_ctx,
                    .element_if,
                    .element_if_var,
                    .element_if_ctx,
                    .element_else,
                    .element_else_var,
                    .element_else_ctx,
                    .element_loop,
                    .element_loop_var,
                    .element_loop_ctx,
                    .element_inloop,
                    .element_inloop_var,
                    .element_inloop_ctx,
                    .element_id_if,
                    .element_id_if_var,
                    .element_id_if_ctx,
                    .element_id_else,
                    .element_id_else_var,
                    .element_id_else_ctx,
                    .element_id_loop,
                    .element_id_loop_var,
                    .element_id_loop_ctx,
                    .element_id_inloop,
                    .element_id_inloop_var,
                    .element_id_inloop_ctx,
                    => {
                        @panic("TODO: explain why these blocks can't have an inline-loop attr");
                    },

                    .root,
                    .extend,
                    .super,
                    .block,
                    .block_var,
                    .block_ctx,
                    // never discovered yet
                    .super_block,
                    .super_block_ctx,
                    => unreachable,
                };

                const value = attr.value orelse {
                    @panic("TODO: explain that loop must have a value");
                };

                //TODO: implement unescape
                // const code = try value.unescape(gpa, p.src);
                const code = value.span.slice(p.src);
                // TODO: typecheck the expression
                tmp_result.if_else_loop = .{
                    .attr = attr,
                    .code = .{
                        .slice = code,
                    },
                };

                continue;
            }

            // normal attribute
            if (attr.value) |value| {
                // TODO: implement unescape
                // const code = try value.unescape(gpa, p.src);
                const code = value.span.slice(p.src);

                if (std.mem.startsWith(u8, code, "$")) {
                    scripted_attrs_span.end += 1;
                    try p.scripted_attrs.append(gpa, .{
                        .attr = attr,
                        .code = .{ .slice = code },
                    });
                }
            }
        }

        const scripted_attrs_count = scripted_attrs_span.end - scripted_attrs_span.start;
        switch (tmp_result.kind) {
            .element, .element_id => if (scripted_attrs_count == 0) return null,
            else => {},
        }

        // TODO: see if the error reporting order makes sense
        if (tmp_result.kind.role() == .block and !attrs_seen.contains("id")) {
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
        new_node.scripted_attrs_span = scripted_attrs_span;
        return new_node;
    }

    fn validateNodeInTree(p: Parser, node: Node) !void {
        // NOTE: This function should only validate rules that require
        //       having inserted the node in the tree. anything that
        //       can be tested sooner should go in self.buildNode().
        //
        // NOTE: We can only validate constraints *upwards* with regards
        //       to the SuperTree.

        switch (node.kind.role()) {
            .root => unreachable,
            .element => {},

            .extend => {
                // if present, <extend/> must be the first tag in the document
                // (validated on creation)
                // TODO: check for empty body
            },
            .block => {
                // blocks must have an id
                // (validated on creation)

                // blocks must be at depth = 1
                // (validated on creation)
            },

            .super_block => {
                // must have an id
                // (validated on creation)

                // must have a <super/> inside
                // (validated when validating the <super/>)
            },
            .super => {
                // <super/> must have super_block right above
                // (validated on creation)

                // // <super/> can't be inside any subtree with branching in it
                // var out = node.parent;
                // while (out) |o| : (out = o.parent) if (o.kind.branching() != .none) {
                //     self.reportError(node.elem.node, "<SUPER/> UNDER BRANCHING",
                //         \\The <super/> tag is used to define a static template
                //         \\extension hierarchy, and as such should not be placed
                //         \\inside of elements that feature branching logic.
                //     ) catch {};
                //     std.debug.print("note: branching happening here:\n", .{});
                //     self.diagnostic(o.branchingAttr().attr.name());
                //     return error.Reported;
                // };

                // each super_block can only have one <super/> in it.

                // TODO: this only catches the simplest case,
                //       it needs to also enter prev nodes.

                // TODO: triage this error
                // var html_up = ast.prev(node.elem);
                // while (html_up) |u| : (html_up = u.prev()) {
                //     const elem = u.toElement() orelse continue;
                //     const start_tag = elem.startTag();
                //     if (is(start_tag.name().string(ast.html), "super")) {
                //         ast.reportError(
                //             node.elem.node,
                //             "too_many_supers",
                //             "MULTIPLE SUPER TAGS UNDER SAME ID",
                //             \\TODO: write explanation
                //             ,
                //         ) catch {};
                //         try ast.diagnostic(
                //             "note: the other tag:",
                //             start_tag.name(),
                //         );
                //         try ast.diagnostic(
                //             "note: both are relative to:",
                //             node.superBlock().id_value.node,
                //         );
                //         return error.Fatal;

                //         // self.reportError(elem_name, "UNEXPECTED SUPER TAG",
                //         //     \\All <super/> tags must have a parent element with an id,
                //         //     \\which is what defines a block, and each block can only have
                //         //     \\one <super/> tag.
                //         //     \\
                //         //     \\Add an `id` attribute to a new element to split them into
                //         //     \\two blocks, or remove one.
                //         // ) catch {};
                //         // std.debug.print("note: this is where the other tag is:", .{});
                //         // self.templateDiagnostics(gop.value_ptr.*);
                //         // std.debug.print("note: both refer to this ancestor:", .{});
                //         // self.templateDiagnostics(s.tag_name);
                //         // return error.Reported;
                //     }
                // }
            },
        }

        // nodes under a loop can't have ids
        if (node.kind.hasId()) {
            var maybe_parent = p.parent(node);
            while (maybe_parent) |par| : (maybe_parent = p.parent(par)) switch (par.kind.branching()) {
                else => continue,
                .loop, .inloop => {
                    @panic("TODO");
                    // p.reportError(
                    //     node.idAttr().name,
                    //     "id_under_loop",
                    //     "ID UNDER LOOP",
                    //     \\In a valid HTML document all `id` attributes must
                    //     \\have unique values.
                    //     \\
                    //     \\Giving an `id` attribute to elements under a loop
                    //     \\makes that impossible.
                    //     ,
                    // ) catch {};
                    // try p.diagnostic("note: the loop:\n", p.loopAttr().attr.name);
                    // return error.Fatal;
                },
            };
        }

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

fn fatal(self: Ast, comptime msg: []const u8, args: anytype) errors.Fatal {
    return errors.fatal(self.err, msg, args);
}

fn reportError(
    self: Ast,
    span: Span,
    comptime error_code: []const u8,
    comptime title: []const u8,
    comptime msg: []const u8,
) errors.Fatal {
    return errors.report(
        self.err,
        self.template_name,
        self.template_path,
        span,
        self.src,
        error_code,
        title,
        msg,
    );
}

fn diagnostic(
    self: Ast,
    comptime note_line: []const u8,
    span: Span,
) !void {
    return errors.diagnostic(
        self.err,
        self.template_name,
        self.template_path,
        note_line,
        span,
        self.src,
    );
}

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

test "var - errors" {
    const cases =
        \\<div var></div>
        \\<div var="$page.content" else></div>
        \\<div var="$page.content" if></div>
        \\<div var="$page.content" loop></div>
        \\<div var="$page.content" var></div>
        \\<div var="not scripted"></div>
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
        \\  <span if="$foo"></span>
        \\  <p var="$bar"></p>
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

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    tree.root().debugWriter(case, html_ast, tree, out.writer());

    const ex =
        \\(root 0
        \\    (element_if 2)
        \\    (element_var 2)
        \\)
        \\
    ;
    try std.testing.expectEqualStrings(ex, out.items);
}

test "nesting" {
    const case =
        \\<div loop="$page.authors">
        \\  Hello World!
        \\  <span if="$foo"></span>
        \\  <p var="$bar"></p>
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

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    tree.root().debugWriter(case, html_ast, tree, out.writer());

    const ex =
        \\(root 0
        \\    (element_loop 1
        \\        (element_if 2)
        \\        (element_var 2)
        \\    )
        \\)
        \\
    ;
    try std.testing.expectEqualStrings(ex, out.items);
}

test "deeper nesting" {
    const case =
        \\<div loop="$page.authors">
        \\  Hello World!
        \\  <span if="$foo"></span>
        \\  <div><p var="$bar"></p></div>
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

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    tree.root().debugWriter(case, html_ast, tree, out.writer());

    const ex =
        \\(root 0
        \\    (element_loop 1
        \\        (element_if 2)
        \\        (element_var 3)
        \\    )
        \\)
        \\
    ;
    try std.testing.expectEqualStrings(ex, out.items);
}

test "complex example" {
    const case =
        \\<div if="$page.authors">
        \\  Hello World!
        \\  <span if="$foo"></span>
        \\  <span else>
        \\    <p loop="foo" id="p-loop">
        \\      <span var="$bar"></span>
        \\    </p>
        \\  </span>
        \\  <div><p id="last" var="$bar"></p></div>
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

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    const r = tree.root();
    r.debugWriter(case, html_ast, tree, out.writer());

    const cex: usize = 3;
    try std.testing.expectEqual(cex, tree.childrenCount(tree.child(r).?));

    const ex =
        \\(root 0
        \\    (element_if 1
        \\        (element_if 2)
        \\        (element_else 2
        \\            (element_id_loop 3 #p-loop
        \\                (element_var 4)
        \\            )
        \\        )
        \\        (element_id_var 3 #last)
        \\    )
        \\)
        \\
    ;
    try std.testing.expectEqualStrings(ex, out.items);
}

test "if-else-loop errors" {
    const cases =
        \\<div if></div>
        \\<div else="$foo"></div>
        \\<div else="bar"></div>
        \\<div else if></div>
        \\<div else if="$foo"></div>
        \\<div else if="bar"></div>
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
        \\<div if="$page.authors">
        \\  Hello World!
        \\  <span>
        \\    <p loop="$page.authors" id="p-loop">
        \\      <span var="$loop.it.name"></span>
        \\      <super>
        \\    </p>
        \\  </span>
        \\  <div><p id="last" var="$bar"></p></div>
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

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    const r = tree.root();
    r.debugWriter(case, html_ast, tree, out.writer());

    const ex =
        \\(root 0
        \\    (element_if 1
        \\        (element_id_loop 3 #p-loop
        \\            (element_var 4)
        \\            (super 4 ->#p-loop)
        \\        )
        \\        (element_id_var 3 #last)
        \\    )
        \\)
        \\
    ;
    try std.testing.expectEqualStrings(ex, out.items);

    const cex: usize = 2;
    try std.testing.expectEqual(cex, tree.childrenCount(tree.child(r).?));
}
// TODO: get rid of this once stack traces on arm64 work again
fn assert(loc: std.builtin.SourceLocation, condition: bool) void {
    if (!condition) {
        std.debug.print("assertion error in {s} at {s}:{}:{}\n", .{
            loc.fn_name,
            loc.file,
            loc.line,
            loc.column,
        });
        std.process.exit(1);
    }
}

pub const SuperCursor = struct {
    depth: usize,
    current: *const Node,
    skip_children_of_current_node: bool = false,

    pub fn init(node: *const Node) SuperCursor {
        return .{ .depth = 0, .current = node };
    }
    pub fn skipChildrenOfCurrentNode(self: *SuperCursor) void {
        self.skip_children_of_current_node = true;
    }
    pub fn next(self: *SuperCursor) ?*const Node {
        if (self.skip_children_of_current_node) {
            self.skip_children_of_current_node = false;
        } else {
            if (self.current.child) |ch| {
                self.depth += 1;
                self.current = ch;
                return ch;
            }
        }

        if (self.depth == 0) return null;

        if (self.current.next) |sb| {
            self.current = sb;
            return sb;
        }

        self.depth -= 1;
        if (self.depth == 0) return null;

        const parent = self.current.parent.?;
        if (parent.next) |un| {
            self.current = un;
            return un;
        }

        return null;
    }

    pub fn reset(self: *SuperCursor, node: *const Node) void {
        self.* = SuperCursor.init(node);
    }
};
