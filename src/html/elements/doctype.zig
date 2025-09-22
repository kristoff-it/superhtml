const std = @import("std");
const Element = @import("../Element.zig");

pub const doctype: Element = .{
    .tag = .doctype,
    .model = .{
        .categories = .none,
        .content = .none,
    },
    .meta = .{ .categories_superset = .none },
    .attributes = .static,
    .content = .model,

    .desc =
    \\A doctype declaration.
    \\
    \\SuperHTML only supports `<!doctype html>`. Setting the doctype to a different
    \\value will not change how SuperHTML analyzes the document.
    ,
};
