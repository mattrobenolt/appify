//! appify - Generate macOS .app bundles from terminal commands.
//! Wraps TUI applications to run in Ghostty terminal emulator.

const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const process = std.process;
const Allocator = mem.Allocator;
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

const ParsedArgs = struct {
    command: ?[]const u8 = null,
    name: ?[]const u8 = null,
    output_dir: ?[]const u8 = null,
    icon_path: ?[]const u8 = null,
    bundle_id: ?[]const u8 = null,
    show_help: bool = false,
    show_version: bool = false,
};

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    // Set up allocator
    const gpa, const is_debug = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    // Use arena for temporary CLI parsing allocations
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    // Parse arguments
    const args = try parseArgs(arena_allocator);

    // Handle help and version flags
    if (args.show_help) {
        try fs.File.stdout().writeAll(help_text);
        return;
    }

    if (args.show_version) {
        const stdout = fs.File.stdout();
        try stdout.writeAll("appify version ");
        try stdout.writeAll(version);
        try stdout.writeAll("\n");
        return;
    }

    // Validate command is provided
    const command = args.command orelse {
        try printError("missing required argument: <command>", .{});
        process.exit(1);
    };

    // Derive defaults
    const name = args.name orelse deriveAppName(command);
    const output_dir = args.output_dir orelse ".";
    const bundle_id = args.bundle_id orelse try deriveBundleId(arena_allocator, name);

    // Validate output directory exists
    fs.cwd().access(output_dir, .{}) catch {
        try printError("output directory does not exist: {s}", .{output_dir});
        process.exit(1);
    };

    // Validate icon file exists if provided
    if (args.icon_path) |icon_path| {
        fs.cwd().access(icon_path, .{}) catch {
            try printError("icon file not found: {s}", .{icon_path});
            process.exit(1);
        };
    }

    // Create bundle config
    const config: bundle.Config = .{
        .command = command,
        .name = name,
        .output_dir = output_dir,
        .bundle_id = bundle_id,
        .icon_path = args.icon_path,
    };

    // Generate the app bundle
    bundle.generate(gpa, config) catch |err| {
        switch (err) {
            error.FileNotFound => {
                try printError("file not found during bundle generation", .{});
            },
            error.AccessDenied => {
                try printError("permission denied", .{});
            },
            else => {
                try printError("failed to generate app bundle: {s}", .{@errorName(err)});
            },
        }
        process.exit(1);
    };

    // Success - print confirmation
    const stdout = fs.File.stdout();
    try stdout.writeAll("Created ");
    try stdout.writeAll(name);
    try stdout.writeAll(".app in ");
    try stdout.writeAll(output_dir);
    try stdout.writeAll("\n");
}

/// Parse command line arguments into ParsedArgs struct.
fn parseArgs(allocator: Allocator) !ParsedArgs {
    var result: ParsedArgs = .{};
    var args = try process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip(); // Skip program name

    while (args.next()) |arg| {
        if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help")) {
            result.show_help = true;
        } else if (mem.eql(u8, arg, "-v") or mem.eql(u8, arg, "--version")) {
            result.show_version = true;
        } else if (mem.eql(u8, arg, "-n") or mem.eql(u8, arg, "--name")) {
            result.name = args.next() orelse {
                try printError("missing value for {s}", .{arg});
                process.exit(1);
            };
        } else if (mem.eql(u8, arg, "-o") or mem.eql(u8, arg, "--output")) {
            result.output_dir = args.next() orelse {
                try printError("missing value for {s}", .{arg});
                process.exit(1);
            };
        } else if (mem.eql(u8, arg, "-i") or mem.eql(u8, arg, "--icon")) {
            result.icon_path = args.next() orelse {
                try printError("missing value for {s}", .{arg});
                process.exit(1);
            };
        } else if (mem.eql(u8, arg, "-b") or mem.eql(u8, arg, "--bundle-id")) {
            result.bundle_id = args.next() orelse {
                try printError("missing value for {s}", .{arg});
                process.exit(1);
            };
        } else if (mem.startsWith(u8, arg, "-")) {
            try printError("unknown option: {s}", .{arg});
            process.exit(1);
        } else {
            // First non-flag argument is the command
            if (result.command == null) {
                result.command = arg;
            } else {
                try printError("unexpected argument: {s}", .{arg});
                process.exit(1);
            }
        }
    }

    return result;
}

/// Derive app name from command basename.
fn deriveAppName(command: []const u8) []const u8 {
    const basename = fs.path.basename(command);

    // Capitalize first letter if possible
    if (basename.len > 0) {
        // For now, just return basename as-is
        // Could add capitalization logic if desired
        return basename;
    }

    return "App";
}

/// Derive bundle identifier from app name.
fn deriveBundleId(allocator: Allocator, name: []const u8) ![]const u8 {
    // Convert name to lowercase for bundle ID
    const lowercase_name = try allocator.alloc(u8, name.len);
    defer allocator.free(lowercase_name);

    for (name, 0..) |c, i| {
        lowercase_name[i] = std.ascii.toLower(c);
    }

    // Replace spaces with hyphens
    for (lowercase_name) |*c| {
        if (c.* == ' ') {
            c.* = '-';
        }
    }

    return std.fmt.allocPrint(allocator, "com.appify.{s}", .{lowercase_name});
}

/// Print error message to stderr.
fn printError(comptime fmt: []const u8, args: anytype) !void {
    const stderr = fs.File.stderr();
    try stderr.writeAll("error: ");

    // Format the error message
    var buffer: [1024]u8 = undefined;
    const msg = try std.fmt.bufPrint(&buffer, fmt, args);
    try stderr.writeAll(msg);
    try stderr.writeAll("\n");
}

// Tests

test "deriveAppName from simple command" {
    const name = deriveAppName("lazygit");
    try std.testing.expectEqualStrings("lazygit", name);
}

test "deriveAppName from full path" {
    const name = deriveAppName("/opt/homebrew/bin/btop");
    try std.testing.expectEqualStrings("btop", name);
}

test "deriveBundleId from simple name" {
    const allocator = std.testing.allocator;
    const bundle_id = try deriveBundleId(allocator, "LazyGit");
    defer allocator.free(bundle_id);

    try std.testing.expectEqualStrings("com.appify.lazygit", bundle_id);
}

test "deriveBundleId with spaces" {
    const allocator = std.testing.allocator;
    const bundle_id = try deriveBundleId(allocator, "My App");
    defer allocator.free(bundle_id);

    try std.testing.expectEqualStrings("com.appify.my-app", bundle_id);
}
