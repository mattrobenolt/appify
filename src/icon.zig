//! Icon file handling and conversion for macOS application bundles.
//! Supports copying .icns files and converting .png files to .icns using the system sips utility.

const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const testing = std.testing;
const Allocator = mem.Allocator;

pub const IconError = error{
    FileNotFound,
    UnsupportedFormat,
    ConversionFailed,
};

/// Process an icon file by copying or converting it to the Resources directory.
/// Accepts .icns (direct copy) or .png (converted via sips) formats.
pub fn process(gpa: Allocator, root: fs.Dir, icon_path: []const u8, resources_dir: fs.Dir) !void {
    // Check if icon file exists
    const icon_file = root.openFile(icon_path, .{}) catch {
        return IconError.FileNotFound;
    };
    icon_file.close();

    // Detect extension and process accordingly
    if (mem.endsWith(u8, icon_path, ".icns")) {
        try copyIconsFile(root, icon_path, resources_dir);
    } else if (mem.endsWith(u8, icon_path, ".png")) {
        try convertPngToIconS(gpa, icon_path, resources_dir);
    } else {
        return IconError.UnsupportedFormat;
    }
}

/// Copy an existing .icns file directly to the Resources directory.
fn copyIconsFile(root: fs.Dir, icon_path: []const u8, resources_dir: fs.Dir) !void {
    try root.copyFile(icon_path, resources_dir, "AppIcon.icns", .{});
}

/// Convert a .png file to .icns using the system sips utility.
fn convertPngToIconS(gpa: Allocator, icon_path: []const u8, resources_dir: fs.Dir) !void {
    var resources_path_buf: [fs.max_path_bytes]u8 = undefined;
    const resources_path = try resources_dir.realpath(".", &resources_path_buf);

    var dest_path_buf: [fs.max_path_bytes]u8 = undefined;
    const dest_path = try std.fmt.bufPrint(
        &dest_path_buf,
        "{f}",
        .{fs.path.fmtJoin(&.{ resources_path, "AppIcon.icns" })},
    );

    // Build sips command: sips -s format icns <input> --out <output>
    const argv = [_][]const u8{
        "sips",
        "-s",
        "format",
        "icns",
        icon_path,
        "--out",
        dest_path,
    };

    var child: std.process.Child = .init(&argv, gpa);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    const term = try child.spawnAndWait();

    switch (term) {
        .Exited => |code| if (code != 0) return IconError.ConversionFailed,
        else => return IconError.ConversionFailed,
    }
}

// Tests

test "extension detection - icns" {
    const path = "/path/to/icon.icns";
    try testing.expect(mem.endsWith(u8, path, ".icns"));
}

test "extension detection - png" {
    const path = "/path/to/icon.png";
    try testing.expect(mem.endsWith(u8, path, ".png"));
}

test "extension detection - unsupported" {
    const path = "/path/to/icon.jpg";
    try testing.expect(!mem.endsWith(u8, path, ".icns"));
    try testing.expect(!mem.endsWith(u8, path, ".png"));
}
