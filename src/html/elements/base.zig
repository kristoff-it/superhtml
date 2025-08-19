const std = @import("std");
const Allocator = std.mem.Allocator;
const Tokenizer = @import("../Tokenizer.zig");
const Ast = @import("../Ast.zig");
const Element = @import("../Element.zig");
const Model = Element.Model;
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;
const log = std.log.scoped(.base);

pub const base: Element = .{
    .tag = .base,
    .model = .{
        .categories = .{
            .metadata = true,
        },
        .content = .none,
    },
    .meta = .{
        .categories_superset = .{ .metadata = true },
    },
    .attributes = .{
        .dynamic = validate,
    },
    .content = .model,
    .desc =
    \\The `<base>` HTML element specifies the base URL to use for all
    \\relative URLs in a document. There can be only one `<base>` element
    \\in a document.
    \\
    \\A document's used base URL can be accessed by scripts with
    \\`Node.baseURI`. If the document has no `<base>` elements, then
    \\`baseURI` defaults to `location.href`.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/base)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-base-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "href",
        .model = .{
            .rule = .{ .custom = validateHref },
            .desc =
            \\The base URL to be used throughout the document for relative
            \\URLs. Absolute and relative URLs are allowed. `data:` and
            \\`javascript:` URLs are not allowed.
            ,
        },
    },
    .{
        .name = "target",
        .model = .{
            .rule = Attribute.common.target.rule,
            .desc =
            \\A keyword or author-defined name of the default browsing
            \\context to show the results of navigation from `<a>`, `<area>`,
            \\or `<form>` elements without explicit target attributes.
            ,
        },
    },
});

// TODO: consider moving this into validation made by <head>
fn validate(
    gpa: Allocator,
    errors: *std.ArrayListUnmanaged(Ast.Error),
    src: []const u8,
    nodes: []const Ast.Node,
    parent_idx: u32,
    node_idx: u32,
    vait: *Attribute.ValidatingIterator,
) error{OutOfMemory}!Model {
    _ = parent_idx;

    // A base element must have either an href attribute, a target attribute,
    // or both.
    var has_href = false;
    var has_target = false;
    while (try vait.next(gpa, src)) |attr| {
        const name = attr.name.slice(src);
        const model = if (attributes.index(name)) |idx| blk: {
            switch (idx) {
                else => {},
                attributes.comptimeIndex("href") => {
                    has_href = true;
                },
                attributes.comptimeIndex("target") => {
                    has_target = true;
                },
            }

            break :blk attributes.list[idx].model;
        } else Attribute.global.get(name) orelse {
            if (Attribute.isData(name)) continue;
            try errors.append(gpa, .{
                .tag = .invalid_attr,
                .main_location = attr.name,
                .node_idx = node_idx,
            });
            continue;
        };

        try model.rule.validate(gpa, errors, src, node_idx, attr);
    }

    if (!has_target and !has_href) {
        try errors.append(gpa, .{
            .tag = .{ .missing_required_attr = "[href] or [target]" },
            .main_location = vait.name,
            .node_idx = node_idx,
        });
        return base.model;
    }

    var before_idx = node_idx - 1;
    while (before_idx != 0) : (before_idx -= 1) {
        const node = nodes[before_idx];
        if (!node.kind.isElement()) continue;

        // There must be no more than one base element per document.
        if (node.kind == .base) {
            try errors.append(gpa, .{
                .tag = .{
                    .duplicate_child = .{
                        .span = node.span(src),
                        .reason = "there must be no more than one <base> per document",
                    },
                },
                .main_location = vait.name,
                .node_idx = node_idx,
            });
            break;
        }

        // A base element, if it has a target attribute, must come before any
        // elements in the tree that represent hyperlinks.
        //
        // Links are a conceptual construct, created by `a`, `area`, `form`, and
        // `link` elements
        if (has_target) switch (node.kind) {
            .a, .area, .form, .link => {
                try errors.append(gpa, .{
                    .tag = .{
                        .invalid_nesting = .{
                            .span = node.span(src),
                            .reason = "if <base> has [target], it must come before any elements that represent hyperlinks",
                        },
                    },
                    .main_location = vait.name,
                    .node_idx = node_idx,
                });
                break;
            },
            else => {},
        };

        // A base element, if it has an href attribute, must come before any
        // other elements in the tree that have attributes defined as taking
        // URLs.
        if (has_href) {
            const attrs = Attribute.element_attrs.get(node.kind);
            for (attrs.list) |named| {
                if (named.model.rule == .url) {
                    try errors.append(gpa, .{
                        .tag = .{
                            .invalid_nesting = .{
                                .span = node.span(src),
                                .reason = "if <base> has [href], it must come before any elements that have attributes defined as taking URLs",
                            },
                        },
                        .main_location = vait.name,
                        .node_idx = node_idx,
                    });
                    break;
                }
            }
        }
    }

    return base.model;
}

fn validateHref(
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

    const value_slice = std.mem.trim(u8, value.span.slice(src), &std.ascii.whitespace);

    const url = Attribute.parseUri(value_slice) catch return errors.append(gpa, .{
        .tag = .{ .invalid_attr_value = .{ .reason = "invalid URL" } },
        .main_location = attr.name,
        .node_idx = node_idx,
    });

    if (std.ascii.eqlIgnoreCase("js", url.scheme)) {
        return errors.append(gpa, .{
            .tag = .{ .invalid_attr_value = .{ .reason = "'js:' scheme not allowed" } },
            .main_location = attr.name,
            .node_idx = node_idx,
        });
    }
    if (std.ascii.eqlIgnoreCase("data", url.scheme)) {
        return errors.append(gpa, .{
            .tag = .{ .invalid_attr_value = .{ .reason = "'data:' scheme not allowed" } },
            .main_location = attr.name,
            .node_idx = node_idx,
        });
    }
}
