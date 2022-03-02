const std = @import("std");

pub fn main() void {
    std.time.sleep(std.time.ns_per_week * 1);
}
