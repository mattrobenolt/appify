//! appify - Generate macOS .app bundles from terminal commands.
//! Wraps TUI applications to run in Ghostty terminal emulator.

const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const Io = std.Io;
const Allocator = mem.Allocator;
const heap = std.heap;
const testing = std.testing;
const ascii = std.ascii;
const builtin = @import("builtin");
const build_options = @import("build_options");
const version = build_options.version;

const Args = @import("Args.zig");
const bundle = @import("bundle.zig");

const help_text =
    \\appify - Turn TUI apps into real macOS applications
    \\
    \\Usage: appify [options] <command> [command-args...]
    \\       appify [options] -- <command> [args...]
    \\
    \\Arguments:
    \\  <command>    The command to run (e.g., "/opt/homebrew/bin/lazygit" or "lazygit")
    \\
    \\Options:
    \\  -n, --name <name>           App name for Cmd+Tab/Dock (default: derived from command)
    \\  -o, --output <path>         Output directory (default: current directory)
    \\  -i, --icon <path>           Path to icon file (.icns or .png)
    \\  -b, --bundle-id <id>        Bundle identifier (default: com.withmatt.appify.<name-lowercase>)
    \\  --cwd <path>                Working directory for the command
    \\  --width <points>            Initial window width in points
    \\  --height <points>           Initial window height in points
    \\  --ghostty-config <path>     Ghostty config override file (optional)
    \\  --shell                     Run command through 'sh -c' for shell features
    \\
    \\  -h, --help                  Show this help message
    \\  -v, --version               Show version
    \\
    \\Notes:
    \\  Use -- to pass through args that look like options.
    \\  Shell mode requires quoting the command string.
    \\
    \\Examples:
    \\  appify lazygit
    \\  appify /opt/homebrew/bin/btop --name "System Monitor" --icon ./btop.icns
    \\  appify nvim -u init.vim
    \\  appify nvim --name "Neovim" --bundle-id "com.matt.neovim" --output ~/Applications
    \\  appify --name "WeeChat" -- weechat --dir ~/irc
    \\  appify --shell 'cd /dir && ./run'
    \\
;

var stdout_buffer: [1024]u8 = undefined;
var stdout_writer = fs.File.stdout().writer(&stdout_buffer);
const stdout = &stdout_writer.interface;

var debug_allocator: heap.DebugAllocator(.{}) = .init;

pub fn main() u8 {
    const gpa, const is_debug = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };
    defer stdout.flush() catch {};

    var arena: heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    const code = run(allocator) catch |err| {
        printError("unexpected error: {s}", .{@errorName(err)});
        return 1;
    };
    return code;
}

fn run(gpa: Allocator) !u8 {
    const parsed = try Args.parse(gpa);
    const args = switch (parsed) {
        .help => {
            try stdout.writeAll(help_text);
            return 0;
        },
        .version => {
            try stdout.print("appify version {f}\n", .{version});
            return 0;
        },
        .err => |err| {
            reportParseError(err);
            return 1;
        },
        .run => |run_args| run_args,
    };

    // Validate command is provided
    const command = args.command;
    const command_line = args.command_line;

    // Derive defaults
    const name = args.name orelse deriveAppName(command);
    const output_dir = args.output_dir orelse ".";
    const bundle_id = args.bundle_id orelse try deriveBundleId(gpa, name);

    const root = fs.cwd();

    // Validate output directory exists
    root.access(output_dir, .{}) catch {
        printError("output directory does not exist: {s}", .{output_dir});
        return 1;
    };

    // Validate icon file exists if provided
    if (args.icon_path) |icon_path| {
        root.access(icon_path, .{}) catch {
            printError("icon file not found: {s}", .{icon_path});
            return 1;
        };
    }
    if (args.ghostty_config) |ghostty_config| {
        root.access(ghostty_config, .{}) catch {
            printError("ghostty config file not found: {s}", .{ghostty_config});
            return 1;
        };
    }
    if (args.cwd) |cwd| {
        root.access(cwd, .{}) catch {
            printError("working directory does not exist: {s}", .{cwd});
            return 1;
        };
    }

    // Create bundle config
    const config: bundle.Config = .{
        .command = command_line,
        .name = name,
        .output_dir = output_dir,
        .bundle_id = bundle_id,
        .icon_path = args.icon_path,
        .cwd = args.cwd,
        .width = args.width,
        .height = args.height,
        .ghostty_config = args.ghostty_config,
    };

    // Generate the app bundle
    config.generate(gpa, root) catch |err| {
        switch (err) {
            error.FileNotFound => printError("file not found during bundle generation", .{}),
            error.AccessDenied => printError("permission denied", .{}),
            else => printError("failed to generate app bundle: {s}", .{@errorName(err)}),
        }
        return 1;
    };

    // Success - print confirmation
    try stdout.print("Created {s}.app in {s}\n", .{ name, output_dir });
    return 0;
}

