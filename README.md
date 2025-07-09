# Simple Hammerspoon Workspace Manager

Save and restore window layouts on macOS with simple desktop shortcuts.

## Features

- **Simple workspace creation** - Save current window layout with ⌘⌥⌃+S
- **Desktop assignment** - Assign workspaces to desktop slots 0-9
- **Automatic desktop creation** - Creates desktops as needed when switching
- **MacBook display focus** - Manages built-in screen only
- **Smart window restoration** - Restores apps and window positions

## Installation

1. **Install Hammerspoon** from [hammerspoon.org](https://www.hammerspoon.org/)
2. **Grant accessibility permissions** in System Preferences
3. **Run installer**: `./install.sh`

## Usage

| Shortcut | Action |
|----------|--------|
| **⌘⌥⌃+S** | Save current desktop as workspace |
| **⌘⌥⌃+0-9** | Switch to desktop/workspace (0 = desktop 10) |
| **⌘⌥⌃+R** | Reload Hammerspoon |
| **⌘⌥⌃+C** | Show console |
| **⌘⌥⌃+/** | Show help |

### Creating Workspaces

1. Arrange windows as desired on current desktop
2. Press **⌘⌥⌃+S** to save workspace
3. Enter workspace name and desktop slot (0-9)
4. Switch anytime with **⌘⌥⌃+[0-9]**

### Switching Workspaces

- **⌘⌥⌃+1** through **⌘⌥⌃+9** - Switch to desktops 1-9
- **⌘⌥⌃+0** - Switch to desktop 10
- If no workspace is saved, just switches to empty desktop
- If workspace is saved, restores the saved window layout

## Files

```
~/.hammerspoon/
├── init.lua                 # Main configuration
├── simple-workspaces.lua    # Workspace engine
└── simple-workspaces.json   # Saved workspaces
```

## Troubleshooting

- **Shortcuts not working**: Check accessibility permissions in System Preferences
- **Desktop not switching**: Ensure you have enough desktops or let the system create them
- **Windows not restoring**: Re-save workspace with current layout
- **Apps not launching**: Verify app is in Applications folder

For debugging, check Hammerspoon Console (⌘⌥⌃+C) for error messages.