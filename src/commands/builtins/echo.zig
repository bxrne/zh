const std = @import("std");
const api = @import("../api.zig");
const command_line = @import("../../command_line.zig");

pub fn execute(ctx: *const api.Context, stdout: *std.Io.Writer, stderr: *std.Io.Writer, args: []const command_line.Argument) !void {
    _ = ctx;
    _ = stderr;
    for (args, 0..) |arg, index| {
        if (index > 0) try stdout.print(" ", .{});
        try stdout.print("{s}", .{arg.text});
    }
    try stdout.print("\n", .{});
    try stdout.flush();
}
