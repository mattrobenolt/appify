# Ghostty Configuration Flags for Single-Window Apps

This document lists Ghostty configuration options that are relevant for wrapped single-window applications created with appify.

## Currently Applied Flags

These flags are already included in generated launcher scripts:

- `--title='<app-name>'` - Sets window title to app name
- `--command='<command>'` - The command to run
- `--quit-after-last-window-closed=true` - Auto-quit when window closes
- `--window-save-state=never` - Don't save window state
- `--confirm-close-surface=false` - No quit confirmation dialog

## Recommended Additional Flags for Single-Window Mode

### Disable Tabs
To prevent users from creating tabs (which would be confusing in a single-purpose app):

```
--keybind=super+t=unbind           # Disable Cmd+T (new tab)
--keybind=ctrl+tab=unbind          # Disable Ctrl+Tab (next tab)
--keybind=ctrl+shift+tab=unbind    # Disable Ctrl+Shift+Tab (previous tab)
--keybind=super+shift+bracket_left=unbind   # Disable Cmd+Shift+[ (prev tab)
--keybind=super+shift+bracket_right=unbind  # Disable Cmd+Shift+] (next tab)
--keybind=super+1=unbind           # Disable Cmd+1-9 (goto tab N)
--keybind=super+2=unbind
--keybind=super+3=unbind
--keybind=super+4=unbind
--keybind=super+5=unbind
--keybind=super+6=unbind
--keybind=super+7=unbind
--keybind=super+8=unbind
--keybind=super+9=unbind
```

### Disable Splits
To prevent users from creating split panes:

```
--keybind=super+d=unbind                    # Disable Cmd+D (split right)
--keybind=super+shift+d=unbind              # Disable Cmd+Shift+D (split down)
--keybind=super+bracket_left=unbind         # Disable Cmd+[ (prev split)
--keybind=super+bracket_right=unbind        # Disable Cmd+] (next split)
--keybind=super+alt+arrow_up=unbind         # Disable Cmd+Opt+↑ (goto split up)
--keybind=super+alt+arrow_down=unbind       # Disable Cmd+Opt+↓ (goto split down)
--keybind=super+alt+arrow_left=unbind       # Disable Cmd+Opt+← (goto split left)
--keybind=super+alt+arrow_right=unbind      # Disable Cmd+Opt+→ (goto split right)
--keybind=super+shift+enter=unbind          # Disable Cmd+Shift+Enter (zoom split)
--keybind=super+ctrl+equal=unbind           # Disable Cmd+Ctrl+= (equalize splits)
--keybind=super+ctrl+arrow_up=unbind        # Disable Cmd+Ctrl+↑ (resize split)
--keybind=super+ctrl+arrow_down=unbind      # Disable Cmd+Ctrl+↓ (resize split)
--keybind=super+ctrl+arrow_left=unbind      # Disable Cmd+Ctrl+← (resize split)
--keybind=super+ctrl+arrow_right=unbind     # Disable Cmd+Ctrl+→ (resize split)
```

### Disable New Windows
To prevent creating additional windows:

```
--keybind=super+n=unbind                    # Disable Cmd+N (new window)
```

### Window Appearance
These don't affect functionality but might be useful:

```
--window-decoration=true                    # Show/hide window decorations (titlebar, borders)
--window-padding-balance=true               # Balance padding around grid
--window-inherit-font-size=false            # Don't inherit font size from other windows
--window-inherit-working-directory=false    # Don't inherit working directory
```

### Tab Bar Visibility (Linux GTK only)
```
--gtk-tabs-location=hidden                  # Hide tab bar completely (GTK only)
```

## Implementation Options

### Option 1: Add All Flags (Maximum Lockdown)
Add all the keybind unbindings to the launcher script. This makes the wrapped app truly single-window with no escape hatches.

**Pros:**
- Clean single-purpose experience
- No confusion about tabs/splits
- Matches the mental model of "one app = one thing"

**Cons:**
- Very long launcher script
- Some power users might want splits/tabs

### Option 2: Add Critical Flags Only (Minimal)
Only add flags that prevent the most common multi-window actions:

```
--keybind=super+t=unbind     # No new tabs
--keybind=super+d=unbind     # No splits
--keybind=super+n=unbind     # No new windows
```

**Pros:**
- Shorter launcher script
- Still allows power users to use goto_split/goto_tab keybinds if they really want
- Blocks the most common accidental actions

**Cons:**
- Not fully locked down
- Users can still navigate between tabs/splits if they're created somehow

### Option 3: Make it Configurable
Add a `--single-window` flag to appify that applies all the lockdown flags.

```bash
# Default behavior (no restrictions)
appify lazygit --name "LazyGit"

# Single-window mode (all restrictions)
appify lazygit --name "LazyGit" --single-window
```

**Pros:**
- User choice
- Good for both simple and power users
- Self-documenting

**Cons:**
- More complex implementation
- Need to maintain list of flags

## Recommendation

**Option 2: Add Critical Flags Only** seems like the best default:

1. Add these 3 flags to all generated apps:
   - `--keybind=super+t=unbind` (no new tabs)
   - `--keybind=super+d=unbind` (no split right)
   - `--keybind=super+shift+d=unbind` (no split down)

2. Document in README that users can add more restrictions by editing the launcher script

3. Consider adding `--single-window` flag in a future version if users request it

This gives a clean single-window experience while keeping the launcher script readable and not being too restrictive.
