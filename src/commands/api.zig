const std = @import("std");
const command_line = @import("../command_line.zig");

pub const max_eval_depth = 32;

pub const ShellState = struct {
    env: std.process.EnvMap,
    path_index: PathIndex,
    eval_depth: u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !ShellState {
        var env = try std.process.getEnvMap(allocator);
        errdefer env.deinit();

        const path_slice = env.get("PATH") orelse "";
        var path_index = try PathIndex.init(allocator, path_slice);
        errdefer path_index.deinit();

        return .{
            .env = env,
            .path_index = path_index,
            .eval_depth = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ShellState) void {
        self.path_index.deinit();
        self.env.deinit();
    }

    pub fn refreshPathIndex(self: *ShellState) !void {
        self.path_index.deinit();
        const path_slice = self.env.get("PATH") orelse "";
        self.path_index = try PathIndex.init(self.allocator, path_slice);
    }
};

pub const BuiltinFn = *const fn (
    ctx: *Context,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    args: []const command_line.Argument,
) anyerror!void;

pub const Context = struct {
    resolve_builtin: *const fn (name: []const u8) ?BuiltinFn,
    state: *ShellState,
    allocator: std.mem.Allocator,
};

pub const PathIndex = struct {
    map: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, path_env: ?[]const u8) !PathIndex {
        var map = std.StringHashMap([]const u8).init(allocator);
        errdefer deinitOwnedMap(&map, allocator);

        const path_value = path_env orelse std.posix.getenv("PATH") orelse "";
        if (path_value.len == 0) {
            return .{ .map = map, .allocator = allocator };
        }

        var segments = std.mem.splitScalar(u8, path_value, ':');
        while (segments.next()) |segment| {
            const directory_path = if (segment.len == 0) "." else segment;
            var directory = std.fs.cwd().openDir(directory_path, .{ .iterate = true }) catch continue;
            defer directory.close();

            var iterator = directory.iterate();
            while (try iterator.next()) |entry| {
                if (entry.kind == .directory) continue;
                if (map.get(entry.name) != null) continue;

                const absolute_path = try std.fs.path.join(allocator, &.{ directory_path, entry.name });
                defer allocator.free(absolute_path);

                std.posix.access(absolute_path, std.posix.X_OK) catch continue;

                const name_copy = try allocator.dupe(u8, entry.name);
                errdefer allocator.free(name_copy);

                const path_copy = try allocator.dupe(u8, absolute_path);
                errdefer allocator.free(path_copy);

                try map.put(name_copy, path_copy);
            }
        }

        return .{ .map = map, .allocator = allocator };
    }

    pub fn deinit(self: *PathIndex) void {
        deinitOwnedMap(&self.map, self.allocator);
    }

    pub fn lookup(self: *const PathIndex, name: []const u8) ?[]const u8 {
        return self.map.get(name);
    }
};

fn deinitOwnedMap(map: *std.StringHashMap([]const u8), allocator: std.mem.Allocator) void {
    var iterator = map.iterator();
    while (iterator.next()) |entry| {
        allocator.free(entry.key_ptr.*);
        allocator.free(entry.value_ptr.*);
    }
    map.deinit();
}
