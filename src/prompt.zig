const std = @import("std");

fn gitBranch(allocator: std.mem.Allocator, env: *const std.process.EnvMap, cwd: []const u8) ![]u8 {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "rev-parse", "--abbrev-ref", "HEAD" },
        .cwd = cwd,
        .env_map = env,
        .max_output_bytes = 256,
    }) catch return try allocator.dupe(u8, "");
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| if (code != 0) return try allocator.dupe(u8, ""),
        else => return try allocator.dupe(u8, ""),
    }
    const trimmed = std.mem.trim(u8, result.stdout, " \t\r\n");
    if (trimmed.len == 0) return try allocator.dupe(u8, "");
    return try allocator.dupe(u8, trimmed);
}

fn writeCwd(writer: *std.Io.Writer, env: *const std.process.EnvMap, cwd: []const u8) !void {
    if (env.get("HOME")) |home| {
        if (home.len > 0 and std.mem.eql(u8, cwd, home)) {
            try writer.writeAll("~");
            return;
        }
        if (home.len > 0 and std.mem.startsWith(u8, cwd, home) and (cwd.len == home.len or cwd[home.len] == '/')) {
            try writer.writeAll("~");
            try writer.writeAll(cwd[home.len..]);
            return;
        }
    }
    try writer.print("{s}", .{cwd});
}

fn writeCwdBasename(writer: *std.Io.Writer, cwd: []const u8) !void {
    const base = std.fs.path.basename(cwd);
    if (base.len == 0) {
        try writer.writeAll("/");
    } else {
        try writer.print("{s}", .{base});
    }
}

fn writeHostname(writer: *std.Io.Writer, env: *const std.process.EnvMap) !void {
    if (env.get("HOSTNAME")) |h| {
        const short = h[0..std.mem.indexOfScalar(u8, h, '.') orelse h.len];
        try writer.print("{s}", .{short});
        return;
    }
    const uts = std.posix.uname();
    const nodename = std.mem.sliceTo(&uts.nodename, 0);
    const short = nodename[0..std.mem.indexOfScalar(u8, nodename, '.') orelse nodename.len];
    try writer.print("{s}", .{short});
}

/// Expands `ZH_PROMPT`, or `PS1` if unset, or `$ `.
/// Escapes: `\u` user, `\h` short hostname, `\w` cwd (with `~`), `\W` basename of cwd, `\g` git branch in `(branch)`, `\$` `#` if root else `$`, `\\` literal `\`.
pub fn writePrompt(
    writer: *std.Io.Writer,
    allocator: std.mem.Allocator,
    env: *const std.process.EnvMap,
) !void {
    const raw = env.get("ZH_PROMPT") orelse env.get("PS1");
    const template: []const u8 = if (raw == null or raw.?.len == 0) "$ " else raw.?;

    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = std.posix.getcwd(&cwd_buf) catch {
        try writer.print("$ ", .{});
        try writer.flush();
        return;
    };

    var i: usize = 0;
    while (i < template.len) {
        if (template[i] == '\\' and i + 1 < template.len) {
            i += 1;
            switch (template[i]) {
                '\\' => try writer.writeByte('\\'),
                'u' => try writer.print("{s}", .{env.get("USER") orelse "user"}),
                'h' => try writeHostname(writer, env),
                'w' => try writeCwd(writer, env, cwd),
                'W' => try writeCwdBasename(writer, cwd),
                'g' => {
                    const branch = try gitBranch(allocator, env, cwd);
                    defer allocator.free(branch);
                    if (branch.len > 0) {
                        try writer.print("({s})", .{branch});
                    }
                },
                '$' => {
                    const uid = std.posix.geteuid();
                    try writer.writeByte(if (uid == 0) '#' else '$');
                },
                else => {
                    try writer.writeByte('\\');
                    try writer.writeByte(template[i]);
                },
            }
            i += 1;
            continue;
        }
        try writer.writeByte(template[i]);
        i += 1;
    }
    try writer.flush();
}
