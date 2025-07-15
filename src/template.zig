const std = @import("std");
const Writer = std.Io.Writer;
const scripty = @import("scripty");
const tracy = @import("tracy");
const root = @import("root.zig");
const errors = @import("errors.zig");
const html = @import("html.zig");
const Ast = @import("Ast.zig");
const HtmlSafe = root.HtmlSafe;
const Span = root.Span;
const Node = Ast.Node;

const log = std.log.scoped(.supertemplate);

pub fn SuperTemplate(comptime ScriptyVM: type) type {
    return struct {
        arena: std.mem.Allocator,
        name: []const u8,
        path: []const u8,
        src: []const u8,
        ast: Ast,
        html: html.Ast,
        print_cursor: u32 = 0,
        print_end: u32,
        role: Role,

        cursor: Ast.Cursor,
        if_stack: std.ArrayListUnmanaged(IfFrame) = .{},
        loop_stack: std.ArrayListUnmanaged(LoopFrame) = .{},
        ctx: std.StringHashMapUnmanaged(Value) = .{},

        const Template = @This();
        const Value = ScriptyVM.Value;
        const Context = ScriptyVM.Context;
        const Role = enum { layout, template };

        const IfFrame = struct {
            node_idx: u32,
            value: *const Value.Optional,
        };

        const LoopFrame = struct {
            node_idx: u32,
            iterator: *Value.Iterator,
        };

        pub fn superBlock(tpl: Template, idx: u32) Ast.Node.Block {
            return tpl.ast.nodes[idx].superBlock(tpl.src, tpl.html);
        }

        pub fn startTag(tpl: Template, idx: u32) Span {
            return tpl.ast.nodes[idx].elem(tpl.html).open;
        }

        pub fn getName(tpl: Template, idx: u32) Span {
            const span = tpl.startTag(idx);
            return span.getName(tpl.src, tpl.html.language);
        }

        pub fn init(
            arena: std.mem.Allocator,
            path: []const u8,
            name: []const u8,
            src: []const u8,
            html_ast: html.Ast,
            ast: Ast,
            role: Role,
        ) !Template {
            return .{
                .arena = arena,
                .path = path,
                .name = name,
                .src = src,
                .html = html_ast,
                .ast = ast,
                .role = role,
                .cursor = ast.cursor(0),
                .print_end = @intCast(src.len),
            };
        }

        pub fn finalCheck(tpl: Template) void {
            std.debug.assert(tpl.print_cursor == tpl.print_end);
        }

        pub fn showBlocks(tpl: Template, err_writer: *Writer) error{ErrIO}!void {
            var found_first = false;
            var it = tpl.ast.blocks.iterator();
            while (it.next()) |kv| {
                const id = kv.key_ptr.*;
                const tag_name = tpl.getName(kv.value_ptr.*).slice(tpl.src);
                if (!found_first) {
                    err_writer.print("\n[missing_block]\n", .{}) catch return error.ErrIO;
                    err_writer.print("({s}) {s}:\n", .{ tpl.name, tpl.path }) catch return error.ErrIO;
                    found_first = true;
                }
                err_writer.print("\t<{s} id=\"{s}\"></{s}>\n", .{
                    tag_name,
                    id,
                    tag_name,
                }) catch return error.ErrIO;
            }

            if (!found_first) {
                err_writer.print(
                    \\
                    \\{s} doesn't define any block! You can copy the interface 
                    \\from the extended template to get started.
                    \\
                , .{tpl.name}) catch return error.ErrIO;
            }
            err_writer.print("\n", .{}) catch return error.ErrIO;
        }

        pub fn showInterface(tpl: Template, err_writer: *Writer) error{ErrIO}!void {
            var found_first = false;
            var it = tpl.ast.interface.iterator();
            while (it.next()) |kv| {
                const id = kv.key_ptr.*;
                const parent_idx = kv.value_ptr.*;
                const tag_name = tpl.superBlock(parent_idx).parent_tag_name.slice(tpl.src);
                if (!found_first) {
                    err_writer.print("\nExtended template interface ({s}):\n", .{tpl.name}) catch return error.ErrIO;
                    found_first = true;
                }
                err_writer.print("\t<{s} id=\"{s}\"></{s}>\n", .{
                    tag_name,
                    id,
                    tag_name,
                }) catch return error.ErrIO;
            }

            if (!found_first) {
                std.debug.print(
                    \\The extended template has no interface!
                    \\Add <super> tags to `{s}` to make it extensible.
                    \\
                , .{tpl.name});
            }
            std.debug.print("\n", .{});
        }

        pub fn activateBlock(
            tpl: *Template,
            script_vm: *ScriptyVM,
            script_ctx: *Context,
            super_id: []const u8,
            writer: *Writer,
            err_writer: *Writer,
        ) errors.FatalOOM!void {
            _ = script_vm;
            _ = script_ctx;
            _ = writer;
            _ = err_writer;
            std.debug.assert(tpl.ast.extends_idx != 0);
            std.debug.assert(tpl.cursor.current() == null);

            const block_idx = tpl.ast.blocks.get(super_id).?;
            const block = tpl.ast.nodes[block_idx];
            const elem = block.elem(tpl.html);

            log.debug("activating block_idx = {}, '{s}'", .{
                block_idx,
                elem.open.slice(tpl.src),
            });

            tpl.cursor = tpl.ast.cursor(block_idx);
            tpl.print_cursor = block.elem(tpl.html).open.end;
            tpl.print_end = block.elem(tpl.html).close.start;

            //     switch (block.kind.branching()) {
            //         else => unreachable,
            //         .none => {},
            //         .@"if" => {
            //             const scripted_attr = block.ifAttr();
            //             const attr = scripted_attr.attr;
            //             const value = block.ifValue();

            //             const result = try tpl.evalIf(
            //                 err_writer,
            //                 script_vm,
            //                 script_ctx,
            //                 attr.name,
            //                 value.span,
            //             );

            //             switch (result) {
            //                 else => unreachable,
            //                 .optional => @panic("TODO: implement optional if for blocks"),
            //                 .bool => |b| {
            //                     if (!b) {
            //                         const elem = block.elem(tpl.html);
            //                         switch (elem.kind) {
            //                             .root, .comment, .text => unreachable,
            //                             .element_void,
            //                             .element_self_closing,
            //                             .doctype,
            //                             => {
            //                                 tpl.print_cursor = elem.open.end;
            //                             },
            //                             .element => {
            //                                 tpl.print_cursor = elem.close.start;
            //                                 const frame = &tpl.stack.items[0];
            //                                 frame.default.skipChildrenOfCurrentNode();
            //                             },
            //                         }
            //                     }
            //                 },
            //             }
            //         },
            //     }

            //     switch (block.kind.output()) {
            //         .@"var" => {
            //             const scripted_attr = block.varAttr();
            //             const attr = scripted_attr.attr;
            //             const value = block.varValue();

            //             const var_value = try tpl.evalVar(
            //                 err_writer,
            //                 script_vm,
            //                 script_ctx,
            //                 attr.name,
            //                 value.span,
            //             );

            //             switch (var_value) {
            //                 .string => |s| writer.writeAll(s) catch return error.OutIO,
            //                 .int => |i| writer.print("{}", .{i}) catch return error.OutIO,
            //                 else => unreachable,
            //             }
            //         },
            //         else => {},
            //     }
            //     // TODO: void tag dude
        }

        pub const Continuation = union(enum) {
            // A <super> was found, contains relative id
            super_idx: u32,
            // Done executing the template.
            end,
        };

        pub fn eval(
            tpl: *Template,
            scripty_vm: *ScriptyVM,
            scripty_ctx: *Context,
            writer: *Writer,
            err_writer: *Writer,
        ) errors.FatalShowOOM!Continuation {
            const zone = tracy.trace(@src());
            defer zone.end();

            scripty_vm.reset();
            scripty_ctx.ctx._map = &tpl.ctx;
            std.debug.assert(tpl.cursor.current() != null);
            while (tpl.cursor.current()) |ev| switch (ev.node.kind) {
                .extend => unreachable,
                .root => switch (ev.dir) {
                    .enter => {
                        _ = tpl.cursor.next();
                    },
                    .exit => {
                        const to_end = tpl.src[tpl.print_cursor..];
                        writer.writeAll(to_end) catch return error.OutIO;
                        tpl.print_cursor = @intCast(tpl.src.len);
                        _ = tpl.cursor.next();
                        return .end;
                    },
                },
                .block => switch (ev.dir) {
                    .enter => {
                        const elem = ev.node.elem(tpl.html);
                        var it = elem.startTagIterator(
                            tpl.src,
                            tpl.html.language,
                        );

                        var out: union(enum) {
                            none,
                            html: Value,
                            text: Value,
                        } = .none;

                        var skip_body = false;

                        while (it.next(tpl.src)) |attr| {
                            const name = attr.name;
                            const expr = attr.value.?;
                            const special_attr = std.meta.stringToEnum(
                                Ast.SpecialAttr,
                                name.slice(tpl.src),
                            ) orelse {
                                // if (is(name.slice(tpl.src), "id")) continue;
                                // TODO: implement this stuff
                                continue;
                            };

                            switch (special_attr) {
                                else => {},
                                .@":html" => {
                                    out = .{
                                        .html = try tpl.evalVar(
                                            err_writer,
                                            scripty_vm,
                                            scripty_ctx,
                                            name,
                                            expr.span,
                                        ),
                                    };
                                },
                                .@":text" => {
                                    out = .{
                                        .text = try tpl.evalVar(
                                            err_writer,
                                            scripty_vm,
                                            scripty_ctx,
                                            name,
                                            expr.span,
                                        ),
                                    };
                                },
                                .@":if" => {
                                    const value = try tpl.evalIf(
                                        err_writer,
                                        scripty_vm,
                                        scripty_ctx,
                                        name,
                                        expr.span,
                                    );

                                    switch (value) {
                                        else => unreachable,
                                        .bool => |b| if (!b.value) {
                                            skip_body = true;
                                        },
                                        .optional => |opt| if (opt) |v| {
                                            try tpl.if_stack.append(tpl.arena, .{
                                                .node_idx = ev.idx,
                                                .value = v,
                                            });
                                        } else {
                                            skip_body = true;
                                        },
                                    }
                                },
                                .@":loop" => {
                                    var loop_iterator = try tpl.evalLoop(
                                        err_writer,
                                        scripty_vm,
                                        scripty_ctx,
                                        name,
                                        expr.span,
                                    );
                                    loop_iterator._superhtml_context = .{
                                        .tpl = tpl,
                                        .idx = @intCast(
                                            tpl.loop_stack.items.len,
                                        ),
                                    };

                                    if (!try loop_iterator.next(tpl.arena)) {
                                        skip_body = true;
                                        continue;
                                    }

                                    try tpl.loop_stack.append(tpl.arena, .{
                                        .node_idx = ev.idx,
                                        .iterator = loop_iterator,
                                    });
                                },
                            }
                        }

                        if (skip_body) {
                            tpl.print_cursor = elem.close.start;
                            tpl.cursor.cur.?.dir = .exit;
                        } else {
                            tpl.print_cursor = elem.open.end;
                            _ = tpl.cursor.next();
                            switch (out) {
                                .none => {},
                                .html => |h| switch (h) {
                                    else => unreachable,
                                    .string => |s| {
                                        writer.writeAll(s.value) catch return error.OutIO;
                                    },
                                    .int => |i| {
                                        writer.print("{d}", .{
                                            i.value,
                                        }) catch return error.OutIO;
                                    },
                                },
                                .text => |text| switch (text) {
                                    else => unreachable,
                                    .string => |s| {
                                        writer.print("{f}", .{
                                            HtmlSafe{ .bytes = s.value },
                                        }) catch return error.OutIO;
                                    },
                                    .int => |i| {
                                        writer.print("{d}", .{
                                            i.value,
                                        }) catch return error.OutIO;
                                    },
                                },
                            }
                        }
                    },
                    .exit => {
                        const elem = ev.node.elem(tpl.html);
                        const last = if (tpl.loop_stack.items.len == 0) null else blk: {
                            break :blk &tpl.loop_stack.items[tpl.loop_stack.items.len - 1];
                        };
                        if (last) |loop_frame| blk: {
                            if (loop_frame.node_idx == ev.idx) {
                                if (!try loop_frame.iterator.next(tpl.arena)) {
                                    _ = tpl.loop_stack.pop();
                                    break :blk;
                                }

                                const end = elem.close.start;
                                const up_to_close_tag = tpl.src[tpl.print_cursor..end];
                                writer.writeAll(up_to_close_tag) catch return error.OutIO;
                                tpl.print_cursor = elem.open.end;

                                if (ev.node.first_child_idx != 0) {
                                    // if there are scripted nodes in the body
                                    // we move the cursor again back to the
                                    // beginning of it.
                                    tpl.cursor.move(ev.node.first_child_idx);
                                } else {
                                    // there are no scripted children of the
                                    // current node, but there might still be
                                    // unscripted html elements that need to
                                    // be printed.
                                    // even if we don't use $loop, we still
                                    // want to trigger element evaluation in
                                    // case that the procedure has side effects
                                }
                                continue;
                            }
                        }

                        // Skip </close tag>
                        {
                            const up_to_elem = tpl.src[tpl.print_cursor..elem.close.start];
                            writer.writeAll(up_to_elem) catch return error.OutIO;
                            tpl.print_cursor = elem.close.start;
                        }
                        _ = tpl.cursor.next();
                        return .end;
                    },
                },
                .super => switch (ev.dir) {
                    .enter => {
                        _ = tpl.cursor.next();
                        // Print up to the element (non inclusive)
                        // and then skip it
                        {
                            const elem = ev.node.elem(tpl.html);
                            const end = elem.open.start;
                            const up_to_attr = tpl.src[tpl.print_cursor..end];
                            writer.writeAll(up_to_attr) catch return error.OutIO;
                            tpl.print_cursor = elem.open.end;
                        }
                        return .{ .super_idx = ev.idx };
                    },
                    .exit => {
                        _ = tpl.cursor.next();
                    },
                },
                .ctx => switch (ev.dir) {
                    .enter => {
                        const elem = ev.node.elem(tpl.html);
                        var it = elem.startTagIterator(
                            tpl.src,
                            tpl.html.language,
                        );

                        var out: union(enum) {
                            none,
                            html: Value,
                            text: Value,
                        } = .none;

                        var skip_body = false;
                        while (it.next(tpl.src)) |attr| {
                            const name = attr.name;
                            const expr = attr.value.?;
                            const special_attr = std.meta.stringToEnum(
                                Ast.SpecialAttr,
                                name.slice(tpl.src),
                            ) orelse {
                                const gop = try tpl.ctx.getOrPut(
                                    tpl.arena,
                                    name.slice(tpl.src),
                                );
                                if (gop.found_existing) {
                                    @panic("TODO: error reporting for ctx collisions");
                                }

                                const result = try tpl.evalAttr(
                                    err_writer,
                                    scripty_vm,
                                    scripty_ctx,
                                    name,
                                    expr.span,
                                );
                                gop.value_ptr.* = result.value;
                                continue;
                            };

                            switch (special_attr) {
                                else => {},
                                .@":html" => {
                                    out = .{
                                        .html = try tpl.evalVar(
                                            err_writer,
                                            scripty_vm,
                                            scripty_ctx,
                                            name,
                                            expr.span,
                                        ),
                                    };
                                },
                                .@":text" => {
                                    out = .{
                                        .text = try tpl.evalVar(
                                            err_writer,
                                            scripty_vm,
                                            scripty_ctx,
                                            name,
                                            expr.span,
                                        ),
                                    };
                                },
                                .@":if" => {
                                    const value = try tpl.evalIf(
                                        err_writer,
                                        scripty_vm,
                                        scripty_ctx,
                                        name,
                                        expr.span,
                                    );

                                    switch (value) {
                                        else => unreachable,
                                        .bool => |b| if (!b.value) {
                                            skip_body = true;
                                        },
                                        .optional => |opt| if (opt) |v| {
                                            try tpl.if_stack.append(tpl.arena, .{
                                                .node_idx = ev.idx,
                                                .value = v,
                                            });
                                        } else {
                                            skip_body = true;
                                        },
                                    }
                                },
                                .@":loop" => {
                                    var loop_iterator = try tpl.evalLoop(
                                        err_writer,
                                        scripty_vm,
                                        scripty_ctx,
                                        name,
                                        expr.span,
                                    );
                                    loop_iterator._superhtml_context = .{
                                        .tpl = tpl,
                                        .idx = @intCast(
                                            tpl.loop_stack.items.len,
                                        ),
                                    };

                                    if (!try loop_iterator.next(tpl.arena)) {
                                        skip_body = true;
                                        continue;
                                    }

                                    try tpl.loop_stack.append(tpl.arena, .{
                                        .node_idx = ev.idx,
                                        .iterator = loop_iterator,
                                    });
                                },
                            }
                        }

                        // Skip <ctx ...>
                        const up_to_elem = tpl.src[tpl.print_cursor..elem.open.start];
                        writer.writeAll(up_to_elem) catch return error.OutIO;
                        if (skip_body) {
                            tpl.print_cursor = elem.close.start;
                            tpl.cursor.cur.?.dir = .exit;
                        } else {
                            tpl.print_cursor = elem.open.end;
                            _ = tpl.cursor.next();
                            switch (out) {
                                .none => {},
                                .html => |h| switch (h) {
                                    else => unreachable,
                                    .string => |s| {
                                        writer.writeAll(s.value) catch return error.OutIO;
                                    },
                                    .int => |i| {
                                        writer.print("{d}", .{
                                            i.value,
                                        }) catch return error.OutIO;
                                    },
                                },
                                .text => |text| switch (text) {
                                    else => unreachable,
                                    .string => |s| {
                                        writer.print("{f}", .{
                                            HtmlSafe{ .bytes = s.value },
                                        }) catch return error.OutIO;
                                    },
                                    .int => |i| {
                                        writer.print("{d}", .{
                                            i.value,
                                        }) catch return error.OutIO;
                                    },
                                },
                            }
                        }
                    },
                    .exit => {
                        const elem = ev.node.elem(tpl.html);
                        const last = if (tpl.loop_stack.items.len == 0) null else blk: {
                            break :blk &tpl.loop_stack.items[tpl.loop_stack.items.len - 1];
                        };
                        if (last) |loop_frame| blk: {
                            if (loop_frame.node_idx == ev.idx) {
                                if (!try loop_frame.iterator.next(tpl.arena)) {
                                    _ = tpl.loop_stack.pop();
                                    break :blk;
                                }

                                const end = elem.close.start;
                                const up_to_close_tag = tpl.src[tpl.print_cursor..end];
                                writer.writeAll(up_to_close_tag) catch return error.OutIO;
                                tpl.print_cursor = elem.open.end;

                                if (ev.node.first_child_idx != 0) {
                                    // if there are scripted nodes in the body
                                    // we move the cursor again back to the
                                    // beginning of it.
                                    tpl.cursor.move(ev.node.first_child_idx);
                                } else {
                                    // there are no scripted children of the
                                    // current node, but there might still be
                                    // unscripted html elements that need to
                                    // be printed.
                                    // even if we don't use $loop, we still
                                    // want to trigger element evaluation in
                                    // case that the procedure has side effects
                                }
                                continue;
                            }
                        }

                        var it = elem.startTagIterator(
                            tpl.src,
                            tpl.html.language,
                        );
                        while (it.next(tpl.src)) |attr| {
                            const name = attr.name;
                            const kv = tpl.ctx.fetchRemove(name.slice(tpl.src));
                            _ = kv;
                            // TODO: free the value
                        }

                        // Skip </ctx>
                        {
                            const up_to_elem = tpl.src[tpl.print_cursor..elem.close.start];
                            writer.writeAll(up_to_elem) catch return error.OutIO;
                            tpl.print_cursor = elem.close.end;
                        }
                        _ = tpl.cursor.next();
                    },
                },
                .element, .super_block => switch (ev.dir) {
                    .enter => {
                        const elem = ev.node.elem(tpl.html);
                        var it = elem.startTagIterator(
                            tpl.src,
                            tpl.html.language,
                        );

                        // Print up to the tag name (inclusive)
                        {
                            const end = it.name_span.end;
                            const up_to_attr = tpl.src[tpl.print_cursor..end];
                            writer.writeAll(up_to_attr) catch return error.OutIO;
                            tpl.print_cursor = end;
                        }

                        var out: union(enum) {
                            none,
                            html: Value,
                            text: Value,
                        } = .none;

                        var skip_body = false;
                        while (it.next(tpl.src)) |attr| {
                            const name = attr.name;
                            const special_attr = std.meta.stringToEnum(
                                Ast.SpecialAttr,
                                name.slice(tpl.src),
                            ) orelse {
                                writer.print(" {s}", .{
                                    name.slice(tpl.src),
                                }) catch return error.OutIO;
                                tpl.print_cursor = name.end;
                                const expr = attr.value orelse continue;
                                tpl.print_cursor = expr.span.end;

                                const src = expr.span.slice(tpl.src);
                                if (!std.mem.startsWith(u8, src, "$")) {
                                    writer.print(
                                        "=\"{s}\"",
                                        .{src},
                                    ) catch return error.OutIO;
                                    continue;
                                }

                                const value = try tpl.evalVar(
                                    err_writer,
                                    scripty_vm,
                                    scripty_ctx,
                                    name,
                                    expr.span,
                                );

                                switch (value) {
                                    else => unreachable,
                                    .string => |s| {
                                        writer.print(
                                            "=\"{f}\"",
                                            .{
                                                HtmlSafe{
                                                    .bytes = s.value,
                                                },
                                            },
                                        ) catch return error.OutIO;
                                    },
                                    .int => |i| {
                                        writer.print("=\"{d}\"", .{
                                            i.value,
                                        }) catch return error.OutIO;
                                    },
                                }
                                continue;
                            };

                            const expr = attr.value.?;
                            tpl.print_cursor = expr.span.end;

                            switch (special_attr) {
                                else => {},
                                .@":html" => {
                                    out = .{
                                        .html = try tpl.evalVar(
                                            err_writer,
                                            scripty_vm,
                                            scripty_ctx,
                                            name,
                                            expr.span,
                                        ),
                                    };
                                },
                                .@":text" => {
                                    out = .{
                                        .text = try tpl.evalVar(
                                            err_writer,
                                            scripty_vm,
                                            scripty_ctx,
                                            name,
                                            expr.span,
                                        ),
                                    };
                                },
                                .@":if" => {
                                    const value = try tpl.evalIf(
                                        err_writer,
                                        scripty_vm,
                                        scripty_ctx,
                                        name,
                                        expr.span,
                                    );

                                    switch (value) {
                                        else => unreachable,
                                        .bool => |b| if (!b.value) {
                                            skip_body = true;
                                        },
                                        .optional => |opt| if (opt) |v| {
                                            try tpl.if_stack.append(tpl.arena, .{
                                                .node_idx = ev.idx,
                                                .value = v,
                                            });
                                        } else {
                                            skip_body = true;
                                        },
                                    }
                                },
                                .@":loop" => {
                                    var loop_iterator = try tpl.evalLoop(
                                        err_writer,
                                        scripty_vm,
                                        scripty_ctx,
                                        name,
                                        expr.span,
                                    );
                                    loop_iterator._superhtml_context = .{
                                        .tpl = tpl,
                                        .idx = @intCast(
                                            tpl.loop_stack.items.len,
                                        ),
                                    };

                                    if (!try loop_iterator.next(tpl.arena)) {
                                        skip_body = true;
                                        continue;
                                    }

                                    try tpl.loop_stack.append(tpl.arena, .{
                                        .node_idx = ev.idx,
                                        .iterator = loop_iterator,
                                    });
                                },
                            }
                        }

                        // finish printing the start tag
                        writer.writeAll(">") catch return error.OutIO;
                        if (skip_body) {
                            tpl.print_cursor = elem.close.start;
                            tpl.cursor.cur.?.dir = .exit;
                        } else {
                            tpl.print_cursor = elem.open.end;
                            _ = tpl.cursor.next();
                            switch (out) {
                                .none => {},
                                .html => |h| switch (h) {
                                    else => unreachable,
                                    .string => |s| {
                                        writer.writeAll(s.value) catch return error.OutIO;
                                    },
                                    .int => |i| {
                                        writer.print("{d}", .{
                                            i.value,
                                        }) catch return error.OutIO;
                                    },
                                },
                                .text => |text| switch (text) {
                                    else => unreachable,
                                    .string => |s| {
                                        writer.print("{f}", .{
                                            HtmlSafe{ .bytes = s.value },
                                        }) catch return error.OutIO;
                                    },
                                    .int => |i| {
                                        writer.print("{d}", .{
                                            i.value,
                                        }) catch return error.OutIO;
                                    },
                                },
                            }
                        }
                    },
                    .exit => {
                        const elem = ev.node.elem(tpl.html);
                        const last = if (tpl.loop_stack.items.len == 0) null else blk: {
                            break :blk &tpl.loop_stack.items[tpl.loop_stack.items.len - 1];
                        };
                        if (last) |loop_frame| blk: {
                            if (loop_frame.node_idx == ev.idx) {
                                if (!try loop_frame.iterator.next(tpl.arena)) {
                                    _ = tpl.loop_stack.pop();
                                    break :blk;
                                }

                                const end = elem.close.start;
                                const up_to_close_tag = tpl.src[tpl.print_cursor..end];
                                writer.writeAll(up_to_close_tag) catch return error.OutIO;
                                tpl.print_cursor = elem.open.end;

                                if (ev.node.first_child_idx != 0) {
                                    // if there are scripted nodes in the body
                                    // we move the cursor again back to the
                                    // beginning of it.
                                    tpl.cursor.move(ev.node.first_child_idx);
                                } else {
                                    // there are no scripted children of the
                                    // current node, but there might still be
                                    // unscripted html elements that need to
                                    // be printed.
                                    // even if we don't use $loop, we still
                                    // want to trigger element evaluation in
                                    // case that the procedure has side effects
                                }
                                continue;
                            }
                        }

                        if (elem.kind == .element) {
                            // Print up to the close tag
                            const end = elem.close.end;
                            const up_to_attr = tpl.src[tpl.print_cursor..end];
                            writer.writeAll(up_to_attr) catch return error.OutIO;
                            tpl.print_cursor = end;
                        }
                        _ = tpl.cursor.next();
                    },
                },
            };

            unreachable;
        }

        fn evalVar(
            tpl: *Template,
            err_writer: *Writer,
            script_vm: *ScriptyVM,
            script_ctx: *Context,
            script_attr_name: Span,
            code_span: Span,
        ) errors.Fatal!Value {
            const zone = tracy.trace(@src());
            defer zone.end();
            tracy.messageCopy(code_span.slice(tpl.src));

            tpl.setContext(script_ctx);

            const result = script_vm.run(
                tpl.arena,
                script_ctx,
                code_span.slice(tpl.src),
                .{},
            ) catch return error.Fatal;

            switch (result.value) {
                .string, .int => {},
                else => {
                    tpl.reportError(
                        err_writer,
                        script_attr_name,
                        "script_eval_not_string_or_int",
                        "SCRIPT RESULT TYPE MISMATCH",
                        \\A script evaluated to an unexpected type.
                        \\
                        \\This attribute expects to evaluate to one
                        \\of the following types:
                        \\   - string
                        \\   - int
                        ,
                    ) catch {};

                    try tpl.diagnostic(
                        err_writer,
                        false,
                        "note: value was generated from this sub-expression:",
                        .{
                            .start = code_span.start + result.loc.start,
                            .end = code_span.start + result.loc.end,
                        },
                    );
                    try result.value.renderForError(tpl.arena, err_writer);
                    return error.Fatal;
                },
            }
            return result.value;
        }

        fn evalCtx(
            tpl: *Template,
            err_writer: *Writer,
            script_vm: *ScriptyVM,
            script_ctx: *Context,
            script_attr_name: Span,
            code_span: Span,
        ) errors.Fatal!Value {
            const zone = tracy.trace(@src());
            defer zone.end();
            tracy.messageCopy(code_span.slice(tpl.src));

            tpl.setContext(script_ctx);

            const result = script_vm.run(
                tpl.arena,
                script_ctx,
                code_span.slice(tpl.src),
                .{},
            ) catch return error.Fatal;

            switch (result.value) {
                else => {},
                .err, .iterator_element, .optional => {
                    tpl.reportError(
                        err_writer,
                        script_attr_name,
                        "bad_ctx_value",
                        "SCRIPT RESULT TYPE MISMATCH",
                        \\A script evaluated to an unexpected type.
                        \\
                        \\The `ctx` attribute can evaluate to any type
                        \\except `error`, `optional`, and `@TypeOf($loop)`.
                        ,
                    ) catch {};

                    try tpl.diagnostic(
                        err_writer,
                        false,
                        "note: value was generated from this sub-expression:",
                        .{
                            .start = code_span.start + result.loc.start,
                            .end = code_span.start + result.loc.end,
                        },
                    );
                    try result.value.renderForError(tpl.arena, err_writer);
                    return error.Fatal;
                },
            }
            return result.value;
        }

        fn evalAttr(
            tpl: *Template,
            err_writer: *Writer,
            script_vm: *ScriptyVM,
            script_ctx: *Context,
            script_attr_name: Span,
            code_span: Span,
        ) errors.Fatal!ScriptyVM.Result {
            const zone = tracy.trace(@src());
            defer zone.end();
            tracy.messageCopy(code_span.slice(tpl.src));

            tpl.setContext(script_ctx);
            const result = script_vm.run(
                tpl.arena,
                script_ctx,
                code_span.slice(tpl.src),
                .{},
            ) catch return error.Fatal;

            switch (result.value) {
                else => {},
                .err => {
                    tpl.reportError(
                        err_writer,
                        script_attr_name,
                        "script_err",
                        "SCRIPT EVAL ERROR",
                        \\A script evaluated to an error.
                        \\
                        ,
                    ) catch {};

                    try tpl.diagnostic(
                        err_writer,
                        false,
                        "note: value was generated from this sub-expression:",
                        .{
                            .start = code_span.start + result.loc.start,
                            .end = code_span.start + result.loc.end,
                        },
                    );
                    try result.value.renderForError(tpl.arena, err_writer);
                    return error.Fatal;
                },
            }
            return result;
        }

        fn evalIf(
            tpl: *Template,
            err_writer: *Writer,
            script_vm: *ScriptyVM,
            script_ctx: *Context,
            script_attr_name: Span,
            code_span: Span,
        ) errors.Fatal!Value {
            const zone = tracy.trace(@src());
            defer zone.end();
            tracy.messageCopy(code_span.slice(tpl.src));

            tpl.setContext(script_ctx);
            const result = script_vm.run(
                tpl.arena,
                script_ctx,
                code_span.slice(tpl.src),
                .{},
            ) catch return error.Fatal;

            switch (result.value) {
                .bool, .optional => {},
                else => {
                    tpl.reportError(
                        err_writer,
                        script_attr_name,
                        "script_eval_not_bool",
                        "SCRIPT RESULT TYPE MISMATCH",
                        \\A script evaluated to an unexpected type.
                        \\
                        \\This attribute expects to evaluate to one
                        \\of the following types:
                        \\   - bool
                        ,
                    ) catch {};

                    try tpl.diagnostic(
                        err_writer,
                        false,
                        "note: value was generated from this sub-expression:",
                        .{
                            .start = code_span.start + result.loc.start,
                            .end = code_span.start + result.loc.end,
                        },
                    );

                    try result.value.renderForError(tpl.arena, err_writer);
                    return error.Fatal;
                },
            }
            return result.value;
        }

        fn evalLoop(
            tpl: *Template,
            err_writer: *Writer,
            script_vm: *ScriptyVM,
            script_ctx: *Context,
            script_attr_name: Span,
            code_span: Span,
        ) errors.Fatal!*Value.Iterator {
            const zone = tracy.trace(@src());
            defer zone.end();
            tracy.messageCopy(code_span.slice(tpl.src));

            tpl.setContext(script_ctx);

            const result = script_vm.run(
                tpl.arena,
                script_ctx,
                code_span.slice(tpl.src),
                .{},
            ) catch return error.Fatal;

            switch (result.value) {
                .iterator => |i| return i,
                .array => |a| return Value.Iterator.fromArray(tpl.arena, a) catch return error.Fatal,
                else => {
                    tpl.reportError(
                        err_writer,
                        script_attr_name,
                        "script_eval_not_iterable",
                        "SCRIPT RESULT TYPE MISMATCH",
                        \\A script evaluated to an unexpected type.
                        \\
                        \\This attribute expects to evaluate to one
                        \\of the following types:
                        \\   - iterable
                        ,
                    ) catch {};

                    try tpl.diagnostic(
                        err_writer,
                        false,
                        "note: value was generated from this sub-expression:",
                        .{
                            .start = code_span.start + result.loc.start,
                            .end = code_span.start + result.loc.end,
                        },
                    );
                    try result.value.renderForError(tpl.arena, err_writer);
                    return error.Fatal;
                },
            }
        }

        pub fn reportError(
            self: Template,
            err_writer: *Writer,
            bad_node: Span,
            error_code: []const u8,
            comptime title: []const u8,
            comptime msg: []const u8,
        ) errors.Fatal {
            return errors.report(
                err_writer,
                self.name,
                self.path,
                bad_node,
                self.src,
                error_code,
                title,
                msg,
            );
        }

        pub fn diagnostic(
            tpl: Template,
            err_writer: *Writer,
            bracket: bool,
            note_line: []const u8,
            bad_node: Span,
        ) error{ErrIO}!void {
            try errors.diagnostic(
                err_writer,
                tpl.name,
                tpl.path,
                bracket,
                note_line,
                bad_node,
                tpl.src,
            );
        }

        pub fn loopUp(tpl: *const Template, frame_idx: u32) Value {
            // const tpl: *const Template = @alignCast(@ptrCast(ptr));
            if (frame_idx == 0) {
                return .{
                    .err = "already at the topmost $loop value",
                };
            } else {
                const frame = tpl.loop_stack.items[frame_idx - 1];
                return .{ .iterator = frame.iterator };
            }
        }

        pub fn setContext(tpl: Template, script_ctx: *Context) void {
            script_ctx.loop = if (tpl.loop_stack.getLastOrNull()) |last|
                last.iterator
            else
                null;

            script_ctx.@"if" = if (tpl.if_stack.getLastOrNull()) |last|
                last.value
            else
                null;
        }
    };
}

fn is(str1: []const u8, str2: []const u8) bool {
    return std.ascii.eqlIgnoreCase(str1, str2);
}
