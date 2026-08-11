const std = @import("std");
const Ast = @import("Ast.zig");
const Tokenizer = @import("Tokenizer.zig");

pub fn ParseResult(comptime T: type) type {
    return union(enum) {
        pass: struct {
            value: T,
            rest: []const u8,
        },
        fail: Failure,

        pub const Failure = struct {
            reason: T.Error,
            offset: u32,
            length: u32,

            pub fn propagate(self: @This(), comptime Target: type) ParseResult(Target) {
                return .{ .fail = .{
                    .reason = self.reason,
                    .offset = self.offset,
                    .length = self.length,
                } };
            }
        };

        pub fn accept(value: T, rest: []const u8) ParseResult(T) {
            return .{ .pass = .{
                .value = value,
                .rest = rest,
            } };
        }

        pub fn reject(reason: T.Error, src: []const u8, token: []const u8) ParseResult(T) {
            return .{ .fail = .{
                .reason = reason,
                .offset = @intCast(@intFromPtr(token.ptr) - @intFromPtr(src.ptr)),
                .length = @intCast(token.len),
            } };
        }
    };
}

/// See: https://html.spec.whatwg.org/multipage/common-microsyntaxes.html#valid-month-string
pub const Month = struct {
    year: u64,
    month: u8,

    pub const Error = error{
        YearTooShort,
        InvalidYear,
        YearZero,
        MissingMonth,
        WrongMonthLength,
        InvalidMonth,
        InvalidMonthValue,
    };

    pub fn parse(src: []const u8) ParseResult(Month) {
        // Caller should handle empty strings
        std.debug.assert(src.len > 0);

        // A string is a valid month string representing a year year and month month
        // if it consists of the following components in the given order:
        // 1. Four or more ASCII digits, representing year, where year > 0
        // 2. A U+002D HYPHEN-MINUS character (-)
        const year, var rest = blk: {
            const dash = std.mem.indexOfScalar(u8, src, '-') orelse return .reject(error.MissingMonth, src, src);
            const str = src[0..dash];
            if (str.len < 4) return .reject(error.YearTooShort, src, str);
            const year = std.fmt.parseInt(u64, str, 10) catch return .reject(error.InvalidYear, src, str);
            if (year == 0) return .reject(error.YearZero, src, str);
            break :blk .{ year, src[dash + 1 ..] };
        };
        // 3. Two ASCII digits, representing the month month, in the range 1 ≤ month ≤ 12
        const month, rest = blk: {
            const dash = std.mem.indexOfScalar(u8, rest, '-') orelse rest.len;
            const str = rest[0..dash];
            if (str.len == 0) return .reject(error.MissingMonth, src, src);
            if (str.len != 2) return .reject(error.WrongMonthLength, src, str);
            const month = std.fmt.parseInt(u8, str, 10) catch return .reject(error.InvalidMonth, src, str);
            if (month < 1 or month > 12) return .reject(error.InvalidMonthValue, src, str);
            break :blk .{ month, rest[dash..] };
        };

        return .accept(.{ .year = year, .month = month }, rest);
    }

    pub fn validate(
        gpa: std.mem.Allocator,
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
        const value_slice = value.span.slice(src);
        if (value_slice.len == 0) return errors.append(gpa, .{
            .tag = .missing_attr_value,
            .main_location = attr.name,
            .node_idx = node_idx,
        });

        const result = parse(value_slice);
        const error_text = switch (result) {
            .pass => |success| if (success.rest.len > 0) "invalid format: trailing characters" else return,
            .fail => |failure| switch (failure.reason) {
                error.YearTooShort => "year must be at least 4 characters long",
                error.InvalidYear => "year must be a decimal number",
                error.YearZero => "year must be greater or equal to 1",
                error.MissingMonth => "month is missing after year",
                error.WrongMonthLength => "month must be 2 characters long",
                error.InvalidMonth => "month must be a decimal number",
                error.InvalidMonthValue => "month must be between 1 and 12",
            },
        };
        return errors.append(gpa, .{
            .tag = .{ .invalid_attr_value = .{ .reason = error_text } },
            .main_location = value.span,
            .node_idx = node_idx,
        });
    }
};

