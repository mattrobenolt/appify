# AGENTS.md

This file provides guidance to AI coding agents when working with code in this repository.

## Project Overview

`appify` is a Zig CLI tool that generates macOS `.app` bundles from terminal commands. It wraps TUI applications (like `lazygit`, `btop`, `nvim`) so they appear as distinct applications in Cmd+Tab, Spotlight, and the Dock.

**Architecture:**
Generated apps are standalone **native Swift macOS applications** that embed the **GhosttyKit** terminal emulator library. They are *not* shell scripts. The CLI tool generates these by unpacking a pre-built template of the native app and injecting configuration.

## Development Commands

### Building
The build process is multi-stage:
1.  Builds `GhosttyKit.xcframework` (via `ghostty` dependency).
2.  Builds the Swift template app (`macos/appify`) using `xcodebuild`.
3.  Embeds the built `.app` into the Zig CLI binary.
4.  Builds the final `appify` CLI.

```bash
zig build                    # Build everything (CLI + Template)
zig build -Doptimize=ReleaseFast  # Build optimized release version
```

### Testing
```bash
zig build test              # Run unit tests
./test-integration.sh       # Run integration tests (requires build first)
```

### Running
```bash
zig build run -- <command> [options]   # Build and run CLI with arguments
./zig-out/bin/appify <command>         # Run built binary directly
```

### Code Formatting
```bash
zig fmt src/                # Format Zig source files
zig fmt --check src/        # Check formatting without modifying
```

## Code Architecture

### Module Structure

The codebase consists of the Zig CLI (`src/`) and the Swift Runtime (`macos/`).

#### Zig CLI (`src/`)

**main.zig** - CLI entry point
- Parses arguments using `std.process.args()`.
- Validates inputs (existence of files, directories).
- Orchestrates bundle generation via `bundle.zig`.

**bundle.zig** - Bundle Generation
- Unpacks the **embedded `appify.app` template** to the output directory.
- Updates `Info.plist` with the user's name and bundle ID.
- Writes runtime configuration to `Contents/Resources/appify.json`.
- Processes and installs the icon.

**plist.zig** - Info.plist Generation
- Generates `Info.plist` XML.
- Sets `LSUIElement=false` (Dock app).
- Configures standard macOS metadata.

**icon.zig** - Icon Processing
- Converts/copies icons to `Contents/Resources/AppIcon.icns`.
- Uses `sips` for PNG-to-ICNS conversion.

#### Swift Runtime (`macos/appify/`)

The generated app is a lightweight Swift wrapper around `GhosttyKit`.

**AppifyConfig.swift**
- Reads configuration from `Bundle.main.url(forResource: "appify", withExtension: "json")`.
- Structure: `{ "command": "...", "title": "...", "cwd": "...", "env": {...} }`.
- Defaults to running `yazi` if no config is found.

**GhosttyRuntime.swift**
- Initializes the `libghostty` / `GhosttyKit` runtime.
- Manages the global `ghostty_app_t` instance.

**GhosttySurfaceView.swift**
- A `NSView` subclass (wrapped in `NSViewRepresentable` for SwiftUI) that hosts the terminal surface.
- Configures the surface using the command and environment from `AppifyConfig`.
- Handles input bridging between macOS events and Ghostty.

## Configuration & Data Flow

1.  **User Run**: `appify lazygit -n "LazyGit"`
2.  **CLI Action**:
    - Unpacks template `appify.app`.
    - Writes `{"command": "lazygit", "title": "LazyGit"}` to `Contents/Resources/appify.json`.
3.  **App Launch**:
    - Swift app starts.
    - `AppifyConfig` reads `appify.json`.
    - `GhosttySurfaceView` initializes a surface executing `lazygit`.

## Zig Style Conventions

This project follows conventions documented in `ZIG_STYLE.md`.

**Allocators**:
- Use `ArenaAllocator` for short-lived CLI tasks.
- Pass allocators explicitly.
- Use `defer` for cleanup.

**Error Handling**:
- Use typed error sets.
- Return errors to `main` for printing/exit code handling.

## Testing Approach

### Unit Tests (`zig build test`)
- Tests logic in `bundle.zig`, `plist.zig`, etc.
- Mocks file system operations where possible or uses temp dirs.

### Integration Tests (`./test-integration.sh`)
- Generates actual apps.
- Verifies directory structure and file content.
- Ensures the generated app has the correct structure (Contents/MacOS, Info.plist, Resources).

## Key Implementation Details

**Template Embedding**:
The `build.zig` script packages the compiled Swift app into a TAR file and embeds it into the Zig binary as `template_tar`. This ensures the CLI is a single, self-contained binary that can generate apps without external dependencies at runtime.

**GhosttyKit Integration**:
The Swift app links against `GhosttyKit.xcframework`. The build system manages this dependency, ensuring the framework is built and placed correctly in the bundle.