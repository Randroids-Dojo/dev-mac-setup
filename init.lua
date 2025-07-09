-- Hammerspoon Configuration for Simple Workspace Management
-- Simplified version: workspace creation and 0-9 desktop assignment only

-- Load Simple Workspace Manager
local simpleWorkspaces = require("simple-workspaces")

-- Configuration
local config = {
    hyper = {"cmd", "alt", "ctrl"}
}

-- Utility Hotkeys
hs.hotkey.bind(config.hyper, "r", function()
    hs.reload()
    hs.alert.show("Hammerspoon Reloaded")
end)

hs.hotkey.bind(config.hyper, "c", function()
    if hs.console.hswindow() then
        hs.console.hswindow():focus()
    else
        hs.openConsole()
    end
end)

-- Save current desktop as workspace
hs.hotkey.bind(config.hyper, "s", function()
    simpleWorkspaces.showSaveDialog()
end)

-- Switch to workspace shortcuts (0-9)
for i = 1, 9 do
    hs.hotkey.bind(config.hyper, tostring(i), function()
        simpleWorkspaces.switchToWorkspaceSlot(i)
    end)
end

-- Desktop 10 mapped to key "0"
hs.hotkey.bind(config.hyper, "0", function()
    simpleWorkspaces.switchToWorkspaceSlot(10)
end)

-- Show hotkey help
local function showHotkeys()
    local message = [[
Simple Workspace Manager:

⌘⌥⌃ + S: Save Current Desktop as Workspace
⌘⌥⌃ + 0-9: Switch to Workspace (0 = Desktop 10)

Utilities:
⌘⌥⌃ + R: Reload Hammerspoon
⌘⌥⌃ + C: Show Console
⌘⌥⌃ + /: Show This Help

Note: ⌘ = Command, ⌥ = Option, ⌃ = Control
]]
    hs.alert.show(message, 5)
end

hs.hotkey.bind(config.hyper, "/", showHotkeys)

-- Initialize
hs.alert.show("Simple Workspace Manager Loaded")