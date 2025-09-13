const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const root = @import("../../root.zig");
const Span = root.Span;
const Tokenizer = @import("../Tokenizer.zig");
const Ast = @import("../Ast.zig");
const Content = Ast.Node.Categories;
const Element = @import("../Element.zig");
const Model = Element.Model;
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;
const log = std.log.scoped(.button);

pub const script: Element = .{
    .tag = .script,
    .model = .{
        .categories = .{
            .metadata = true,
            .flow = true,
            .phrasing = true,
        },
        .content = .{ .text = true },
    },
    .meta = .{
        .categories_superset = .{
            .metadata = true,
            .flow = true,
            .phrasing = true,
        },
    },
    .attributes = .{ .dynamic = validate },
    .content = .model,
    .desc =
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/script)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-script-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "src",
        .model = .{
            .rule = .{ .url = .not_empty },
            .desc = "This attribute specifies the URI of an external script; this can be used as an alternative to embedding a script directly within a document.",
        },
    },
    .{
        .name = "type",
        .model = .{
            .desc =
            \\This attribute indicates the type of script represented.
            \\
            \\If this `<script>` element is meant to represent JavaScript code
            \\(a.k.a. a classic script), you can safely omit this attribute.
            ,
            .rule = .{
                .list = .init(.manual, .one, &.{
                    .{
                        .label = "module",
                        .desc = "This value causes the code to be treated as a JavaScript module. The processing of the script contents is deferred. The `charset` and `defer` attributes have no effect. Unlike classic scripts, module scripts require the use of the CORS protocol for cross-origin fetching.",
                    },
                    .{
                        .label = "importmap",
                        .desc = "This value indicates that the body of the element contains an import map. The import map is a JSON object that developers can use to control how the browser resolves module specifiers when importing JavaScript modules.",
                    },
                    .{
                        .label = "MIME Value",
                        .desc = "A valid MIME type, used to denote a data block, which is not processed by the user agent.",
                    },
                }),
            },
        },
    },
    .{
        .name = "async",
        .model = .{
            .rule = .bool,
            .desc =
            \\For classic scripts, if the `async` attribute is present, then
            \\the classic script will be fetched in parallel to parsing and
            \\evaluated as soon as it is available.
            \\
            \\For module scripts, if the `async` attribute is present then the
            \\scripts and all their dependencies will be fetched in parallel
            \\to parsing and evaluated as soon as they are available.
            ,
        },
    },
    .{
        .name = "defer",
        .model = .{
            .rule = .bool,
            .desc =
            \\This Boolean attribute is set to indicate to a browser that
            \\the script is meant to be executed after the document has been
            \\parsed, but before firing `DOMContentLoaded` event.
            \\
            \\Scripts with the `defer` attribute will prevent the
            \\`DOMContentLoaded` event from firing until the script has loaded
            \\and finished evaluating.
            \\
            \\# Warning:
            \\This attribute must not be used if the `src` attribute is absent
            \\(i.e., for inline scripts), in this case it would have no
            \\effect.
            \\
            \\The `defer` attribute has no effect on module scripts — they defer
            \\by default.
            \\
            \\Scripts with the `defer` attribute will execute in the order in
            \\which they appear in the document.
            \\
            \\This attribute allows the elimination of parser-blocking
            \\JavaScript where the browser would have to load and evaluate
            \\scripts before continuing to parse. `async` has a similar effect
            \\in this case.
            \\
            \\If the attribute is specified with the `async` attribute, the
            \\element will act as if only the `async` attribute is specified.
            ,
        },
    },
    .{
        .name = "blocking",
        .model = .{
            .desc = "This attribute explicitly indicates that certain operations should be blocked until the script has executed. The operations that are to be blocked must be a space-separated list of blocking tokens. ",
            .rule = .{
                .list = .init(.none, .one, &.{
                    .{
                        .label = "render",
                        .desc = "The rendering of content on the screen is blocked.",
                    },
                }),
            },
        },
    },
    .{
        .name = "crossorigin",
        .model = .{
            .rule = .cors,
            .desc = "Normal script elements pass minimal information to the `window.onerror` for scripts which do not pass the standard CORS checks. To allow error logging for sites which use a separate domain for static media, use this attribute.",
        },
    },
    .{
        .name = "fetchpriority",
        .model = Attribute.common.fetchpriority,
    },
    .{
        .name = "integrity",
        .model = .{
            .rule = .not_empty, // TODO
            .desc = "This attribute contains inline metadata that a user agent can use to verify that a fetched resource has been delivered without unexpected manipulation. The attribute must not be specified when the src attribute is absent.",
        },
    },
    .{
        .name = "nomodule",
        .model = .{
            .rule = .bool,
            .desc = "This Boolean attribute is set to indicate that the script should not be executed in browsers that support ES modules — in effect, this can be used to serve fallback scripts to older browsers that do not support modular JavaScript code.",
        },
    },
    .{
        .name = "referrerpolicy",
        .model = Attribute.common.referrerpolicy,
    },
});

