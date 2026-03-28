const std = @import("std");
const api = @import("api.zig");
const command_line = @import("../command_line.zig");
const redirection = @import("redirection.zig");

pub fn executeParsed(
    ctx: *api.Context,
    terminal_stdout: *std.Io.Writer,
    terminal_stderr: *std.Io.Writer,
    parsed: *const command_line.CommandLine,
) !void {
    if (parsed.args.len == 0) return;

    const command_name = parsed.args[0].text;
    const command_args = parsed.args[1..];

    if (ctx.resolve_builtin(command_name)) |builtin_fn| {
        var builtin_io = redirection.prepareBuiltinIo(terminal_stdout, terminal_stderr, parsed.redirections) catch |err| switch (err) {
            error.RedirectOpenFailed => return,
            else => return err,
        };
        defer builtin_io.deinit();

        try builtin_fn(ctx, builtin_io.stdout(), builtin_io.stderr(), command_args);
        return;
    }

    if (isExecutable(ctx, command_name)) {
        try runExternalCommand(ctx, command_name, command_args, parsed.redirections);
        return;
    }

    var builtin_io = redirection.prepareBuiltinIo(terminal_stdout, terminal_stderr, parsed.redirections) catch |err| switch (err) {
        error.RedirectOpenFailed => return,
        else => return err,
    };
    defer builtin_io.deinit();

    try builtin_io.stderr().print("{s}: command not found\n", .{command_name});
    try builtin_io.stderr().flush();
}

/// Parse a single command line and execute it (used by eval and zhrc).
pub fn executeLine(
    ctx: *api.Context,
    terminal_stdout: *std.Io.Writer,
    terminal_stderr: *std.Io.Writer,
    line: []const u8,
) !void {
    var parsed = try command_line.parse(ctx.allocator, line);
    defer parsed.deinit(ctx.allocator);
    try executeParsed(ctx, terminal_stdout, terminal_stderr, &parsed);
}

pub fn describeCommand(ctx: *api.Context, writer: *std.Io.Writer, name: []const u8) !void {
    if (ctx.resolve_builtin(name) != null) {
        try writer.print("{s} is a shell builtin\n", .{name});
        return;
    }

    if (isExecutable(ctx, name)) {
        if (std.mem.indexOfScalar(u8, name, '/')) |_| {
            try writer.print("{s} is {s}\n", .{ name, name });
        } else {
            try writer.print("{s} is {s}\n", .{ name, ctx.state.path_index.lookup(name).? });
        }
        return;
    }

    try writer.print("{s}: not found\n", .{name});
}

pub fn isExecutable(ctx: *api.Context, name: []const u8) bool {
    if (std.mem.indexOfScalar(u8, name, '/')) |_| {
        std.posix.access(name, std.posix.X_OK) catch return false;
        return true;
    }

    return ctx.state.path_index.lookup(name) != null;
}

fn runExternalCommand(
    ctx: *api.Context,
    command_name: []const u8,
    command_args: []const command_line.Argument,
    redirections: command_line.Redirections,
) !void {
    const argument_count = 1 + command_args.len;
    const argv = try ctx.allocator.alloc(?[*:0]const u8, argument_count + 1);
    defer {
        for (0..argument_count) |index| {
            const value = argv[index].?;
            ctx.allocator.free(std.mem.sliceTo(value, 0));
        }
        ctx.allocator.free(argv);
    }

    for (0..argument_count) |index| {
        const value = if (index == 0) command_name else command_args[index - 1].text;
        argv[index] = (try ctx.allocator.dupeZ(u8, value)).ptr;
    }
    argv[argument_count] = null;

    const command_name_z = try ctx.allocator.dupeZ(u8, command_name);
    defer ctx.allocator.free(std.mem.sliceTo(command_name_z.ptr, 0));

    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();

    const envp_slice = try std.process.createEnvironFromMap(arena.allocator(), &ctx.state.env, .{});
    const pid = try std.posix.fork();
    if (pid == 0) {
        redirection.applyToChild(redirections) catch std.posix.exit(127);
        const argv_ptr: [*:null]const ?[*:0]const u8 = @ptrCast(argv.ptr);
        _ = std.posix.execvpeZ(command_name_z.ptr, argv_ptr, envp_slice.ptr) catch {};
        std.posix.exit(127);
    }

    _ = std.posix.waitpid(pid, 0);
}

