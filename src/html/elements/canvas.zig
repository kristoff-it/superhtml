const std = @import("std");
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

pub const canvas: Element = .{
    .tag = .canvas,
    .model = .{
        .categories = .{
            .flow = true,
            .phrasing = true,
            // .embedded = true,
        },
        .content = .transparent,
    },
    .meta = .{
        .categories_superset = .{
            .flow = true,
            .phrasing = true,
            // .embedded = true,
        },
        .content_reject = .{
            .interactive = true,
        },
    },
    .attributes = .static,
    .content = .{
        .simple = .{
            .extra_children = &.{ .a, .img, .button, .input, .select },
        },
    },
    .desc =
    \\Use the HTML `<canvas>` element with either the canvas scripting API
    \\or the WebGL API to draw graphics and animations.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/canvas)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-canvas-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "width",
        .model = .{
            .rule = .{ .non_neg_int = .{} },
            .desc = "The height of the coordinate space in CSS pixels. Defaults to 150.",
        },
    },
    .{
        .name = "height",
        .model = .{
            .rule = .{ .non_neg_int = .{} },
            .desc = "The width of the coordinate space in CSS pixels. Defaults to 300.",
        },
    },
});

// for when the time comes

// pub fn validateContent(
//     gpa: Allocator,
//     nodes: []const Ast.Node,
//     errors: *std.ArrayListUnmanaged(Ast.Error),
//     src: []const u8,
//     parent_idx: u32,
// ) error{OutOfMemory}!void {}

// fn completionsContent(
//     arena: Allocator,
//     ast: Ast,
//     src: []const u8,
//     parent_idx: u32,
//     offset: u32,
// ) error{OutOfMemory}![]const Ast.Completion {}