fn validate(
    gpa: Allocator,
    errors: *std.ArrayListUnmanaged(Ast.Error),
    src: []const u8,
    nodes: []const Ast.Node,
    parent_idx: u32,
    node_idx: u32,
    vait: *Attribute.ValidatingIterator,
) error{OutOfMemory}!Model {
    _ = nodes;
    _ = parent_idx;

    var attrs: [attributes.list.len]?Tokenizer.Attr = @splat(null);
    while (try vait.next(gpa, src)) |attr| {
        const name = attr.name.slice(src);
        if (attributes.index(name)) |idx| {
            attrs[idx] = attr;
            continue;
        } else if (Attribute.global.get(name)) |model| {
            try model.rule.validate(gpa, errors, src, node_idx, attr);
        } else {
            if (Attribute.isData(name)) continue;
            try errors.append(gpa, .{
                .tag = .invalid_attr,
                .main_location = attr.name,
                .node_idx = node_idx,
            });
            continue;
        }
    }

    const type_value: enum {
        js,
        module,
        importmap,
        mime,
    } = if (attrs[attributes.comptimeIndex("type")]) |attr| blk: {
        const value = attr.value orelse break :blk .js;
        const value_slice = value.span.slice(src);
        if (std.ascii.eqlIgnoreCase(value_slice, "module")) {
            break :blk .module;
        }
        if (std.ascii.eqlIgnoreCase(value_slice, "importmap")) {
            break :blk .importmap;
        }

        const Set = std.StaticStringMapWithEql(
            void,
            std.static_string_map.eqlAsciiIgnoreCase,
        );
        const js_set: Set = .initComptime(.{
            .{"application/ecmascript"},
            .{"application/javascript"},
            .{"application/x-ecmascript"},
            .{"application/x-javascript"},
            .{"text/ecmascript"},
            .{"text/javascript"},
            .{"text/javascript1.0"},
            .{"text/javascript1.1"},
            .{"text/javascript1.2"},
            .{"text/javascript1.3"},
            .{"text/javascript1.4"},
            .{"text/javascript1.5"},
            .{"text/jscript"},
            .{"text/livescript"},
            .{"text/x-ecmascript"},
            .{"text/x-javascript"},
        });

        if (js_set.has(value_slice)) {
            break :blk .js;
        }

        const before = errors.items.len;
        try Attribute.validateMime(gpa, errors, src, node_idx, attr);
        const after = errors.items.len;
        if (before != after) return script.model;
        break :blk .mime;
    } else .js;

    const external: bool = if (attrs[attributes.comptimeIndex("src")]) |attr| blk: {
        const model = comptime attributes.get("src").?;
        try model.rule.validate(gpa, errors, src, node_idx, attr);

        switch (type_value) {
            .js, .module => {},
            else => try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_combination = "requires [type] to be omitted or indicate a JavaScript MIME type",
                },
                .main_location = attr.name,
                .node_idx = node_idx,
            }),
        }

        break :blk true;
    } else false;

    var allowed: [attributes.list.len]bool = @splat(external == true);
    switch (type_value) {
        .js => if (!external) {
            allowed[attributes.comptimeIndex("nomodule")] = true;
            allowed[attributes.comptimeIndex("crossorigin")] = true;
            allowed[attributes.comptimeIndex("referrerpolicy")] = true;
        },
        .module => if (external) {
            allowed[attributes.comptimeIndex("nomodule")] = false;
            allowed[attributes.comptimeIndex("defer")] = false;
        } else {
            allowed[attributes.comptimeIndex("async")] = true;
            allowed[attributes.comptimeIndex("crossorigin")] = true;
            allowed[attributes.comptimeIndex("referrerpolicy")] = true;
        },
        .importmap, .mime => allowed = @splat(false),
    }

    for (attrs[2..], allowed[2..], 2..) |maybe_attr, a, idx| {
        const attr = maybe_attr orelse continue;
        if (!a) {
            try errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_combination = "not allowed with the current state of [type] and [src]",
                },
                .main_location = attr.name,
                .node_idx = node_idx,
            });
            continue;
        }

        try attributes.list[idx].model.rule.validate(
            gpa,
            errors,
            src,
            node_idx,
            attr,
        );
    }

    return script.model;
}
