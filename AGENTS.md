# AGENTS.md

This file provides guidance to AI coding agents when working with code in this repository.

## Project Overview

`appify` is a Zig CLI tool that generates macOS `.app` bundles from terminal commands. It wraps TUI applications (like `lazygit`, `btop`, `nvim`) so they appear as distinct applications in Cmd+Tab, Spotlight, and the Dock.

Generated apps are shell script launchers that invoke Ghostty terminal emulator with the specified command. No compilation occurs at generation time—output is a properly structured `.app` folder with a shell script and metadata.

## Development Commands

### Building
```bash
zig build                    # Build debug version to zig-out/bin/appify
zig build -Doptimize=ReleaseFast  # Build optimized release version
```

### Testing
```bash
zig build test              # Run unit tests
./test-integration.sh       # Run integration tests (requires build first)
```

### Running
```bash
zig build run -- <command> [options]   # Build and run with arguments
./zig-out/bin/appify <command>         # Run built binary directly
```

### Code Formatting
```bash
zig fmt src/                # Format all source files
zig fmt --check src/        # Check formatting without modifying
```

## Code Architecture

### Module Structure

The codebase is organized into four focused modules:

**main.zig** - CLI entry point and argument parsing
- Manual argument parsing using `std.process.args()` (no external CLI library)
- Derives defaults: app name from command basename, bundle ID from lowercased name
- Validates inputs: checks output directory exists, icon file exists
- Orchestrates bundle generation by calling `bundle.generate()`

**bundle.zig** - App bundle generation orchestrator
- Creates `.app` directory structure: `Contents/`, `Contents/MacOS/`, `Contents/Resources/`
- Coordinates writing Info.plist, launcher script, and processing icon
- Overwrites existing `.app` bundles without confirmation
- Makes launcher script executable using `std.posix.fchmodat()`

**plist.zig** - Info.plist XML generation
- Generates well-formed XML plists with standard macOS app metadata
- Conditionally includes `CFBundleIconFile` only if icon provided
- Uses generic `std.Io.Writer` interface for flexibility in tests
- Sets `LSUIElement=false` so apps appear in Dock while running

**icon.zig** - Icon handling and conversion
- Supports two input formats: `.icns` (direct copy) or `.png` (converted via `sips`)
- PNG conversion spawns `sips` child process: `sips -s format icns <input> --out <output>`
- All icons copied to `Resources/AppIcon.icns` regardless of input format
- Returns typed errors: `FileNotFound`, `UnsupportedFormat`, `ConversionFailed`

### Launcher Script Behavior

Generated launcher scripts (`Contents/MacOS/<AppName>`) use this pattern:

1. **AppleScript activation**: Uses `osascript` to bring app window to front
2. **Direct exec**: Uses `exec` to replace launcher process with Ghostty (not spawning subprocess)
3. **Window title**: Sets `--title='<app-name>'` so Cmd+Tab shows custom name
4. **Auto-quit**: Uses `--quit-after-last-window-closed=true`
5. **Single-window mode**: Unbinds Cmd+T (new tab), Cmd+D (split right), Cmd+Shift+D (split down)

The app appears in Dock/Cmd+Tab with the custom name, but the macOS menu bar still shows "Ghostty" (controlled by Ghostty's internal code).

### Memory Management Patterns

- **Arena for CLI parsing**: Uses `ArenaAllocator` for temporary CLI argument allocations that are freed at once
- **Stack buffers for paths**: Uses stack-allocated buffers (`[fs.max_path_bytes]u8`) with `std.fmt.bufPrint` for constructing paths
- **Allocator passing**: Only pass allocators to functions that actually need them (e.g., spawning child processes)
- **Defer cleanup**: Uses `defer` for deterministic cleanup, `errdefer` for error-path cleanup

### Error Handling Strategy

- **Early validation**: Check file existence, directory access before bundle generation
- **Typed errors**: Use custom error sets (`IconError`) with specific cases
- **User-friendly messages**: Convert errors to actionable messages via `printError()`
- **Exit codes**: Exit with code 1 on any error, 0 on success

## Zig Style Conventions

This project follows conventions documented in `ZIG_STYLE.md`:

**Type inference with anonymous literals:**
```zig
const config: bundle.Config = .{ .command = cmd, .name = name };  // Preferred
```

**Control flow as expressions:**
```zig
return switch (term) {
    .Exited => |code| if (code == 0) {} else error.Failed,
    else => error.Failed,
};
```

**Function ordering:** `init` → `deinit` → public API → private helpers

**Allocator parameter:** Only add allocator parameters to functions that actually allocate memory

## Testing Approach

### Unit Tests
- Inline in source files using `test` blocks
- Test XML generation, path construction, argument parsing edge cases
- Use `std.testing.allocator` to detect memory leaks

### Integration Tests
`test-integration.sh` validates end-to-end behavior:
1. Generates multiple test apps with various configurations
2. Verifies directory structure, file existence, executable permissions
3. Checks Info.plist and launcher script content using `grep`
4. Tests edge cases: spaces in names, custom bundle IDs, overwrites
5. Cleans up test artifacts in `/tmp`

## Key Implementation Details

### Bundle ID Generation
- Lowercase the app name
- Replace spaces with hyphens
- Prefix with `com.appify.`
- Example: "My App" → "com.appify.my-app"

### Icon File Validation
Checked at CLI parsing time, before bundle generation:
```zig
if (args.icon_path) |icon_path| {
    fs.cwd().access(icon_path, .{}) catch {
        try printError("icon file not found: {s}", .{icon_path});
        process.exit(1);
    };
}
```

### Overwrite Behavior
Silently removes existing `.app` bundles using `deleteTree()`, ignoring `FileNotFound` errors.

### Why Direct `exec` in Launcher
Using `exec` instead of spawning subprocess means:
- Launcher process is replaced by Ghostty (lower memory footprint)
- The launched app's PID belongs to Ghostty directly
- Simplifies process management (no need to wait/monitor child)

## Ghostty Flags Reference

See `GHOSTTY_FLAGS.md` for detailed documentation of flags used in launcher scripts. Key flags currently applied:

- `--title='<app-name>'` - Custom window title
- `--command='<command>'` - Command to run
- `--quit-after-last-window-closed=true` - Auto-quit behavior
- `--window-save-state=never` - Don't persist window state
- `--confirm-close-surface=false` - No quit confirmation
- `--keybind=super+t=unbind` - Disable new tab
- `--keybind=super+d=unbind` - Disable split right
- `--keybind=super+shift+d=unbind` - Disable split down

## Requirements

**For building appify:**
- Zig 0.15.2 or later
- macOS (for `sips` utility used in PNG conversion)

**For generated apps:**
- macOS 11.0 or later (enforced by `LSMinimumSystemVersion` in Info.plist)
- Ghostty terminal emulator installed at `/Applications/Ghostty.app`
