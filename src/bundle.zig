//! macOS application bundle generation.
//! Creates .app directory structure with Info.plist, launcher script, and optional icon.

const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const tar = std.tar;
const posix = std.posix;
const Allocator = mem.Allocator;
const json = std.json;
const Io = std.Io;
const testing = std.testing;

const embedded_template_tar = @import("template_tar").data;

const icon = @import("icon.zig");
const plist = @import("plist.zig");

pub const Config = struct {
    command: []const u8,
    name: []const u8,
    output_dir: []const u8,
    bundle_id: []const u8,
    icon_path: ?[]const u8,
    ghostty_config_path: ?[]const u8 = null,
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

    try extractEmbeddedTemplate(app_path);

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
        .executable_name = "appify",
        .bundle_id = config.bundle_id,
        .display_name = config.name,
        .has_icon = config.icon_path != null,
    };

    try plist.generate(&plist_writer.interface, plist_config);

    // Flush the buffered data to the file
    try plist_writer.end();

    // Process icon if provided
    if (config.icon_path) |icon_path| {
        try icon.process(allocator, icon_path, resources_path);
    }

    if (config.ghostty_config_path) |ghostty_config_path| {
        try copyGhosttyConfig(allocator, ghostty_config_path, resources_path);
    }

    try writeAppifyConfig(allocator, resources_path, config);

    const launcher_path = try fs.path.join(allocator, &.{ macos_path, "appify" });
    defer allocator.free(launcher_path);

    // Make launcher executable
    try makeExecutable(launcher_path);
}

/// Make the launcher script executable using fchmodat.
fn makeExecutable(path: []const u8) !void {
    // Use posix.fchmodat to set executable permissions
    // Mode 0o755 = rwxr-xr-x
    try posix.fchmodat(posix.AT.FDCWD, path, 0o755, 0);
}

fn copyGhosttyConfig(
    allocator: Allocator,
    ghostty_config_path: []const u8,
    resources_path: []const u8,
) !void {
    const dest_path = try fs.path.join(allocator, &.{ resources_path, "appify.ghostty" });
    defer allocator.free(dest_path);
    try fs.cwd().copyFile(ghostty_config_path, fs.cwd(), dest_path, .{});
}

const AppifyRuntimeConfig = struct {
    command: []const u8,
    title: []const u8,
    cwd: ?[]const u8 = null,
};

fn writeAppifyConfig(allocator: Allocator, resources_path: []const u8, config: Config) !void {
    const config_path = try fs.path.join(allocator, &.{ resources_path, "appify.json" });
    defer allocator.free(config_path);

    const file = try fs.cwd().createFile(config_path, .{ .truncate = true });
    defer file.close();

    const runtime_config: AppifyRuntimeConfig = .{
        .command = config.command,
        .title = config.name,
        .cwd = null,
    };

    var buffer: [4096]u8 = undefined;
    var writer = file.writer(&buffer);
    try writer.interface.print(
        "{f}\n",
        .{json.fmt(runtime_config, .{ .whitespace = .indent_2 })},
    );
    try writer.end();
}

fn extractEmbeddedTemplate(app_path: []const u8) !void {
    try fs.cwd().makePath(app_path);
    var dir = try fs.cwd().openDir(app_path, .{});
    defer dir.close();

    var reader: Io.Reader = .fixed(embedded_template_tar);
    try tar.pipeToFileSystem(dir, &reader, .{});
}

// Tests

test "appify config json" {
    const allocator = testing.allocator;

    var out: Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    const runtime_config: AppifyRuntimeConfig = .{
        .command = "lazygit",
        .title = "LazyGit",
        .cwd = null,
    };

    try out.writer.print(
        "{f}",
        .{json.fmt(runtime_config, .{ .whitespace = .indent_2 })},
    );

    const output = out.written();

    try testing.expect(mem.indexOf(u8, output, "\"command\": \"lazygit\"") != null);
    try testing.expect(mem.indexOf(u8, output, "\"title\": \"LazyGit\"") != null);
}
