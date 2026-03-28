const std = @import("std");
const command_line = @import("command_line.zig");
const commands = @import("commands/mod.zig");

pub fn readCommandLine(writer: *std.Io.Writer, reader: *std.Io.Reader) !?[]const u8 {
    try writer.print("$ ", .{});
    try writer.flush();

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

    var path_index = try commands.PathIndex.init(allocator, null);
    defer path_index.deinit();

    const shell_ctx = commands.Context{
        .resolve_builtin = commands.findBuiltin,
        .path_index = &path_index,
        .allocator = allocator,
    };

    while (true) {
        const line = try readCommandLine(term_out, reader);
        if (line == null) break;
        if (line.?.len == 0) continue;

        var parsed = (try parseOrReportError(allocator, line.?, term_err)) orelse continue;
        defer parsed.deinit(allocator);

        try commands.executeParsed(&shell_ctx, term_out, term_err, &parsed);
    }
}
