# appify - Project Specification

## Overview

`appify` is a command-line tool written in Zig that generates standalone macOS `.app` bundles from terminal commands. The primary use case is wrapping TUI applications (like `lazygit`, `btop`, `nvim`) so they appear as distinct applications in Cmd+Tab, Spotlight, and the Dock.

The generated apps are **native Swift macOS applications** that embed the **GhosttyKit** terminal emulator library.

**Key concept:** The native app is pre-compiled as a "template" and embedded into the `appify` CLI binary. When the user runs `appify`, this template is unpacked and configured via a JSON file and Info.plist updates. No compilation happens at generation time.

## Goals

- Single static binary with no runtime dependencies for the CLI.
- Fast execution (instant generation).
- Simple, ergonomic CLI.
- Generated apps are native, high-performance terminal windows.
- Clean, idiomatic Zig code for the CLI.

## Non-Goals

- GUI interface for the CLI.
- Supporting terminal emulators other than Ghostty (the app *is* a Ghostty instance).
- Icon editing/creation (just embedding existing icons).
- Code signing (user can do this separately with `codesign`).

---

## CLI Interface

```
appify <command> [options]

Arguments:
  <command>    The command to run (e.g., "/opt/homebrew/bin/lazygit" or just "lazygit")

Options:
  -n, --name <name>           App name for Cmd+Tab/Dock (default: derived from command basename)
  -o, --output <path>         Output directory (default: current directory)
  -i, --icon <path>           Path to icon file (.icns or .png)
  -b, --bundle-id <id>        Bundle identifier (default: com.appify.<name-lowercase>)
  
  -h, --help                  Show help message
  -v, --version               Show version

Examples:
  appify lazygit
  appify /opt/homebrew/bin/btop --name "System Monitor" --icon ./btop.icns
  appify nvim --name "Neovim" --bundle-id "com.matt.neovim" --output ~/Applications
```

### Behavior Notes

- If `<command>` is not an absolute path, it should be preserved as-is (user's PATH will resolve it at runtime).
- `--name` should allow spaces and be properly escaped in generated files.
- If `--icon` is a `.png` file, convert it to `.icns` using `sips` (available on all Macs).
- Output creates `<name>.app` in the specified output directory.
- Overwrite existing `.app` bundle if present (no confirmation prompt—keep it simple).

---

## Generated App Structure

For `appify lazygit --name "LazyGit" --bundle-id "com.matt.lazygit" --icon ./icon.icns`:

```
LazyGit.app/
  Contents/
    Info.plist
    MacOS/
      appify            # Native Swift Executable (renamed from template if needed, or kept as appify)
    Resources/
      AppIcon.icns      # Only present if --icon provided
      appify.json       # Runtime configuration
      appify.ghostty    # Optional Ghostty config override
```

### Info.plist

Standard macOS `Info.plist` with:
- `CFBundleIdentifier`: `com.matt.lazygit`
- `CFBundleName`: `LazyGit`
- `CFBundleDisplayName`: `LazyGit`
- `LSUIElement`: `false` (Dock app)

### Runtime Config (`appify.json`)

Located in `Contents/Resources/appify.json`.

```json
{
  "command": "lazygit",
  "title": "LazyGit",
  "cwd": null,
  "env": {}
}
```

The Swift app reads this on launch to configure the terminal surface.

### Ghostty Config Override (`appify.ghostty`)

If `--ghostty-config` is provided, the file is copied into
`Contents/Resources/appify.ghostty` and loaded after the user's default
Ghostty config files.

---

## Icon Handling

If `--icon` is provided:

1. If path ends in `.icns`: copy directly to `Contents/Resources/AppIcon.icns`
2. If path ends in `.png`: convert using system `sips`:
   ```bash
   sips -s format icns input.png --out AppIcon.icns
   ```
3. If file doesn't exist or has unsupported extension: exit with error

Run the `sips` conversion by spawning a child process from Zig.

---

## Implementation Details

### Project Structure

```
appify/
  src/
    main.zig          # Entry point, CLI parsing
    bundle.zig        # App bundle generation logic (unpacks template)
    plist.zig         # Info.plist XML generation
    icon.zig          # Icon handling/conversion
  macos/              # Native Swift App Source
    appify/           # Xcode project and source files
  build.zig           # Zig build script (builds GhosttyKit -> Swift App -> CLI)
  README.md
  LICENSE
```

### Build Process

1. **GhosttyKit**: Built from `ghostty` dependency (Swift/Zig).
2. **Swift App**: Built using `xcodebuild`, linking `GhosttyKit.xcframework`.
3. **Template**: The resulting `.app` is tarred.
4. **CLI**: The tarball is embedded into `src/main.zig` via `@embedFile`.

### Dependencies

- **Build Time**: Zig, Xcode (for `xcodebuild`), macOS SDK.
- **Run Time (CLI)**: None (static binary).
- **Run Time (Generated App)**: macOS 11+.

### Error Handling

Exit with non-zero status and print to stderr for:
- Invalid/missing arguments
- Icon file not found or invalid format
- Output directory doesn't exist or not writable
- Failed to create directory structure
- Failed to convert PNG to ICNS (sips failed)

### CLI Parsing

Use Zig's `std.process.args()` and manual parsing—keep it simple.

---

## Future Enhancements (Out of Scope for v1)

- `--args` to pass additional arguments to the command
- `--working-dir` to set initial directory
- Read config from a file for batch generation
- Homebrew formula
