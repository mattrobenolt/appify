//! appify - Generate macOS .app bundles from terminal commands.
//! Wraps TUI applications to run in Ghostty terminal emulator.

const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const process = std.process;
const Allocator = mem.Allocator;
const heap = std.heap;
const testing = std.testing;
const builtin = @import("builtin");

const bundle = @import("bundle.zig");

const version = "0.1.0";

const help_text =
    \\appify - Generate macOS .app bundles from terminal commands
    \\
    \\Usage: appify <command> [options]
    \\
    \\Arguments:
    \\  <command>    The command to run (e.g., "/opt/homebrew/bin/lazygit" or "lazygit")
    \\
    \\Options:
    \\  -n, --name <name>           App name for Cmd+Tab/Dock (default: derived from command)
    \\  -o, --output <path>         Output directory (default: current directory)
    \\  -i, --icon <path>           Path to icon file (.icns or .png)
    \\  -b, --bundle-id <id>        Bundle identifier (default: com.appify.<name-lowercase>)
    \\  --ghostty-config <path>     Ghostty config override file (optional)
    \\
    \\  -h, --help                  Show this help message
    \\  -v, --version               Show version
    \\
    \\Examples:
    \\  appify lazygit
    \\  appify /opt/homebrew/bin/btop --name "System Monitor" --icon ./btop.icns
    \\  appify nvim --name "Neovim" --bundle-id "com.matt.neovim" --output ~/Applications
    \\
;

var stdout_buffer: [1024]u8 = undefined;
var stdout_writer = fs.File.stdout().writer(&stdout_buffer);
const stdout = &stdout_writer.interface;

var debug_allocator: heap.DebugAllocator(.{}) = .init;

const ParsedArgs = struct {
    command: ?[]const u8 = null,
    name: ?[]const u8 = null,
    output_dir: ?[]const u8 = null,
    icon_path: ?[]const u8 = null,
    bundle_id: ?[]const u8 = null,
    ghostty_config_path: ?[]const u8 = null,
    show_help: bool = false,
    show_version: bool = false,
};

pub fn main() !void {
    // Set up allocator
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

    // Use arena for temporary CLI parsing allocations
    var arena: heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Parse arguments
    const args = try parseArgs();

    // Handle help and version flags
    if (args.show_help) {
        try stdout.writeAll(help_text);
        return;
    }

    if (args.show_version) {
        try stdout.print("appify version {s}\n", .{version});
        return;
    }

    // Validate command is provided
    const command = args.command orelse {
        die("missing required argument: <command>", .{});
    };

    // Derive defaults
    const name = args.name orelse deriveAppName(command);
    const output_dir = args.output_dir orelse ".";
    const bundle_id = args.bundle_id orelse try deriveBundleId(allocator, name);

    // Validate output directory exists
    fs.cwd().access(output_dir, .{}) catch {
        die("output directory does not exist: {s}", .{output_dir});
    };

    // Validate icon file exists if provided
    if (args.icon_path) |icon_path| {
        fs.cwd().access(icon_path, .{}) catch {
            die("icon file not found: {s}", .{icon_path});
        };
    }
    if (args.ghostty_config_path) |ghostty_config_path| {
        fs.cwd().access(ghostty_config_path, .{}) catch {
            die("ghostty config file not found: {s}", .{ghostty_config_path});
        };
    }

    // Create bundle config
    const config: bundle.Config = .{
        .command = command,
        .name = name,
        .output_dir = output_dir,
        .bundle_id = bundle_id,
        .icon_path = args.icon_path,
        .ghostty_config_path = args.ghostty_config_path,
    };

    // Generate the app bundle
    bundle.generate(allocator, config) catch |err| {
        switch (err) {
            error.FileNotFound => die("file not found during bundle generation", .{}),
            error.AccessDenied => die("permission denied", .{}),
            else => die("failed to generate app bundle: {s}", .{@errorName(err)}),
        }
    };

    // Success - print confirmation
    try stdout.print("Created {s}.app in {s}\n", .{ name, output_dir });
}

/// Parse command line arguments into ParsedArgs struct.
fn parseArgs() !ParsedArgs {
    var result: ParsedArgs = .{};
    var args = process.args();
    defer args.deinit();

    _ = args.skip(); // Skip program name

    while (args.next()) |arg| {
        if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help")) {
            result.show_help = true;
        } else if (mem.eql(u8, arg, "-v") or mem.eql(u8, arg, "--version")) {
            result.show_version = true;
        } else if (mem.eql(u8, arg, "-n") or mem.eql(u8, arg, "--name")) {
            result.name = args.next() orelse die("missing value for {s}", .{arg});
        } else if (mem.eql(u8, arg, "-o") or mem.eql(u8, arg, "--output")) {
            result.output_dir = args.next() orelse die("missing value for {s}", .{arg});
        } else if (mem.eql(u8, arg, "-i") or mem.eql(u8, arg, "--icon")) {
            result.icon_path = args.next() orelse die("missing value for {s}", .{arg});
        } else if (mem.eql(u8, arg, "-b") or mem.eql(u8, arg, "--bundle-id")) {
            result.bundle_id = args.next() orelse die("missing value for {s}", .{arg});
        } else if (mem.eql(u8, arg, "--ghostty-config")) {
            result.ghostty_config_path = args.next() orelse die("missing value for {s}", .{arg});
        } else if (mem.startsWith(u8, arg, "-")) {
            die("unknown option: {s}", .{arg});
        } else {
            // First non-flag argument is the command
            if (result.command == null) {
                result.command = arg;
            } else {
                die("unexpected argument: {s}", .{arg});
            }
        }
    }

    return result;
}

/// Derive app name from command basename.
fn deriveAppName(command: []const u8) []const u8 {
    const basename = fs.path.basename(command);

    return if (basename.len > 0) basename else "App";
}

/// Derive bundle identifier from app name.
fn deriveBundleId(allocator: Allocator, name: []const u8) ![]const u8 {
    // Convert name to lowercase for bundle ID
    const result = try allocator.alloc(u8, name.len);
    defer allocator.free(result);

    for (name, 0..) |c, i| {
        result[i] = switch (c) {
            ' ' => '-',
            else => std.ascii.toLower(c),
        };
    }

    return std.fmt.allocPrint(allocator, "com.appify.{s}", .{result});
}

/// Print error message to stderr.
fn die(comptime fmt: []const u8, args: anytype) noreturn {
    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = fs.File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;

    stderr.print("error: " ++ fmt ++ "\n", args) catch {};
    stderr.flush() catch {};
    std.process.exit(1);
}

// Tests

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

    try testing.expectEqualStrings("com.appify.lazygit", bundle_id);
}

test "deriveBundleId with spaces" {
    const allocator = testing.allocator;
    const bundle_id = try deriveBundleId(allocator, "My App");
    defer allocator.free(bundle_id);

    try testing.expectEqualStrings("com.appify.my-app", bundle_id);
}
