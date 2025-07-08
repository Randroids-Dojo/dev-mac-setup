-- Simple Visual Workspace Manager for Hammerspoon
local simpleWorkspaces = {}

-- Configuration
local config = {
    workspacesFile = os.getenv("HOME") .. "/.hammerspoon/simple-workspaces.json"
}

-- State
local state = {
    workspaces = {},
    chooser = nil,
    shortcuts = {}, -- Track bound shortcuts
    spaceWatcher = nil,
    lastSpace = nil
}

-- Utility functions
local function log(message)
    print("SimpleWorkspaces: " .. message)
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

-- Utility function to validate shortcut keys
local function isValidShortcutKey(key)
    if not key or key == "" then
        log("Validation failed: key is nil or empty")
        return false
    end
    
    -- Only allow single character keys (letters and numbers)
    if #key ~= 1 then
        log("Validation failed: key length is " .. #key .. ", expected 1")
        return false
    end
    
    local char = key:lower()
    
    -- Check if it's a letter (a-z)
    local isLetter = char >= 'a' and char <= 'z'
    
    -- Check if it's a number (0-9) 
    local isNumber = char >= '0' and char <= '9'
    
    local isValid = isLetter or isNumber
    
    -- Debug logging
    log("Validating shortcut key '" .. key .. "': " .. tostring(isValid))
    
    return isValid
end

-- Check for conflicting shortcuts
local function hasConflictingShortcut(key)
    -- Check against system shortcuts only (r, c, w, s, h, /)
    local conflicts = {"r", "c", "w", "s", "h", "/"}
    local keyLower = key:lower()
    
    for _, conflict in ipairs(conflicts) do
        if keyLower == conflict then
            log("Shortcut conflict: '" .. key .. "' conflicts with system shortcut ⌘⌥⌃+" .. conflict)
            return true, "conflicts with system shortcut ⌘⌥⌃+" .. conflict
        end
    end
    return false, nil
end

-- Check for existing workspace using the same shortcut
local function findWorkspaceWithShortcut(key)
    if not key or key == "" then
        log("findWorkspaceWithShortcut: key is empty or nil")
        return nil
    end
    
    log("findWorkspaceWithShortcut: Looking for shortcut key '" .. key .. "'")
    log("findWorkspaceWithShortcut: Current workspaces count: " .. #state.workspaces)
    
    for i, workspace in ipairs(state.workspaces) do
        local workspaceShortcut = workspace.shortcutKey or "none"
        log("findWorkspaceWithShortcut: Checking workspace " .. i .. " ('" .. tostring(workspace.name) .. "') shortcut: '" .. workspaceShortcut .. "'")
        if workspace.shortcutKey and workspace.shortcutKey:lower() == key:lower() then
            log("findWorkspaceWithShortcut: Found matching shortcut!")
            return workspace
        end
    end
    log("findWorkspaceWithShortcut: No matching shortcut found")
    return nil
end

-- Check for existing workspace with the same name
local function findWorkspaceWithName(name)
    if not name or name == "" then
        log("findWorkspaceWithName: name is empty or nil")
        return nil
    end
    
    log("findWorkspaceWithName: Looking for workspace named '" .. name .. "'")
    log("findWorkspaceWithName: Current workspaces count: " .. #state.workspaces)
    
    for i, workspace in ipairs(state.workspaces) do
        log("findWorkspaceWithName: Checking workspace " .. i .. " name: '" .. tostring(workspace.name) .. "'")
        if workspace.name == name then
            log("findWorkspaceWithName: Found matching workspace!")
            return workspace
        end
    end
    log("findWorkspaceWithName: No matching workspace found")
    return nil
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
            for i, workspace in ipairs(state.workspaces) do
                log("Loaded workspace " .. i .. ": '" .. tostring(workspace.name) .. "'")
            end
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

-- Helper function to position windows for an app
local function positionAppWindows(app, windowInfos, builtInScreen, builtInScreenFrame)
    hs.timer.doAfter(0.5, function()
        local windows = app:allWindows()
        log("Positioning " .. #windows .. " windows for " .. app:name())
        
        -- Filter windows to only those on the built-in screen
        local screenWindows = {}
        for _, window in ipairs(windows) do
            log("Checking window: " .. window:title() .. 
                ", screen match: " .. tostring(window:screen():id() == builtInScreen:id()) ..
                ", visible: " .. tostring(window:isVisible()) ..
                ", standard: " .. tostring(window:isStandard()))
            
            -- Filter windows appropriately for positioning
            local includeWindow = false
            if window:screen():id() == builtInScreen:id() and window:isVisible() then
                if app:bundleID() == "com.apple.finder" then
                    -- For Finder positioning, only include standard windows with titles
                    includeWindow = window:isStandard() and window:title() ~= ""
                else
                    -- For other apps, require standard windows
                    includeWindow = window:isStandard()
                end
            end
            
            if includeWindow then
                table.insert(screenWindows, window)
            end
        end
        
        log("Found " .. #screenWindows .. " windows on built-in screen for positioning")
        
        for i, windowInfo in ipairs(windowInfos) do
            local window = nil
            
            -- First try to find by saved windowID
            for _, w in ipairs(screenWindows) do
                if w:id() == windowInfo.windowID then
                    window = w
                    log("Found exact window match by ID: " .. windowInfo.windowID)
                    break
                end
            end
            
            -- If no exact match, sort windows by ID and use positional matching
            if not window then
                table.sort(screenWindows, function(a, b)
                    return a:id() < b:id()
                end)
                window = screenWindows[i]
                if window then
                    log("Using positional match - window " .. i .. " (ID: " .. window:id() .. ") for saved windowID: " .. windowInfo.windowID)
                end
            end
            
            if window then
                log("Positioning window " .. i .. " (ID: " .. window:id() .. "): " .. window:title())
                
                hs.timer.doAfter(i * 0.1, function()
                    -- Move to built-in screen if not already there
                    if window:screen():id() ~= builtInScreen:id() then
                        window:moveToScreen(builtInScreen)
                        hs.timer.usleep(100000) -- Wait 0.1 seconds for move to complete
                    end
                    
                    if windowInfo.isFullscreen then
                        window:setFullScreen(true)
                    else
                        local newFrame = {
                            x = builtInScreenFrame.x + (windowInfo.frame.x * builtInScreenFrame.w),
                            y = builtInScreenFrame.y + (windowInfo.frame.y * builtInScreenFrame.h),
                            w = windowInfo.frame.w * builtInScreenFrame.w,
                            h = windowInfo.frame.h * builtInScreenFrame.h
                        }
                        log("Setting frame for window " .. i .. ": x=" .. newFrame.x .. ", y=" .. newFrame.y .. ", w=" .. newFrame.w .. ", h=" .. newFrame.h)
                        window:setFrame(newFrame)
                    end
                    -- Ensure window is visible and raised
                    window:unminimize()
                    window:raise()
                end)
            else
                log("Warning: Could not find window " .. i .. " for positioning")
            end
        end
    end)
end

-- Forward declarations
local applyWorkspaceWindows
local moveWorkspaceWindows
local isWorkspaceAlreadyActive

-- Apply workspace configuration
local function applyWorkspace(workspace)
    log("=== APPLYING WORKSPACE: " .. workspace.name .. " ===")
    
    local builtInScreen = getBuiltInScreen()
    local builtInScreenFrame = builtInScreen:frame()
    
    -- Get current desktop info for debugging
    if workspace.spaceSupported and workspace.desktopIndex and hs.spaces then
        local allSpaces = hs.spaces.allSpaces()
        local screenUUID = builtInScreen:getUUID()
        local screenSpaces = allSpaces[screenUUID] or {}
        local currentSpace = hs.spaces.focusedSpace()
        
        local currentDesktopIndex = nil
        for index, spaceID in ipairs(screenSpaces) do
            if spaceID == currentSpace then
                currentDesktopIndex = index
                break
            end
        end
        
        log("Current desktop: " .. tostring(currentDesktopIndex) .. ", Target desktop: " .. tostring(workspace.desktopIndex))
    end
    
    -- Fast path: Check if workspace is already correctly set up
    log("Checking if workspace is already active...")
    if isWorkspaceAlreadyActive(workspace, builtInScreen) then
        log("*** WORKSPACE ALREADY ACTIVE - NO CHANGES NEEDED ***")
        hs.alert.show("✓ " .. workspace.name .. " (already active)")
        return
    else
        log("*** WORKSPACE NOT DETECTED AS ACTIVE - PROCEEDING WITH SETUP ***")
    end
    
    -- Try fast desktop switch - switch first, then validate
    if workspace.spaceSupported and workspace.desktopIndex and hs.spaces then
        local allSpaces = hs.spaces.allSpaces()
        local screenUUID = builtInScreen:getUUID()
        local screenSpaces = allSpaces[screenUUID] or {}
        
        if workspace.desktopIndex <= #screenSpaces then
            local targetSpaceID = screenSpaces[workspace.desktopIndex]
            local currentSpace = hs.spaces.focusedSpace()
            
            log("Target desktop " .. workspace.desktopIndex .. " has current space ID: " .. tostring(targetSpaceID))
            
            -- Only do this check if we're NOT already on the target desktop
            if currentSpace ~= targetSpaceID then
                log("Attempting fast desktop switch to desktop " .. workspace.desktopIndex)
                log("🚀 CALLING hs.spaces.gotoSpace(" .. tostring(targetSpaceID) .. ") for fast switch")
                hs.spaces.gotoSpace(targetSpaceID)
                
                -- Wait for switch, then validate
                hs.timer.doAfter(0.5, function()
                    log("Validating fast switch - checking if workspace is now correctly set up")
                    if isWorkspaceAlreadyActive(workspace, builtInScreen) then
                        log("✅ Fast switch successful - workspace is correctly set up")
                        hs.alert.show("→ " .. workspace.name .. " (Desktop " .. workspace.desktopIndex .. ")")
                    else
                        log("❌ Fast switch validation failed - proceeding with full workspace setup")
                        applyWorkspaceWindows(workspace, builtInScreen, builtInScreenFrame)
                    end
                end)
                return
            end
        end
    end
    
    -- Handle desktop switching if supported
    if workspace.spaceSupported and workspace.desktopIndex and hs.spaces then
        log("Workspace has desktop index: " .. tostring(workspace.desktopIndex))
        
        -- Get current desktop info
        local allSpaces = hs.spaces.allSpaces()
        local screenUUID = builtInScreen:getUUID()
        local screenSpaces = allSpaces[screenUUID] or {}
        
        log("Available desktops: " .. #screenSpaces .. ", target desktop: " .. tostring(workspace.desktopIndex))
        
        -- Check if the desktop index is valid
        if workspace.desktopIndex <= #screenSpaces then
            local targetSpaceID = screenSpaces[workspace.desktopIndex]
            
            -- Get current desktop index
            local currentSpace = hs.spaces.focusedSpace()
            local currentDesktopIndex = nil
            for index, spaceID in ipairs(screenSpaces) do
                if spaceID == currentSpace then
                    currentDesktopIndex = index
                    break
                end
            end
            
            log("Current desktop: " .. tostring(currentDesktopIndex) .. ", Target desktop: " .. tostring(workspace.desktopIndex))
            
            if currentDesktopIndex ~= workspace.desktopIndex then
                -- Switch to the target desktop
                log("Switching to desktop " .. workspace.desktopIndex .. " (space ID: " .. tostring(targetSpaceID) .. ")")
                log("🚀 CALLING hs.spaces.gotoSpace(" .. tostring(targetSpaceID) .. ") for full workspace setup")
                hs.spaces.gotoSpace(targetSpaceID)
                -- Wait longer for desktop switch to complete and ensure we're on the right desktop
                hs.timer.doAfter(1.5, function()
                    -- Double-check we're on the right desktop before proceeding
                    local currentSpace = hs.spaces.focusedSpace()
                    if currentSpace == targetSpaceID then
                        log("Confirmed on correct desktop, applying workspace")
                        applyWorkspaceWindows(workspace, builtInScreen, builtInScreenFrame)
                    else
                        log("Desktop switch failed, retrying...")
                        log("🚀 RETRY CALLING hs.spaces.gotoSpace(" .. tostring(targetSpaceID) .. ")")
                        hs.spaces.gotoSpace(targetSpaceID)
                        hs.timer.doAfter(1.0, function()
                            applyWorkspaceWindows(workspace, builtInScreen, builtInScreenFrame)
                        end)
                    end
                end)
            else
                log("Already on correct desktop")
                applyWorkspaceWindows(workspace, builtInScreen, builtInScreenFrame)
            end
            return
        else
            log("Desktop index " .. workspace.desktopIndex .. " no longer exists (only " .. #screenSpaces .. " desktops available)")
            -- Could create a new desktop here if needed, but for now just apply normally
        end
    end
    
    -- If spaces not supported or failed, apply normally
    applyWorkspaceWindows(workspace, builtInScreen, builtInScreenFrame)
end

-- Helper function to check if workspace is already correctly set up
isWorkspaceAlreadyActive = function(workspace, builtInScreen)
    log("=== CHECKING IF WORKSPACE IS ALREADY ACTIVE ===")
    
    if not workspace.spaceSupported or not workspace.desktopIndex or not hs.spaces then
        log("Space support not available")
        return false
    end
    
    -- Check if we're on the correct desktop
    local allSpaces = hs.spaces.allSpaces()
    local screenUUID = builtInScreen:getUUID()
    local screenSpaces = allSpaces[screenUUID] or {}
    
    log("Available desktops: " .. #screenSpaces .. ", target desktop: " .. workspace.desktopIndex)
    
    if workspace.desktopIndex > #screenSpaces then
        log("Target desktop doesn't exist")
        return false
    end
    
    -- Get the CURRENT space ID for the target desktop index (not the saved one)
    local targetSpaceID = screenSpaces[workspace.desktopIndex]
    local currentSpace = hs.spaces.focusedSpace()
    
    log("Desktop check: current space=" .. tostring(currentSpace) .. ", target space=" .. tostring(targetSpaceID) .. " (desktop " .. workspace.desktopIndex .. ")")
    
    if currentSpace ~= targetSpaceID then
        log("❌ Not on correct desktop")
        return false
    else
        log("✅ On correct desktop")
    end
    
    -- Quick check: if we're on the right desktop and have the right number of windows, assume it's correct
    local quickCheck = true
    local windowsByApp = {}
    for _, windowInfo in ipairs(workspace.windows) do
        if not windowsByApp[windowInfo.bundleID] then
            windowsByApp[windowInfo.bundleID] = 0
        end
        windowsByApp[windowInfo.bundleID] = windowsByApp[windowInfo.bundleID] + 1
    end
    
    for bundleID, expectedCount in pairs(windowsByApp) do
        local app = hs.application.get(bundleID)
        if not app then
            quickCheck = false
            break
        end
        
        local actualCount = 0
        local windowsOnCurrentDesktop = 0
        
        for _, window in ipairs(app:allWindows()) do
            if window:screen():id() == builtInScreen:id() and window:isVisible() and window:isStandard() then
                actualCount = actualCount + 1
                
                -- Check if window is on current desktop (we're already on target desktop)
                local windowSpaces = hs.spaces.windowSpaces(window)
                if windowSpaces and #windowSpaces > 0 then
                    for _, spaceID in ipairs(windowSpaces) do
                        if spaceID == currentSpace then
                            windowsOnCurrentDesktop = windowsOnCurrentDesktop + 1
                            break
                        end
                    end
                end
            end
        end
        
        log("Quick check - " .. bundleID .. ": expected=" .. expectedCount .. ", actual=" .. actualCount .. ", on current desktop=" .. windowsOnCurrentDesktop)
        
        -- For quick check, we want exact match on current desktop (which is the target)
        if windowsOnCurrentDesktop ~= expectedCount then
            quickCheck = false
            break
        end
    end
    
    if quickCheck then
        log("✅ Quick check passed - right desktop, right number of windows, assuming workspace is active")
        return true
    end
    
    log("Quick check failed, doing detailed position check...")
    
    -- Check if all required windows exist and are positioned correctly
    local tolerance = 50 -- 50 pixel tolerance for window position differences
    local builtInScreenFrame = builtInScreen:frame()
    
    log("Checking " .. #workspace.windows .. " windows for correct positioning...")
    
    -- Use a smarter approach for apps with multiple windows
    local windowsByApp = {}
    for _, windowInfo in ipairs(workspace.windows) do
        if not windowsByApp[windowInfo.bundleID] then
            windowsByApp[windowInfo.bundleID] = {}
        end
        table.insert(windowsByApp[windowInfo.bundleID], windowInfo)
    end
    
    for bundleID, expectedWindows in pairs(windowsByApp) do
        log("=== CHECKING APP: " .. bundleID .. " ===")
        local app = hs.application.get(bundleID)
        if not app then
            log("❌ App not running: " .. bundleID)
            return false
        end
        
        -- Get all actual windows for this app on the built-in screen
        local actualWindows = {}
        for _, window in ipairs(app:allWindows()) do
            if window:screen():id() == builtInScreen:id() and window:isVisible() and window:isStandard() then
                table.insert(actualWindows, window)
                log("Found window: " .. window:title() .. " (ID: " .. window:id() .. ")")
            end
        end
        
        log("Window count - Expected: " .. #expectedWindows .. ", Actual: " .. #actualWindows)
        
        if #actualWindows < #expectedWindows then
            log("❌ Not enough windows for " .. bundleID)
            return false
        end
        
        -- Try to match windows by position first, then by title
        local matchedWindows = {}
        for i, windowInfo in ipairs(expectedWindows) do
            local expectedFrame = {
                x = builtInScreenFrame.x + (windowInfo.frame.x * builtInScreenFrame.w),
                y = builtInScreenFrame.y + (windowInfo.frame.y * builtInScreenFrame.h),
                w = windowInfo.frame.w * builtInScreenFrame.w,
                h = windowInfo.frame.h * builtInScreenFrame.h
            }
            
            local bestMatch = nil
            local bestScore = math.huge
            
            for _, window in ipairs(actualWindows) do
                -- Skip if this window is already matched
                local alreadyMatched = false
                for _, matched in ipairs(matchedWindows) do
                    if matched:id() == window:id() then
                        alreadyMatched = true
                        break
                    end
                end
                
                if not alreadyMatched then
                    local currentFrame = window:frame()
                    local xDiff = math.abs(currentFrame.x - expectedFrame.x)
                    local yDiff = math.abs(currentFrame.y - expectedFrame.y)
                    local wDiff = math.abs(currentFrame.w - expectedFrame.w)
                    local hDiff = math.abs(currentFrame.h - expectedFrame.h)
                    
                    local totalDiff = xDiff + yDiff + wDiff + hDiff
                    
                    if totalDiff < bestScore and 
                       xDiff < tolerance and yDiff < tolerance and 
                       wDiff < tolerance and hDiff < tolerance then
                        bestMatch = window
                        bestScore = totalDiff
                    end
                end
            end
            
            if bestMatch then
                table.insert(matchedWindows, bestMatch)
                log("  ✅ Matched window " .. i .. ": " .. bestMatch:title() .. " (score: " .. bestScore .. "px)")
            else
                log("  ❌ Could not match window " .. i .. " (" .. windowInfo.title .. ") - no window within tolerance")
                return false
            end
        end
    end
    
    log("Workspace is already correctly set up!")
    return true
end

-- Helper function to move windows to the correct desktop
moveWorkspaceWindows = function(workspace, windowsByApp, builtInScreen, targetSpaceID)
    log("Moving windows to desktop " .. workspace.desktopIndex .. " (space ID: " .. tostring(targetSpaceID) .. ")")
    
    for bundleID, windowInfos in pairs(windowsByApp) do
        local app = hs.application.get(bundleID)
        if app then
            for _, window in ipairs(app:allWindows()) do
                if window:screen():id() == builtInScreen:id() then
                    -- Only try to move standard windows or Finder windows with titles
                    local shouldMoveWindow = window:isStandard() or 
                                           (app:bundleID() == "com.apple.finder" and window:title() ~= "")
                    
                    if shouldMoveWindow then
                        -- Move window to the workspace's desktop
                        local success = hs.spaces.moveWindowToSpace(window, targetSpaceID)
                        if success then
                            log("Moved window to desktop " .. workspace.desktopIndex .. ": " .. window:title())
                        else
                            log("Failed to move window to desktop: " .. window:title())
                        end
                    else
                        log("Skipping window move (non-standard): " .. window:title())
                    end
                end
            end
        end
    end
end

-- Helper function to apply workspace windows
applyWorkspaceWindows = function(workspace, builtInScreen, builtInScreenFrame)
    
    -- Hide all apps on built-in screen
    local apps = hs.application.runningApplications()
    for _, app in ipairs(apps) do
        if app:bundleID() ~= "com.apple.dock" then
            for _, window in ipairs(app:allWindows()) do
                if window:screen():id() == builtInScreen:id() then
                    app:hide()
                    break
                end
            end
        end
    end
    
    hs.timer.doAfter(0.5, function()
        -- Group windows by bundle ID to handle multiple instances
        local windowsByApp = {}
        for _, windowInfo in ipairs(workspace.windows) do
            if not windowsByApp[windowInfo.bundleID] then
                windowsByApp[windowInfo.bundleID] = {}
            end
            table.insert(windowsByApp[windowInfo.bundleID], windowInfo)
        end
        
        -- Process each application with staggered timing to avoid conflicts
        local appIndex = 0
        for bundleID, windowInfos in pairs(windowsByApp) do
            appIndex = appIndex + 1
            local delay = appIndex * 0.5 -- Stagger app processing
            
            hs.timer.doAfter(delay, function()
                log("Processing application: " .. bundleID .. " with " .. #windowInfos .. " windows")
                local app = hs.application.get(bundleID)
                if not app then
                    log("App not running, launching: " .. bundleID)
                    -- Try to launch by bundle ID first, then fall back to name
                    local success = hs.application.launchOrFocusByBundleID(bundleID)
                    if success then
                        -- Wait for app to launch
                        hs.timer.doAfter(2, function()
                            app = hs.application.get(bundleID)
                        end)
                    else
                        log("Failed to launch app with bundle ID: " .. bundleID)
                    end
                end
                
                if app then
                    log("Activating app: " .. app:name())
                    -- First unhide the app to ensure it's visible
                    app:unhide()
                    -- Then activate it
                    app:activate()
                    
                    hs.timer.doAfter(1, function()
                    local existingWindows = app:allWindows()
                    local requiredWindowCount = #windowInfos
                    
                    -- For Finder, count only standard windows for creation purposes
                    local standardWindowCount = 0
                    if app:bundleID() == "com.apple.finder" then
                        for _, window in ipairs(existingWindows) do
                            if window:isStandard() and window:title() ~= "" then
                                standardWindowCount = standardWindowCount + 1
                            end
                        end
                        log("App: " .. app:name() .. " - Required windows: " .. requiredWindowCount .. ", Standard windows: " .. standardWindowCount .. ", All windows: " .. #existingWindows)
                        currentWindowCount = standardWindowCount
                    else
                        currentWindowCount = #existingWindows
                        log("App: " .. app:name() .. " - Required windows: " .. requiredWindowCount .. ", Current windows: " .. currentWindowCount)
                    end
                    
                    -- Create additional windows if needed
                    if currentWindowCount < requiredWindowCount then
                        local windowsToCreate = requiredWindowCount - currentWindowCount
                        log("Need to create " .. windowsToCreate .. " additional windows for " .. app:name())
                        
                        -- Create windows sequentially and verify creation
                        local function createWindowAndVerify(windowIndex)
                            if windowIndex <= windowsToCreate then
                                log("Creating new window " .. windowIndex .. " for " .. app:name())
                                local allWindowsBefore = app:allWindows()
                                local windowCountBefore = #allWindowsBefore
                                
                                -- For Finder, also count standard windows before
                                local standardCountBefore = 0
                                if app:bundleID() == "com.apple.finder" then
                                    for _, window in ipairs(allWindowsBefore) do
                                        if window:isStandard() and window:title() ~= "" then
                                            standardCountBefore = standardCountBefore + 1
                                        end
                                    end
                                end
                                
                                -- Create the window
                                if app:bundleID() == "com.apple.finder" then
                                    -- Finder uses a different menu item
                                    if not app:selectMenuItem({"File", "New Finder Window"}) then
                                        hs.eventtap.keyStroke({"cmd"}, "n")
                                    end
                                else
                                    if not app:selectMenuItem({"File", "New Window"}) then
                                        if not app:selectMenuItem({"Window", "New Window"}) then
                                            hs.eventtap.keyStroke({"cmd"}, "n")
                                        end
                                    end
                                end
                                
                                -- Wait and verify window was created
                                hs.timer.doAfter(0.5, function()
                                    local allWindowsAfter = app:allWindows()
                                    local windowCountAfter = #allWindowsAfter
                                    
                                    -- For Finder, also count standard windows
                                    local standardCountAfter = 0
                                    if app:bundleID() == "com.apple.finder" then
                                        for _, window in ipairs(allWindowsAfter) do
                                            if window:isStandard() and window:title() ~= "" then
                                                standardCountAfter = standardCountAfter + 1
                                            end
                                        end
                                        log("Window creation " .. windowIndex .. ": before=" .. windowCountBefore .. ", after=" .. windowCountAfter .. " (standard before: " .. standardCountBefore .. ", standard after: " .. standardCountAfter .. ")")
                                    else
                                        log("Window creation " .. windowIndex .. ": before=" .. windowCountBefore .. ", after=" .. windowCountAfter)
                                    end
                                    
                                    -- Create next window
                                    createWindowAndVerify(windowIndex + 1)
                                end)
                            else
                                -- All windows created, now position them
                                log("All windows created, positioning...")
                                hs.timer.doAfter(1, function()
                                    positionAppWindows(app, windowInfos, builtInScreen, builtInScreenFrame)
                                end)
                            end
                        end
                        
                        -- Start creating windows
                        createWindowAndVerify(1)
                    else
                        -- Position existing windows immediately
                        positionAppWindows(app, windowInfos, builtInScreen, builtInScreenFrame)
                    end
                    end)
                end
            end)
        end
        
        -- Move windows to current desktop if desktop is specified (with increased delay)
        if workspace.spaceSupported and workspace.desktopIndex and hs.spaces then
            hs.timer.doAfter(4, function()
                local allSpaces = hs.spaces.allSpaces()
                local screenUUID = builtInScreen:getUUID()
                local screenSpaces = allSpaces[screenUUID] or {}
                
                if workspace.desktopIndex <= #screenSpaces then
                    local targetSpaceID = screenSpaces[workspace.desktopIndex]
                    
                    -- Verify we're still on the correct desktop before moving windows
                    local currentSpace = hs.spaces.focusedSpace()
                    if currentSpace ~= targetSpaceID then
                        log("Desktop switched unexpectedly, correcting...")
                        log("🚀 CORRECTION CALLING hs.spaces.gotoSpace(" .. tostring(targetSpaceID) .. ")")
                        hs.spaces.gotoSpace(targetSpaceID)
                        hs.timer.doAfter(0.5, function()
                            moveWorkspaceWindows(workspace, windowsByApp, builtInScreen, targetSpaceID)
                        end)
                    else
                        moveWorkspaceWindows(workspace, windowsByApp, builtInScreen, targetSpaceID)
                    end
                else
                    log("Cannot move windows: desktop " .. workspace.desktopIndex .. " no longer exists")
                end
            end)
        end
        
        -- Final pass to ensure all workspace windows are visible
        hs.timer.doAfter(5, function()
            log("Final pass: ensuring all workspace windows are visible")
            for bundleID, _ in pairs(windowsByApp) do
                local app = hs.application.get(bundleID)
                if app then
                    app:unhide()
                    for _, window in ipairs(app:allWindows()) do
                        if window:screen():id() == builtInScreen:id() then
                            window:unminimize()
                            window:raise()
                        end
                    end
                end
            end
        end)
    end)
end

-- Create workspace chooser
local function createChooser()
    local chooser = hs.chooser.new(function(choice)
        if choice then
            if choice.action == "apply" then
                applyWorkspace(choice.workspace)
                hs.alert.show("Applied workspace: " .. choice.workspace.name)
            elseif choice.action == "delete" then
                for i, workspace in ipairs(state.workspaces) do
                    if workspace.name == choice.workspace.name then
                        table.remove(state.workspaces, i)
                        saveWorkspacesToFile()
                        hs.alert.show("Deleted workspace: " .. choice.workspace.name)
                        break
                    end
                end
            end
        end
    end)
    
    chooser:bgDark(true)
    chooser:fgColor({red = 1, green = 1, blue = 1, alpha = 1})
    chooser:subTextColor({red = 0.7, green = 0.7, blue = 0.7, alpha = 1})
    
    return chooser
end

local function updateChooserChoices()
    if not state.chooser then
        return
    end
    
    local choices = {}
    
    -- Add "Save Current" option
    table.insert(choices, {
        text = "💾 Save Current Desktop",
        subText = "Save current window layout as new workspace",
        action = "save"
    })
    
    -- Add existing workspaces
    for _, workspace in ipairs(state.workspaces) do
        local windowCount = #workspace.windows
        local date = os.date("%Y-%m-%d %H:%M", workspace.created or os.time())
        local shortcutText = workspace.shortcutKey and (" • ⌘⌥⌃+" .. workspace.shortcutKey) or ""
        local desktopText = workspace.spaceSupported and workspace.desktopIndex and (" • 🖥️ Desktop " .. workspace.desktopIndex) or ""
        
        -- Apply option
        table.insert(choices, {
            text = "🖥️  " .. workspace.name,
            subText = windowCount .. " windows • " .. date .. shortcutText .. desktopText .. " • Press Enter to apply",
            workspace = workspace,
            action = "apply"
        })
        
        -- Delete option
        table.insert(choices, {
            text = "🗑️  Delete: " .. workspace.name,
            subText = "⚠️  This will permanently delete the workspace" .. shortcutText,
            workspace = workspace,
            action = "delete"
        })
        
        -- Update desktop option (if workspace has space support)
        if workspace.spaceSupported and hs.spaces then
            table.insert(choices, {
                text = "🔄 Update Desktop: " .. workspace.name,
                subText = "Reassign this workspace to the current desktop",
                workspace = workspace,
                action = "updateSpace"
            })
        end
    end
    
    state.chooser:choices(choices)
end

-- Public API
function simpleWorkspaces.show()
    loadWorkspacesFromFile()
    
    if not state.chooser then
        state.chooser = createChooser()
    end
    
    updateChooserChoices()
    state.chooser:show()
end

function simpleWorkspaces.hide()
    if state.chooser then
        state.chooser:hide()
    end
end

function simpleWorkspaces.toggle()
    if state.chooser and state.chooser:isVisible() then
        simpleWorkspaces.hide()
    else
        simpleWorkspaces.show()
    end
end

function simpleWorkspaces.saveCurrentDesktop(name, shortcutKey)
    local workspaceName = name or hs.dialog.textPrompt("Save Workspace", "Enter workspace name:", "", "Save", "Cancel")
    
    if not workspaceName or workspaceName == "" then
        log("Save cancelled: no workspace name provided")
        return
    end
    
    log("Saving workspace '" .. workspaceName .. "' with shortcut: '" .. tostring(shortcutKey) .. "'")
    
    local windows = getAllWindowInfo()
    
    -- Get current desktop index if hs.spaces is available
    local currentDesktopIndex = nil
    local spaceSupported = false
    if hs.spaces then
        spaceSupported = true
        local builtInScreen = getBuiltInScreen()
        local screenUUID = builtInScreen:getUUID()
        
        -- Get the focused space for this screen
        local focusedSpace = hs.spaces.focusedSpace()
        log("Focused space ID: " .. tostring(focusedSpace))
        
        -- Get all spaces for this screen to determine index
        local allSpaces = hs.spaces.allSpaces()
        local screenSpaces = allSpaces[screenUUID] or {}
        log("Screen spaces: " .. hs.inspect(screenSpaces))
        
        -- Find the index of the focused space (1-based)
        for index, spaceID in ipairs(screenSpaces) do
            if spaceID == focusedSpace then
                currentDesktopIndex = index
                break
            end
        end
        
        log("Current desktop index: " .. tostring(currentDesktopIndex))
    end
    
    local newWorkspace = {
        name = workspaceName,
        windows = windows,
        created = os.time(),
        shortcutKey = shortcutKey and shortcutKey ~= "" and shortcutKey or nil,
        desktopIndex = currentDesktopIndex,
        spaceSupported = spaceSupported
    }
    
    log("Workspace shortcut key after processing: '" .. tostring(newWorkspace.shortcutKey) .. "'")
    
    -- Always reload from file to ensure we have the latest data
    loadWorkspacesFromFile()
    log("Current workspaces count before adding: " .. #state.workspaces)
    table.insert(state.workspaces, newWorkspace)
    log("Current workspaces count after adding: " .. #state.workspaces)
    saveWorkspacesToFile()
    
    -- Bind shortcut key if provided and valid
    if newWorkspace.shortcutKey then
        log("Attempting to bind shortcut: " .. newWorkspace.shortcutKey)
        -- Skip conflict check since we've already handled it in the UI
        local success = simpleWorkspaces.bindWorkspaceShortcut(newWorkspace.shortcutKey, newWorkspace, true)
        if success then
            log("SUCCESS: Saved workspace '" .. workspaceName .. "' with shortcut: Cmd+Alt+Ctrl+" .. newWorkspace.shortcutKey)
            hs.alert.show("Workspace saved: " .. workspaceName .. " (⌘⌥⌃+" .. newWorkspace.shortcutKey .. ")")
        else
            log("FAILED: Shortcut binding failed for: " .. newWorkspace.shortcutKey)
            -- Remove invalid shortcut key from workspace
            newWorkspace.shortcutKey = nil
            -- Update the saved file
            for i, workspace in ipairs(state.workspaces) do
                if workspace.name == workspaceName then
                    state.workspaces[i] = newWorkspace
                    break
                end
            end
            saveWorkspacesToFile()
            log("Saved workspace: " .. workspaceName .. " (invalid shortcut key removed)")
            hs.alert.show("Workspace saved: " .. workspaceName .. " (invalid shortcut)")
        end
    else
        log("No shortcut key provided, saving workspace without shortcut")
        hs.alert.show("Workspace saved: " .. workspaceName)
    end
    
    return newWorkspace
end

-- Custom input dialog using chooser for auto-focus
local function createInputChooser(title, placeholder, callback)
    local inputChooser = hs.chooser.new(function(choice)
        if choice and choice.text then
            callback(choice.text)
        else
            callback(nil) -- User cancelled
        end
    end)
    
    inputChooser:placeholderText(placeholder)
    inputChooser:searchSubText(false)
    inputChooser:choices({})
    inputChooser:queryChangedCallback(function(query)
        if query and #query > 0 then
            inputChooser:choices({{text = query}})
        else
            inputChooser:choices({})
        end
    end)
    
    inputChooser:show()
    return inputChooser
end

-- Handle workspace name conflicts with confirmation
local function handleNameConflict(workspaceName, existingWorkspace, callback)
    local confirmChooser = hs.chooser.new(function(choice)
        if choice and choice.action then
            if choice.action == "override" then
                log("Override selected - removing existing workspace: " .. existingWorkspace.name)
                -- Remove existing workspace with same name
                loadWorkspacesFromFile() -- Ensure we have the latest data
                local removed = false
                for i = #state.workspaces, 1, -1 do -- Loop backwards to avoid index issues
                    local workspace = state.workspaces[i]
                    if workspace.name == existingWorkspace.name then
                        -- Unbind its shortcut if it has one
                        if workspace.shortcutKey then
                            simpleWorkspaces.unbindWorkspaceShortcut(workspace.shortcutKey)
                            log("Unbound shortcut: " .. workspace.shortcutKey)
                        end
                        table.remove(state.workspaces, i)
                        log("Successfully removed existing workspace: " .. workspace.name .. " at index " .. i)
                        removed = true
                        break
                    end
                end
                if not removed then
                    log("WARNING: Could not find workspace to remove: " .. existingWorkspace.name)
                end
                saveWorkspacesToFile()
                callback(true) -- Proceed with save
            elseif choice.action == "cancel" then
                log("Override cancelled by user")
                callback(false) -- Cancel save
            end
        else
            log("Override dialogue cancelled")
            callback(false) -- Cancel save
        end
    end)
    
    local shortcutText = existingWorkspace.shortcutKey and (" (⌘⌥⌃+" .. existingWorkspace.shortcutKey .. ")") or ""
    
    confirmChooser:choices({
        {
            text = "🔄 Replace Workspace",
            subText = "Replace existing workspace '" .. existingWorkspace.name .. "'" .. shortcutText .. " with new layout",
            action = "override"
        },
        {
            text = "❌ Cancel",
            subText = "Keep existing workspace unchanged",
            action = "cancel"
        }
    })
    
    confirmChooser:bgDark(true)
    confirmChooser:fgColor({red = 1, green = 1, blue = 1, alpha = 1})
    confirmChooser:subTextColor({red = 0.7, green = 0.7, blue = 0.7, alpha = 1})
    confirmChooser:show()
end

-- Handle shortcut conflicts with confirmation
local function handleShortcutConflict(workspaceName, shortcutKey, existingWorkspace, callback)
    local confirmChooser = hs.chooser.new(function(choice)
        if choice and choice.action then
            if choice.action == "replace" then
                log("User chose to replace entire workspace")
                -- Remove the entire existing workspace
                loadWorkspacesFromFile()
                for i = #state.workspaces, 1, -1 do
                    local workspace = state.workspaces[i]
                    if workspace.name == existingWorkspace.name then
                        -- Unbind its shortcut
                        if workspace.shortcutKey then
                            simpleWorkspaces.unbindWorkspaceShortcut(workspace.shortcutKey)
                        end
                        table.remove(state.workspaces, i)
                        log("Removed entire workspace: " .. workspace.name)
                        break
                    end
                end
                saveWorkspacesToFile()
                callback(true) -- Proceed with save
            elseif choice.action == "override" then
                log("User chose to only take the shortcut")
                -- Remove shortcut from existing workspace but keep the workspace
                loadWorkspacesFromFile()
                for _, workspace in ipairs(state.workspaces) do
                    if workspace.name == existingWorkspace.name then
                        workspace.shortcutKey = nil
                        log("Removed shortcut from workspace: " .. workspace.name)
                        break
                    end
                end
                simpleWorkspaces.unbindWorkspaceShortcut(shortcutKey)
                saveWorkspacesToFile()
                callback(true) -- Proceed with save
            elseif choice.action == "cancel" then
                log("User cancelled shortcut conflict resolution")
                callback(false) -- Cancel save
            end
        else
            callback(false) -- Cancel save
        end
    end)
    
    confirmChooser:choices({
        {
            text = "🔄 Replace Workspace",
            subText = "Delete '" .. existingWorkspace.name .. "' completely and create '" .. workspaceName .. "' with ⌘⌥⌃+" .. shortcutKey,
            action = "replace"
        },
        {
            text = "⚠️  Take Shortcut Only",
            subText = "Remove ⌘⌥⌃+" .. shortcutKey .. " from '" .. existingWorkspace.name .. "' (keep workspace) and assign to '" .. workspaceName .. "'",
            action = "override"
        },
        {
            text = "❌ Cancel",
            subText = "Keep existing shortcut assignment",
            action = "cancel"
        }
    })
    
    confirmChooser:bgDark(true)
    confirmChooser:fgColor({red = 1, green = 1, blue = 1, alpha = 1})
    confirmChooser:subTextColor({red = 0.7, green = 0.7, blue = 0.7, alpha = 1})
    confirmChooser:show()
end

-- Handle chooser selection for save action
local function handleSaveAction()
    -- Hide the main chooser first
    if state.chooser then
        state.chooser:hide()
    end
    
    -- Reload workspace data to ensure we have the latest information
    loadWorkspacesFromFile()
    
    -- Get workspace name using custom input
    createInputChooser("Save Workspace", "Enter workspace name...", function(workspaceName)
        if workspaceName and workspaceName ~= "" then
            log("Checking for name conflicts for: " .. workspaceName)
            -- Check for name conflicts first
            local existingWorkspaceWithName = findWorkspaceWithName(workspaceName)
            if existingWorkspaceWithName then
                log("Found existing workspace with name: " .. existingWorkspaceWithName.name)
                -- Show name conflict confirmation
                handleNameConflict(workspaceName, existingWorkspaceWithName, function(proceedWithName)
                    if proceedWithName then
                        log("User chose to proceed with name override")
                        -- Get shortcut key after name conflict is resolved
                        createInputChooser("Shortcut Key", "Enter shortcut key (optional): a-z, 0, 6-9", function(shortcutKey)
                            log("After name conflict resolution, shortcut key entered: '" .. tostring(shortcutKey) .. "'")
                            -- Check for shortcut conflicts
                            if shortcutKey and shortcutKey ~= "" then
                                log("Checking for shortcut conflicts for key: " .. shortcutKey)
                                local existingWorkspaceWithShortcut = findWorkspaceWithShortcut(shortcutKey)
                                if existingWorkspaceWithShortcut and existingWorkspaceWithShortcut.name ~= workspaceName then
                                    log("Found shortcut conflict with workspace: " .. existingWorkspaceWithShortcut.name)
                                    -- Show shortcut conflict confirmation
                                    handleShortcutConflict(workspaceName, shortcutKey, existingWorkspaceWithShortcut, function(proceedWithShortcut)
                                        if proceedWithShortcut then
                                            log("User chose to proceed with shortcut override")
                                            simpleWorkspaces.saveCurrentDesktop(workspaceName, shortcutKey)
                                        else
                                            log("User cancelled shortcut override")
                                        end
                                        
                                        -- Show the main chooser again
                                        if state.chooser then
                                            updateChooserChoices()
                                            state.chooser:show()
                                        end
                                    end)
                                    return
                                end
                            end
                            
                            -- No shortcut conflict, proceed with save
                            log("No shortcut conflict found, saving workspace with shortcut: '" .. tostring(shortcutKey) .. "'")
                            simpleWorkspaces.saveCurrentDesktop(workspaceName, shortcutKey)
                            
                            -- Show the main chooser again
                            if state.chooser then
                                updateChooserChoices()
                                state.chooser:show()
                            end
                        end)
                    else
                        -- Name conflict cancelled, show main chooser
                        if state.chooser then
                            state.chooser:show()
                        end
                    end
                end)
                return
            end
            
            -- No name conflict, get shortcut key
            createInputChooser("Shortcut Key", "Enter shortcut key (optional): a-z, 0, 6-9", function(shortcutKey)
                -- Check for shortcut conflicts
                if shortcutKey and shortcutKey ~= "" then
                    log("Checking for shortcut conflicts for key: " .. shortcutKey)
                    local existingWorkspaceWithShortcut = findWorkspaceWithShortcut(shortcutKey)
                    if existingWorkspaceWithShortcut and existingWorkspaceWithShortcut.name ~= workspaceName then
                        log("Found shortcut conflict with workspace: " .. existingWorkspaceWithShortcut.name)
                        -- Show shortcut conflict confirmation
                        handleShortcutConflict(workspaceName, shortcutKey, existingWorkspaceWithShortcut, function(proceed)
                            if proceed then
                                log("User chose to proceed with shortcut override")
                                simpleWorkspaces.saveCurrentDesktop(workspaceName, shortcutKey)
                            else
                                log("User cancelled shortcut override")
                            end
                            
                            -- Show the main chooser again
                            if state.chooser then
                                updateChooserChoices()
                                state.chooser:show()
                            end
                        end)
                        return
                    end
                end
                
                -- No conflict, proceed with save
                simpleWorkspaces.saveCurrentDesktop(workspaceName, shortcutKey)
                
                -- Show the main chooser again
                if state.chooser then
                    updateChooserChoices()
                    state.chooser:show()
                end
            end)
        else
            -- Show the main chooser again if cancelled
            if state.chooser then
                state.chooser:show()
            end
        end
    end)
end

-- Override chooser callback to handle save action
local function createChooserWithSave()
    local chooser = hs.chooser.new(function(choice)
        if choice then
            if choice.action == "save" then
                handleSaveAction()
            elseif choice.action == "apply" then
                applyWorkspace(choice.workspace)
                hs.alert.show("Applied workspace: " .. choice.workspace.name)
                if state.chooser then
                    state.chooser:hide()
                end
            elseif choice.action == "delete" then
                for i, workspace in ipairs(state.workspaces) do
                    if workspace.name == choice.workspace.name then
                        -- Unbind shortcut if it exists
                        if workspace.shortcutKey then
                            simpleWorkspaces.unbindWorkspaceShortcut(workspace.shortcutKey)
                        end
                        table.remove(state.workspaces, i)
                        saveWorkspacesToFile()
                        hs.alert.show("Deleted workspace: " .. choice.workspace.name)
                        updateChooserChoices()
                        break
                    end
                end
            elseif choice.action == "updateSpace" then
                -- Update workspace to use current desktop
                if hs.spaces then
                    local builtInScreen = getBuiltInScreen()
                    local screenUUID = builtInScreen:getUUID()
                    local focusedSpace = hs.spaces.focusedSpace()
                    local allSpaces = hs.spaces.allSpaces()
                    local screenSpaces = allSpaces[screenUUID] or {}
                    
                    -- Find current desktop index
                    local currentDesktopIndex = nil
                    for index, spaceID in ipairs(screenSpaces) do
                        if spaceID == focusedSpace then
                            currentDesktopIndex = index
                            break
                        end
                    end
                    
                    if currentDesktopIndex then
                        for i, workspace in ipairs(state.workspaces) do
                            if workspace.name == choice.workspace.name then
                                local oldDesktopIndex = state.workspaces[i].desktopIndex
                                state.workspaces[i].desktopIndex = currentDesktopIndex
                                -- Also clear old spaceID if it exists
                                state.workspaces[i].spaceID = nil
                                saveWorkspacesToFile()
                                log("Updated workspace '" .. workspace.name .. "' from desktop " .. tostring(oldDesktopIndex) .. " to desktop " .. tostring(currentDesktopIndex))
                                hs.alert.show("Updated workspace '" .. workspace.name .. "' to Desktop " .. currentDesktopIndex)
                                updateChooserChoices()
                                break
                            end
                        end
                    else
                        hs.alert.show("Could not determine current desktop")
                    end
                else
                    hs.alert.show("Spaces not available")
                end
            end
        end
    end)
    
    chooser:bgDark(true)
    chooser:fgColor({red = 1, green = 1, blue = 1, alpha = 1})
    chooser:subTextColor({red = 0.7, green = 0.7, blue = 0.7, alpha = 1})
    
    return chooser
end

-- Update the createChooser function
createChooser = createChooserWithSave

function simpleWorkspaces.showSaveDialog()
    -- Show save dialog directly without opening main chooser first
    handleSaveAction()
end

-- Shortcut management functions
function simpleWorkspaces.bindWorkspaceShortcut(key, workspace, skipConflictCheck)
    if not isValidShortcutKey(key) then
        log("Invalid shortcut key: " .. tostring(key))
        return false
    end
    
    -- Check for conflicts with built-in shortcuts
    local hasConflict, conflictReason = hasConflictingShortcut(key)
    if hasConflict then
        log("Cannot bind shortcut '" .. key .. "': " .. conflictReason)
        hs.alert.show("Shortcut ⌘⌥⌃+" .. key .. " " .. conflictReason)
        return false
    end
    
    -- Check for existing workspace shortcut conflicts (unless skipping)
    if not skipConflictCheck then
        local existingWorkspace = findWorkspaceWithShortcut(key)
        if existingWorkspace and existingWorkspace.name ~= workspace.name then
            log("Shortcut ⌘⌥⌃+" .. key .. " is already used by workspace: " .. existingWorkspace.name)
            return false, existingWorkspace
        end
    end
    
    -- Unbind existing shortcut if it exists
    if state.shortcuts[key] then
        state.shortcuts[key]:delete()
    end
    
    -- Bind new shortcut
    local success, hotkey = pcall(function()
        return hs.hotkey.bind({"cmd", "alt", "ctrl"}, key, function()
            applyWorkspace(workspace)
            hs.alert.show("Applied workspace: " .. workspace.name)
        end)
    end)
    
    if success then
        state.shortcuts[key] = hotkey
        log("Bound shortcut Cmd+Alt+Ctrl+" .. key .. " to workspace: " .. workspace.name)
        return true
    else
        log("Failed to bind shortcut: " .. key)
        return false
    end
end

function simpleWorkspaces.unbindWorkspaceShortcut(key)
    if state.shortcuts[key] then
        state.shortcuts[key]:delete()
        state.shortcuts[key] = nil
        log("Unbound shortcut: Cmd+Alt+Ctrl+" .. key)
    end
end

function simpleWorkspaces.bindAllWorkspaceShortcuts()
    -- Clear existing shortcuts
    for key, hotkey in pairs(state.shortcuts) do
        if hotkey and hotkey.delete then
            hotkey:delete()
        end
    end
    state.shortcuts = {}
    
    -- Bind shortcuts for all workspaces that have them
    for _, workspace in ipairs(state.workspaces) do
        if workspace.shortcutKey and isValidShortcutKey(workspace.shortcutKey) then
            simpleWorkspaces.bindWorkspaceShortcut(workspace.shortcutKey, workspace)
        end
    end
end

-- Clean up invalid shortcut keys and space IDs from saved workspaces
local function cleanupWorkspaces()
    local needsSave = false
    
    -- Clean up invalid shortcut keys
    for _, workspace in ipairs(state.workspaces) do
        if workspace.shortcutKey and not isValidShortcutKey(workspace.shortcutKey) then
            log("Removing invalid shortcut key '" .. workspace.shortcutKey .. "' from workspace: " .. workspace.name)
            workspace.shortcutKey = nil
            needsSave = true
        end
    end
    
    -- Clean up and migrate from spaceID to desktopIndex if hs.spaces is available
    if hs.spaces then
        local allSpaces = hs.spaces.allSpaces()
        local builtInScreen = getBuiltInScreen()
        local screenUUID = builtInScreen:getUUID()
        local screenSpaces = allSpaces[screenUUID] or {}
        
        log("Available desktops for cleanup: " .. #screenSpaces)
        
        for _, workspace in ipairs(state.workspaces) do
            -- Migrate from old spaceID system to desktopIndex
            if workspace.spaceSupported and workspace.spaceID and not workspace.desktopIndex then
                -- Try to find desktop index for the old spaceID
                for index, spaceID in ipairs(screenSpaces) do
                    if spaceID == workspace.spaceID then
                        workspace.desktopIndex = index
                        log("Migrated workspace '" .. workspace.name .. "' from spaceID " .. workspace.spaceID .. " to desktop " .. index)
                        needsSave = true
                        break
                    end
                end
                -- Remove old spaceID
                workspace.spaceID = nil
                needsSave = true
            end
            
            -- Validate desktop indices
            if workspace.spaceSupported and workspace.desktopIndex then
                if workspace.desktopIndex > #screenSpaces then
                    log("Removing invalid desktop index " .. tostring(workspace.desktopIndex) .. " from workspace: " .. workspace.name .. " (only " .. #screenSpaces .. " desktops available)")
                    workspace.desktopIndex = nil
                    needsSave = true
                end
            end
        end
    end
    
    if needsSave then
        saveWorkspacesToFile()
        log("Cleaned up invalid shortcut keys and migrated to desktop indices")
    end
end

-- Test function for debugging
function simpleWorkspaces.testValidation(key)
    log("=== Testing validation for key: " .. tostring(key) .. " ===")
    local validResult = isValidShortcutKey(key)
    log("Validation result: " .. tostring(validResult))
    
    if validResult then
        local conflictResult, reason = hasConflictingShortcut(key)
        log("Conflict result: " .. tostring(conflictResult))
        if reason then
            log("Conflict reason: " .. reason)
        end
    end
    
    log("=== Final result: " .. tostring(validResult and not hasConflictingShortcut(key)) .. " ===")
    return validResult
end

-- Get workspaces for help display
function simpleWorkspaces.getWorkspacesForHelp()
    loadWorkspacesFromFile()
    local workspaceInfo = {}
    for _, workspace in ipairs(state.workspaces) do
        if workspace.shortcutKey then
            table.insert(workspaceInfo, {
                name = workspace.name,
                shortcutKey = workspace.shortcutKey
            })
        end
    end
    return workspaceInfo
end

-- Desktop change monitoring
local function startSpaceWatcher()
    if hs.spaces then
        local builtInScreen = getBuiltInScreen()
        local screenUUID = builtInScreen:getUUID()
        
        -- Get initial space
        local currentSpace = hs.spaces.focusedSpace()
        local allSpaces = hs.spaces.allSpaces()
        local screenSpaces = allSpaces[screenUUID] or {}
        
        local currentDesktopIndex = nil
        for index, spaceID in ipairs(screenSpaces) do
            if spaceID == currentSpace then
                currentDesktopIndex = index
                break
            end
        end
        
        state.lastSpace = currentSpace
        log("🖥️ INITIAL DESKTOP: " .. tostring(currentDesktopIndex) .. " (Space ID: " .. tostring(currentSpace) .. ")")
        
        -- Watch for space changes
        state.spaceWatcher = hs.spaces.watcher.new(function()
            local newSpace = hs.spaces.focusedSpace()
            if newSpace ~= state.lastSpace then
                local newDesktopIndex = nil
                local updatedSpaces = hs.spaces.allSpaces()[screenUUID] or {}
                for index, spaceID in ipairs(updatedSpaces) do
                    if spaceID == newSpace then
                        newDesktopIndex = index
                        break
                    end
                end
                
                log("🔄 DESKTOP CHANGE: " .. tostring(currentDesktopIndex) .. " → " .. tostring(newDesktopIndex) .. " (Space: " .. tostring(state.lastSpace) .. " → " .. tostring(newSpace) .. ")")
                state.lastSpace = newSpace
                currentDesktopIndex = newDesktopIndex
            end
        end)
        
        state.spaceWatcher:start()
        log("Started desktop change monitoring")
    end
end

-- Initialize
loadWorkspacesFromFile()
cleanupWorkspaces()
simpleWorkspaces.bindAllWorkspaceShortcuts()
startSpaceWatcher()

return simpleWorkspaces