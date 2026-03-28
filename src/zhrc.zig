const std = @import("std");
const command_line = @import("command_line.zig");
const commands = @import("commands/mod.zig");
const runtime = @import("commands/runtime.zig");
const api = @import("commands/api.zig");

const max_zhrc_bytes: usize = 256 * 1024;

fn wordBoundaryAfterKeyword(line: []const u8, keyword: []const u8) bool {
    if (!std.mem.startsWith(u8, line, keyword)) return false;
    if (line.len == keyword.len) return true;
    return std.ascii.isWhitespace(line[keyword.len]);
}

fn applyExportPayload(ctx: *commands.Context, stderr: *std.Io.Writer, line_no: usize, payload: []const u8) !void {
    const trimmed = std.mem.trim(u8, payload, " \t");
    if (trimmed.len == 0) return;

    if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq| {
        const key = std.mem.trim(u8, trimmed[0..eq], " \t");
        if (key.len == 0) {
            try stderr.print("zhrc:{d}: export: empty variable name\n", .{line_no});
            try stderr.flush();
            return;
        }
        const val = trimmed[eq + 1 ..];
        try ctx.state.env.put(key, val);
        if (std.mem.eql(u8, key, "PATH")) try ctx.state.refreshPathIndex();
    } else {
        const key = trimmed;
        try ctx.state.env.put(key, "");
        if (std.mem.eql(u8, key, "PATH")) try ctx.state.refreshPathIndex();
    }
}

fn runEvalLine(
    ctx: *commands.Context,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    line_no: usize,
    script: []const u8,
) void {
    const trimmed = std.mem.trim(u8, script, " \t\r");
    if (trimmed.len == 0) return;

    if (ctx.state.eval_depth >= api.max_eval_depth) {
        stderr.print("zhrc:{d}: eval: maximum nesting depth exceeded\n", .{line_no}) catch return;
        stderr.flush() catch return;
        return;
    }

    ctx.state.eval_depth += 1;
    defer ctx.state.eval_depth -= 1;

    runtime.executeLine(ctx, stdout, stderr, trimmed) catch |err| {
        stderr.print("zhrc:{d}: eval: {s}\n", .{ line_no, @errorName(err) }) catch return;
        stderr.flush() catch return;
    };
}

fn runCommandLine(
    ctx: *commands.Context,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    line_no: usize,
    line: []const u8,
) void {
    var parsed = command_line.parse(ctx.allocator, line) catch |err| switch (err) {
        error.MissingRedirectTarget => {
            stderr.print("zhrc:{d}: syntax error: missing redirect target\n", .{line_no}) catch return;
            stderr.flush() catch return;
            return;
        },
        error.UnterminatedQuote => {
            stderr.print("zhrc:{d}: syntax error: unterminated quote\n", .{line_no}) catch return;
            stderr.flush() catch return;
            return;
        },
        else => {
            stderr.print("zhrc:{d}: {s}\n", .{ line_no, @errorName(err) }) catch return;
            stderr.flush() catch return;
            return;
        },
    };
    defer parsed.deinit(ctx.allocator);

    commands.executeParsed(ctx, stdout, stderr, &parsed) catch |err| {
        stderr.print("zhrc:{d}: {s}\n", .{ line_no, @errorName(err) }) catch return;
        stderr.flush() catch return;
    };
}

/// Reads `path` (typically `$HOME/.zhrc`). Missing file is ignored. Oversized files error once.
pub fn loadFromPath(
    ctx: *commands.Context,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    path: []const u8,
) !void {
    var file = std.fs.openFileAbsolute(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => |e| return e,
    };
    defer file.close();

    const contents = file.readToEndAlloc(ctx.allocator, max_zhrc_bytes) catch |err| switch (err) {
        error.FileTooBig => {
            try stderr.print("zhrc: file too large (max {d} bytes): {s}\n", .{ max_zhrc_bytes, path });
            try stderr.flush();
            return;
        },
        else => |e| return e,
    };
    defer ctx.allocator.free(contents);

    var line_no: usize = 0;
    var iter = std.mem.splitScalar(u8, contents, '\n');
    while (iter.next()) |raw_line| {
        line_no += 1;
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (line[0] == '#') continue;

        if (wordBoundaryAfterKeyword(line, "export")) {
            const payload = line["export".len..];
            const trimmed_payload = std.mem.trim(u8, payload, " \t");
            applyExportPayload(ctx, stderr, line_no, trimmed_payload) catch |err| {
                try stderr.print("zhrc:{d}: {s}\n", .{ line_no, @errorName(err) });
                try stderr.flush();
            };
            continue;
        }

        if (wordBoundaryAfterKeyword(line, "eval")) {
            const after = line["eval".len..];
            const script = std.mem.trimLeft(u8, after, " \t");
            runEvalLine(ctx, stdout, stderr, line_no, script);
            continue;
        }

        runCommandLine(ctx, stdout, stderr, line_no, line);
    }
}

