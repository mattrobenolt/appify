//! Info.plist generation for macOS application bundles.
//! Generates properly formatted XML plists with standard app metadata.

const std = @import("std");
const Io = std.Io;
const testing = std.testing;
const mem = std.mem;

const PlistConfig = @This();

executable_name: []const u8,
bundle_id: []const u8,
display_name: []const u8,
has_icon: bool,

/// Generate an Info.plist file with the provided configuration.
pub fn write(self: *const PlistConfig, writer: *Io.Writer) !void {
    // Write XML declaration and DOCTYPE
    try writer.writeAll(
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        \\<plist version="1.0">
        \\<dict>
        \\    <key>CFBundleExecutable</key>
        \\    <string>
    );
    try writer.writeAll(self.executable_name);
    try writer.writeAll(
        \\</string>
        \\
        \\    <key>CFBundleIdentifier</key>
        \\    <string>
    );
    try writer.writeAll(self.bundle_id);
    try writer.writeAll(
        \\</string>
        \\
        \\    <key>CFBundleName</key>
        \\    <string>
    );
    try writer.writeAll(self.display_name);
    try writer.writeAll(
        \\</string>
        \\
        \\    <key>CFBundleDisplayName</key>
        \\    <string>
    );
    try writer.writeAll(self.display_name);
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
    if (self.has_icon) {
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
    const allocator = testing.allocator;

    const config: PlistConfig = .{
        .executable_name = "TestApp",
        .bundle_id = "com.test.testapp",
        .display_name = "TestApp",
        .has_icon = false,
    };

    var writer: Io.Writer.Allocating = .init(allocator);
    defer writer.deinit();

    try config.write(&writer.writer);

    const output = try writer.toOwnedSlice();
    defer allocator.free(output);

    // Verify essential keys are present
    try testing.expect(mem.indexOf(u8, output, "CFBundleExecutable") != null);
    try testing.expect(mem.indexOf(u8, output, "TestApp") != null);
    try testing.expect(mem.indexOf(u8, output, "CFBundleIdentifier") != null);
    try testing.expect(mem.indexOf(u8, output, "com.test.testapp") != null);
    try testing.expect(mem.indexOf(u8, output, "LSUIElement") != null);
    try testing.expect(mem.indexOf(u8, output, "<false/>") != null);

    // Verify icon key is NOT present
    try testing.expect(mem.indexOf(u8, output, "CFBundleIconFile") == null);
}

test "plist generation with icon" {
    const allocator = testing.allocator;

    const config: PlistConfig = .{
        .executable_name = "IconApp",
        .bundle_id = "com.test.iconapp",
        .display_name = "IconApp",
        .has_icon = true,
    };

    var writer: Io.Writer.Allocating = .init(allocator);
    defer writer.deinit();

    try config.write(&writer.writer);

    const output = try writer.toOwnedSlice();
    defer allocator.free(output);

    // Verify icon key IS present
    try testing.expect(mem.indexOf(u8, output, "CFBundleIconFile") != null);
    try testing.expect(mem.indexOf(u8, output, "AppIcon") != null);
}

test "plist generation with special characters in name" {
    const allocator = testing.allocator;

    const config: PlistConfig = .{
        .executable_name = "My App",
        .bundle_id = "com.test.my-app",
        .display_name = "My App",
        .has_icon = false,
    };

    var writer: Io.Writer.Allocating = .init(allocator);
    defer writer.deinit();

    try config.write(&writer.writer);

    const output = try writer.toOwnedSlice();
    defer allocator.free(output);

    // Verify spaces are preserved in names
    try testing.expect(mem.indexOf(u8, output, "My App") != null);
}
