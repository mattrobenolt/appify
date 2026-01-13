# appify

Generate macOS `.app` bundles from terminal commands. Wrap TUI applications (like `lazygit`, `btop`, `nvim`) so they appear as distinct applications in Cmd+Tab, Spotlight, and the Dock.

## Features

- Fast, single static binary with no runtime dependencies
- Generates `.app` bundles that launch commands in Ghostty terminal
- Support for custom icons (.icns or .png with automatic conversion)
- Clean, idiomatic Zig codebase

## Installation

### Build from source

```bash
zig build
# Binary will be in zig-out/bin/appify
```

### Install

```bash
zig build
cp zig-out/bin/appify /usr/local/bin/
```

## Usage

```bash
appify <command> [options]
```

### Arguments

- `<command>` - The command to run (e.g., `/opt/homebrew/bin/lazygit` or just `lazygit`)

### Options

- `-n, --name <name>` - App name for Cmd+Tab/Dock (default: derived from command)
- `-o, --output <path>` - Output directory (default: current directory)
- `-i, --icon <path>` - Path to icon file (.icns or .png)
- `-b, --bundle-id <id>` - Bundle identifier (default: com.appify.<name-lowercase>)
- `-h, --help` - Show help message
- `-v, --version` - Show version

### Examples

```bash
# Simple usage
appify lazygit

# With custom name and icon
appify /opt/homebrew/bin/btop --name "System Monitor" --icon ./btop.icns

# Full customization
appify nvim --name "Neovim" --bundle-id "com.matt.neovim" --output ~/Applications
```

## How It Works

Generated apps directly execute Ghostty with the specified command:

```sh
#!/bin/sh
# Activate this app to bring window to front
osascript -e 'tell application "System Events" to set frontmost of the first process whose unix id is '"$$"' to true' 2>/dev/null &
exec /Applications/Ghostty.app/Contents/MacOS/ghostty \
    --title='<app-name>' \
    --command='<your-command>' \
    --quit-after-last-window-closed=true \
    --window-save-state=never \
    --confirm-close-surface=false \
    --keybind=super+t=unbind \
    --keybind=super+d=unbind \
    --keybind=super+shift+d=unbind
```

The `.app` bundle includes:
- `Contents/Info.plist` - macOS application metadata with your custom app name
- `Contents/MacOS/<AppName>` - Executable launcher script
- `Contents/Resources/AppIcon.icns` - Optional icon (if provided)

**Key behavior:**
- Uses AppleScript to activate the app window, bringing it to the front
- Uses `exec` to replace the launcher process with Ghostty directly
- The app appears in Dock and Cmd+Tab with **your chosen name** (e.g., "LazyGit", not "Ghostty")
- Each wrapped app is a distinct entry in Cmd+Tab
- Custom icons (if provided) are displayed in Dock and Cmd+Tab
- Disables tab and split creation keybinds for a cleaner single-window experience:
  - Cmd+T (new tab) disabled
  - Cmd+D (split right) disabled
  - Cmd+Shift+D (split down) disabled

**Note:** The macOS menu bar will still display "Ghostty" as this is controlled by Ghostty's internal code, not the wrapper.

## Requirements

**For generated apps:**
- macOS 11.0 or later
- [Ghostty](https://ghostty.org/) terminal emulator installed

**For building appify:**
- Zig 0.15.2 or later
- macOS (for `sips` utility, used for PNG to ICNS conversion)

## Development

### Run tests

```bash
# Unit tests
zig build test

# Integration tests
./test-integration.sh
```

### Code formatting

```bash
zig fmt src/
```

## Project Structure

```
appify/
  src/
    main.zig      # CLI parsing and entry point
    bundle.zig    # App bundle generation
    plist.zig     # Info.plist XML generation
    icon.zig      # Icon handling and conversion
  build.zig       # Build configuration
  test-integration.sh  # Integration tests
```

## License

MIT
