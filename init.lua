-- Hammerspoon Configuration for Workspace Management
-- Author: Custom workspace automation

-- Debug mode - set to true to see debug messages
local DEBUG = false

-- Load Simple Workspace Manager
local visualWorkspaces = require("simple-workspaces")

-- Helper function for debug logging
local function debug(message)
    if DEBUG then
        print("DEBUG: " .. message)
    end
end

-- Configuration
local config = {
    -- Modifier keys for hotkeys (using Option key on Mac)
    hyper = {"cmd", "alt", "ctrl"}
}

-- Setup Hotkeys
debug("Setting up hotkeys...")

-- Additional Utility Hotkeys
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

-- Visual Workspace Manager
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "w", function()
    visualWorkspaces.toggle()
end)

hs.hotkey.bind({"cmd", "alt", "ctrl"}, "s", function()
    -- Use the visual workspace manager's input system for consistency
    visualWorkspaces.showSaveDialog()
end)

-- Window Management Helpers
hs.hotkey.bind(config.hyper, "h", function()
    local apps = hs.application.runningApplications()
    for _, app in ipairs(apps) do
        if app:bundleID() ~= "com.apple.finder" and app:bundleID() ~= "com.apple.dock" then
            app:hide()
        end
    end
    hs.alert.show("All apps hidden")
end)

-- Debug hotkey removed - validation works correctly

-- Initialize
hs.alert.show("Hammerspoon Workspace Manager Loaded")
debug("Configuration loaded successfully")

-- Test hotkey to verify Hammerspoon is working (disabled)
-- hs.hotkey.bind(config.hyper, "t", function()
--     hs.alert.show("Test hotkey works!")
-- end)

-- Show available hotkeys
local function showHotkeys()
    local message = [[
Workspace Manager Hotkeys:

Visual Workspace Manager:
⌘⌥⌃ + W: Open Visual Workspace Manager
⌘⌥⌃ + S: Save Current Desktop as Workspace

Utilities:
⌘⌥⌃ + R: Reload Hammerspoon
⌘⌥⌃ + C: Show Console
⌘⌥⌃ + H: Hide All Apps
⌘⌥⌃ + /: Show This Help
]]
    
    -- Get saved workspaces with shortcuts
    local workspaces = visualWorkspaces.getWorkspacesForHelp()
    if workspaces and #workspaces > 0 then
        message = message .. "\nSaved Workspaces:\n"
        for _, workspace in ipairs(workspaces) do
            message = message .. "⌘⌥⌃ + " .. workspace.shortcutKey .. ": " .. workspace.name .. "\n"
        end
    else
        message = message .. "\nNo saved workspaces yet. Use ⌘⌥⌃+S to create one!\n"
    end
    
    message = message .. "\nNote: ⌘ = Command, ⌥ = Option, ⌃ = Control"
    
    hs.alert.show(message, 5)
end

hs.hotkey.bind(config.hyper, "/", showHotkeys)
