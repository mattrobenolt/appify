//! macOS application bundle generation.
//! Creates .app directory structure with Info.plist, launcher script, and optional icon.

const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const Allocator = mem.Allocator;

const icon = @import("icon.zig");
const plist = @import("plist.zig");

pub const Config = struct {
    command: []const u8,
    name: []const u8,
    output_dir: []const u8,
    bundle_id: []const u8,
    icon_path: ?[]const u8,
};

/// Generate a complete .app bundle from the provided configuration.
pub fn generate(allocator: Allocator, config: Config) !void {
    // Construct full app bundle path
    const app_name_with_ext = try std.fmt.allocPrint(allocator, "{s}.app", .{config.name});
    defer allocator.free(app_name_with_ext);

    const app_path = try fs.path.join(
        allocator,
        &.{ config.output_dir, app_name_with_ext },
    );
    defer allocator.free(app_path);

    // Remove existing bundle if present (overwrite behavior)
    fs.cwd().deleteTree(app_path) catch |err| {
        // Ignore error if directory doesn't exist
        if (err != error.FileNotFound) {
            return err;
        }
    };

    // Create directory structure
    try createDirectoryStructure(allocator, app_path);

    // Construct paths for subdirectories
    const contents_path = try fs.path.join(allocator, &.{ app_path, "Contents" });
    defer allocator.free(contents_path);

    const macos_path = try fs.path.join(allocator, &.{ contents_path, "MacOS" });
    defer allocator.free(macos_path);

    const resources_path = try fs.path.join(allocator, &.{ contents_path, "Resources" });
    defer allocator.free(resources_path);

    // Write Info.plist
    const plist_path = try fs.path.join(allocator, &.{ contents_path, "Info.plist" });
    defer allocator.free(plist_path);

    const plist_file = try fs.cwd().createFile(plist_path, .{});
    defer plist_file.close();

    var plist_buffer: [4096]u8 = undefined;
    var plist_writer = plist_file.writer(&plist_buffer);

    const plist_config: plist.PlistConfig = .{
        .executable_name = config.name,
        .bundle_id = config.bundle_id,
        .display_name = config.name,
        .has_icon = config.icon_path != null,
    };

    try plist.generate(allocator, &plist_writer.interface, plist_config);

    // Flush the buffered data to the file
    try plist_writer.end();

    // Process icon if provided
    if (config.icon_path) |icon_path| {
        try icon.process(allocator, icon_path, resources_path);
    }

    // Write launcher script
    const launcher_path = try fs.path.join(allocator, &.{ macos_path, config.name });
    defer allocator.free(launcher_path);

    try writeLauncherScript(allocator, launcher_path, config.command, config.name);

    // Make launcher executable
    try makeExecutable(launcher_path);
}

/// Create the standard .app directory structure.
fn createDirectoryStructure(allocator: Allocator, app_path: []const u8) !void {
    // Create top-level .app directory
    try fs.cwd().makePath(app_path);

    // Create Contents subdirectory
    const contents_path = try fs.path.join(allocator, &.{ app_path, "Contents" });
    defer allocator.free(contents_path);
    try fs.cwd().makePath(contents_path);

    // Create MacOS subdirectory
    const macos_path = try fs.path.join(allocator, &.{ contents_path, "MacOS" });
    defer allocator.free(macos_path);
    try fs.cwd().makePath(macos_path);

    // Create Resources subdirectory
    const resources_path = try fs.path.join(allocator, &.{ contents_path, "Resources" });
    defer allocator.free(resources_path);
    try fs.cwd().makePath(resources_path);
}

/// Write the launcher shell script that directly executes Ghostty with the command.
fn writeLauncherScript(allocator: Allocator, launcher_path: []const u8, command: []const u8, app_name: []const u8) !void {
    const script = try std.fmt.allocPrint(
        allocator,
        \\#!/bin/sh
        \\# Activate this app to bring window to front
        \\osascript -e 'tell application "System Events" to set frontmost of the first process whose unix id is '"$$"' to true' 2>/dev/null &
        \\exec /Applications/Ghostty.app/Contents/MacOS/ghostty \
        \\    --title='{s}' \
        \\    --command='{s}' \
        \\    --quit-after-last-window-closed=true \
        \\    --window-save-state=never \
        \\    --confirm-close-surface=false
        \\
    ,
        .{ app_name, command },
    );
    defer allocator.free(script);

    const launcher_file = try fs.cwd().createFile(launcher_path, .{});
    defer launcher_file.close();

    try launcher_file.writeAll(script);
}

/// Make the launcher script executable using fchmodat.
fn makeExecutable(path: []const u8) !void {
    // Use std.posix.fchmodat to set executable permissions
    // Mode 0o755 = rwxr-xr-x
    try std.posix.fchmodat(std.posix.AT.FDCWD, path, 0o755, 0);
}

// Tests

test "launcher script generation" {
    const allocator = std.testing.allocator;

    const script = try std.fmt.allocPrint(
        allocator,
        \\#!/bin/sh
        \\# Activate this app to bring window to front
        \\osascript -e 'tell application "System Events" to set frontmost of the first process whose unix id is '"$$"' to true' 2>/dev/null &
        \\exec /Applications/Ghostty.app/Contents/MacOS/ghostty \
        \\    --title='{s}' \
        \\    --command='{s}' \
        \\    --quit-after-last-window-closed=true \
        \\    --window-save-state=never \
        \\    --confirm-close-surface=false
        \\
    ,
        .{ "LazyGit", "lazygit" },
    );
    defer allocator.free(script);

    // Verify shebang
    try std.testing.expect(mem.startsWith(u8, script, "#!/bin/sh"));

    // Verify activation command
    try std.testing.expect(mem.indexOf(u8, script, "osascript") != null);

    // Verify exec and Ghostty binary path
    try std.testing.expect(mem.indexOf(u8, script, "exec /Applications/Ghostty.app/Contents/MacOS/ghostty") != null);

    // Verify title is set
    try std.testing.expect(mem.indexOf(u8, script, "--title='LazyGit'") != null);

    // Verify command is present
    try std.testing.expect(mem.indexOf(u8, script, "'lazygit'") != null);

    // Verify Ghostty flags
    try std.testing.expect(mem.indexOf(u8, script, "--quit-after-last-window-closed=true") != null);
    try std.testing.expect(mem.indexOf(u8, script, "--window-save-state=never") != null);
    try std.testing.expect(mem.indexOf(u8, script, "--confirm-close-surface=false") != null);
}

test "launcher script with command containing spaces" {
    const allocator = std.testing.allocator;

    const script = try std.fmt.allocPrint(
        allocator,
        \\#!/bin/sh
        \\# Activate this app to bring window to front
        \\osascript -e 'tell application "System Events" to set frontmost of the first process whose unix id is '"$$"' to true' 2>/dev/null &
        \\exec /Applications/Ghostty.app/Contents/MacOS/ghostty \
        \\    --title='{s}' \
        \\    --command='{s}' \
        \\    --quit-after-last-window-closed=true \
        \\    --window-save-state=never \
        \\    --confirm-close-surface=false
        \\
    ,
        .{ "My App", "/usr/local/bin/my app" },
    );
    defer allocator.free(script);

    // Verify command with spaces is preserved
    try std.testing.expect(mem.indexOf(u8, script, "'/usr/local/bin/my app'") != null);
}
