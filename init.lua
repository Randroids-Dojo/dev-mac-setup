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
    local message = "Simple Workspace Manager:\n\n⌘⌥⌃+S: Save Current Desktop as Workspace\n⌘⌥⌃+0-9: Switch to Workspace (0=Desktop 10)\n\nUtilities: R=Reload, C=Console, /=Help\n"
    
    -- Get workspace mappings - show only assigned ones to save space
    local workspaceMappings = simpleWorkspaces.getWorkspaceMappings()
    if workspaceMappings and next(workspaceMappings) then
        message = message .. "\nAssigned Workspaces:\n"
        for i = 1, 10 do
            local key = i == 10 and "0" or tostring(i)
            local workspace = workspaceMappings[i]
            if workspace then
                message = message .. "⌘⌥⌃+" .. key .. ": " .. workspace .. "\n"
            end
        end
    else
        message = message .. "\nNo workspaces saved yet. Use ⌘⌥⌃+S to create one!"
    end
    
    -- Create a custom alert positioned higher on screen
    local screen = hs.screen.mainScreen()
    local screenFrame = screen:frame()
    
    -- Position alert in upper third of screen
    local alertFrame = {
        x = screenFrame.x + screenFrame.w * 0.2,
        y = screenFrame.y + screenFrame.h * 0.15,
        w = screenFrame.w * 0.6,
        h = screenFrame.h * 0.4
    }
    
    -- Use a webview for better positioning control
    local webview = hs.webview.new(alertFrame)
    webview:windowTitle("Workspace Help")
    webview:windowStyle("utility")
    webview:allowTextEntry(false)
    webview:level(hs.drawing.windowLevels.floating)
    webview:behavior(hs.drawing.windowBehaviors.canJoinAllSpaces)
    webview:html([[
        <html>
        <head>
            <style>
                body { 
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif; 
                    font-size: 14px; 
                    background: rgba(0,0,0,0.85); 
                    color: white; 
                    margin: 20px; 
                    line-height: 1.4;
                }
                pre { 
                    white-space: pre-wrap; 
                    margin: 0; 
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif; 
                }
            </style>
        </head>
        <body>
            <pre>]] .. message .. [[</pre>
        </body>
        </html>
    ]])
    webview:show()
    webview:bringToFront()
    
    -- Auto-hide after 5 seconds
    hs.timer.doAfter(5, function()
        webview:delete()
    end)
end

hs.hotkey.bind(config.hyper, "/", showHotkeys)

-- Initialize
hs.alert.show("Simple Workspace Manager Loaded")