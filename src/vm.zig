const std = @import("std");
const Writer = std.Io.Writer;
const scripty = @import("scripty");
const tracy = @import("tracy");
const errors = @import("errors.zig");
const template = @import("template.zig");
const root = @import("root.zig");
const utils = root.utils;
const Span = root.Span;
const html = @import("html.zig");
const Ast = @import("Ast.zig");
const Node = Ast.Node;
const SuperTemplate = template.SuperTemplate;

const log = std.log.scoped(.supervm);

pub const Exception = error{
    Done,
    Quota,
    OutOfMemory,
    WantTemplate,
    WantSnippet,

    // Unrecoverable errors
    Fatal,
    ErrIO,
    OutIO,
};

pub fn VM(
    comptime Context: type,
    comptime Value: type,
) type {
    return struct {
        arena: std.mem.Allocator,
        content_name: []const u8,
        out: *Writer,
        err: *Writer,

        state: State,
        quota: usize = 100,
        templates: std.ArrayListUnmanaged(Template) = .{},
        ctx: *Context,
        scripty_vm: ScriptyVM = .{},

        // discovering templates state
        seen_templates: std.StringHashMapUnmanaged(struct {
            extend: *const Node,
            idx: usize,
        }) = .{},

        const ScriptyVM = scripty.VM(Context, Value);
        const Self = @This();

        pub const Template = SuperTemplate(ScriptyVM);
        pub const State = union(enum) {
            init: TemplateCartridge,
            discovering_templates,
            running,
            done,
            fatal,
            want_template: struct {
                name: []const u8,
                span: Span,
            },
            loaded_template: TemplateCartridge,
            want_snippet: []const u8, // snippet name

        };

        pub const TemplateCartridge = struct {
            name: []const u8,
            path: []const u8,
            src: []const u8,
            html_ast: html.Ast,
            super_ast: Ast,
            is_xml: bool,
        };

        pub fn init(
            arena: std.mem.Allocator,
            context: *Context,
            layout_name: []const u8,
            layout_path: []const u8,
            layout_src: []const u8,
            layout_html_ast: html.Ast,
            layout_super_ast: Ast,
            layout_is_xml: bool,
            content_name: []const u8,
            out_writer: *Writer,
            err_writer: *Writer,
        ) Self {
            return .{
                .arena = arena,
                .content_name = content_name,
                .ctx = context,
                .out = out_writer,
                .err = err_writer,
                .state = .{
                    .init = .{
                        .name = layout_name,
                        .path = layout_path,
                        .src = layout_src,
                        .html_ast = layout_html_ast,
                        .super_ast = layout_super_ast,
                        .is_xml = layout_is_xml,
                    },
                },
            };
        }

        // When state is `WantTemplate`, call this function
        // to get the name of the wanted template.
        pub fn wantedTemplateName(vm: Self) []const u8 {
            return vm.state.want_template.name;
        }

        // When state is `WantTemplate`, call this function to prepare the VM
        // for loading the requested template.
        pub fn insertTemplate(
            vm: *Self,
            path: []const u8,
            src: []const u8,
            html_ast: html.Ast,
            super_ast: Ast,
            is_xml: bool,
        ) void {
            const name = vm.state.want_template.name;
            vm.state = .{
                .loaded_template = .{
                    .name = name,
                    .path = path,
                    .src = src,
                    .html_ast = html_ast,
                    .super_ast = super_ast,
                    .is_xml = is_xml,
                },
            };
        }

        pub fn setQuota(vm: *Self, q: usize) void {
            vm.quota = q;
        }

        // Call this function to report an evaluation trace when the caller
        // failed to fetch a requested resource (eg templates, snippets, ...)
        pub fn reportResourceFetchError(vm: *Self, error_code: []const u8) void {
            std.debug.assert(vm.state == .want_template);
            const wanted = vm.state.want_template;
            const t = vm.templates.items[vm.templates.items.len - 1];

            t.reportError(
                vm.err,
                wanted.span,
                error_code,
                "ERROR FETCHING TEMPLATE",
                \\There was an error while fetching a template,
                \\see the error code for more information.
                ,
            ) catch {};
            vm.state = .fatal;
        }

        pub fn run(vm: *Self) Exception!void {
            if (vm.state == .fatal) return error.Fatal;

            vm.runInternal() catch |err| {
                switch (err) {
                    error.OutOfMemory,
                    error.Fatal,
                    error.OutIO,
                    error.ErrIO,
                    => vm.state = .fatal,
                    error.WantTemplate,
                    error.WantSnippet,
                    error.Quota,
                    error.Done,
                    => {},
                }
                return err;
            };
        }

        fn runInternal(vm: *Self) Exception!void {
            const zone = tracy.trace(@src());
            defer zone.end();
            while (true) switch (vm.state) {
                .done, .want_template, .want_snippet, .fatal => unreachable,
                .running => break,
                .init => try vm.loadLayout(),
                .discovering_templates => try vm.discoverTemplates(),
                .loaded_template => try vm.loadTemplate(),
            };

            // current template index
            var idx: usize = vm.templates.items.len - 1;
            while (vm.quota > 0) : (vm.quota -= 1) {
                const t = &vm.templates.items[idx];

                const continuation = t.eval(
                    &vm.scripty_vm,
                    vm.ctx,
                    vm.out,
                    vm.err,
                ) catch |err| switch (err) {
                    error.OutOfMemory,
                    error.OutIO,
                    error.ErrIO,
                    => |e| {
                        return e;
                    },
                    error.Fatal => {
                        return fatalTrace(
                            vm.content_name,
                            vm.templates.items[0 .. idx + 1],
                            vm.err,
                        );
                    },
                    error.FatalShowInterface => {
                        try vm.templates.items[idx + 1].showInterface(vm.err);
                        return fatalTrace(
                            vm.content_name,
                            vm.templates.items[0 .. idx + 1],
                            vm.err,
                        );
                    },
                };

                switch (continuation) {
                    .super_idx => |s| {
                        // loaded layouts have no super tags in them
                        std.debug.assert(idx != 0);
                        idx -= 1;

                        const super_template = &vm.templates.items[idx];
                        super_template.activateBlock(
                            &vm.scripty_vm,
                            vm.ctx,
                            // TODO: unescape
                            t.superBlock(s).id_value.span.slice(t.src),
                            vm.out,
                            vm.err,
                        ) catch {
                            @panic("TODO: error reporting");
                        };
                    },
                    .end => {
                        if (t.ast.extends_idx == 0) break;
                        idx += 1;
                        std.debug.assert(idx < vm.templates.items.len);
                    },
                }
            } else {
                try errors.header(vm.err, "INFINITE LOOP",
                    \\Super encountered a condition that caused an infinite loop.
                    \\This should not have happened, please report this error to 
                    \\the maintainers.
                );
                return error.Fatal;
            }

            for (vm.templates.items) |l| l.finalCheck();
            return error.Done;
        }

        fn loadLayout(vm: *Self) errors.FatalOOM!void {
            const cartridge = vm.state.init;

            const layout = try Template.init(
                vm.arena,
                cartridge.path,
                cartridge.name,
                cartridge.src,
                cartridge.html_ast,
                cartridge.super_ast,
                .layout,
            );

            try vm.templates.append(vm.arena, layout);
            vm.state = .discovering_templates;
            try vm.reportSyntaxErrors(layout);
        }

        const DiscoverException = error{ OutOfMemory, WantTemplate } || errors.Fatal;
        fn discoverTemplates(vm: *Self) DiscoverException!void {
            var current_idx = vm.templates.items.len - 1;
            while (vm.templates.items[current_idx].ast.extends_idx != 0) : ({
                current_idx = vm.templates.items.len - 1;
            }) {
                const current = &vm.templates.items[current_idx];
                const ext = &current.ast.nodes[current.ast.extends_idx];

                // _ = current.stack.pop();
                current.cursor.cur = null;
                const template_value = ext.templateValue();
                //TODO: unescape
                const template_name = template_value.span.slice(current.src);

                const gop = try vm.seen_templates.getOrPut(vm.arena, template_name);
                if (gop.found_existing) {
                    current.reportError(
                        vm.err,
                        template_value.span,
                        "infinite_loop",
                        "EXTENSION LOOP DETECTED",
                        "We were trying to load the same template twice!",
                    ) catch {};

                    const ctx = gop.value_ptr;
                    try vm.templates.items[ctx.idx].diagnostic(
                        vm.err,
                        false,
                        "note: the template was previously found here:",
                        ctx.extend.templateValue().span,
                    );

                    return fatalTrace(
                        vm.content_name,
                        vm.templates.items[0 .. current_idx + 1],
                        vm.err,
                    );
                }

                gop.value_ptr.* = .{
                    .extend = ext,
                    .idx = current_idx,
                };

                vm.state = .{
                    .want_template = .{
                        .name = template_name,
                        .span = template_value.span,
                    },
                };
                return error.WantTemplate;
            }

            try vm.validateInterfaces();
            vm.state = .running;
        }

        fn loadTemplate(vm: *Self) !void {
            const cartridge = vm.state.loaded_template;

            const t = try Template.init(
                vm.arena,
                cartridge.path,
                cartridge.name,
                cartridge.src,
                cartridge.html_ast,
                cartridge.super_ast,
                .template,
            );

            try vm.templates.append(vm.arena, t);
            vm.state = .discovering_templates;
            try vm.reportSyntaxErrors(t);
        }

        // This function assumes that `tpl` has already been
        // added to `vm.templates`.
        pub fn reportSyntaxErrors(vm: Self, tpl: Template) !void {
            const advice =
                \\A syntax error was found inside one of your SuperHTML 
                \\template files.
                \\
                \\It's strongly recommended to setup your editor to 
                \\leverage the `superhtml` CLI tool in order to obtain 
                \\in-editor syntax checking and autoformatting. 
                \\
                \\Download it from here:
                \\   https://github.com/kristoff-it/superhtml
            ;
            if (tpl.html.errors.len > 0) {
                const first_err = tpl.html.errors[0];
                switch (first_err.tag) {
                    inline else => |tag| tpl.reportError(
                        vm.err,
                        first_err.main_location,
                        @tagName(tag),
                        "HTML SYNTAX ERROR(S)",
                        advice,
                    ) catch {},
                }
                for (tpl.html.errors[1..]) |err| {
                    switch (err.tag) {
                        inline else => |tag| try tpl.diagnostic(
                            vm.err,
                            true,
                            @tagName(tag),
                            err.main_location,
                        ),
                    }
                }
                const current_idx = vm.templates.items.len;
                return fatalTrace(
                    vm.content_name,
                    vm.templates.items[0..current_idx],
                    vm.err,
                );
            }

            if (tpl.ast.errors.len > 0) {
                const first_err = tpl.ast.errors[0];
                tpl.reportError(
                    vm.err,
                    first_err.main_location,
                    @tagName(first_err.kind),
                    "SUPER TEMPLATE SYNTAX ERROR(S)",
                    advice,
                ) catch {};

                for (tpl.ast.errors[1..]) |err| {
                    try tpl.diagnostic(
                        vm.err,
                        true,
                        @tagName(err.kind),
                        err.main_location,
                    );
                }
                const current_idx = vm.templates.items.len;
                return fatalTrace(
                    vm.content_name,
                    vm.templates.items[0..current_idx],
                    vm.err,
                );
            }
        }

        fn validateInterfaces(vm: Self) !void {
            const templates = vm.templates.items;
            std.debug.assert(templates.len > 0);
            if (templates.len == 1) return;

            var idx = templates.len - 1;
            while (idx > 0) : (idx -= 1) {
                const extended = templates[idx];
                const super = templates[idx - 1];

                var it = extended.ast.interface.iterator();
                var blocks = try super.ast.blocks.clone(vm.arena);
                defer blocks.deinit(vm.arena);
                while (it.next()) |kv| {
                    // super parent element id
                    const extended_id = kv.key_ptr.*;
                    // ast node idx of super parent element
                    const extended_super_element_idx = kv.value_ptr.*;

                    const block_kv = blocks.fetchRemove(extended_id) orelse {
                        try errors.header(
                            vm.err,
                            "MISSING TOP-LEVEL BLOCK",
                            \\A template that extends another must have a  
                            \\top-level element (called 'block' in Zine) for 
                            \\each <super> element in the template being 
                            \\extended.
                            \\
                            \\Each block must match both 'id' and tag name of
                            \\the element that contains <super> in the template
                            \\being extended.
                            ,
                        );
                        try super.showBlocks(vm.err);

                        const super_parent_id = extended.superBlock(extended_super_element_idx).id_value;
                        try extended.diagnostic(
                            vm.err,
                            false,
                            "note: extended block defined here:",
                            super_parent_id.span,
                        );

                        const super_tag_name = extended.getName(
                            extended_super_element_idx,
                        );
                        try extended.diagnostic(
                            vm.err,
                            false,
                            "note: extended template super tag:",
                            super_tag_name,
                        );

                        try extended.showInterface(vm.err);
                        return fatalTrace(
                            vm.content_name,
                            templates[0..idx],
                            vm.err,
                        );
                    };

                    const super_parent_name = extended.superBlock(
                        extended_super_element_idx,
                    ).parent_tag_name;
                    const super_parent_name_slice = super_parent_name.slice(extended.src);

                    const block_idx = block_kv.value;
                    const block_name = super.getName(block_idx);
                    const block_name_string = block_name.slice(super.src);

                    if (!is(block_name_string, super_parent_name_slice)) {
                        try errors.header(vm.err, "MISMATCHED BLOCK TAG",
                            \\A template defines a block that has the wrong element name.
                            \\Both element names and ids must match in order to avoid confusion
                            \\about where the block contents are going to be placed in
                            \\the extended template.
                        );

                        try super.diagnostic(
                            vm.err,
                            false,
                            "note: super template block name:",
                            block_name,
                        );

                        try extended.diagnostic(
                            vm.err,
                            false,
                            "note: extended template super parent defined here:",
                            super_parent_name,
                        );

                        return fatalTrace(
                            vm.content_name,
                            templates[0..idx],
                            vm.err,
                        );
                    }
                }

                var unbound_it = blocks.iterator();
                var unbound_idx: usize = 0;
                while (unbound_it.next()) |kv| : (unbound_idx += 1) {
                    const block_idx = kv.value_ptr.*;
                    const block_name = super.getName(block_idx);
                    if (unbound_idx == 0) {
                        super.reportError(
                            vm.err,
                            block_name,
                            "unbound_block",
                            "UNBOUND TOP-LEVEL BLOCK",
                            \\Found an unbound block, i.e. the extended template doesn't declare
                            \\a corresponding <super>. Either remove it from the current
                            \\template, or add a <super> in the extended template.
                            ,
                        ) catch {};
                    } else {
                        try super.diagnostic(
                            vm.err,
                            false,
                            "error: another unbound block is here:",
                            block_name,
                        );
                    }
                }
                if (unbound_idx > 0) return fatalTrace(
                    vm.content_name,
                    templates[0..idx],
                    vm.err,
                );

                // Should already been validated by the parser.
                const layout = templates[0];
                std.debug.assert(layout.ast.interface.count() == 0);
            }
        }

        fn fatalTrace(
            content_name: []const u8,
            items: []const Template,
            err_writer: *Writer,
        ) errors.Fatal {
            err_writer.print("trace:\n", .{}) catch return error.ErrIO;
            var cursor = items.len - 1;
            while (cursor > 0) : (cursor -= 1) {
                err_writer.print("    template `{s}`,\n", .{
                    items[cursor].name,
                }) catch return error.ErrIO;
            }

            if (items.len > 0) err_writer.print("    layout `{s}`,\n", .{items[0].name}) catch return error.ErrIO;

            err_writer.print("    content `{s}`.", .{content_name}) catch return error.ErrIO;

            return error.Fatal;
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
