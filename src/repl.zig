const std = @import("std");
const command_line = @import("command_line.zig");
const commands = @import("commands/mod.zig");
const prompt = @import("prompt.zig");
const zhrc = @import("zhrc.zig");

pub fn readCommandLine(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    reader: *std.Io.Reader,
    state: *const commands.ShellState,
) !?[]const u8 {
    try prompt.writePrompt(writer, allocator, &state.env);

    const line = reader.takeDelimiterInclusive('\n') catch |err| {
        if (err == error.EndOfStream) return null;
        return err;
    };

    return std.mem.trim(u8, line, " \t\r\n");
}

fn parseOrReportError(allocator: std.mem.Allocator, input: []const u8, stderr: *std.Io.Writer) !?command_line.CommandLine {
    return command_line.parse(allocator, input) catch |err| switch (err) {
        error.MissingRedirectTarget => {
            try stderr.print("syntax error: missing redirect target\n", .{});
            try stderr.flush();
            return null;
        },
        error.UnterminatedQuote => {
            try stderr.print("syntax error: unterminated quote\n", .{});
            try stderr.flush();
            return null;
        },
        else => return err,
    };
}

pub fn run(term_out: *std.Io.Writer, term_err: *std.Io.Writer, reader: *std.Io.Reader) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var shell_state = try commands.ShellState.init(allocator);
    defer shell_state.deinit();

    var shell_ctx = commands.Context{
        .resolve_builtin = commands.findBuiltin,
        .state = &shell_state,
        .allocator = allocator,
    };

    if (shell_state.env.get("HOME")) |home| {
        const zhrc_path = try std.fs.path.join(allocator, &.{ home, ".zhrc" });
        defer allocator.free(zhrc_path);
        try zhrc.loadFromPath(&shell_ctx, term_out, term_err, zhrc_path);
    }

    while (true) {
        const line = try readCommandLine(allocator, term_out, reader, &shell_state);
        if (line == null) break;
        if (line.?.len == 0) continue;

        var parsed = (try parseOrReportError(allocator, line.?, term_err)) orelse continue;
        defer parsed.deinit(allocator);

        try commands.executeParsed(&shell_ctx, term_out, term_err, &parsed);
    }
}
