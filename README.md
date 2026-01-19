# appify

Turn TUI apps into real macOS applications.

On Linux, terminal apps are just... apps. They get their own windows, their own Alt+Tab entries, their own launcher icons. On macOS, they're second-class citizens—buried in terminal tabs, invisible to Cmd+Tab, forgotten by Spotlight.

**appify fixes that.** Generate native `.app` bundles from any TUI. Your `btop` becomes a proper System Monitor. Your `weechat` gets its own Dock icon. GPU-accelerated rendering via an embedded Ghostty terminal engine—no existing Ghostty installation required.

<img width="2152" height="1104" alt="CleanShot 2026-01-18 at 17 33 41@2x" src="https://github.com/user-attachments/assets/a5aa481f-02ae-4486-bce7-d59aa09d05ef" />


## Features

- **Zero Dependencies**: Single static binary. Generated apps embed their own terminal engine—no Ghostty installation required.
- **Native Experience**: Real macOS applications (Swift + GhosttyKit), not shell script wrappers.
- **GPU Accelerated**: Ghostty's Metal-based renderer under the hood.
- **Customizable**: Custom names, bundle IDs, and icons (.icns or .png).

## Installation

### Homebrew

```bash
brew install --cask mattrobenolt/stuff/appify
```

### Build from source

```bash
zig build -Doptimize=ReleaseFast -p /usr/local/bin/
```

## Usage

```bash
appify <command> [options]
```

### Options

- `-n, --name <n>` - App name for Cmd+Tab/Dock (default: derived from command)
- `-o, --output <path>` - Output directory (default: current directory)
- `-i, --icon <path>` - Path to icon file (.icns or .png)
- `-b, --bundle-id <id>` - Bundle identifier (default: `com.appify.<n>`)
- `--ghostty-config <path>` - Ghostty config file to bundle with the app
- `-h, --help` - Show help message
- `-v, --version` - Show version

### Examples

```bash
# Simple usage
appify btop

# With custom name and icon
appify btop --name "System Monitor" --icon ./monitor.icns

# Full customization
appify weechat --name "WeeChat" --bundle-id "com.matt.weechat" --output ~/Applications
```

## Good Candidates

Apps that work best are **destinations**, not context-dependent tools:

- **System monitors**: `btop`, `bottom`, `htop`, `zenith`
- **Chat/IRC**: `weechat`, `irssi`, `gomuks`
- **Email**: `aerc`, `neomutt`
- **Music**: `cmus`, `ncmpcpp`, `spotify-tui`
- **RSS readers**: `newsboat`
- **Calendar/TODO**: `calcurse`

Apps that need a working directory context (like `lazygit` or `nvim`) are less ideal since appified apps launch from Finder/Spotlight without that context.

## Requirements

**Generated apps require:**
- macOS 11.0+

**Building from source requires:**
- Zig 0.15.2
- Xcode

## License

MIT
