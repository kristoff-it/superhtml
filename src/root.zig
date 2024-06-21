const interpreter = @import("interpreter.zig");

pub const SuperVM = interpreter.SuperVM;
pub const Exception = interpreter.Exception;

pub const html = @import("html.zig");

test {
    _ = @import("template.zig");
    _ = @import("SuperTree.zig");
}
