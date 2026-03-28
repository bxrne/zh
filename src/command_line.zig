const std = @import("std");

pub const RedirectTarget = enum {
    stdout,
    stderr,
};

pub const Redirect = struct {
    path: ?[]const u8 = null,
    append: bool = false,

    fn set(self: *Redirect, allocator: std.mem.Allocator, path: []const u8, append: bool) void {
        if (self.path) |existing| allocator.free(existing);
        self.* = .{ .path = path, .append = append };
    }

    fn deinit(self: *const Redirect, allocator: std.mem.Allocator) void {
        if (self.path) |path| allocator.free(path);
    }
};

pub const Redirections = struct {
    stdout: Redirect = .{},
    stderr: Redirect = .{},

    fn deinit(self: *const Redirections, allocator: std.mem.Allocator) void {
        self.stdout.deinit(allocator);
        self.stderr.deinit(allocator);
    }
};

pub const Argument = struct {
    text: []const u8,
    /// When false, `~` in `cd` targets must stay literal because the word contained quotes.
    tilde_expand: bool,
};

pub const CommandLine = struct {
    args: []const Argument,
    redirections: Redirections = .{},

    pub fn deinit(self: *CommandLine, allocator: std.mem.Allocator) void {
        for (self.args) |arg| allocator.free(arg.text);
        allocator.free(self.args);
        self.redirections.deinit(allocator);
    }
};

const DetectedRedirect = struct {
    target: RedirectTarget,
    append: bool,
    width: usize,
};

fn skipWhitespace(input: []const u8, index: *usize) void {
    while (index.* < input.len and std.ascii.isWhitespace(input[index.*])) index.* += 1;
}

fn detectRedirect(input: []const u8, index: usize) ?DetectedRedirect {
    if (index >= input.len) return null;

    var cursor = index;
    const target: RedirectTarget = switch (input[cursor]) {
        '1' => blk: {
            cursor += 1;
            break :blk .stdout;
        },
        '2' => blk: {
            cursor += 1;
            break :blk .stderr;
        },
        '>' => .stdout,
        else => return null,
    };

    if (cursor >= input.len or input[cursor] != '>') return null;

    cursor += 1;
    const append = cursor < input.len and input[cursor] == '>';
    if (append) cursor += 1;

    return .{
        .target = target,
        .append = append,
        .width = cursor - index,
    };
}

const ParseState = enum { normal, single_quote, double_quote };

const ParsedWord = struct {
    text: []const u8,
    tilde_expand: bool,
};

/// Parses a single shell word.
///
/// Parsing stops at unquoted whitespace or an unquoted `>` so the caller can handle redirects.
fn parseWord(allocator: std.mem.Allocator, input: []const u8, index: *usize) !ParsedWord {
    var buffer = std.ArrayList(u8).empty;
    errdefer buffer.deinit(allocator);

    var state: ParseState = .normal;
    var had_quotes = false;

    while (index.* < input.len) {
        const current = input[index.*];
        switch (state) {
            .normal => {
                if (std.ascii.isWhitespace(current) or current == '>') break;
                if (current == '\'') {
                    had_quotes = true;
                    state = .single_quote;
                    index.* += 1;
                    continue;
                }
                if (current == '"') {
                    had_quotes = true;
                    state = .double_quote;
                    index.* += 1;
                    continue;
                }
                if (current == '\\') {
                    index.* += 1;
                    if (index.* >= input.len) break;
                    try buffer.append(allocator, input[index.*]);
                    index.* += 1;
                    continue;
                }

                try buffer.append(allocator, current);
                index.* += 1;
            },
            .single_quote => {
                if (current == '\'') {
                    state = .normal;
                    index.* += 1;
                    continue;
                }

                try buffer.append(allocator, current);
                index.* += 1;
            },
            .double_quote => {
                if (current == '"') {
                    state = .normal;
                    index.* += 1;
                    continue;
                }
                if (current == '\\') {
                    index.* += 1;
                    if (index.* >= input.len) break;
                    try buffer.append(allocator, input[index.*]);
                    index.* += 1;
                    continue;
                }

                try buffer.append(allocator, current);
                index.* += 1;
            },
        }
    }

    if (state != .normal) return error.UnterminatedQuote;

    return .{
        .text = try buffer.toOwnedSlice(allocator),
        .tilde_expand = !had_quotes,
    };
}

pub fn parse(allocator: std.mem.Allocator, input: []const u8) !CommandLine {
    var arguments = std.ArrayList(Argument).empty;
    errdefer {
        for (arguments.items) |arg| allocator.free(arg.text);
        arguments.deinit(allocator);
    }

    var redirections: Redirections = .{};
    errdefer redirections.deinit(allocator);

    var index: usize = 0;
    while (true) {
        skipWhitespace(input, &index);
        if (index >= input.len) break;

        if (detectRedirect(input, index)) |redirect| {
            index += redirect.width;
            skipWhitespace(input, &index);

            const word = try parseWord(allocator, input, &index);
            if (word.text.len == 0) {
                allocator.free(word.text);
                return error.MissingRedirectTarget;
            }

            switch (redirect.target) {
                .stdout => redirections.stdout.set(allocator, word.text, redirect.append),
                .stderr => redirections.stderr.set(allocator, word.text, redirect.append),
            }
            continue;
        }

        const word = try parseWord(allocator, input, &index);
        try arguments.append(allocator, .{
            .text = word.text,
            .tilde_expand = word.tilde_expand,
        });
    }

    return .{
        .args = try arguments.toOwnedSlice(allocator),
        .redirections = redirections,
    };
}

test "parse recognizes explicit stdout and stderr redirects" {
    const allocator = std.testing.allocator;

    var parsed = try parse(allocator, "echo hello 1>out 2>err");
    defer parsed.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), parsed.args.len);
    try std.testing.expectEqualStrings("echo", parsed.args[0].text);
    try std.testing.expectEqualStrings("hello", parsed.args[1].text);
    try std.testing.expectEqualStrings("out", parsed.redirections.stdout.path.?);
    try std.testing.expect(!parsed.redirections.stdout.append);
    try std.testing.expectEqualStrings("err", parsed.redirections.stderr.path.?);
    try std.testing.expect(!parsed.redirections.stderr.append);
}

test "parse recognizes append redirects for stdout and stderr" {
    const allocator = std.testing.allocator;

    var parsed = try parse(allocator, "echo hello 1>>out 2>>err");
    defer parsed.deinit(allocator);

    try std.testing.expectEqualStrings("out", parsed.redirections.stdout.path.?);
    try std.testing.expect(parsed.redirections.stdout.append);
    try std.testing.expectEqualStrings("err", parsed.redirections.stderr.path.?);
    try std.testing.expect(parsed.redirections.stderr.append);
}

test "parse reports missing redirect target" {
    try std.testing.expectError(error.MissingRedirectTarget, parse(std.testing.allocator, "echo hello 1>"));
}

test "parse reports unterminated quotes" {
    try std.testing.expectError(error.UnterminatedQuote, parse(std.testing.allocator, "echo \"hello"));
}