/// Derive app name from command basename.
fn deriveAppName(command: []const u8) []const u8 {
    const basename = fs.path.basename(command);

    return if (basename.len > 0) basename else "App";
}

/// Derive bundle identifier from app name.
fn deriveBundleId(gpa: Allocator, name: []const u8) ![]const u8 {
    var buffer: [255]u8 = undefined;
    var writer: Io.Writer = .fixed(&buffer);

    var prev_sep = true;
    for (name) |c| {
        if (ascii.isAlphanumeric(c)) {
            try writer.writeByte(ascii.toLower(c));
            prev_sep = false;
        } else if (!prev_sep) {
            try writer.writeByte('-');
            prev_sep = true;
        }
    }

    return std.fmt.allocPrint(gpa, "com.withmatt.appify.{s}", .{writer.buffered()});
}

fn reportParseError(err: Args.ParseError) void {
    switch (err) {
        .missing_value => |opt| printError("missing value for {s}", .{opt}),
        .invalid_value => |info| printError("invalid value for {s}: {s}", .{ info.option, info.value }),
        .unknown_option => |opt| printError("unknown option: {s}", .{opt}),
        .missing_command => printError("missing required argument: <command>", .{}),
    }
}

/// Print error message to stderr.
fn printError(comptime fmt: []const u8, args: anytype) void {
    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = fs.File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;

    stderr.print("error: " ++ fmt ++ "\n", args) catch {};
    stderr.flush() catch {};
}

test {
    testing.refAllDeclsRecursive(@This());
}

test "deriveAppName from simple command" {
    const name = deriveAppName("lazygit");
    try testing.expectEqualStrings("lazygit", name);
}

test "deriveAppName from full path" {
    const name = deriveAppName("/opt/homebrew/bin/btop");
    try testing.expectEqualStrings("btop", name);
}

test "deriveBundleId from simple name" {
    const allocator = testing.allocator;
    const bundle_id = try deriveBundleId(allocator, "LazyGit");
    defer allocator.free(bundle_id);

    try testing.expectEqualStrings("com.withmatt.appify.lazygit", bundle_id);
}

test "deriveBundleId with spaces" {
    const allocator = testing.allocator;
    const bundle_id = try deriveBundleId(allocator, "My App");
    defer allocator.free(bundle_id);

    try testing.expectEqualStrings("com.withmatt.appify.my-app", bundle_id);
}

test "deriveBundleId strips punctuation" {
    const allocator = testing.allocator;
    const bundle_id = try deriveBundleId(allocator, "My@App!");
    defer allocator.free(bundle_id);

    try testing.expectEqualStrings("com.withmatt.appify.my-app-", bundle_id);
}

test "deriveBundleId allows numeric start" {
    const allocator = testing.allocator;
    const bundle_id = try deriveBundleId(allocator, "123 App");
    defer allocator.free(bundle_id);

    try testing.expectEqualStrings("com.withmatt.appify.123-app", bundle_id);
}
