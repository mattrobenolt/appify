//! Icon file handling and conversion for macOS application bundles.
//! Supports copying .icns files and converting .png files to .icns using the system sips utility.

const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const Allocator = mem.Allocator;

pub const IconError = error{
    FileNotFound,
    UnsupportedFormat,
    ConversionFailed,
};

/// Process an icon file by copying or converting it to the Resources directory.
/// Accepts .icns (direct copy) or .png (converted via sips) formats.
pub fn process(allocator: Allocator, icon_path: []const u8, resources_dir: []const u8) !void {
    // Check if icon file exists
    const icon_file = fs.cwd().openFile(icon_path, .{}) catch {
        return IconError.FileNotFound;
    };
    icon_file.close();

    // Detect extension and process accordingly
    if (mem.endsWith(u8, icon_path, ".icns")) {
        try copyIconsFile(icon_path, resources_dir);
    } else if (mem.endsWith(u8, icon_path, ".png")) {
        try convertPngToIconS(allocator, icon_path, resources_dir);
    } else {
        return IconError.UnsupportedFormat;
    }
}

/// Copy an existing .icns file directly to the Resources directory.
fn copyIconsFile(icon_path: []const u8, resources_dir: []const u8) !void {
    var dest_path_buf: [fs.max_path_bytes]u8 = undefined;
    const dest_path = try std.fmt.bufPrint(&dest_path_buf, "{s}/AppIcon.icns", .{resources_dir});

    try fs.cwd().copyFile(icon_path, fs.cwd(), dest_path, .{});
}

/// Convert a .png file to .icns using the system sips utility.
fn convertPngToIconS(allocator: Allocator, icon_path: []const u8, resources_dir: []const u8) !void {
    var dest_path_buf: [fs.max_path_bytes]u8 = undefined;
    const dest_path = try std.fmt.bufPrint(&dest_path_buf, "{s}/AppIcon.icns", .{resources_dir});

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

    var child: std.process.Child = .init(&argv, allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    const term = try child.spawnAndWait();

    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                return IconError.ConversionFailed;
            }
        },
        else => return IconError.ConversionFailed,
    }
}

// Tests

test "extension detection - icns" {
    const path = "/path/to/icon.icns";
    try std.testing.expect(mem.endsWith(u8, path, ".icns"));
}

test "extension detection - png" {
    const path = "/path/to/icon.png";
    try std.testing.expect(mem.endsWith(u8, path, ".png"));
}

test "extension detection - unsupported" {
    const path = "/path/to/icon.jpg";
    try std.testing.expect(!mem.endsWith(u8, path, ".icns"));
    try std.testing.expect(!mem.endsWith(u8, path, ".png"));
}