/// See: https://html.spec.whatwg.org/multipage/common-microsyntaxes.html#valid-date-string
pub const Date = struct {
    year: u64,
    month: u8,
    day: u8,

    pub const Error = Month.Error || error{
        MissingDay,
        WrongDayLength,
        InvalidDay,
        WrongDayValue,
    };

    pub fn parse(src: []const u8) ParseResult(Date) {
        // A string is a valid date string representing a year year, month month, and day day
        // if it consists of the following components in the given order:
        // 1. A valid month string, representing year and month
        const month_result = switch (Month.parse(src)) {
            .pass => |result| result,
            .fail => |failure| return failure.propagate(Date),
        };
        const year = month_result.value.year;
        const month = month_result.value.month;
        var rest = month_result.rest;
        // 2. A U+002D HYPHEN-MINUS character (-)
        if (rest.len == 0 or rest[0] != '-') return .reject(error.MissingDay, src, src);
        rest = rest[1..];
        // 3. Two ASCII digits, representing day, in the range 1 ≤ day ≤ maxday
        //    where maxday is the number of days in the month month and year year
        const day, rest = blk: {
            const dash = std.mem.indexOfScalar(u8, rest, '-') orelse rest.len;
            const str = rest[0..dash];
            if (str.len == 0) return .reject(error.MissingDay, src, src);
            if (str.len != 2) return .reject(error.WrongDayLength, src, str);
            const day = std.fmt.parseInt(u8, str, 10) catch return .reject(error.InvalidDay, src, str);
            const maxday: u8 = switch (month) {
                1, 3, 5, 7, 8, 10, 12 => 31,
                4, 6, 9, 11 => 30,
                2 => if (year % 400 == 0 or (year % 4 == 0 and year % 100 != 0)) 29 else 28,
                else => unreachable,
            };
            if (day < 1 or day > maxday) return .reject(error.WrongDayValue, src, str);
            break :blk .{ day, rest[dash..] };
        };
        return .accept(.{ .year = year, .month = month, .day = day }, rest);
    }

    pub fn validate(
        gpa: std.mem.Allocator,
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
        const value_slice = value.span.slice(src);
        if (value_slice.len == 0) return errors.append(gpa, .{
            .tag = .missing_attr_value,
            .main_location = attr.name,
            .node_idx = node_idx,
        });

        const result = parse(value_slice);
        const error_text = switch (result) {
            .pass => |success| if (success.rest.len > 0) "invalid format: trailing characters" else return,
            .fail => |failure| switch (failure.reason) {
                error.YearTooShort => "year must be at least 4 characters long",
                error.InvalidYear => "year must be a decimal number",
                error.YearZero => "year must be greater or equal to 1",
                error.MissingMonth => "month is missing after year",
                error.WrongMonthLength => "month must be 2 characters long",
                error.InvalidMonth => "month must be a decimal number",
                error.InvalidMonthValue => "month must be between 1 and 12",
                error.MissingDay => "day is missing after month",
                error.WrongDayLength => "day must be 2 characters long",
                error.InvalidDay => "day must be a decimal number",
                error.WrongDayValue => "day is incompatible with year and month",
            },
        };
        return errors.append(gpa, .{
            .tag = .{ .invalid_attr_value = .{ .reason = error_text } },
            .main_location = value.span,
            .node_idx = node_idx,
        });
    }
};

test Month {
    const src = "2025-09";
    const result = Month.parse(src);
    try std.testing.expectEqual(2025, result.pass.value.year);
    try std.testing.expectEqual(9, result.pass.value.month);
}

test Date {
    const src = "2025-09-22";
    const result = Date.parse(src);
    try std.testing.expectEqual(2025, result.pass.value.year);
    try std.testing.expectEqual(9, result.pass.value.month);
    try std.testing.expectEqual(22, result.pass.value.day);
}