test "zhrc export and command lines" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const rc_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(rc_path);
    const rc_file = try std.fs.path.join(allocator, &.{ rc_path, "zhrc_test" });
    defer allocator.free(rc_file);

    try tmp.dir.writeFile(.{ .sub_path = "zhrc_test", .data =
        \\export FOO=bar
        \\# comment
        \\export PATH=
        \\
    });

    var shell_state = try commands.ShellState.init(allocator);
    defer shell_state.deinit();

    var ctx = commands.Context{
        .resolve_builtin = commands.findBuiltin,
        .state = &shell_state,
        .allocator = allocator,
    };

    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    var err: std.Io.Writer.Allocating = .init(allocator);
    defer err.deinit();

    try loadFromPath(&ctx, &out.writer, &err.writer, rc_file);

    try std.testing.expectEqualStrings("bar", shell_state.env.get("FOO").?);
    try std.testing.expectEqualStrings("", shell_state.env.get("PATH").?);
    try std.testing.expectEqualStrings("", err.written());
}

test "zhrc eval runs a command" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const rc_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(rc_path);
    const rc_file = try std.fs.path.join(allocator, &.{ rc_path, "zhrc_eval" });
    defer allocator.free(rc_file);

    try tmp.dir.writeFile(.{ .sub_path = "zhrc_eval", .data = "eval echo hello\n" });

    var shell_state = try commands.ShellState.init(allocator);
    defer shell_state.deinit();

    var ctx = commands.Context{
        .resolve_builtin = commands.findBuiltin,
        .state = &shell_state,
        .allocator = allocator,
    };

    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    var err: std.Io.Writer.Allocating = .init(allocator);
    defer err.deinit();

    try loadFromPath(&ctx, &out.writer, &err.writer, rc_file);

    try std.testing.expect(std.mem.startsWith(u8, out.written(), "hello"));
    try std.testing.expectEqualStrings("", err.written());
}

test "zhrc export PATH refreshes path index" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var bin_dir = try tmp.dir.makeOpenPath("bin", .{});
    try bin_dir.writeFile(.{ .sub_path = "zh_mark", .data = "#!/bin/sh\necho mark\n" });

    const bin_abs = try tmp.dir.realpathAlloc(allocator, "bin");
    defer allocator.free(bin_abs);
    const mark_abs = try std.fs.path.join(allocator, &.{ bin_abs, "zh_mark" });
    defer allocator.free(mark_abs);
    {
        var mark_file = try std.fs.openFileAbsolute(mark_abs, .{ .mode = .read_write });
        defer mark_file.close();
        try mark_file.chmod(0o755);
    }

    const rc_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(rc_path);
    const rc_file = try std.fs.path.join(allocator, &.{ rc_path, "zhrc_path" });
    defer allocator.free(rc_file);

    const rc_body = try std.fmt.allocPrint(allocator, "export PATH={s}\n", .{bin_abs});
    defer allocator.free(rc_body);
    try tmp.dir.writeFile(.{ .sub_path = "zhrc_path", .data = rc_body });

    var shell_state = try commands.ShellState.init(allocator);
    defer shell_state.deinit();

    var ctx = commands.Context{
        .resolve_builtin = commands.findBuiltin,
        .state = &shell_state,
        .allocator = allocator,
    };

    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    var err: std.Io.Writer.Allocating = .init(allocator);
    defer err.deinit();

    try loadFromPath(&ctx, &out.writer, &err.writer, rc_file);

    try std.testing.expectEqualStrings(bin_abs, shell_state.env.get("PATH").?);
    try std.testing.expect(shell_state.path_index.lookup("zh_mark") != null);
    try std.testing.expectEqualStrings("", err.written());
}
