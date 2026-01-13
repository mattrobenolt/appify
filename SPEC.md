# appify - Project Specification

## Overview

`appify` is a command-line tool written in Zig that generates standalone macOS `.app` bundles from terminal commands. The primary use case is wrapping TUI applications (like `lazygit`, `btop`, `nvim`) so they appear as distinct applications in Cmd+Tab, Spotlight, and the Dock.

The generated apps are simple shell script launchers that invoke Ghostty (or another terminal emulator) with the specified command. No compilation happens at generation time—the output is just a properly structured folder with a shell script and metadata.

## Goals

- Single static binary with no runtime dependencies
- Fast execution (should feel instant)
- Simple, ergonomic CLI
- Generated apps should work on any modern macOS (11+) without additional dependencies
- Clean, idiomatic Zig code

## Non-Goals

- GUI interface
- Supporting terminal emulators other than Ghostty (initially—can be added later)
- Icon editing/creation (just embedding existing icons)
- Code signing (user can do this separately with `codesign`)

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

- If `<command>` is not an absolute path, it should be preserved as-is (user's PATH will resolve it at runtime)
- `--name` should allow spaces and be properly escaped in generated files
- If `--icon` is a `.png` file, convert it to `.icns` using `sips` (available on all Macs)
- Output creates `<name>.app` in the specified output directory
- Overwrite existing `.app` bundle if present (no confirmation prompt—keep it simple)

---

## Generated App Structure

For `appify lazygit --name "LazyGit" --bundle-id "com.matt.lazygit" --icon ./icon.icns`:

```
LazyGit.app/
  Contents/
    Info.plist
    MacOS/
      LazyGit           # Shell script (executable)
    Resources/
      AppIcon.icns      # Only present if --icon provided
```

### Info.plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>LazyGit</string>
    
    <key>CFBundleIdentifier</key>
    <string>com.matt.lazygit</string>
    
    <key>CFBundleName</key>
    <string>LazyGit</string>
    
    <key>CFBundleDisplayName</key>
    <string>LazyGit</string>
    
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    
    <key>CFBundleVersion</key>
    <string>1.0</string>
    
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    
    <key>LSUIElement</key>
    <false/>
    
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
```

Notes:
- Omit `CFBundleIconFile` if no icon provided
- `CFBundleExecutable` must match the script filename in `MacOS/`
- `LSUIElement` is `false` so the app appears in Dock while running

### Launcher Script

`Contents/MacOS/<AppName>`:

```bash
#!/bin/bash
open -nW -a Ghostty --args \
    --command='<command>' \
    --quit-after-last-window-closed=true \
    --window-save-state=never
```

Notes:
- Must be executable (`chmod +x`)
- Use single quotes around command to handle arguments/spaces properly
- The script name must match `CFBundleExecutable` in Info.plist
- Filename should be the app name (matching the `.app` bundle name, without extension)

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
    bundle.zig        # App bundle generation logic
    plist.zig         # Info.plist XML generation
    icon.zig          # Icon handling/conversion
  build.zig
  README.md
  LICENSE
  .github/
    workflows/
      ci.yml          # Build + test on push/PR
      release.yml     # Build release binaries on tag
```

### Dependencies

- No external Zig dependencies (use std lib only)
- System dependency on `sips` for PNG conversion (present on all macOS)

### Error Handling

Exit with non-zero status and print to stderr for:
- Invalid/missing arguments
- Icon file not found or invalid format
- Output directory doesn't exist or not writable
- Failed to create directory structure
- Failed to convert PNG to ICNS (sips failed)

Keep error messages concise and actionable:
```
error: icon file not found: ./missing.png
error: output directory does not exist: /bad/path
error: failed to convert PNG to ICNS (sips exited with code 1)
```

### CLI Parsing

Use Zig's `std.process.args()` and manual parsing—keep it simple. No need for a CLI parsing library for this few options.

---

## CI/CD

### `.github/workflows/ci.yml`

Trigger: push to `main`, all pull requests

Jobs:
1. **Build**: Build on macOS (macos-latest)
2. **Test**: Run `zig build test`
3. **Lint**: Run `zig fmt --check src/`

### `.github/workflows/release.yml`

Trigger: push of version tags (`v*`)

Jobs:
1. Build release binary on macOS (both ARM and Intel if possible via cross-compile, or use matrix)
2. Create GitHub Release
3. Upload binary as release asset

Release binary naming: `appify-darwin-arm64`, `appify-darwin-x86_64`

Optionally create a universal binary by building both and using `lipo`:
```bash
lipo -create -output appify appify-arm64 appify-x86_64
```

---

## Testing

### Unit Tests

In each module, test:
- `plist.zig`: XML generation produces valid plist structure
- `bundle.zig`: correct file paths generated for given inputs
- CLI argument parsing: defaults, overrides, edge cases

### Integration Test

A build step or shell script that:
1. Runs `appify /bin/echo --name "TestApp" --output /tmp`
2. Verifies `/tmp/TestApp.app` structure exists
3. Verifies `Info.plist` contains expected values
4. Verifies launcher script is executable and contains expected content
5. Cleans up

---

## README.md

Should include:
- One-liner description
- Installation (download binary, or `zig build`)
- Usage examples
- How generated apps work (briefly explain the Ghostty invocation)
- Note that Ghostty must be installed for generated apps to work
- License

---

## Future Enhancements (Out of Scope for v1)

- `--terminal` flag to support other terminal emulators (Kitty, WezTerm, etc.)
- `--args` to pass additional arguments to the command
- `--working-dir` to set initial directory
- Read config from a file for batch generation
- Homebrew formula

---

## License

MIT
