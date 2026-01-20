const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const Io = std.Io;

const Args = @This();

command: []const u8,
command_line: []const u8,
name: ?[]const u8 = null,
output_dir: ?[]const u8 = null,
icon_path: ?[]const u8 = null,
bundle_id: ?[]const u8 = null,
cwd: ?[]const u8 = null,
width: ?u32 = null,
height: ?u32 = null,
ghostty_config: ?[]const u8 = null,

pub const ParseError = union(enum) {
    missing_value: []const u8,
    invalid_value: struct {
        option: []const u8,
        value: []const u8,
    },
    unknown_option: []const u8,
    missing_command,
};

pub const ParseResult = union(enum) {
    run: Args,
    help,
    version,
    err: ParseError,
};

const Raw = struct {
    command: ?[]const u8 = null,
    name: ?[]const u8 = null,
    output_dir: ?[]const u8 = null,
    icon_path: ?[]const u8 = null,
    bundle_id: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
    width: ?u32 = null,
    height: ?u32 = null,
    ghostty_config: ?[]const u8 = null,
    show_help: bool = false,
    show_version: bool = false,
    shell: bool = false,
};

const SplitOption = struct {
    option: []const u8,
    value: ?[]const u8,
};

const SliceIter = struct {
    args: []const []const u8,
    index: usize = 0,

    fn next(self: *SliceIter) ?[]const u8 {
        if (self.index >= self.args.len) return null;
        const arg = self.args[self.index];
        self.index += 1;
        return arg;
    }
};

pub fn parse(gpa: Allocator) !ParseResult {
    var args = std.process.args();
    _ = args.skip();
    return parseIter(gpa, &args);
}

pub fn parseFromSlice(gpa: Allocator, argv: []const []const u8) !ParseResult {
    var iter: SliceIter = .{ .args = argv };
    _ = iter.next();
    return parseIter(gpa, &iter);
}

fn parseIter(gpa: Allocator, args: anytype) !ParseResult {
    var result: Raw = .{};

    var command_line_builder: Io.Writer.Allocating = .init(gpa);
    defer command_line_builder.deinit();
    const command_writer = &command_line_builder.writer;
    var has_command_parts = false;
    var end_of_options = false;

    while (args.next()) |arg| {
        if (end_of_options) {
            if (result.command == null) {
                result.command = arg;
            }
            try appendCommandArg(command_writer, &has_command_parts, arg);
            continue;
        }

        if (mem.eql(u8, arg, "--")) {
            end_of_options = true;
            continue;
        }

        const split = splitOption(arg);
        if (mem.startsWith(u8, split.option, "-")) {
            if (mem.eql(u8, split.option, "-h") or mem.eql(u8, split.option, "--help")) {
                result.show_help = true;
            } else if (mem.eql(u8, split.option, "-v") or mem.eql(u8, split.option, "--version")) {
                result.show_version = true;
            } else if (mem.eql(u8, split.option, "--shell")) {
                result.shell = true;
            } else if (mem.eql(u8, split.option, "-n") or mem.eql(u8, split.option, "--name")) {
                const value = split.value orelse args.next() orelse
                    return .{ .err = .{ .missing_value = split.option } };
                result.name = value;
            } else if (mem.eql(u8, split.option, "-o") or mem.eql(u8, split.option, "--output")) {
                const value = split.value orelse args.next() orelse
                    return .{ .err = .{ .missing_value = split.option } };
                result.output_dir = value;
            } else if (mem.eql(u8, split.option, "-i") or mem.eql(u8, split.option, "--icon")) {
                const value = split.value orelse args.next() orelse
                    return .{ .err = .{ .missing_value = split.option } };
                result.icon_path = value;
            } else if (mem.eql(u8, split.option, "-b") or mem.eql(u8, split.option, "--bundle-id")) {
                const value = split.value orelse args.next() orelse
                    return .{ .err = .{ .missing_value = split.option } };
                result.bundle_id = value;
            } else if (mem.eql(u8, split.option, "--cwd")) {
                const value = split.value orelse args.next() orelse
                    return .{ .err = .{ .missing_value = split.option } };
                result.cwd = value;
            } else if (mem.eql(u8, split.option, "--width")) {
                const value = split.value orelse args.next() orelse
                    return .{ .err = .{ .missing_value = split.option } };
                const parsed = parseDimension(value) orelse
                    return .{ .err = .{ .invalid_value = .{ .option = split.option, .value = value } } };
                result.width = parsed;
            } else if (mem.eql(u8, split.option, "--height")) {
                const value = split.value orelse args.next() orelse
                    return .{ .err = .{ .missing_value = split.option } };
                const parsed = parseDimension(value) orelse
                    return .{ .err = .{ .invalid_value = .{ .option = split.option, .value = value } } };
                result.height = parsed;
            } else if (mem.eql(u8, split.option, "--ghostty-config")) {
                const value = split.value orelse args.next() orelse
                    return .{ .err = .{ .missing_value = split.option } };
                result.ghostty_config = value;
            } else if (result.command != null) {
                try appendCommandArg(command_writer, &has_command_parts, arg);
            } else {
                return .{ .err = .{ .unknown_option = split.option } };
            }
            continue;
        }

        if (result.command == null) {
            result.command = arg;
        }
        try appendCommandArg(command_writer, &has_command_parts, arg);
    }

    if (result.show_help) return .help;
    if (result.show_version) return .version;
    if (result.command == null) return .{ .err = .missing_command };

    const raw_command_line: []const u8 = try command_line_builder.toOwnedSlice();
    var command_line = raw_command_line;
    if (result.shell) {
        command_line = try wrapShellCommand(gpa, raw_command_line);
        gpa.free(raw_command_line);
    }

    return .{
        .run = .{
            .command = result.command.?,
            .command_line = command_line,
            .name = result.name,
            .output_dir = result.output_dir,
            .icon_path = result.icon_path,
            .bundle_id = result.bundle_id,
            .cwd = result.cwd,
            .width = result.width,
            .height = result.height,
            .ghostty_config = result.ghostty_config,
        },
    };
}

