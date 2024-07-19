const std = @import("std");
const scripty = @import("scripty");
const root = @import("root.zig");
const Span = root.Span;
const errors = @import("errors.zig");
const html = @import("html.zig");
const Ast = @import("Ast.zig");
const Node = Ast.Node;

const log = std.log.scoped(.supertemplate);

pub fn SuperTemplate(comptime Context: type, comptime Value: type, comptime OutWriter: type) type {
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

        // Template-wide analysis
        eval_frame: std.ArrayListUnmanaged(EvalFrame) = .{},

        const Self = @This();
        const ScriptyVM = scripty.ScriptyVM(Context, Value);
        const EvalFrame = union(enum) {
            if_condition: IfCondition,
            loop_condition: LoopCondition,
            loop_iter: LoopIter,
            default: Ast.Cursor,

            const LoopIter = struct {
                cursor: Ast.Cursor,
                loop: Value.IterElement,
            };

            const LoopCondition = struct {
                /// if set, it's an inline-loop
                /// (ie container element must be duplicated)
                inloop_idx: ?u32 = null,
                /// pointer to the parent print cursor
                cursor_ptr: *Ast.Cursor,
                /// start of the loop body
                print_loop_body: u32,
                // end of the loop body (ie end_tag)
                print_loop_body_end: u32,
                // previous print_end value
                print_end: u32,
                // eval result
                iter: Value.Iterator,
                // iteration progress counter
                index: usize,
            };

            const IfCondition = struct {
                /// cursor scoped to the if body
                cursor: Ast.Cursor,
                // eval result
                if_result: ?Value,
            };
        };

        const Role = enum { layout, template };

        pub fn superBlock(tpl: Self, idx: u32) Ast.Node.Block {
            return tpl.ast.nodes[idx].superBlock(tpl.src, tpl.html);
        }

        pub fn startTag(tpl: Self, idx: u32) Span {
            return tpl.ast.nodes[idx].elem(tpl.html).open;
        }

        pub fn getName(tpl: Self, idx: u32) Span {
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
        ) !Self {
            var t: Self = .{
                .arena = arena,
                .path = path,
                .name = name,
                .src = src,
                .html = html_ast,
                .ast = ast,
                .role = role,
                .print_end = @intCast(src.len),
            };
            try t.eval_frame.append(arena, .{
                .default = t.ast.cursor(0),
            });
            return t;
        }

        pub fn finalCheck(tpl: Self) void {
            std.debug.assert(tpl.print_cursor == tpl.print_end);
        }

        pub fn showBlocks(tpl: Self, err_writer: errors.ErrWriter) error{ErrIO}!void {
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

        pub fn showInterface(tpl: Self, err_writer: errors.ErrWriter) error{ErrIO}!void {
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
            tpl: *Self,
            script_vm: *ScriptyVM,
            script_ctx: *Context,
            super_id: []const u8,
            writer: OutWriter,
            err_writer: errors.ErrWriter,
        ) errors.FatalOOM!void {
            std.debug.assert(tpl.ast.extends_idx != 0);
            std.debug.assert(tpl.eval_frame.items.len == 0);

            const block_idx = tpl.ast.blocks.get(super_id).?;
            const block = tpl.ast.nodes[block_idx];

            log.debug("activating block_idx = {}, '{s}'", .{
                block_idx,
                block.elem(tpl.html).open.slice(tpl.src),
            });
            try tpl.eval_frame.append(tpl.arena, .{
                .default = tpl.ast.cursor(block_idx),
            });

            tpl.print_cursor = block.elem(tpl.html).open.end;
            tpl.print_end = block.elem(tpl.html).close.start;

            switch (block.kind.branching()) {
                else => unreachable,
                .none => {},
                .@"if" => {
                    const scripted_attr = block.ifAttr();
                    const attr = scripted_attr.attr;
                    const value = block.ifValue();

                    const result = try tpl.evalIf(
                        err_writer,
                        script_vm,
                        script_ctx,
                        attr.name,
                        value.span,
                    );

                    switch (result) {
                        else => unreachable,
                        .optional => @panic("TODO: implement optional if for blocks"),
                        .bool => |b| {
                            if (!b) {
                                const elem = block.elem(tpl.html);
                                switch (elem.kind) {
                                    .root, .comment, .text => unreachable,
                                    .element_void,
                                    .element_self_closing,
                                    .doctype,
                                    => {
                                        tpl.print_cursor = elem.open.end;
                                    },
                                    .element => {
                                        tpl.print_cursor = elem.close.start;
                                        const frame = &tpl.eval_frame.items[0];
                                        frame.default.skipChildrenOfCurrentNode();
                                    },
                                }
                            }
                        },
                    }
                },
            }

            switch (block.kind.output()) {
                .@"var" => {
                    const scripted_attr = block.varAttr();
                    const attr = scripted_attr.attr;
                    const value = block.varValue();

                    const var_value = try tpl.evalVar(
                        err_writer,
                        script_vm,
                        script_ctx,
                        attr.name,
                        value.span,
                    );

                    switch (var_value) {
                        .string => |s| writer.writeAll(s) catch return error.OutIO,
                        .int => |i| writer.print("{}", .{i}) catch return error.OutIO,
                        else => unreachable,
                    }
                },
                else => {},
            }
            // TODO: void tag dude
        }

        pub const Continuation = union(enum) {
            // A <super> was found, contains relative id
            super_idx: u32,
            end,
        };

        pub fn eval(
            tpl: *Self,
            script_vm: *ScriptyVM,
            script_ctx: *Context,
            writer: OutWriter,
            err_writer: errors.ErrWriter,
        ) errors.FatalShowOOM!Continuation {
            std.debug.assert(tpl.eval_frame.items.len > 0);
            outer: while (tpl.eval_frame.items.len > 0) {
                const current_context = &tpl.eval_frame.items[tpl.eval_frame.items.len - 1];
                switch (current_context.*) {
                    .default, .loop_iter, .if_condition => {},
                    .loop_condition => |*l| {
                        if (l.iter.next(tpl.arena)) |n| {
                            var cursor_copy = l.cursor_ptr.*;
                            cursor_copy.depth = 0;
                            try tpl.eval_frame.append(tpl.arena, .{
                                .loop_iter = .{
                                    .cursor = cursor_copy,
                                    .loop = n.iter_elem,
                                },
                            });
                            tpl.print_cursor = l.print_loop_body;
                            tpl.print_end = l.print_loop_body_end;
                            l.index += 1;
                            if (l.inloop_idx) |node_idx| {
                                // print container element start tag
                                const node = tpl.ast.nodes[node_idx];
                                const start_tag = node.elem(tpl.html).open;
                                const scripted_attr = node.loopAttr();
                                const attr = scripted_attr.attr;

                                const up_to_attr = tpl.src[tpl.print_cursor..attr.span().start];
                                writer.writeAll(up_to_attr) catch return error.OutIO;
                                const rest_of_start_tag = tpl.src[attr.span().end..start_tag.end];
                                writer.writeAll(rest_of_start_tag) catch return error.OutIO;
                                tpl.print_cursor = start_tag.end;
                            }
                            continue;
                        } else {
                            tpl.print_cursor = l.print_loop_body_end;
                            tpl.print_end = l.print_end;
                            l.cursor_ptr.skipChildrenOfCurrentNode();
                            _ = tpl.eval_frame.pop();
                            continue;
                        }
                    },
                }
                const cur = switch (current_context.*) {
                    .default => |*d| d,
                    .loop_iter => |*li| &li.cursor,
                    .if_condition => |*ic| &ic.cursor,
                    .loop_condition => unreachable,
                };
                while (cur.next()) |node| {
                    switch (node.kind.role()) {
                        .root, .extend, .block, .super_block => {
                            std.debug.print("unexpected '{s}'", .{
                                @tagName(node.kind),
                            });
                            unreachable;
                        },
                        .super => {
                            writer.writeAll(
                                tpl.src[tpl.print_cursor..node.elem(tpl.html).open.start],
                            ) catch return error.OutIO;
                            tpl.print_cursor = node.elem(tpl.html).open.end;
                            log.debug("SWITCHING TEMPLATE, SUPER TAG: ({}) {}", .{
                                cur.current_idx,
                                node.elem(tpl.html).open.range(tpl.src),
                            });

                            return .{ .super_idx = cur.current_idx };
                        },
                        .element => {},
                    }

                    switch (node.kind.branching()) {
                        else => @panic("TODO: more branching support in eval"),
                        .none => {},
                        .inloop => {
                            const start_tag = node.elem(tpl.html).open;
                            const scripted_attr = node.loopAttr();
                            const attr = scripted_attr.attr;
                            const value = node.loopValue();

                            const elem_start = start_tag.start;
                            const up_to_elem = tpl.src[tpl.print_cursor..elem_start];
                            tpl.print_cursor = elem_start;
                            writer.writeAll(up_to_elem) catch return error.OutIO;

                            const iter = try tpl.evalLoop(
                                err_writer,
                                script_vm,
                                script_ctx,
                                attr.name,
                                value.span,
                            );

                            try tpl.eval_frame.append(tpl.arena, .{
                                .loop_condition = .{
                                    .inloop_idx = cur.current_idx,
                                    .print_loop_body = tpl.print_cursor,
                                    .print_loop_body_end = node.elem(tpl.html).close.end,
                                    .print_end = tpl.print_end,
                                    .cursor_ptr = cur,
                                    .iter = iter,
                                    .index = 0,
                                },
                            });

                            continue :outer;
                        },
                        .loop => {
                            const start_tag = node.elem(tpl.html).open;
                            const scripted_attr = node.loopAttr();
                            const attr = scripted_attr.attr;
                            const value = node.loopValue();

                            const up_to_attr = tpl.src[tpl.print_cursor..attr.span().start];
                            writer.writeAll(up_to_attr) catch return error.OutIO;
                            const rest_of_start_tag = tpl.src[attr.span().end..start_tag.end];
                            writer.writeAll(rest_of_start_tag) catch return error.OutIO;
                            tpl.print_cursor = start_tag.end;

                            const iter = try tpl.evalLoop(
                                err_writer,
                                script_vm,
                                script_ctx,
                                attr.name,
                                value.span,
                            );

                            try tpl.eval_frame.append(tpl.arena, .{
                                .loop_condition = .{
                                    .print_loop_body = tpl.print_cursor,
                                    .print_loop_body_end = node.elem(tpl.html).close.start,
                                    .print_end = tpl.print_end,
                                    .cursor_ptr = cur,
                                    .iter = iter,
                                    .index = 0,
                                },
                            });

                            continue :outer;
                        },
                        .@"if" => {
                            const start_tag = node.elem(tpl.html).open;
                            const scripted_attr = node.ifAttr();
                            const attr = scripted_attr.attr;
                            const value = node.ifValue();

                            const up_to_attr = tpl.src[tpl.print_cursor..attr.span().start];
                            writer.writeAll(up_to_attr) catch return error.OutIO;
                            const rest_of_start_tag = tpl.src[attr.span().end..start_tag.end];
                            writer.writeAll(rest_of_start_tag) catch return error.OutIO;
                            tpl.print_cursor = start_tag.end;

                            const result = try tpl.evalIf(
                                err_writer,
                                script_vm,
                                script_ctx,
                                attr.name,
                                value.span,
                            );

                            switch (result) {
                                else => unreachable,
                                .bool => |b| {
                                    if (!b) {
                                        tpl.print_cursor = node.elem(tpl.html).close.start;
                                        // TODO: void tags :^)
                                        cur.skipChildrenOfCurrentNode();
                                    }
                                },
                                .optional => |opt| {
                                    if (opt) |o| {
                                        // if resulted in a non-boolean value
                                        var new_frame: EvalFrame = .{
                                            .if_condition = .{
                                                .cursor = cur.*,
                                                .if_result = Value.from(tpl.arena, o),
                                            },
                                        };

                                        new_frame.if_condition.cursor.depth = 0;
                                        try tpl.eval_frame.append(
                                            tpl.arena,
                                            new_frame,
                                        );

                                        cur.skipChildrenOfCurrentNode();
                                        continue :outer;
                                    } else {
                                        tpl.print_cursor = node.elem(tpl.html).close.start;
                                        // TODO: void tags :^)
                                        cur.skipChildrenOfCurrentNode();
                                    }
                                },
                            }
                        },
                    }

                    var it = node.elem(tpl.html).startTagIterator(tpl.src, tpl.html.language);
                    while (it.next(tpl.src)) |attr| {
                        const value = attr.value orelse continue;
                        if (value.span.len() == 0) continue;

                        const attr_name = attr.name.slice(tpl.src);
                        if (is(attr_name, "var") or
                            is(attr_name, "if") or
                            is(attr_name, "loop")) continue;

                        // TODO: unescape
                        const code = value.span.slice(tpl.src);
                        if (code[0] != '$') continue;
                        // defer code.deinit(tpl.arena);

                        const result = try tpl.evalAttr(
                            script_vm,
                            script_ctx,
                            value.span,
                        );

                        const attr_string = switch (result.value) {
                            .string => |s| s,
                            else => {
                                tpl.reportError(
                                    err_writer,
                                    attr.name,
                                    "script_eval",
                                    "SCRIPT RUNTIME ERROR",
                                    \\A script evaluated to an unxepected type.
                                    \\
                                    \\This attribute expects to evaluate to one
                                    \\of the following types:
                                    \\   - string
                                    ,
                                ) catch {};

                                try tpl.diagnostic(
                                    err_writer,
                                    false,
                                    "note: value was generated from this sub-expression:",
                                    .{
                                        .start = value.span.start + result.loc.start,
                                        .end = value.span.start + result.loc.end,
                                    },
                                );
                                try result.value.renderForError(
                                    tpl.arena,
                                    err_writer,
                                );
                                return error.Fatal;
                            },
                        };

                        const up_to_value = tpl.src[tpl.print_cursor..value.span.start];
                        writer.writeAll(up_to_value) catch return error.OutIO;
                        writer.writeAll(attr_string) catch return error.OutIO;
                        tpl.print_cursor = value.span.end;
                    }

                    switch (node.kind.output()) {
                        .none => {},
                        .@"var" => {
                            const start_tag = node.elem(tpl.html).open;
                            const scripted_attr = node.varAttr();
                            const attr = scripted_attr.attr;
                            const value = node.varValue();

                            const var_value = try tpl.evalVar(
                                err_writer,
                                script_vm,
                                script_ctx,
                                attr.name,
                                value.span,
                            );

                            log.debug("code = '{s}', print_cursor: {}, attr_end: {}", .{
                                value.span.slice(tpl.src),
                                (root.Span{ .start = tpl.print_cursor, .end = tpl.print_cursor }).range(tpl.src).start,
                                (root.Span{ .start = attr.name.start, .end = attr.name.end }).range(tpl.src).start,
                            });

                            const up_to_attr = tpl.src[tpl.print_cursor..attr.span().start];
                            writer.writeAll(up_to_attr) catch return error.OutIO;
                            const rest_of_start_tag = tpl.src[attr.span().end..start_tag.end];
                            writer.writeAll(rest_of_start_tag) catch return error.OutIO;
                            tpl.print_cursor = start_tag.end;

                            switch (var_value) {
                                .string => |s| writer.writeAll(s) catch return error.OutIO,
                                .int => |i| writer.print("{}", .{i}) catch return error.OutIO,
                                else => unreachable,
                            }
                        },
                        .ctx => @panic("TODO: implement ctx"),
                    }
                }

                if (tpl.eval_frame.popOrNull()) |ctx| {
                    if (ctx == .if_condition) continue;
                    // finalization
                    std.debug.assert(ctx != .loop_condition);
                    writer.writeAll(
                        tpl.src[tpl.print_cursor..tpl.print_end],
                    ) catch return error.OutIO;
                    tpl.print_cursor = tpl.print_end;
                }
            }

            std.debug.assert(tpl.print_cursor == tpl.print_end);
            return .end;
        }

        fn evalVar(
            tpl: *Self,
            err_writer: errors.ErrWriter,
            script_vm: *ScriptyVM,
            script_ctx: *Context,
            script_attr_name: Span,
            code_span: Span,
        ) errors.Fatal!Value {
            const current_eval_frame = &tpl.eval_frame.items[tpl.eval_frame.items.len - 1];
            const loop = switch (current_eval_frame.*) {
                .loop_iter => |li| li.loop,
                else => null,
            };

            const old_loop = script_ctx.loop;
            script_ctx.loop = if (loop) |l| .{ .iterator_element = l } else null;
            defer script_ctx.loop = old_loop;
            // if (loop) |l| switch (l.it) {
            //     .string => std.debug.print("loop it.string = `{s}`\n", .{l.it.string}),
            // };

            // if
            const if_value = switch (current_eval_frame.*) {
                .if_condition => |ic| ic.if_result,
                else => null,
            };
            const old_if = script_ctx.@"if";
            script_ctx.@"if" = if_value;
            defer script_ctx.@"if" = old_if;

            // const diag: script.Interpreter.Diagnostics = .{};
            const result = script_vm.run(
                tpl.arena,
                script_ctx,
                code_span.slice(tpl.src),
                .{},
            ) catch |err| {
                std.debug.panic("TODO: handle scripty vm error: {s}", .{
                    @errorName(err),
                });
            };

            switch (result.value) {
                .string, .int => {},
                else => {
                    tpl.reportError(
                        err_writer,
                        script_attr_name,
                        "script_eval_not_string_or_int",
                        "SCRIPT RESULT TYPE MISMATCH",
                        \\A script evaluated to an unxepected type.
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
        fn evalAttr(
            tpl: *Self,
            script_vm: *ScriptyVM,
            script_ctx: *Context,
            code_span: Span,
        ) errors.Fatal!ScriptyVM.Result {
            const current_eval_frame = &tpl.eval_frame.items[tpl.eval_frame.items.len - 1];
            const loop = switch (current_eval_frame.*) {
                .loop_iter => |li| li.loop,
                else => null,
            };

            const old_loop = script_ctx.loop;
            script_ctx.loop = if (loop) |l| .{ .iterator_element = l } else null;
            defer script_ctx.loop = old_loop;
            // if (loop) |l| switch (l.it) {
            //     .string => std.debug.print("loop it.string = `{s}`\n", .{l.it.string}),
            // };

            // if
            const if_value = switch (current_eval_frame.*) {
                .if_condition => |ic| ic.if_result,
                else => null,
            };
            const old_if = script_ctx.@"if";
            script_ctx.@"if" = if_value;
            defer script_ctx.@"if" = old_if;

            // const diag: script.Interpreter.Diagnostics = .{};
            const result = script_vm.run(
                tpl.arena,
                script_ctx,
                code_span.slice(tpl.src),
                .{},
            ) catch |err| {
                std.debug.panic("TODO: handle scripty vm error: {s}", .{
                    @errorName(err),
                });
            };

            return result;
        }

        fn evalIf(
            tpl: *Self,
            err_writer: errors.ErrWriter,
            script_vm: *ScriptyVM,
            script_ctx: *Context,
            script_attr_name: Span,
            code_span: Span,
        ) errors.Fatal!Value {
            const current_eval_frame = &tpl.eval_frame.items[tpl.eval_frame.items.len - 1];
            // loop
            const loop = switch (current_eval_frame.*) {
                .loop_iter => |li| li.loop,
                else => null,
            };

            const old_loop = script_ctx.loop;
            script_ctx.loop = if (loop) |l| .{ .iterator_element = l } else null;
            defer script_ctx.loop = old_loop;
            // if
            const if_value = switch (current_eval_frame.*) {
                .if_condition => |ic| ic.if_result,
                else => null,
            };

            const old_if = script_ctx.@"if";
            script_ctx.@"if" = if_value;
            defer script_ctx.@"if" = old_if;
            // std.debug.print("({s}) evalIf if: {any}\n", .{ self.name, script_ctx });
            // const diag: script.Interpreter.Diagnostics = .{};
            const result = script_vm.run(
                tpl.arena,
                script_ctx,
                code_span.slice(tpl.src),
                .{},
            ) catch |err| {
                std.debug.panic("TODO: handle scripty vm error: {s}", .{
                    @errorName(err),
                });
            };

            switch (result.value) {
                .bool, .optional => {},
                else => {
                    tpl.reportError(
                        err_writer,
                        script_attr_name,
                        "script_eval_not_bool",
                        "SCRIPT RESULT TYPE MISMATCH",
                        \\A script evaluated to an unxepected type.
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
            tpl: *Self,
            err_writer: errors.ErrWriter,
            script_vm: *ScriptyVM,
            script_ctx: *Context,
            script_attr_name: Span,
            code_span: Span,
        ) errors.Fatal!Value.Iterator {

            // const diag: script.Interpreter.Diagnostics = .{};
            const result = script_vm.run(
                tpl.arena,
                script_ctx,
                code_span.slice(tpl.src),
                .{},
            ) catch |err| {
                std.debug.panic("TODO: handle scripty vm error: {s}", .{
                    @errorName(err),
                });
            };

            switch (result.value) {
                .iterator => |i| return i,
                else => {
                    tpl.reportError(
                        err_writer,
                        script_attr_name,
                        "script_eval_not_iterable",
                        "SCRIPT RESULT TYPE MISMATCH",
                        \\A script evaluated to an unxepected type.
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
            self: Self,
            err_writer: errors.ErrWriter,
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
            tpl: Self,
            err_writer: errors.ErrWriter,
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
    };
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

fn is(str1: []const u8, str2: []const u8) bool {
    return std.ascii.eqlIgnoreCase(str1, str2);
}
