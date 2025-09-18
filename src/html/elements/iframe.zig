const std = @import("std");
const Allocator = std.mem.Allocator;
const root = @import("../../root.zig");
const Language = root.Language;
const Span = root.Span;
const Tokenizer = @import("../Tokenizer.zig");
const Ast = @import("../Ast.zig");
const Element = @import("../Element.zig");
const Model = Element.Model;
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;

pub const iframe: Element = .{
    .tag = .iframe,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
            // .embedded = true,
            .interactive = true,
        },
        .content = .none,
    },
    .meta = .{
        .categories_superset = .{
            .flow = true,
            .phrasing = true,
            // .embedded = true,
            .interactive = true,
        },
    },
    .attributes = .{ .dynamic = validate },
    .content = .model,

    .desc =
    \\The `<iframe>` HTML element represents a nested browsing context,
    \\embedding another HTML page into the current one.
    \\
    \\Each embedded browsing context has its own document and allows URL
    \\navigations. The navigations of each embedded browsing context are
    \\linearized into the session history of the topmost browsing context.
    \\The browsing context that embeds the others is called the parent
    \\browsing context. The topmost browsing context — the one with no
    \\parent — is usually the browser window, represented by the `Window`
    \\object.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/iframe)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/semantics.html#the-iframe-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "src",
        .model = .{
            .rule = .{ .url = .not_empty },
            .desc = "The URL of the page to embed. Use a value of `about:blank` to embed an empty page that conforms to the same-origin policy. Also note that programmatically removing an `<iframe>`'s src attribute (e.g., via `Element.removeAttribute()`) causes `about:blank` to be loaded in the frame in Firefox (from version 65), Chromium-based browsers, and Safari/iOS.",
        },
    },
    .{
        .name = "srcdoc",
        .model = .{
            .rule = .any,
            .desc = "Inline HTML to embed, overriding the `src` attribute. Its content should follow the syntax of a full HTML document, which includes the doctype directive, `<html>`, `<body>` tags, etc., although most of them can be omitted, leaving only the body content. This doc will have `about:srcdoc` as its location. If a browser does not support the `srcdoc` attribute, it will fall back to the URL in the `src` attribute.",
        },
    },
    .{
        .name = "name",
        .model = .{
            .rule = .not_empty,
            .desc =
            \\A targetable name for the embedded browsing context. This
            \\can be used in the target attribute of the `<a>`, `<form>`,
            \\or `<base>` elements; the `formtarget` attribute of the
            \\`<input>` or `<button>` elements; or the `windowName`
            \\parameter in the `window.open()` method. In addition, the
            \\name becomes a property of the `Window` and `Document`
            \\objects, containing a reference to the embedded window or
            \\the element itself.
            ,
        },
    },
    .{
        .name = "sandbox",
        .model = .{
            .desc =
            \\Controls the restrictions applied to the content embedded
            \\in the `<iframe>`. The value of the attribute can either be
            \\empty to apply all restrictions, or space-separated tokens
            \\to lift particular restrictions.
            \\
            \\## Note
            \\
            \\- When the embedded document has the same origin as the
            \\  embedding page, it is strongly discouraged to use both
            \\  `allow-scripts` and `allow-same-origin`, as that lets the
            \\  embedded document remove the sandbox attribute — making it
            \\  no more secure than not using the sandbox attribute at all.
            \\
            \\- Sandboxing is useless if the attacker can display content
            \\  outside a sandboxed iframe — such as if the viewer opens the
            \\  frame in a new tab. Such content should be also served from
            \\  a separate origin to limit potential damage.
            ,
            .rule = .{
                .list = .init(.none, .many_unique, &.{
                    .{
                        .label = "allow-downloads",
                        .desc = "Allows downloading files through an `<a>` or `<area>` element with the download attribute, as well as through the navigation that leads to a download of a file. This works regardless of whether the user clicked on the link, or JS code initiated it without user interaction.",
                    },
                    .{
                        .label = "allow-forms",
                        .desc = "Allows the page to submit forms. If this keyword is not used, a form will be displayed as normal, but submitting it will not trigger input validation, send data to a web server, or close a dialog.",
                    },
                    .{
                        .label = "allow-modals",
                        .desc = "Allows the page to open modal windows by `Window.alert()`, `Window.confirm()`, `Window.print()` and `Window.prompt()`, while opening a `<dialog>` is allowed regardless of this keyword. It also allows the page to receive `BeforeUnloadEvent` event.",
                    },
                    .{
                        .label = "allow-pointer-lock",
                        .desc = "Allows the page to use the Pointer Lock API.",
                    },
                    .{
                        .label = "allow-popups",
                        .desc = "Allows popups (created, for example, by `Window.open()` or `target=\"_blank\"`). If this keyword is not used, such functionality will silently fail.",
                    },
                    .{
                        .label = "allow-popups-to-escape-sandbox",
                        .desc = "Allows a sandboxed document to open a new browsing context without forcing the sandboxing flags upon it. This will allow, for example, a third-party advertisement to be safely sandboxed without forcing the same restrictions upon the page the ad links to. If this flag is not included, a redirected page, popup window, or new tab will be subject to the same sandbox restrictions as the originating `<iframe>`.",
                    },
                    .{
                        .label = "allow-presentation",
                        .desc = "Allows embedders to have control over whether an iframe can start a presentation session.",
                    },
                    .{
                        .label = "allow-same-origin,",
                        .desc = "If this token is not used, the resource is treated as being from a special origin that always fails the same-origin policy (potentially preventing access to data storage/cookies and some JavaScript APIs).",
                    },
                    .{
                        .label = "allow-scripts",
                        .desc = "Allows the page to run scripts (but not create pop-up windows). If this keyword is not used, this operation is not allowed.",
                    },
                    .{
                        .label = "allow-storage-access-by-user-activation",
                        .desc = "Allows a document loaded in the <iframe> to use the Storage Access API to request access to unpartitioned cookies.",
                    },
                    .{
                        .label = "allow-top-navigation",
                        .desc = "Lets the resource navigate the top-level browsing context (the one named `_top`).",
                    },
                    .{
                        .label = "allow-top-navigation-by-user-activation",
                        .desc = "Lets the resource navigate the top-level browsing context, but only if initiated by a user gesture.",
                    },
                    .{
                        .label = "allow-top-navigation-to-custom-protocols",
                        .desc = "Allows navigations to non-http protocols built into browser or registered by a website. This feature is also activated by `allow-popups` or `allow-top-navigation` keywords.",
                    },
                    .{
                        .label = "allow-orientation-lock",
                        .desc = "Lets the resource lock the screen orientation.",
                    },
                }),
            },
        },
    },
    .{
        .name = "allow",
        .model = .{
            .desc = "Specifies a Permissions Policy for the `<iframe>`. The policy defines what features are available to the `<iframe>` (for example, access to the microphone, camera, battery, web-share, etc.) based on the origin of the request.",
            .rule = .{ .custom = validateAllow },
        },
    },
    .{
        .name = "allowfullscreen",
        .model = .{
            .rule = .bool,
            .desc = "When present the `<iframe>` can activate fullscreen mode by calling the `requestFullscreen()` method.",
        },
    },
    .{
        .name = "width",
        .model = .{
            .rule = .{ .non_neg_int = .{} },
            .desc = "The width of the frame in CSS pixels. Default is 300.",
        },
    },
    .{
        .name = "height",
        .model = .{
            .rule = .{ .non_neg_int = .{} },
            .desc = "The height of the frame in CSS pixels. Default is 150.",
        },
    },
    .{
        .name = "referrerpolicy",
        .model = Attribute.common.referrerpolicy,
    },
    .{
        .name = "loading",
        .model = .{
            .desc = "Indicates when the browser should load the iframe",
            .rule = .{
                .list = .init(.none, .one, &.{
                    .{
                        .label = "eager",
                        .desc = "Load the iframe immediately on page load (this is the default value).",
                    },
                    .{
                        .label = "lazy",
                        .desc = "Defer loading of the iframe until it reaches a calculated distance from the visual viewport, as defined by the browser. The intent is to avoid using the network and storage bandwidth required to fetch the frame until the browser is reasonably certain that it will be needed. This improves the performance and cost in most typical use cases, in particular by reducing initial page load times.",
                    },
                }),
            },
        },
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

    // If the itemprop attribute is specified on an iframe element, then the src attribute must also be specified.

    var has_src = false;
    var has_itemprop = false;
    while (try vait.next(gpa, src)) |attr| {
        const name = attr.name.slice(src);
        const model = if (attributes.index(name)) |idx| blk: {
            if (idx == attributes.comptimeIndex("src")) {
                has_src = true;
            }

            break :blk attributes.list[idx].model;
        } else if (Attribute.global.index(name)) |idx| blk: {
            if (idx == Attribute.global.comptimeIndex("itemprop")) {
                has_itemprop = true;
            }
            break :blk Attribute.global.list[idx].model;
        } else {
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

    if (has_itemprop and !has_src) try errors.append(gpa, .{
        .tag = .{
            .invalid_attr_combination = "[itemprop] requires [src] to be defined",
        },
        .main_location = vait.name,
        .node_idx = node_idx,
    });

    return iframe.model;
}

pub fn validateAllow(
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

    const data = value.span.slice(src);
    var pos: u32 = 0;

    policy_directive: while (true) {
        const directive_start = pos;
        while (pos < data.len) : (pos += 1) {
            switch (data[pos]) {
                '0'...'9', 'a'...'z', 'A'...'Z', '-' => continue,
                else => break,
            }
        } else return errors.append(gpa, .{
            .tag = .{
                .invalid_attr_value = .{
                    .reason = if (pos == directive_start)
                        "missing feature identifier"
                    else
                        "missing whitespace followed by allow list",
                },
            },
            .main_location = .{
                .start = value.span.end,
                .end = value.span.end,
            },
            .node_idx = node_idx,
        });

        if (std.mem.indexOfScalar(u8, &std.ascii.whitespace, data[pos]) == null) {
            return errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "missing whitespace followed by allow list",
                    },
                },
                .main_location = .{
                    .start = value.span.start + pos,
                    .end = value.span.end,
                },
                .node_idx = node_idx,
            });
        }
        pos += 1;
        allow_list_value: while (true) {
            while (pos < data.len) : (pos += 1) {
                switch (data[pos]) {
                    ' ', '\t'...'\r' => continue,
                    else => break,
                }
            } else return errors.append(gpa, .{
                .tag = .{ .invalid_attr_value = .{ .reason = "missing allow list" } },
                .main_location = .{
                    .start = value.span.end,
                    .end = value.span.end,
                },
                .node_idx = node_idx,
            });

            const start = pos;
            switch (data[pos]) {
                '\'' => {
                    pos += 1;
                    while (pos < data.len) : (pos += 1) {
                        if (data[pos] == '\'') {
                            pos += 1;
                            const v = data[start..pos];
                            if (!std.mem.eql(u8, v, "'self'") and
                                !std.mem.eql(u8, v, "'src'") and
                                !std.mem.eql(u8, v, "'none'"))
                            {
                                try errors.append(gpa, .{
                                    .tag = .{
                                        .invalid_attr_value = .{
                                            .reason = "invalid allow list value",
                                        },
                                    },
                                    .main_location = .{
                                        .start = value.span.start + start,
                                        .end = value.span.start + pos,
                                    },
                                    .node_idx = node_idx,
                                });
                            }
                            break;
                        }
                    }
                },
                '*' => pos += 1,
                else => {
                    // TODO schema / host case
                    while (pos < data.len) : (pos += 1) {
                        switch (data[pos]) {
                            ' ', '\t'...'\r', ';' => break,
                            else => continue,
                        }
                    }
                },
            }

            if (pos >= data.len) return;
            defer pos += 1;
            switch (data[pos]) {
                ' ' => continue :allow_list_value,
                ';' => continue :policy_directive,
                else => return errors.append(gpa, .{
                    .tag = .{ .invalid_attr_value = .{ .reason = "missing allow list" } },
                    .main_location = value.span,
                    .node_idx = node_idx,
                }),
            }
        }
    }
}