fn tempPath(allocator: std.mem.Allocator, tmp_dir: *std.testing.TmpDir, name: []const u8) ![]u8 {
    return try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", tmp_dir.sub_path[0..], name });
}

fn testBuiltin(
    ctx: *api.Context,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    args: []const command_line.Argument,
) !void {
    _ = ctx;
    _ = stderr;

    for (args, 0..) |arg, index| {
        if (index > 0) try stdout.print(" ", .{});
        try stdout.print("{s}", .{arg.text});
    }
    try stdout.print("\n", .{});
    try stdout.flush();
}

fn resolveTestBuiltin(name: []const u8) ?api.BuiltinFn {
    if (std.mem.eql(u8, name, "test-builtin")) return testBuiltin;
    return null;
}

fn resolveNoBuiltins(name: []const u8) ?api.BuiltinFn {
    _ = name;
    return null;
}

test "executeParsed redirects builtin stdout to files" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const out_path = try tempPath(allocator, &tmp_dir, "out");
    defer allocator.free(out_path);

    const input = try std.fmt.allocPrint(allocator, "test-builtin hello 1>{s}", .{out_path});
    defer allocator.free(input);

    var parsed = try command_line.parse(allocator, input);
    defer parsed.deinit(allocator);

    var shell_state = try api.ShellState.init(allocator);
    defer shell_state.deinit();

    var ctx = api.Context{
        .resolve_builtin = resolveTestBuiltin,
        .state = &shell_state,
        .allocator = allocator,
    };

    var terminal_stdout: std.Io.Writer.Allocating = .init(allocator);
    defer terminal_stdout.deinit();

    var terminal_stderr: std.Io.Writer.Allocating = .init(allocator);
    defer terminal_stderr.deinit();

    try executeParsed(&ctx, &terminal_stdout.writer, &terminal_stderr.writer, &parsed);

    const out_contents = try tmp_dir.dir.readFileAlloc(allocator, "out", 1024);
    defer allocator.free(out_contents);

    try std.testing.expectEqualStrings("hello\n", out_contents);
    try std.testing.expectEqualStrings("", terminal_stdout.written());
    try std.testing.expectEqualStrings("", terminal_stderr.written());
}

test "executeParsed redirects shell diagnostics to stderr files" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const out_path = try tempPath(allocator, &tmp_dir, "out");
    defer allocator.free(out_path);

    const err_path = try tempPath(allocator, &tmp_dir, "err");
    defer allocator.free(err_path);

    const input = try std.fmt.allocPrint(allocator, "missing-command 1>{s} 2>{s}", .{ out_path, err_path });
    defer allocator.free(input);

    var parsed = try command_line.parse(allocator, input);
    defer parsed.deinit(allocator);

    var shell_state = try api.ShellState.init(allocator);
    defer shell_state.deinit();

    var ctx = api.Context{
        .resolve_builtin = resolveNoBuiltins,
        .state = &shell_state,
        .allocator = allocator,
    };

    var terminal_stdout: std.Io.Writer.Allocating = .init(allocator);
    defer terminal_stdout.deinit();

    var terminal_stderr: std.Io.Writer.Allocating = .init(allocator);
    defer terminal_stderr.deinit();

    try executeParsed(&ctx, &terminal_stdout.writer, &terminal_stderr.writer, &parsed);

    const out_contents = try tmp_dir.dir.readFileAlloc(allocator, "out", 1024);
    defer allocator.free(out_contents);

    const err_contents = try tmp_dir.dir.readFileAlloc(allocator, "err", 1024);
    defer allocator.free(err_contents);

    try std.testing.expectEqualStrings("", out_contents);
    try std.testing.expectEqualStrings("missing-command: command not found\n", err_contents);
    try std.testing.expectEqualStrings("", terminal_stdout.written());
    try std.testing.expectEqualStrings("", terminal_stderr.written());
}
