const std = @import("std");
const builtin = @import("builtin");
const api = @import("../api.zig");
const command_line = @import("../../command_line.zig");

fn copyHome(allocator: std.mem.Allocator) ![]const u8 {
    const home = std.posix.getenv("HOME") orelse return error.NoHome;
    return try allocator.dupe(u8, home);
}

fn expandTilde(allocator: std.mem.Allocator, arg: []const u8) ![]const u8 {
    if (arg.len == 1) return try copyHome(allocator);
    if (arg[1] == '/') {
        const home = std.posix.getenv("HOME") orelse return error.NoHome;
        if (arg.len == 2) return try allocator.dupe(u8, home);
        return try std.fs.path.join(allocator, &.{ home, arg[2..] });
    }
    if (!builtin.link_libc) return error.NoHome;
    const rest = arg[1..];
    const slash = std.mem.indexOfScalar(u8, rest, '/');
    const uname_len = slash orelse rest.len;
    const username = rest[0..uname_len];
    const uname_z = try allocator.dupeZ(u8, username);
    defer allocator.free(uname_z);
    const pw = std.c.getpwnam(uname_z.ptr) orelse return error.NoUser;
    const home_dir = std.mem.span(pw.pw_dir);
    if (slash) |s| {
        const sub = rest[s + 1 ..];
        if (sub.len == 0) return try allocator.dupe(u8, home_dir);
        return try std.fs.path.join(allocator, &.{ home_dir, sub });
    }
    return try allocator.dupe(u8, home_dir);
}

fn resolveTarget(allocator: std.mem.Allocator, args: []const command_line.Argument) ![]const u8 {
    if (args.len == 0) return try copyHome(allocator);
    const arg = args[0];
    if (arg.tilde_expand and std.mem.startsWith(u8, arg.text, "~")) {
        return try expandTilde(allocator, arg.text);
    }
    return try allocator.dupe(u8, arg.text);
}

pub fn execute(ctx: *const api.Context, stdout: *std.Io.Writer, stderr: *std.Io.Writer, args: []const command_line.Argument) !void {
    _ = stdout;
    const target = resolveTarget(ctx.allocator, args) catch {
        try stderr.print("cd: home directory not available\n", .{});
        try stderr.flush();
        return;
    };
    defer ctx.allocator.free(target);

    std.posix.chdir(target) catch {
        try stderr.print("cd: {s}: No such file or directory\n", .{target});
        try stderr.flush();
        return;
    };
}
