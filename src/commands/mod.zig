const std = @import("std");
const api = @import("api.zig");
const runtime = @import("runtime.zig");
const builtins = @import("builtins/mod.zig");

pub const Context = api.Context;
pub const BuiltinFn = api.BuiltinFn;
pub const PathIndex = api.PathIndex;
pub const ShellState = api.ShellState;

pub const executeParsed = runtime.executeParsed;
pub const executeLine = runtime.executeLine;
pub const describeCommand = runtime.describeCommand;

const builtin_map = std.StaticStringMap(api.BuiltinFn).initComptime(.{
    .{ ":", builtins.colon.execute },
    .{ "exit", builtins.exit.execute },
    .{ "echo", builtins.echo.execute },
    .{ "cd", builtins.cd.execute },
    .{ "pwd", builtins.pwd.execute },
    .{ "type", builtins.type_builtin.execute },
    .{ "export", builtins.export_builtin.execute },
    .{ "eval", builtins.eval_builtin.execute },
    .{ "unset", builtins.unset.execute },
});

pub fn findBuiltin(name: []const u8) ?api.BuiltinFn {
    return builtin_map.get(name);
}
