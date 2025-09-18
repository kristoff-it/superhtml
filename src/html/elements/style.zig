const std = @import("std");
const Element = @import("../Element.zig");
const Attribute = @import("../Attribute.zig");
const AttributeSet = Attribute.AttributeSet;

pub const style: Element = .{
    .tag = .style,
    .model = .{
        .categories = .{ .metadata = true },
        .content = .{ .text = true },
    },
    .meta = .{
        .categories_superset = .{ .metadata = true },
    },
    .attributes = .static,
    .content = .model,
    .desc =
    \\The `<style>` HTML element contains style information for a document, or part
    \\of a document. It contains CSS, which is applied to the contents of the document
    \\containing the `<style>` element.
    \\
    \\- [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/style)
    \\- [HTML Spec](https://html.spec.whatwg.org/multipage/grouping-content.html#the-style-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "media",
        .model = .{
            .rule = .not_empty,
            .desc = "This attribute defines which media the style should be applied to. Its value is a media query, which defaults to `all` if the attribute is missing.",
        },
    },
    .{
        .name = "blocking",
        .model = .{
            .desc = "This attribute explicitly indicates that certain operations should be blocked on the fetching of critical subresources and the application of the stylesheet to the document. @import-ed stylesheets are generally considered as critical subresources, whereas background-image and fonts are not.",
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
});
