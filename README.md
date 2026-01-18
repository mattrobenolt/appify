# appify

Generate macOS `.app` bundles from terminal commands. Wrap TUI applications (like `lazygit`, `btop`, `nvim`) so they appear as distinct applications in Cmd+Tab, Spotlight, and the Dock.

## Features

- **Fast & Self-Contained**: Single static CLI binary with no runtime dependencies.
- **Native Experience**: Generates real macOS applications (Swift + GhosttyKit), not shell scripts.
- **High Performance**: Uses the embedded Ghostty terminal engine for GPU-accelerated rendering.
- **Customizable**: Support for custom names, bundle IDs, and icons (.icns or .png).

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

`appify` embeds a compiled native Swift macOS application template that uses the [GhosttyKit](https://github.com/ghostty-org/ghostty) terminal library.

When you run `appify`:
1. It unpacks this template into a new `.app` bundle.
2. It configures the app by writing a `Contents/Resources/appify.json` file:
   ```json
   {
     "command": "lazygit",
     "title": "LazyGit"
   }
   ```
3. It updates `Info.plist` with your app name and bundle ID.
4. It processes and installs your icon.

The resulting app is a standalone macOS application that launches a dedicated terminal window running your command.

## Ghostty Config Overrides

You can bundle a Ghostty config file that layers on top of the user's system config:

```bash
appify btop --ghostty-config ./btop.ghostty
```

This file is copied into the app at `Contents/Resources/appify.ghostty` and loaded after the default config files.

## Requirements

**For generated apps:**
- macOS 11.0 or later

**For building appify (development):**
- Zig 0.15.2 or later
- Xcode (for building the Swift template)
- macOS (for `sips` utility)

## Development

### Run tests

```bash
# Unit tests
zig build test
```

### Code formatting

```bash
zig fmt src/
```

## Project Structure

```
appify/
  src/            # Zig CLI source
  macos/          # Swift App Template source
  build.zig       # Build configuration (Builds GhosttyKit -> Swift App -> CLI)
```

## License

MIT
