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

pub const ins: Element = .{
    .tag = .ins,
    .model = del.model,
    .meta = del.meta,
    .attributes = del.attributes,
    .content = del.content,
    .desc =
    \\The `<ins>` HTML element represents a range of text that has been
    \\added to a document. You can use the `<del>` element to similarly
    \\represent a range of text that has been deleted from the document.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/ins)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-ins-element)
    ,
};

pub const del: Element = .{
    .tag = .del,
    .model = .{
        .categories = .none,
        .content = .{ .flow = true },
    },
    .meta = .{ .categories_superset = .none },
    .attributes = .static,
    .content = .model,
    .desc =
    \\The `<del>` HTML element represents a range of text that has been
    \\deleted from a document. This can be used when rendering "track
    \\changes" or source code diff information, for example. The `<ins>`
    \\element can be used for the opposite purpose: to indicate text that
    \\has been added to the document.
    \\
    \\ - [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/del)
    \\ - [HTML Spec](https://html.spec.whatwg.org/multipage/form-elements.html#the-del-element)
    ,
};

pub const attributes: AttributeSet = .init(&.{
    .{
        .name = "cite",
        .model = .{
            .rule = .{ .url = .empty },
            .desc = "This attribute defines the URI of a resource that explains the change, such as a link to meeting minutes or a ticket in a troubleshooting system.",
        },
    },
    .{
        .name = "datetime",
        .model = .{
            .rule = .{ .custom = validateDatetime },
            .desc = "This attribute indicates the time and date of the change and must be a valid date with an optional time string. If the value cannot be parsed as a date with an optional time string, the element does not have an associated timestamp.",
        },
    },
});

pub fn validateDatetime(
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
    const date = value.span.slice(src);
    var pos: u32 = 0;

    {
        //  A string is a valid month string representing a year year and month
        // month if it consists of the following components in the given order:

        // Four or more ASCII digits, representing year, where year > 0
        // A U+002D HYPHEN-MINUS character (-)
        // Two ASCII digits, representing the month month, in the range 1 ≤
        // month ≤ 12
        while (pos < date.len) : (pos += 1) {
            if (date[pos] == '-') break;
        } else return errors.append(gpa, .{
            .tag = .{
                .invalid_attr_value = .{
                    .reason = "missing '-' after year",
                },
            },
            .main_location = value.span,
            .node_idx = node_idx,
        });

        if (pos < 4) return errors.append(gpa, .{
            .tag = .{
                .invalid_attr_value = .{
                    .reason = "year must be at least 4-digit long",
                },
            },
            .main_location = .{
                .start = value.span.start,
                .end = value.span.end - 1,
            },
            .node_idx = node_idx,
        });

        _ = std.fmt.parseInt(u64, date[0..pos], 10) catch return errors.append(gpa, .{
            .tag = .{
                .invalid_attr_value = .{
                    .reason = "not a valid year",
                },
            },
            .main_location = .{
                .start = value.span.start,
                .end = value.span.start + pos,
            },
            .node_idx = node_idx,
        });

        pos += 1;

        if (pos + 2 > date.len) return errors.append(gpa, .{
            .tag = .{
                .invalid_attr_value = .{
                    .reason = "missing two-digit month",
                },
            },
            .main_location = .{
                .start = value.span.start + pos,
                .end = value.span.end,
            },
            .node_idx = node_idx,
        });

        const month = std.fmt.parseInt(u64, date[pos..][0..2], 10) catch return errors.append(gpa, .{
            .tag = .{
                .invalid_attr_value = .{
                    .reason = "not a valid month",
                },
            },
            .main_location = .{
                .start = value.span.start,
                .end = value.span.start + pos,
            },
            .node_idx = node_idx,
        });

        if (month < 1 or month > 12) return errors.append(gpa, .{
            .tag = .{
                .invalid_attr_value = .{
                    .reason = "month out of range (must be between 1 and 12)",
                },
            },
            .main_location = .{
                .start = value.span.start + pos,
                .end = value.span.start + pos + 2,
            },
            .node_idx = node_idx,
        });

        pos += 2;
    }

    if (pos >= date.len) return;

    if (date[pos] != 'T' and date[pos] != ' ') return errors.append(gpa, .{
        .tag = .{
            .invalid_attr_value = .{
                .reason = "invalid date time separator, must be 'T' or space",
            },
        },
        .main_location = .{
            .start = value.span.start + pos,
            .end = value.span.start + pos + 1,
        },
        .node_idx = node_idx,
    });

    pos += 1;

    {

        // A string is a valid time string representing an hour hour, a minute minute, and a second second if it consists of the following components in the given order:

        // Two ASCII digits, representing hour, in the range 0 ≤ hour ≤ 23
        // A U+003A COLON character (:)
        // Two ASCII digits, representing minute, in the range 0 ≤ minute ≤ 59
        // If second is nonzero, or optionally if second is zero:
        // A U+003A COLON character (:)
        // Two ASCII digits, representing the integer part of second, in the range 0 ≤ s ≤ 59
        // If second is not an integer, or optionally if second is an integer:
        // A U+002E FULL STOP character (.)
        // One, two, or three ASCII digits, representing the fractional part of second

        //        HH  :   MM  :   SS
        if (pos + 2 + 1 + 2 + 1 + 2 > date.len) return errors.append(gpa, .{
            .tag = .{
                .invalid_attr_value = .{
                    .reason = "missing time, must be HH:MM:SS optionally followed by fractional seconds",
                },
            },
            .main_location = .{
                .start = value.span.start + pos,
                .end = value.span.end,
            },
            .node_idx = node_idx,
        });

        hours: {
            if (std.fmt.parseInt(u64, date[pos..][0..2], 10)) |hours| {
                if (hours <= 23) break :hours;
            } else |_| {}
            return errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "not a valid hour",
                    },
                },
                .main_location = .{
                    .start = value.span.start + pos,
                    .end = value.span.start + pos + 2,
                },
                .node_idx = node_idx,
            });
        }

        pos += 3;

        minutes: {
            if (std.fmt.parseInt(u64, date[pos..][0..2], 10)) |minutes| {
                if (minutes <= 59) break :minutes;
            } else |_| {}
            return errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "not a valid minute",
                    },
                },
                .main_location = .{
                    .start = value.span.start + pos,
                    .end = value.span.start + pos + 2,
                },
                .node_idx = node_idx,
            });
        }

        pos += 3;

        seconds: {
            if (std.fmt.parseInt(u64, date[pos..][0..2], 10)) |seconds| {
                if (seconds <= 59) break :seconds;
            } else |_| {}
            return errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "not a valid second",
                    },
                },
                .main_location = .{
                    .start = value.span.start + pos,
                    .end = value.span.start + pos + 2,
                },
                .node_idx = node_idx,
            });
        }

        pos += 2;

        if (pos >= date.len) return;

        if (date[pos] == '.') {
            for (0..2) |_| {
                pos += 1;
                if (pos >= date.len) return;
                switch (date[pos]) {
                    '0'...'9' => {},
                    'Z', '+', '-' => break,
                    else => return errors.append(gpa, .{
                        .tag = .{
                            .invalid_attr_value = .{
                                .reason = "invalid fractional second value",
                            },
                        },
                        .main_location = .{
                            .start = value.span.start + pos,
                            .end = value.span.start + pos + 1,
                        },
                        .node_idx = node_idx,
                    }),
                }
            }
        }
    }

    switch (date[pos]) {
        else => return errors.append(gpa, .{
            .tag = .{
                .invalid_attr_value = .{
                    .reason = "invalid separator after time, must be 'Z', '+' or '-'",
                },
            },
            .main_location = .{
                .start = value.span.start + pos,
                .end = value.span.start + pos + 1,
            },
            .node_idx = node_idx,
        }),
        'Z' => {
            if (pos != date.len - 1) return errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "invalid value after UTC timezone",
                    },
                },
                .main_location = .{
                    .start = value.span.start + pos + 1,
                    .end = value.span.end,
                },
                .node_idx = node_idx,
            });
        },

        '+', '-' => {
            pos += 1;

            if (pos + 2 > date.len) return errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "missing timezone hour offset",
                    },
                },
                .main_location = .{
                    .start = value.span.start + pos,
                    .end = value.span.end,
                },
                .node_idx = node_idx,
            });

            hours: {
                if (std.fmt.parseInt(u64, date[pos..][0..2], 10)) |hours| {
                    if (hours <= 23) break :hours;
                } else |_| {}
                return errors.append(gpa, .{
                    .tag = .{
                        .invalid_attr_value = .{
                            .reason = "not a valid hour",
                        },
                    },
                    .main_location = .{
                        .start = value.span.start + pos,
                        .end = value.span.start + pos + 2,
                    },
                    .node_idx = node_idx,
                });
            }

            pos += 2;

            if (pos >= date.len) return;
            if (date[pos] == ':') pos += 1;

            if (pos + 2 > date.len) return errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "missing timezone minute offset",
                    },
                },
                .main_location = .{
                    .start = value.span.start + pos,
                    .end = value.span.end,
                },
                .node_idx = node_idx,
            });

            minutes: {
                if (std.fmt.parseInt(u64, date[pos..][0..2], 10)) |minutes| {
                    if (minutes <= 59) break :minutes;
                } else |_| {}
                return errors.append(gpa, .{
                    .tag = .{
                        .invalid_attr_value = .{
                            .reason = "not a valid minute",
                        },
                    },
                    .main_location = .{
                        .start = value.span.start + pos,
                        .end = value.span.start + pos + 2,
                    },
                    .node_idx = node_idx,
                });
            }

            pos += 2;

            if (pos != date.len) return errors.append(gpa, .{
                .tag = .{
                    .invalid_attr_value = .{
                        .reason = "invalid data after timezone",
                    },
                },
                .main_location = .{
                    .start = value.span.start + pos,
                    .end = value.span.end,
                },
                .node_idx = node_idx,
            });
        },
    }
}
