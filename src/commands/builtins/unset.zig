const std = @import("std");
const api = @import("../api.zig");
const command_line = @import("../../command_line.zig");

pub fn execute(ctx: *api.Context, stdout: *std.Io.Writer, stderr: *std.Io.Writer, args: []const command_line.Argument) !void {
    _ = stdout;
    _ = stderr;

    for (args) |arg| {
        ctx.state.env.remove(arg.text);
        if (std.mem.eql(u8, arg.text, "PATH")) try ctx.state.refreshPathIndex();
    }
}
