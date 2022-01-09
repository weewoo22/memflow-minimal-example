const build_options = @import("build_options");
const builtin = @import("builtin");

const std = @import("std");

pub usingnamespace @cImport({
    @cInclude("memflow.h");
});

const memflow = @This();

pub fn slice(s: []const u8) memflow.CSliceRef_u8 {
    return .{
        .data = s.ptr,
        .len = s.len,
    };
}

pub fn tryError(error_number: i32, @"error": ?anyerror) !void {
    if (error_number != 0) {
        memflow.log_errorcode(memflow.Level_Error, error_number);

        if (@"error") |err| return err;
    }
}
