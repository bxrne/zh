const std = @import("std");
const api = @import("../api.zig");
const runtime = @import("../runtime.zig");
const command_line = @import("../../command_line.zig");

pub fn execute(ctx: *api.Context, stdout: *std.Io.Writer, stderr: *std.Io.Writer, args: []const command_line.Argument) !void {
    _ = stderr;

    for (args) |arg| {
        try runtime.describeCommand(ctx, stdout, arg.text);
    }
    try stdout.flush();
}
