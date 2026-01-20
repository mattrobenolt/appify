//! macOS application bundle generation.
//! Creates .app directory structure with Info.plist, launcher script, and optional icon.

const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const tar = std.tar;
const Allocator = mem.Allocator;
const Io = std.Io;

const embedded_template_tar = @import("template_tar").data;

const icon = @import("icon.zig");
const PlistConfig = @import("PlistConfig.zig");
const RuntimeConfig = @import("RuntimeConfig.zig");

pub const Config = struct {
    command: []const u8,
    name: []const u8,
    output_dir: []const u8,
    bundle_id: []const u8,
    icon_path: ?[]const u8,
    cwd: ?[]const u8 = null,
    width: ?u32 = null,
    height: ?u32 = null,
    ghostty_config: ?[]const u8 = null,

    /// Generate a complete .app bundle from the provided configuration.
    pub fn generate(self: *const Config, gpa: Allocator, root: fs.Dir) !void {
        var output_dir = try root.openDir(self.output_dir, .{});
        defer output_dir.close();

        var app_name_buf: [fs.max_name_bytes]u8 = undefined;
        const app_name_with_ext = try std.fmt.bufPrint(&app_name_buf, "{s}.app", .{self.name});

        // Remove existing bundle if present (overwrite behavior)
        output_dir.deleteTree(app_name_with_ext) catch |err| {
            // Ignore error if directory doesn't exist
            if (err != error.FileNotFound) return err;
        };

        try output_dir.makePath(app_name_with_ext);
        var app_dir = try output_dir.openDir(app_name_with_ext, .{});
        defer app_dir.close();

        try extractEmbeddedTemplate(app_dir);

        var contents_dir = try app_dir.openDir("Contents", .{});
        defer contents_dir.close();

        var macos_dir = try contents_dir.openDir("MacOS", .{});
        defer macos_dir.close();

        var resources_dir = try contents_dir.openDir("Resources", .{});
        defer resources_dir.close();

        const plist_config: PlistConfig = .{
            .executable_name = "appify",
            .bundle_id = self.bundle_id,
            .display_name = self.name,
            .has_icon = self.icon_path != null,
        };

        try writeConfig(contents_dir, "Info.plist", &plist_config);

        // Process icon if provided
        if (self.icon_path) |icon_path| {
            try icon.process(gpa, root, icon_path, resources_dir);
        }

        if (self.ghostty_config) |ghostty_config| {
            try copyGhosttyConfig(root, ghostty_config, resources_dir);
        }

        const runtime_config: RuntimeConfig = .init(self);
        try writeConfig(resources_dir, "appify.json", &runtime_config);

        var launcher_file = try macos_dir.openFile("appify", .{});
        defer launcher_file.close();
        try launcher_file.chmod(0o755);
    }
};

fn copyGhosttyConfig(
    source_dir: fs.Dir,
    ghostty_config_path: []const u8,
    resources_dir: fs.Dir,
) !void {
    try source_dir.copyFile(ghostty_config_path, resources_dir, "appify.ghostty", .{});
}

fn writeConfig(dir: fs.Dir, name: []const u8, config: anytype) !void {
    const file = try dir.createFile(name, .{});
    defer file.close();

    var buffer: [1024]u8 = undefined;
    var file_writer = file.writer(&buffer);
    const writer = &file_writer.interface;

    try config.write(writer);
    try file_writer.end();
}

fn extractEmbeddedTemplate(dir: fs.Dir) !void {
    var reader: Io.Reader = .fixed(embedded_template_tar);
    try tar.pipeToFileSystem(dir, &reader, .{});
}
