//! Info.plist generation for macOS application bundles.
//! Generates properly formatted XML plists with standard app metadata.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const PlistConfig = struct {
    executable_name: []const u8,
    bundle_id: []const u8,
    display_name: []const u8,
    has_icon: bool,
};

/// Generate an Info.plist file with the provided configuration.
/// The writer parameter accepts any writer type (file, buffer, etc).
pub fn generate(allocator: Allocator, writer: *std.Io.Writer, config: PlistConfig) !void {
    _ = allocator; // Not currently needed, but kept for consistency

    // Write XML declaration and DOCTYPE
    try writer.writeAll(
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        \\<plist version="1.0">
        \\<dict>
        \\    <key>CFBundleExecutable</key>
        \\    <string>
    );
    try writer.writeAll(config.executable_name);
    try writer.writeAll(
        \\</string>
        \\
        \\    <key>CFBundleIdentifier</key>
        \\    <string>
    );
    try writer.writeAll(config.bundle_id);
    try writer.writeAll(
        \\</string>
        \\
        \\    <key>CFBundleName</key>
        \\    <string>
    );
    try writer.writeAll(config.display_name);
    try writer.writeAll(
        \\</string>
        \\
        \\    <key>CFBundleDisplayName</key>
        \\    <string>
    );
    try writer.writeAll(config.display_name);
    try writer.writeAll(
        \\</string>
        \\
        \\    <key>CFBundlePackageType</key>
        \\    <string>APPL</string>
        \\
        \\    <key>CFBundleVersion</key>
        \\    <string>1.0</string>
        \\
        \\    <key>CFBundleShortVersionString</key>
        \\    <string>1.0</string>
        \\
        \\
    );

    // Only include CFBundleIconFile if icon is present
    if (config.has_icon) {
        try writer.writeAll(
            \\    <key>CFBundleIconFile</key>
            \\    <string>AppIcon</string>
            \\
            \\
        );
    }

    try writer.writeAll(
        \\    <key>LSMinimumSystemVersion</key>
        \\    <string>11.0</string>
        \\
        \\    <key>LSUIElement</key>
        \\    <false/>
        \\
        \\    <key>NSHighResolutionCapable</key>
        \\    <true/>
        \\</dict>
        \\</plist>
        \\
    );
}

// Tests

test "plist generation without icon" {
    const allocator = std.testing.allocator;

    const config: PlistConfig = .{
        .executable_name = "TestApp",
        .bundle_id = "com.test.testapp",
        .display_name = "TestApp",
        .has_icon = false,
    };

    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(allocator);

    try generate(allocator, buffer.writer(allocator), config);

    const output = try buffer.toOwnedSlice(allocator);
    defer allocator.free(output);

    // Verify essential keys are present
    try std.testing.expect(std.mem.indexOf(u8, output, "CFBundleExecutable") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "TestApp") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "CFBundleIdentifier") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "com.test.testapp") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "LSUIElement") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "<false/>") != null);

    // Verify icon key is NOT present
    try std.testing.expect(std.mem.indexOf(u8, output, "CFBundleIconFile") == null);
}

test "plist generation with icon" {
    const allocator = std.testing.allocator;

    const config: PlistConfig = .{
        .executable_name = "IconApp",
        .bundle_id = "com.test.iconapp",
        .display_name = "IconApp",
        .has_icon = true,
    };

    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(allocator);

    try generate(allocator, buffer.writer(allocator), config);

    const output = try buffer.toOwnedSlice(allocator);
    defer allocator.free(output);

    // Verify icon key IS present
    try std.testing.expect(std.mem.indexOf(u8, output, "CFBundleIconFile") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "AppIcon") != null);
}

test "plist generation with special characters in name" {
    const allocator = std.testing.allocator;

    const config: PlistConfig = .{
        .executable_name = "My App",
        .bundle_id = "com.test.my-app",
        .display_name = "My App",
        .has_icon = false,
    };

    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(allocator);

    try generate(allocator, buffer.writer(allocator), config);

    const output = try buffer.toOwnedSlice(allocator);
    defer allocator.free(output);

    // Verify spaces are preserved in names
    try std.testing.expect(std.mem.indexOf(u8, output, "My App") != null);
}
