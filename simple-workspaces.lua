-- Simple Workspace Manager for Hammerspoon
-- Simplified version: only workspace creation and desktop assignment (0-9)

local simpleWorkspaces = {}

-- Configuration
local config = {
    workspacesFile = os.getenv("HOME") .. "/.hammerspoon/simple-workspaces.json"
}

-- State
local state = {
    workspaces = {}
}

-- Utility functions
local function log(message)
    print("[SimpleWorkspaces] " .. message)
end

local function getBuiltInScreen()
    local screens = hs.screen.allScreens()
    for _, screen in ipairs(screens) do
        if screen:name():find("Built%-in") or screen:name():find("MacBook") then
            return screen
        end
    end
    return hs.screen.mainScreen()
end

local function saveWorkspacesToFile()
    local file = io.open(config.workspacesFile, "w")
    if file then
        file:write(hs.json.encode(state.workspaces))
        file:close()
        log("Workspaces saved to file")
    end
end

local function loadWorkspacesFromFile()
    local file = io.open(config.workspacesFile, "r")
    if file then
        local content = file:read("*all")
        file:close()
        
        local success, workspaces = pcall(hs.json.decode, content)
        if success and workspaces then
            state.workspaces = workspaces
            log("Workspaces loaded from file - count: " .. #state.workspaces)
        else
            log("Failed to parse workspaces file")
            state.workspaces = {}
        end
    else
        log("No workspaces file found")
        state.workspaces = {}
    end
end

-- Get current desktop configuration
local function getAllWindowInfo()
    local windows = {}
    local apps = hs.application.runningApplications()
    local builtInScreen = getBuiltInScreen()
    
    for _, app in ipairs(apps) do
        if app:bundleID() ~= "com.apple.dock" then
            for _, window in ipairs(app:allWindows()) do
                if window:isVisible() and window:isStandard() then
                    local screen = window:screen()
                    
                    -- Only include windows on the built-in screen
                    if screen:id() == builtInScreen:id() then
                        local frame = window:frame()
                        local screenFrame = screen:frame()
                        
                        local relativeFrame = {
                            x = (frame.x - screenFrame.x) / screenFrame.w,
                            y = (frame.y - screenFrame.y) / screenFrame.h,
                            w = frame.w / screenFrame.w,
                            h = frame.h / screenFrame.h
                        }
                        
                        table.insert(windows, {
                            app = app:name(),
                            bundleID = app:bundleID(),
                            title = window:title(),
                            frame = relativeFrame,
                            isFullscreen = window:isFullScreen(),
                            isMinimized = window:isMinimized(),
                            windowID = window:id(),
                            screenID = screen:id()
                        })
                    end
                end
            end
        end
    end
    
    return windows
end

-- Apply workspace configuration
local function applyWorkspace(workspace)
    log("Applying workspace: " .. workspace.name)
    
    local builtInScreen = getBuiltInScreen()
    local builtInScreenFrame = builtInScreen:frame()
    
    -- Switch to target desktop if supported
    if workspace.desktopIndex and hs.spaces then
        local allSpaces = hs.spaces.allSpaces()
        local screenUUID = builtInScreen:getUUID()
        local screenSpaces = allSpaces[screenUUID] or {}
        
        if workspace.desktopIndex <= #screenSpaces then
            local targetSpaceID = screenSpaces[workspace.desktopIndex]
            local currentSpace = hs.spaces.focusedSpace()
            
            if currentSpace ~= targetSpaceID then
                hs.spaces.gotoSpace(targetSpaceID)
                hs.timer.doAfter(0.5, function()
                    restoreWindows(workspace, builtInScreen, builtInScreenFrame)
                end)
                return
            end
        end
    end
    
    -- Restore windows immediately if no desktop switch needed
    restoreWindows(workspace, builtInScreen, builtInScreenFrame)
end

-- Restore windows for workspace
local function restoreWindows(workspace, builtInScreen, builtInScreenFrame)
    -- Group windows by app
    local windowsByApp = {}
    for _, windowInfo in ipairs(workspace.windows) do
        if not windowsByApp[windowInfo.bundleID] then
            windowsByApp[windowInfo.bundleID] = {}
        end
        table.insert(windowsByApp[windowInfo.bundleID], windowInfo)
    end
    
    -- Restore each app
    for bundleID, windowInfos in pairs(windowsByApp) do
        local app = hs.application.get(bundleID)
        if not app then
            hs.application.launchOrFocusByBundleID(bundleID)
            hs.timer.doAfter(1, function()
                app = hs.application.get(bundleID)
                if app then
                    restoreAppWindows(app, windowInfos, builtInScreen, builtInScreenFrame)
                end
            end)
        else
            app:unhide()
            app:activate()
            hs.timer.doAfter(0.2, function()
                restoreAppWindows(app, windowInfos, builtInScreen, builtInScreenFrame)
            end)
        end
    end
end

-- Restore windows for a specific app
local function restoreAppWindows(app, windowInfos, builtInScreen, builtInScreenFrame)
    local windows = app:allWindows()
    
    -- Filter to built-in screen windows
    local screenWindows = {}
    for _, window in ipairs(windows) do
        if window:screen():id() == builtInScreen:id() and window:isVisible() and window:isStandard() then
            table.insert(screenWindows, window)
        end
    end
    
    -- Create additional windows if needed
    local needWindows = #windowInfos - #screenWindows
    if needWindows > 0 then
        for i = 1, needWindows do
            if app:bundleID() == "com.apple.finder" then
                app:selectMenuItem({"File", "New Finder Window"})
            else
                if not app:selectMenuItem({"File", "New Window"}) then
                    if not app:selectMenuItem({"Window", "New Window"}) then
                        hs.eventtap.keyStroke({"cmd"}, "n")
                    end
                end
            end
            hs.timer.usleep(300000) -- Wait 0.3 seconds between window creation
        end
        
        -- Wait for windows to be created
        hs.timer.doAfter(1, function()
            screenWindows = {}
            for _, window in ipairs(app:allWindows()) do
                if window:screen():id() == builtInScreen:id() and window:isVisible() and window:isStandard() then
                    table.insert(screenWindows, window)
                end
            end
            positionWindows(screenWindows, windowInfos, builtInScreenFrame)
        end)
    else
        positionWindows(screenWindows, windowInfos, builtInScreenFrame)
    end
end

-- Position windows according to saved layout
local function positionWindows(windows, windowInfos, builtInScreenFrame)
    for i, windowInfo in ipairs(windowInfos) do
        local window = windows[i]
        if window then
            -- First ensure window is unminimized and visible
            window:unminimize()
            window:raise()
            
            -- Small delay to ensure window is ready for positioning
            hs.timer.doAfter(0.1, function()
                if windowInfo.isFullscreen then
                    window:setFullScreen(true)
                else
                    local newFrame = {
                        x = builtInScreenFrame.x + (windowInfo.frame.x * builtInScreenFrame.w),
                        y = builtInScreenFrame.y + (windowInfo.frame.y * builtInScreenFrame.h),
                        w = windowInfo.frame.w * builtInScreenFrame.w,
                        h = windowInfo.frame.h * builtInScreenFrame.h
                    }
                    window:setFrame(newFrame)
                end
                
                -- Ensure window stays unminimized and visible
                window:unminimize()
                window:raise()
            end)
        end
    end
end

-- Save current desktop as workspace
function simpleWorkspaces.saveCurrentDesktop(name, desktopIndex)
    local workspaceName = name or hs.dialog.textPrompt("Save Workspace", "Enter workspace name:", "", "Save", "Cancel")
    
    if not workspaceName or workspaceName == "" then
        log("Save cancelled: no workspace name provided")
        return nil
    end
    
    -- Get desktop index
    local targetDesktopIndex = desktopIndex
    if not targetDesktopIndex and hs.spaces then
        local builtInScreen = getBuiltInScreen()
        local screenUUID = builtInScreen:getUUID()
        local focusedSpace = hs.spaces.focusedSpace()
        local allSpaces = hs.spaces.allSpaces()
        local screenSpaces = allSpaces[screenUUID] or {}
        
        -- Find current desktop index
        for index, spaceID in ipairs(screenSpaces) do
            if spaceID == focusedSpace then
                targetDesktopIndex = index
                break
            end
        end
    end
    
    local windows = getAllWindowInfo()
    
    local newWorkspace = {
        name = workspaceName,
        windows = windows,
        created = os.time(),
        desktopIndex = targetDesktopIndex
    }
    
    -- Remove any existing workspace with same name or same desktop index
    for i = #state.workspaces, 1, -1 do
        if state.workspaces[i].name == workspaceName or 
           (state.workspaces[i].desktopIndex and state.workspaces[i].desktopIndex == targetDesktopIndex) then
            table.remove(state.workspaces, i)
        end
    end
    
    table.insert(state.workspaces, newWorkspace)
    saveWorkspacesToFile()
    
    local slotText = targetDesktopIndex and (" (Desktop " .. targetDesktopIndex .. ")") or ""
    hs.alert.show("Workspace saved: " .. workspaceName .. slotText)
    log("Saved workspace: " .. workspaceName .. slotText)
    
    return newWorkspace
end

-- Switch to workspace by desktop slot (0-9)
function simpleWorkspaces.switchToWorkspaceSlot(slotNumber)
    loadWorkspacesFromFile()
    
    -- Convert slot number to desktop index (0 maps to desktop 10)
    local requestedDesktop = slotNumber == 0 and 10 or slotNumber
    
    -- Always switch to the desktop first
    if hs.spaces then
        local builtInScreen = getBuiltInScreen()
        local allSpaces = hs.spaces.allSpaces()
        local screenUUID = builtInScreen:getUUID()
        local screenSpaces = allSpaces[screenUUID] or {}
        
        -- Create desktops if they don't exist
        while #screenSpaces < requestedDesktop do
            log("Creating desktop " .. (#screenSpaces + 1))
            hs.spaces.addSpaceToScreen(builtInScreen)
            -- Refresh the spaces list
            allSpaces = hs.spaces.allSpaces()
            screenSpaces = allSpaces[screenUUID] or {}
        end
        
        local actualDesktopIndex = requestedDesktop
        
        -- Switch to desktop (it should exist now)
        if actualDesktopIndex <= #screenSpaces and actualDesktopIndex > 0 then
            local targetSpaceID = screenSpaces[actualDesktopIndex]
            local currentSpace = hs.spaces.focusedSpace()
            
            if currentSpace ~= targetSpaceID then
                hs.spaces.gotoSpace(targetSpaceID)
            end
            
            -- Find workspace assigned to this desktop
            local targetWorkspace = nil
            for _, workspace in ipairs(state.workspaces) do
                if workspace.desktopIndex == actualDesktopIndex then
                    targetWorkspace = workspace
                    break
                end
            end
            
            if targetWorkspace then
                -- Apply the workspace after switching desktop
                hs.timer.doAfter(0.5, function()
                    restoreWindows(targetWorkspace, getBuiltInScreen(), getBuiltInScreen():frame())
                end)
                hs.alert.show("→ " .. targetWorkspace.name .. " (Desktop " .. actualDesktopIndex .. ")")
            else
                hs.alert.show("Desktop " .. actualDesktopIndex)
            end
        else
            hs.alert.show("Desktop " .. slotNumber .. " not available")
        end
    else
        hs.alert.show("Desktop switching not supported")
    end
end

-- Show save dialog
function simpleWorkspaces.showSaveDialog()
    local inputChooser = hs.chooser.new(function(choice)
        if choice and choice.text then
            local workspaceName = choice.text
            -- Get desktop slot
            local slotChooser = hs.chooser.new(function(slotChoice)
                if slotChoice and slotChoice.text then
                    local slotNumber = tonumber(slotChoice.text)
                    if slotNumber and slotNumber >= 0 and slotNumber <= 9 then
                        local desktopIndex = slotNumber == 0 and 10 or slotNumber
                        simpleWorkspaces.saveCurrentDesktop(workspaceName, desktopIndex)
                    else
                        hs.alert.show("Invalid slot. Enter 0-9")
                    end
                end
            end)
            
            slotChooser:placeholderText("Enter desktop slot (0-9, where 0 = desktop 10)")
            slotChooser:choices({})
            slotChooser:queryChangedCallback(function(query)
                if query and #query > 0 then
                    slotChooser:choices({{text = query}})
                end
            end)
            slotChooser:show()
        end
    end)
    
    inputChooser:placeholderText("Enter workspace name")
    inputChooser:choices({})
    inputChooser:queryChangedCallback(function(query)
        if query and #query > 0 then
            inputChooser:choices({{text = query}})
        end
    end)
    inputChooser:show()
end

-- Get workspace mappings for help display
function simpleWorkspaces.getWorkspaceMappings()
    local mappings = {}
    
    for _, workspace in ipairs(state.workspaces) do
        if workspace.desktopIndex then
            mappings[workspace.desktopIndex] = workspace.name
        end
    end
    
    return mappings
end

-- Initialize
loadWorkspacesFromFile()

return simpleWorkspaces