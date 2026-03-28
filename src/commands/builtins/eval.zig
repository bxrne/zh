const std = @import("std");
const api = @import("../api.zig");
const runtime = @import("../runtime.zig");
const command_line = @import("../../command_line.zig");

fn joinArgs(allocator: std.mem.Allocator, args: []const command_line.Argument) ![]u8 {
    var buffer = std.ArrayList(u8).empty;
    errdefer buffer.deinit(allocator);
    for (args, 0..) |arg, index| {
        if (index > 0) try buffer.append(allocator, ' ');
        try buffer.appendSlice(allocator, arg.text);
    }
    return try buffer.toOwnedSlice(allocator);
}

pub fn execute(ctx: *api.Context, stdout: *std.Io.Writer, stderr: *std.Io.Writer, args: []const command_line.Argument) !void {
    if (args.len == 0) return;

    if (ctx.state.eval_depth >= api.max_eval_depth) {
        try stderr.print("eval: maximum nesting depth exceeded\n", .{});
        try stderr.flush();
        return;
    }

    const script = try joinArgs(ctx.allocator, args);
    defer ctx.allocator.free(script);

    ctx.state.eval_depth += 1;
    defer ctx.state.eval_depth -= 1;

    runtime.executeLine(ctx, stdout, stderr, script) catch |err| {
        try stderr.print("eval: {s}\n", .{@errorName(err)});
        try stderr.flush();
    };
}
