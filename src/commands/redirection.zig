const std = @import("std");
const command_line = @import("../command_line.zig");

pub const RedirectOpenError = error{RedirectOpenFailed};

pub const BuiltinIo = struct {
    terminal_stdout: *std.Io.Writer,
    terminal_stderr: *std.Io.Writer,
    stdout_file: ?std.fs.File = null,
    stderr_file: ?std.fs.File = null,
    stdout_writer: std.fs.File.Writer = undefined,
    stderr_writer: std.fs.File.Writer = undefined,
    stdout_buffer: [4096]u8 = undefined,
    stderr_buffer: [4096]u8 = undefined,

    pub fn stdout(self: *BuiltinIo) *std.Io.Writer {
        if (self.stdout_file != null) return &self.stdout_writer.interface;
        return self.terminal_stdout;
    }

    pub fn stderr(self: *BuiltinIo) *std.Io.Writer {
        if (self.stderr_file != null) return &self.stderr_writer.interface;
        return self.terminal_stderr;
    }

    pub fn deinit(self: *BuiltinIo) void {
        if (self.stdout_file) |file| file.close();
        if (self.stderr_file) |file| file.close();
    }
};

pub fn prepareBuiltinIo(
    terminal_stdout: *std.Io.Writer,
    terminal_stderr: *std.Io.Writer,
    redirections: command_line.Redirections,
) !BuiltinIo {
    var io = BuiltinIo{
        .terminal_stdout = terminal_stdout,
        .terminal_stderr = terminal_stderr,
    };
    errdefer io.deinit();

    io.stdout_file = try openRedirectOrReport(terminal_stderr, redirections.stdout, "failed to open output file");
    if (io.stdout_file != null) {
        io.stdout_writer = io.stdout_file.?.writerStreaming(&io.stdout_buffer);
    }

    io.stderr_file = try openRedirectOrReport(terminal_stderr, redirections.stderr, "failed to open error output file");
    if (io.stderr_file != null) {
        io.stderr_writer = io.stderr_file.?.writerStreaming(&io.stderr_buffer);
    }

    return io;
}

pub fn applyToChild(redirections: command_line.Redirections) !void {
    try applySingleRedirect(redirections.stdout, std.posix.STDOUT_FILENO);
    try applySingleRedirect(redirections.stderr, std.posix.STDERR_FILENO);
}

fn openRedirectOrReport(
    terminal_stderr: *std.Io.Writer,
    redirect: command_line.Redirect,
    message: []const u8,
) !?std.fs.File {
    const path = redirect.path orelse return null;
    return openRedirectFile(path, redirect.append) catch {
        try terminal_stderr.print("{s}\n", .{message});
        try terminal_stderr.flush();
        return RedirectOpenError.RedirectOpenFailed;
    };
}

fn openRedirectFile(path: []const u8, append: bool) !std.fs.File {
    if (append) {
        var file = try std.fs.cwd().createFile(path, .{ .truncate = false });
        try file.seekFromEnd(0);
        return file;
    }

    return try std.fs.cwd().createFile(path, .{ .truncate = true });
}

fn applySingleRedirect(redirect: command_line.Redirect, target_fd: std.posix.fd_t) !void {
    const path = redirect.path orelse return;
    const flags: std.posix.O = if (redirect.append)
        .{ .ACCMODE = .WRONLY, .CREAT = true, .APPEND = true }
    else
        .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true };

    const file_descriptor = try std.posix.open(path, flags, 0o666);
    defer std.posix.close(file_descriptor);

    try std.posix.dup2(file_descriptor, target_fd);
}

fn tmpPath(allocator: std.mem.Allocator, tmp_dir: *std.testing.TmpDir, name: []const u8) ![]u8 {
    return try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", tmp_dir.sub_path[0..], name });
}

test "prepareBuiltinIo appends redirected builtin output" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(.{ .sub_path = "out", .data = "first\n" });
    const out_path = try tmpPath(allocator, &tmp_dir, "out");
    defer allocator.free(out_path);

    var terminal_stdout: std.Io.Writer.Allocating = .init(allocator);
    defer terminal_stdout.deinit();

    var terminal_stderr: std.Io.Writer.Allocating = .init(allocator);
    defer terminal_stderr.deinit();

    var builtin_io = try prepareBuiltinIo(&terminal_stdout.writer, &terminal_stderr.writer, .{
        .stdout = .{ .path = out_path, .append = true },
    });
    defer builtin_io.deinit();

    try builtin_io.stdout().print("second\n", .{});
    try builtin_io.stdout().flush();

    const contents = try tmp_dir.dir.readFileAlloc(allocator, "out", 1024);
    defer allocator.free(contents);

    try std.testing.expectEqualStrings("first\nsecond\n", contents);
}

test "prepareBuiltinIo reports redirect open failures on stderr" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const invalid_path = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", tmp_dir.sub_path[0..], "missing", "out" });
    defer allocator.free(invalid_path);

    var terminal_stdout: std.Io.Writer.Allocating = .init(allocator);
    defer terminal_stdout.deinit();

    var terminal_stderr: std.Io.Writer.Allocating = .init(allocator);
    defer terminal_stderr.deinit();

    try std.testing.expectError(
        error.RedirectOpenFailed,
        prepareBuiltinIo(&terminal_stdout.writer, &terminal_stderr.writer, .{
            .stdout = .{ .path = invalid_path },
        }),
    );

    try std.testing.expectEqualStrings("failed to open output file\n", terminal_stderr.written());
}
