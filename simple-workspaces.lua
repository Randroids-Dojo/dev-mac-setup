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
    shortcuts = {} -- Track bound shortcuts
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
        if app:bundleID() ~= "com.apple.finder" and app:bundleID() ~= "com.apple.dock" then
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
            if window:screen():id() == builtInScreen:id() and window:isVisible() and window:isStandard() then
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
                end)
            else
                log("Warning: Could not find window " .. i .. " for positioning")
            end
        end
    end)
end

-- Apply workspace configuration
local function applyWorkspace(workspace)
    log("Applying workspace: " .. workspace.name)
    
    local builtInScreen = getBuiltInScreen()
    local builtInScreenFrame = builtInScreen:frame()
    
    -- Hide all apps on built-in screen
    local apps = hs.application.runningApplications()
    for _, app in ipairs(apps) do
        if app:bundleID() ~= "com.apple.finder" and app:bundleID() ~= "com.apple.dock" then
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
        
        -- Process each application
        for bundleID, windowInfos in pairs(windowsByApp) do
            local app = hs.application.get(bundleID)
            if not app then
                app = hs.application.launchOrFocus(bundleID)
            end
            
            if app then
                app:activate()
                
                hs.timer.doAfter(1, function()
                    local existingWindows = app:allWindows()
                    local requiredWindowCount = #windowInfos
                    local currentWindowCount = #existingWindows
                    
                    log("App: " .. app:name() .. " - Required windows: " .. requiredWindowCount .. ", Current windows: " .. currentWindowCount)
                    
                    -- Create additional windows if needed
                    if currentWindowCount < requiredWindowCount then
                        local windowsToCreate = requiredWindowCount - currentWindowCount
                        log("Need to create " .. windowsToCreate .. " additional windows for " .. app:name())
                        
                        for i = 1, windowsToCreate do
                            hs.timer.doAfter(i * 0.5, function()
                                log("Creating new window " .. i .. " for " .. app:name())
                                -- Try different methods to create new window
                                if not app:selectMenuItem({"File", "New Window"}) then
                                    if not app:selectMenuItem({"Window", "New Window"}) then
                                        hs.eventtap.keyStroke({"cmd"}, "n")
                                    end
                                end
                            end)
                        end
                        
                        -- Wait for windows to be created before positioning
                        hs.timer.doAfter((windowsToCreate * 0.5) + 1, function()
                            positionAppWindows(app, windowInfos, builtInScreen, builtInScreenFrame)
                        end)
                    else
                        -- Position existing windows immediately
                        positionAppWindows(app, windowInfos, builtInScreen, builtInScreenFrame)
                    end
                end)
            end
        end
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
        
        -- Apply option
        table.insert(choices, {
            text = "🖥️  " .. workspace.name,
            subText = windowCount .. " windows • " .. date .. shortcutText .. " • Press Enter to apply",
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

function simpleWorkspaces.showSaveDialog()
    -- Show save dialog directly without opening main chooser first
    handleSaveAction()
end

function simpleWorkspaces.saveCurrentDesktop(name, shortcutKey)
    local workspaceName = name or hs.dialog.textPrompt("Save Workspace", "Enter workspace name:", "", "Save", "Cancel")
    
    if not workspaceName or workspaceName == "" then
        log("Save cancelled: no workspace name provided")
        return
    end
    
    log("Saving workspace '" .. workspaceName .. "' with shortcut: '" .. tostring(shortcutKey) .. "'")
    
    local windows = getAllWindowInfo()
    
    local newWorkspace = {
        name = workspaceName,
        windows = windows,
        created = os.time(),
        shortcutKey = shortcutKey and shortcutKey ~= "" and shortcutKey or nil
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

-- Clean up invalid shortcut keys from saved workspaces
local function cleanupWorkspaces()
    local needsSave = false
    for _, workspace in ipairs(state.workspaces) do
        if workspace.shortcutKey and not isValidShortcutKey(workspace.shortcutKey) then
            log("Removing invalid shortcut key '" .. workspace.shortcutKey .. "' from workspace: " .. workspace.name)
            workspace.shortcutKey = nil
            needsSave = true
        end
    end
    
    if needsSave then
        saveWorkspacesToFile()
        log("Cleaned up invalid shortcut keys")
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

-- Initialize
loadWorkspacesFromFile()
cleanupWorkspaces()
simpleWorkspaces.bindAllWorkspaceShortcuts()

return simpleWorkspaces