const std = @import("std");
const api = @import("../api.zig");
const command_line = @import("../../command_line.zig");

fn cmpKeys(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

pub fn execute(ctx: *api.Context, stdout: *std.Io.Writer, stderr: *std.Io.Writer, args: []const command_line.Argument) !void {
    _ = stderr;

    if (args.len == 0) {
        var keys = std.ArrayList([]const u8).empty;
        defer {
            for (keys.items) |k| ctx.allocator.free(k);
            keys.deinit(ctx.allocator);
        }

        var it = ctx.state.env.iterator();
        while (it.next()) |entry| {
            try keys.append(ctx.allocator, try ctx.allocator.dupe(u8, entry.key_ptr.*));
        }

        std.sort.pdq([]const u8, keys.items, {}, cmpKeys);

        for (keys.items) |key| {
            const val = ctx.state.env.get(key).?;
            try stdout.print("export {s}={s}\n", .{ key, val });
        }
        try stdout.flush();
        return;
    }

    for (args) |arg| {
        const text = arg.text;
        if (std.mem.indexOfScalar(u8, text, '=')) |eq| {
            const key = std.mem.trim(u8, text[0..eq], " \t");
            if (key.len == 0) continue;
            const val = text[eq + 1 ..];
            try ctx.state.env.put(key, val);
            if (std.mem.eql(u8, key, "PATH")) try ctx.state.refreshPathIndex();
        } else {
            const key = std.mem.trim(u8, text, " \t");
            if (key.len == 0) continue;
            try ctx.state.env.put(key, "");
            if (std.mem.eql(u8, key, "PATH")) try ctx.state.refreshPathIndex();
        }
    }
}