fn appendCommandArg(writer: *Io.Writer, has_parts: *bool, arg: []const u8) !void {
    if (has_parts.*) {
        try writer.writeByte(' ');
    }
    try appendShellArg(writer, arg);
    has_parts.* = true;
}

fn splitOption(arg: []const u8) SplitOption {
    if (mem.indexOfScalar(u8, arg, '=')) |eq| {
        return .{
            .option = arg[0..eq],
            .value = arg[eq + 1 ..],
        };
    }
    return .{
        .option = arg,
        .value = null,
    };
}

fn parseDimension(value: []const u8) ?u32 {
    const parsed = std.fmt.parseInt(u32, value, 10) catch return null;
    if (parsed == 0) return null;
    return parsed;
}

fn wrapShellCommand(gpa: Allocator, command_line: []const u8) ![]const u8 {
    var out: Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    const writer = &out.writer;

    try writer.writeAll("sh -c ");
    try appendShellArg(writer, command_line);

    return out.toOwnedSlice();
}

fn appendShellArg(writer: *Io.Writer, arg: []const u8) !void {
    if (arg.len == 0) {
        try writer.writeAll("''");
        return;
    }

    try writer.writeByte('\'');
    for (arg) |c| {
        if (c == '\'') {
            try writer.writeAll("'\"'\"'");
        } else {
            try writer.writeByte(c);
        }
    }
    try writer.writeByte('\'');
}

test "parse help returns help result" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const result = try Args.parseFromSlice(allocator, &[_][]const u8{ "appify", "--help" });
    switch (result) {
        .help => {},
        else => try testing.expect(false),
    }
}

test "parse version returns version result" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const result = try Args.parseFromSlice(allocator, &[_][]const u8{ "appify", "--version" });
    switch (result) {
        .version => {},
        else => try testing.expect(false),
    }
}

