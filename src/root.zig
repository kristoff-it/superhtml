const interpreter = @import("interpreter.zig");

pub const SuperVM = interpreter.SuperVM;
pub const Exception = interpreter.Exception;

pub const html = @import("html.zig");

pub const max_size = 4 * 1024 * 1024 * 1024;

test {
    _ = @import("template.zig");
    _ = @import("SuperTree.zig");
}
