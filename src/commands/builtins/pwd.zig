const std = @import("std");
const api = @import("../api.zig");
const command_line = @import("../../command_line.zig");

pub fn execute(ctx: *api.Context, stdout: *std.Io.Writer, stderr: *std.Io.Writer, args: []const command_line.Argument) !void {
    _ = ctx;
    _ = args;

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = std.posix.getcwd(&buf) catch {
        try stderr.print("pwd: unable to determine current directory\n", .{});
        try stderr.flush();
        return;
    };

    try stdout.print("{s}\n", .{cwd});
    try stdout.flush();
}