test "parse command args without separator" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const result = try Args.parseFromSlice(
        allocator,
        &[_][]const u8{ "appify", "nvim", "-u", "init.vim" },
    );
    switch (result) {
        .run => |args| {
            defer allocator.free(args.command_line);
            try testing.expectEqualStrings("nvim", args.command);
            try testing.expectEqualStrings("'nvim' '-u' 'init.vim'", args.command_line);
        },
        else => try testing.expect(false),
    }
}

test "command line escapes args" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const result = try Args.parseFromSlice(
        allocator,
        &[_][]const u8{ "appify", "weechat", "--logfile", "/tmp/with space", "it's" },
    );
    switch (result) {
        .run => |args| {
            defer allocator.free(args.command_line);
            try testing.expectEqualStrings(
                "'weechat' '--logfile' '/tmp/with space' 'it'\"'\"'s'",
                args.command_line,
            );
        },
        else => try testing.expect(false),
    }
}

test "parse long option with equals" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const result = try Args.parseFromSlice(
        allocator,
        &[_][]const u8{ "appify", "--cwd=/tmp", "lazygit" },
    );
    switch (result) {
        .run => |args| {
            defer allocator.free(args.command_line);
            try testing.expectEqualStrings("lazygit", args.command);
            try testing.expectEqualStrings("/tmp", args.cwd.?);
            try testing.expectEqualStrings("'lazygit'", args.command_line);
        },
        else => try testing.expect(false),
    }
}

test "unknown option before command is error" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const result = try Args.parseFromSlice(
        allocator,
        &[_][]const u8{ "appify", "--nope" },
    );
    switch (result) {
        .err => |err| switch (err) {
            .unknown_option => |opt| try testing.expectEqualStrings("--nope", opt),
            else => try testing.expect(false),
        },
        else => try testing.expect(false),
    }
}

test "unknown option after command is passthrough" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const result = try Args.parseFromSlice(
        allocator,
        &[_][]const u8{ "appify", "lazygit", "--foo" },
    );
    switch (result) {
        .run => |args| {
            defer allocator.free(args.command_line);
            try testing.expectEqualStrings("lazygit", args.command);
            try testing.expectEqualStrings("'lazygit' '--foo'", args.command_line);
        },
        else => try testing.expect(false),
    }
}

test "missing option value is error" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const result = try Args.parseFromSlice(
        allocator,
        &[_][]const u8{ "appify", "--name" },
    );
    switch (result) {
        .err => |err| switch (err) {
            .missing_value => |opt| try testing.expectEqualStrings("--name", opt),
            else => try testing.expect(false),
        },
        else => try testing.expect(false),
    }
}

test "options after command still parse" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const result = try Args.parseFromSlice(
        allocator,
        &[_][]const u8{ "appify", "lazygit", "--name", "LazyGit" },
    );
    switch (result) {
        .run => |args| {
            defer allocator.free(args.command_line);
            try testing.expectEqualStrings("lazygit", args.command);
            try testing.expectEqualStrings("LazyGit", args.name.?);
            try testing.expectEqualStrings("'lazygit'", args.command_line);
        },
        else => try testing.expect(false),
    }
}

test "double dash forces command args" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const result = try Args.parseFromSlice(
        allocator,
        &[_][]const u8{ "appify", "lazygit", "--", "--version" },
    );
    switch (result) {
        .run => |args| {
            defer allocator.free(args.command_line);
            try testing.expectEqualStrings("lazygit", args.command);
            try testing.expectEqualStrings("'lazygit' '--version'", args.command_line);
        },
        else => try testing.expect(false),
    }
}

test "shell wraps command line" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const result = try Args.parseFromSlice(
        allocator,
        &[_][]const u8{ "appify", "--shell", "cd /dir && ./run" },
    );
    switch (result) {
        .run => |args| {
            defer allocator.free(args.command_line);
            try testing.expectEqualStrings("cd /dir && ./run", args.command);
            try testing.expect(std.mem.startsWith(u8, args.command_line, "sh -c "));
            try testing.expect(std.mem.indexOf(u8, args.command_line, "cd /dir && ./run") != null);
        },
        else => try testing.expect(false),
    }
}
