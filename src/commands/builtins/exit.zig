const std = @import("std");
const api = @import("../api.zig");
const command_line = @import("../../command_line.zig");

pub fn execute(ctx: *api.Context, stdout: *std.Io.Writer, stderr: *std.Io.Writer, args: []const command_line.Argument) !void {
    _ = ctx;
    _ = stdout;
    _ = stderr;
    _ = args;
    std.process.exit(0);
}
