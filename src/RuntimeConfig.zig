const std = @import("std");
const Io = std.Io;
const json = std.json;

const Config = @import("bundle.zig").Config;

const RuntimeConfig = @This();

command: []const u8,
title: []const u8,
cwd: ?[]const u8 = null,
width: ?u32 = null,
height: ?u32 = null,

pub fn init(config: *const Config) RuntimeConfig {
    return .{
        .command = config.command,
        .title = config.name,
        .cwd = config.cwd,
        .width = config.width,
        .height = config.height,
    };
}

pub fn write(self: *const RuntimeConfig, writer: *Io.Writer) !void {
    var s: json.Stringify = .{
        .writer = writer,
        .options = .{ .whitespace = .indent_2 },
    };
    try s.write(self);
}
