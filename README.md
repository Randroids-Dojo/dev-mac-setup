# Hammerspoon Workspace Manager

Save and restore window layouts on macOS with custom shortcuts.

## Features

- **Visual workspace manager** with native macOS interface
- **Intelligent window restoration** - creates missing app instances automatically
- **Conflict detection** - prevents duplicate names and shortcuts
- **MacBook display focus** - manages laptop screen only

## Installation

1. **Install Hammerspoon** from [hammerspoon.org](https://www.hammerspoon.org/)
2. **Grant accessibility permissions** in System Preferences
3. **Run installer**: `./install.sh`

## Usage

| Shortcut | Action |
|----------|--------|
| **⌘⌥⌃+W** | Open workspace manager |
| **⌘⌥⌃+S** | Save current layout |
| **⌘⌥⌃+R** | Reload Hammerspoon |
| **⌘⌥⌃+/** | Show help |

### Creating Workspaces

1. Arrange windows as desired
2. Press **⌘⌥⌃+S** to save
3. Enter name and shortcut key (a-z, 0-9)
4. Apply anytime with **⌘⌥⌃+W** or custom shortcut

## Files

```
~/.hammerspoon/
├── init.lua                 # Main configuration
├── simple-workspaces.lua    # Workspace engine
└── simple-workspaces.json   # Saved workspaces
```

## Troubleshooting

- **Shortcuts not working**: Check accessibility permissions
- **Positioning issues**: Re-save workspace with current layout
- **Apps not launching**: Verify app is in Applications folder

Enable debug mode: Set `DEBUG = true` in `init.lua`