--[[
=========================================================
  UNIVERSAL AUTOFARM v6.1 - CYBERPUNK RED GUI + ESSENCE LEAF
  Author: Kyriel (for ADIEL)
  Executor: Delta / Codex / Wave / Xeno

FITUR:
  - Autofarm LOCK (Scorpion, Tombguardian, Water Serpent)
  - ULTRA FAST Kill rate
  - Auto-next-target (seamless kill)
  - Anti-death (auto respawn)
  - Stealth Plant Collector (Ginseng, Spirit Grass, Essence Leaf)
  - AUTO CLAIM PLAYTIME REWARDS (dual path)
  - ANTI-AFK (CaptureController)
  - GUI CYBERPUNK RED
  - Script Created by ADIEL
=========================================================
]]

-- ============================================================
-- SERVICES
-- ============================================================
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
local humanoid = character:WaitForChild("Humanoid")

-- ============================================================
-- CONFIG
-- ============================================================
local CONFIG = {
    ATTACK_RANGE = 150,
    TELEPORT_HEIGHT = 10,
    LOCK_UPDATE_RATE = 0.05,
    ATTACK_COOLDOWN = 0.05,
    LOOP_DELAY = 0.1,
    AUTO_EQUIP_TOOL = true,
    USE_SKILLS = true,
    SKILL_KEYS = {"Z", "X", "C", "V", "F"},
    SKILL_COOLDOWN = 0.8,
    AUTO_RESPAWN = true,
    
    PLANT_NAMES = {
        "Ginseng",
        "Spirit Grass",
        "SpiritGrass",
        "Essence Leaf",
        "EssenceLeaf",
    },
    PLANT_SCAN_DELAY = 3,
    PLANT_MAX_DEPTH = 6,
    FORCE_PROMPT_DISTANCE = true,
    PLANT_TELEPORT_DELAY = 0.3,
    PLANT_AFTER_FIRE_DELAY = 0.5,
    
    NPC_WHITELIST = {
        "Scorpion",
        "Tombguardian",
        "Water Serpent",
        "WaterSerpent",
    },
    NPC_BLACKLIST = {},
    MAX_DEPTH = 4,
    LOG_LIMIT = 100,
    SCAN_INTERVAL = 10,
    DEBUG = false,
    
    CLAIM_INTERVAL = 15,
}

-- ============================================================
-- STATE
-- ============================================================
local isRunning = false
local isCollectingPlants = false
local currentTarget = nil
local lastSkillTime = 0
local cachedTool = nil
local lastFarmPosition = nil
local cachedNPCCount = 0
local logOrder = 0

local stats = {
    kills = 0,
    collectedPlants = 0,
    claimedRewards = 0,
    startTime = 0,
    lastKillTime = 0,
}

-- ============================================================
-- LOG SYSTEM
-- ============================================================
local LogScroll = nil
local ConsolePopup = nil

local function log(msg, color)
    if CONFIG.DEBUG then
        print("[Autofarm] " .. tostring(msg))
    end
    
    if not LogScroll or not LogScroll.Parent then return end
    
    logOrder = logOrder + 1
    local newLabel = Instance.new("TextLabel")
    newLabel.LayoutOrder = logOrder
    newLabel.Text = "[" .. os.date("%H:%M:%S") .. "] " .. tostring(msg)
    newLabel.Size = UDim2.new(1, -6, 0, 0)
    newLabel.AutomaticSize = Enum.AutomaticSize.Y
    newLabel.BackgroundTransparency = 1
    newLabel.TextColor3 = color or Color3.fromRGB(255, 90, 110)
    newLabel.Font = Enum.Font.Code
    newLabel.TextSize = 12
    newLabel.TextWrapped = true
    newLabel.TextXAlignment = Enum.TextXAlignment.Left
    newLabel.TextYAlignment = Enum.TextYAlignment.Top
    newLabel.ZIndex = 23
    newLabel.Parent = LogScroll
    
    task.defer(function()
        if LogScroll then
            LogScroll.CanvasPosition = Vector2.new(0, LogScroll.AbsoluteCanvasSize.Y)
        end
    end)
    
    local count = 0
    for _, child in ipairs(LogScroll:GetChildren()) do
        if child:IsA("TextLabel") then count = count + 1 end
    end
    if count > CONFIG.LOG_LIMIT then
        for _, child in ipairs(LogScroll:GetChildren()) do
            if child:IsA("TextLabel") then
                child:Destroy()
                break
            end
        end
    end
end

-- ============================================================
-- UTILITY
-- ============================================================
local function updateCharacterRefs()
    character = player.Character or player.CharacterAdded:Wait()
    humanoidRootPart = character:WaitForChild("HumanoidRootPart")
    humanoid = character:WaitForChild("Humanoid")
    cachedTool = nil
end

-- ============================================================
-- NPC FILTER
-- ============================================================
local function checkNPC(model)
    if not model or not model:IsA("Model") then return false end
    if Players:GetPlayerFromCharacter(model) then return false end
    
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    if hum.Health <= 0 then return false end
    if hum.MaxHealth <= 0 then return false end
    if hum.MaxHealth == math.huge or hum.MaxHealth > 1e9 then return false end
    
    if hum:GetAttribute("Invincible") == true then return false end
    if hum:GetAttribute("IsQuestGiver") == true then return false end
    if model:GetAttribute("Invincible") == true then return false end
    
    local nameLower = string.lower(model.Name)
    local isWhitelisted = false
    
    for _, target in ipairs(CONFIG.NPC_WHITELIST) do
        if string.find(nameLower, string.lower(target)) then
            isWhitelisted = true
            break
        end
    end
    
    if not isWhitelisted then return false end
    
    local root = model:FindFirstChild("HumanoidRootPart")
    if not root then
        root = model:FindFirstChild("Head") or model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso")
    end
    if not root then return false end
    
    return true
end

-- ============================================================
-- CARI SEMUA NPC
-- ============================================================
local function getAllNPCs()
    local npcs = {}
    
    local function scan(instance, depth)
        if depth > CONFIG.MAX_DEPTH then return end
        
        for _, obj in ipairs(instance:GetChildren()) do
            if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") then
                if checkNPC(obj) then
                    local hum = obj:FindFirstChildOfClass("Humanoid")
                    local root = obj:FindFirstChild("HumanoidRootPart") 
                        or obj:FindFirstChild("Head") 
                        or obj:FindFirstChild("Torso")
                        or obj:FindFirstChild("UpperTorso")
                    
                    if hum and root and hum.Health > 0 and humanoidRootPart then
                        local dist = (humanoidRootPart.Position - root.Position).Magnitude
                        table.insert(npcs, {
                            model = obj,
                            humanoid = hum,
                            root = root,
                            distance = dist
                        })
                    end
                end
            elseif obj:IsA("Folder") or (obj:IsA("Model") and #obj:GetChildren() > 0) then
                scan(obj, depth + 1)
            end
        end
    end
    
    scan(workspace, 0)
    table.sort(npcs, function(a, b) return a.distance < b.distance end)
    return npcs
end

-- ============================================================
-- LOCK / TELEPORT
-- ============================================================
local function lockToNPC(npc)
    if not npc or not npc.model or not npc.model.Parent then return end
    if not character or not character.Parent then return end
    if not humanoidRootPart or not humanoidRootPart.Parent then return end
    
    local headPart = npc.model:FindFirstChild("Head")
    local baseY = headPart and headPart.Position.Y or npc.root.Position.Y
    
    local topPos = Vector3.new(
        npc.root.Position.X,
        baseY + CONFIG.TELEPORT_HEIGHT,
        npc.root.Position.Z
    )
    
    pcall(function()
        humanoidRootPart.CFrame = CFrame.new(topPos)
        humanoidRootPart.Velocity = Vector3.new(0, 0, 0)
        humanoidRootPart.RotVelocity = Vector3.new(0, 0, 0)
    end)
end

local function teleportToNPC(npc)
    lockToNPC(npc)
    return true
end

-- ============================================================
-- ATTACK
-- ============================================================
local function attackNPC(npc)
    if not npc or not npc.model or not npc.model.Parent then return end
    if not npc.humanoid or npc.humanoid.Health <= 0 then return end
    if not character or not character.Parent then return end
    
    if CONFIG.AUTO_EQUIP_TOOL then
        local tool = character:FindFirstChildOfClass("Tool")
        if tool then
            cachedTool = tool
        elseif not cachedTool then
            for _, item in ipairs(player.Backpack:GetChildren()) do
                if item:IsA("Tool") then
                    item.Parent = character
                    cachedTool = item
                    break
                end
            end
        end
    end
    
    local tool = cachedTool or character:FindFirstChildOfClass("Tool")
    if tool then
        pcall(function() tool:Activate() end)
    end
    
    pcall(function()
        VirtualUser:Button1Down(Vector2.new(0, 0))
        VirtualUser:Button1Up(Vector2.new(0, 0))
    end)
    
    if CONFIG.USE_SKILLS and tool and (tick() - lastSkillTime > CONFIG.SKILL_COOLDOWN) then
        for _, key in ipairs(CONFIG.SKILL_KEYS) do
            pcall(function()
                VirtualUser:Button1Down(Vector2.new(0, 0))
                VirtualUser:Button1Up(Vector2.new(0, 0))
            end)
        end
        lastSkillTime = tick()
    end
end

-- ============================================================
-- AUTO RESPAWN
-- ============================================================
local function setupAntiDeath()
    if character then
        pcall(function()
            humanoid.Died:Connect(function()
                log("Mati! Auto respawn...", Color3.fromRGB(255, 100, 100))
                task.wait(3)
                
                if CONFIG.AUTO_RESPAWN then
                    pcall(function()
                        player:LoadCharacter()
                    end)
                    
                    task.wait(2)
                    updateCharacterRefs()
                    
                    if lastFarmPosition and humanoidRootPart then
                        pcall(function()
                            humanoidRootPart.CFrame = lastFarmPosition
                        end)
                    end
                    
                    log("Respawned!", Color3.fromRGB(0, 255, 100))
                end
            end)
        end)
    end
end

-- ============================================================
-- START / STOP AUTOFARM
-- ============================================================
local function startAutoFarm()
    if isRunning then return end
    isRunning = true
    stats.startTime = tick()
    
    log("AUTOFARM STARTED", Color3.fromRGB(0, 255, 100))
    
    setupAntiDeath()
    
    task.spawn(function()
        local emptyCount = 0
        
        while isRunning do
            if not character or not character.Parent then
                updateCharacterRefs()
                setupAntiDeath()
            end
            
            if humanoidRootPart and humanoidRootPart.Parent then
                lastFarmPosition = humanoidRootPart.CFrame
            end
            
            local npcs = getAllNPCs()
            
            if #npcs > 0 then
                emptyCount = 0
                currentTarget = npcs[1]
                
                lockToNPC(currentTarget)
                
                local targetKilled = false
                local killTimeout = tick() + 15
                
                while currentTarget and currentTarget.humanoid 
                    and currentTarget.humanoid.Health > 0 
                    and isRunning 
                    and tick() < killTimeout do
                    
                    lockToNPC(currentTarget)
                    attackNPC(currentTarget)
                    
                    if not currentTarget.model or not currentTarget.model.Parent then
                        targetKilled = true
                        break
                    end
                    
                    if currentTarget.humanoid.Health <= 0 then
                        targetKilled = true
                        break
                    end
                    
                    task.wait(CONFIG.LOCK_UPDATE_RATE)
                end
                
                if targetKilled then
                    stats.kills = stats.kills + 1
                    stats.lastKillTime = tick()
                end
            else
                emptyCount = emptyCount + 1
                if emptyCount % 20 == 0 then
                    log("Nunggu NPC spawn...", Color3.fromRGB(255, 200, 100))
                end
                task.wait(0.5)
            end
            
            task.wait(CONFIG.LOOP_DELAY)
        end
    end)
end

local function stopAutoFarm()
    isRunning = false
    currentTarget = nil
    cachedTool = nil
    log("Autofarm Stopped.", Color3.fromRGB(255, 100, 100))
end

-- ============================================================
-- PLANT COLLECTOR
-- ============================================================
local function isPlantName(name)
    local nameLower = string.lower(name)
    for _, plantName in ipairs(CONFIG.PLANT_NAMES) do
        if string.find(nameLower, string.lower(plantName)) then
            return true, plantName
        end
    end
    return false, ""
end

local function findAllPlants()
    local plants = {}
    
    local function scan(instance, depth)
        if depth > CONFIG.PLANT_MAX_DEPTH then return end
        
        for _, obj in ipairs(instance:GetChildren()) do
            local ok, plantType = isPlantName(obj.Name)
            if ok then
                local root = nil
                if obj:IsA("Model") then
                    root = obj.PrimaryPart 
                        or obj:FindFirstChild("HumanoidRootPart")
                        or obj:FindFirstChild("Head")
                        or obj:FindFirstChild("Handle")
                        or obj:FindFirstChild("Base")
                        or obj:FindFirstChildWhichIsA("BasePart", true)
                elseif obj:IsA("BasePart") then
                    root = obj
                end
                
                if root then
                    local prompt = obj:FindFirstChildWhichIsA("ProximityPrompt", true)
                    local cd = obj:FindFirstChildWhichIsA("ClickDetector", true)
                    
                    if prompt or cd then
                        table.insert(plants, {
                            obj = obj,
                            root = root,
                            name = plantType,
                            prompt = prompt,
                            clickDetector = cd
                        })
                    end
                end
            end
            
            if obj:IsA("Folder") or obj:IsA("Model") or obj:IsA("Workspace") then
                if #obj:GetChildren() > 0 then
                    scan(obj, depth + 1)
                end
            end
        end
    end
    
    scan(workspace, 0)
    return plants
end

local function collectAllPlantsStealth()
    local collected = 0
    local foundTypes = {}
    
    local originalCFrame = nil
    if humanoidRootPart and humanoidRootPart.Parent then
        originalCFrame = humanoidRootPart.CFrame
    end
    
    local plants = findAllPlants()
    
    if #plants == 0 then
        return 0, {}
    end
    
    log("Found " .. #plants .. " plants", Color3.fromRGB(150, 255, 100))
    
    for i, plant in ipairs(plants) do
        if not isCollectingPlants then break end
        if plant.root and plant.root.Parent then
            
            pcall(function()
                if humanoidRootPart and humanoidRootPart.Parent then
                    humanoidRootPart.CFrame = CFrame.new(plant.root.Position + Vector3.new(0, 3, 0))
                    humanoidRootPart.Velocity = Vector3.new(0, 0, 0)
                end
            end)
            
            task.wait(CONFIG.PLANT_TELEPORT_DELAY)
            
            local success = false
            
            if plant.prompt then
                pcall(function()
                    if CONFIG.FORCE_PROMPT_DISTANCE then
                        plant.prompt.MaxActivationDistance = math.huge
                        plant.prompt.HoldDuration = 0
                    end
                    fireproximityprompt(plant.prompt)
                    success = true
                end)
            end
            
            if not success and plant.clickDetector then
                pcall(function()
                    fireclickdetector(plant.clickDetector)
                    success = true
                end)
            end
            
            if success then
                collected = collected + 1
                foundTypes[plant.name] = (foundTypes[plant.name] or 0) + 1
            end
            
            task.wait(CONFIG.PLANT_AFTER_FIRE_DELAY)
        end
    end
    
    pcall(function()
        if originalCFrame and humanoidRootPart and humanoidRootPart.Parent then
            humanoidRootPart.CFrame = originalCFrame
            humanoidRootPart.Velocity = Vector3.new(0, 0, 0)
        end
    end)
    
    return collected, foundTypes
end

local function startPlantCollector()
    if isCollectingPlants then return end
    isCollectingPlants = true
    log("Plant Collector STARTED", Color3.fromRGB(150, 255, 100))
    
    task.spawn(function()
        while isCollectingPlants do
            local count, types = collectAllPlantsStealth()
            
            if count > 0 then
                stats.collectedPlants = stats.collectedPlants + count
                
                local typeStr = ""
                for t, c in pairs(types) do
                    typeStr = typeStr .. t .. "(" .. c .. ") "
                end
                log("Collected " .. count .. ": " .. typeStr, Color3.fromRGB(100, 255, 150))
            else
                log("No plants found", Color3.fromRGB(255, 200, 100))
            end
            
            task.wait(CONFIG.PLANT_SCAN_DELAY)
        end
    end)
end

local function stopPlantCollector()
    isCollectingPlants = false
    log("Plant Collector STOPPED", Color3.fromRGB(255, 150, 100))
end

-- ============================================================
-- CYBERPUNK GUI
-- ============================================================
local NEON = Color3.fromRGB(255, 30, 60)
local DARKRED = Color3.fromRGB(180, 20, 40)
local MILK = Color3.fromRGB(220, 220, 230)
local BG = Color3.fromRGB(10, 8, 15)
local PANEL = Color3.fromRGB(16, 12, 24)
local GRAYTXT = Color3.fromRGB(150, 150, 165)
local AMBER = Color3.fromRGB(255, 170, 40)
local PINK = Color3.fromRGB(255, 130, 170)
local YELLOW = Color3.fromRGB(255, 240, 60)
local ORANGE = Color3.fromRGB(255, 140, 0)

local function create(className, props, parent)
    local obj = Instance.new(className)
    for k, v in pairs(props) do
        obj[k] = v
    end
    if parent then
        obj.Parent = parent
    end
    return obj
end

local function lighten(c, a)
    return c:Lerp(Color3.new(1, 1, 1), a)
end

local function darken(c, a)
    return c:Lerp(Color3.new(0, 0, 0), a)
end

local function addCorner(obj, radius)
    return create("UICorner", {CornerRadius = UDim.new(0, radius)}, obj)
end

local function addStroke(obj, color, thickness, transparency)
    return create("UIStroke", {
        Color = color,
        Thickness = thickness,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, obj)
end

local function addTextGlow(label, color, transparency)
    return create("UIStroke", {
        Color = color,
        Thickness = 1,
        Transparency = transparency or 0.6,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
    }, label)
end

local function addGradient(obj, colorSeq, rotation)
    return create("UIGradient", {Color = colorSeq, Rotation = rotation or 0}, obj)
end

local function spaced(text)
    local out = {}
    for i = 1, #text do
        out[#out + 1] = text:sub(i, i)
    end
    return table.concat(out, " ")
end

local function animateGlow(stroke, minT, maxT, duration)
    stroke.Transparency = minT
    local info = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
    local tween = TweenService:Create(stroke, info, {Transparency = maxT})
    tween:Play()
    return tween
end

local function applyHover(btn, normalColor, hoverColor)
    btn:SetAttribute("NormalColor", normalColor)
    btn:SetAttribute("HoverColor", hoverColor)
    btn:SetAttribute("Hovered", false)
    btn.MouseEnter:Connect(function()
        btn:SetAttribute("Hovered", true)
        TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = hoverColor}):Play()
    end)
    btn.MouseLeave:Connect(function()
        btn:SetAttribute("Hovered", false)
        TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = normalColor}):Play()
    end)
end

local function applyPress(btn)
    local baseSize = btn.Size
    local basePos = btn.Position
    local info = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    
    btn.MouseButton1Down:Connect(function()
        local normal = btn:GetAttribute("NormalColor") or btn.BackgroundColor3
        TweenService:Create(btn, info, {
            Size = UDim2.new(baseSize.X.Scale, baseSize.X.Offset - 4, baseSize.Y.Scale, baseSize.Y.Offset - 4),
            Position = UDim2.new(basePos.X.Scale, basePos.X.Offset + 2, basePos.Y.Scale, basePos.Y.Offset + 2),
            BackgroundColor3 = darken(normal, 0.25),
        }):Play()
    end)
    
    local function release()
        local normal = btn:GetAttribute("NormalColor") or btn.BackgroundColor3
        local hover = btn:GetAttribute("HoverColor") or normal
        local target = btn:GetAttribute("Hovered") and hover or normal
        TweenService:Create(btn, info, {
            Size = baseSize,
            Position = basePos,
            BackgroundColor3 = target,
        }):Play()
    end
    
    btn.MouseButton1Up:Connect(release)
    btn.MouseLeave:Connect(release)
end

local function makeDraggable(frame, dragHandle)
    local dragging = false
    local dragStart = nil
    local startPos = nil
    
    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            frame:SetAttribute("WasDragged", false)
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            if delta.Magnitude > 4 then
                frame:SetAttribute("WasDragged", true)
            end
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

local BUTTON_STYLES = {
    primary = {bg = NEON, text = Color3.new(1, 1, 1), stroke = NEON, strokeT = 0.2, transp = 0, font = Enum.Font.GothamBold, gradient = true, pulse = true},
    outlineRed = {bg = DARKRED, text = NEON, stroke = NEON, strokeT = 0.3, transp = 0.85, font = Enum.Font.GothamBold},
    outlineWhite = {bg = MILK, text = MILK, stroke = MILK, strokeT = 0.4, transp = 0.9, font = Enum.Font.GothamBold},
    gray = {bg = Color3.fromRGB(34, 34, 44), text = Color3.fromRGB(200, 200, 210), stroke = Color3.fromRGB(70, 70, 85), strokeT = 0.2, transp = 0, font = Enum.Font.GothamBold},
    darkRed = {bg = Color3.fromRGB(90, 12, 26), text = MILK, stroke = DARKRED, strokeT = 0.3, transp = 0, font = Enum.Font.GothamBold},
}

local function makeButton(parent, text, position, size, styleName, textSize)
    local st = BUTTON_STYLES[styleName]
    local btn = create("TextButton", {
        Text = text,
        Position = position,
        Size = size,
        BackgroundColor3 = st.bg,
        BackgroundTransparency = st.transp,
        TextColor3 = st.text,
        Font = st.font,
        TextSize = textSize or 13,
        AutoButtonColor = false,
        BorderSizePixel = 0,
    }, parent)
    addCorner(btn, 8)
    local stroke = addStroke(btn, st.stroke, 2, st.strokeT)
    if st.gradient then
        addGradient(btn, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(165, 165, 165)), 45)
    end
    if st.pulse then
        animateGlow(stroke, 0.05, 0.65, 1.1)
    end
    applyHover(btn, st.bg, lighten(st.bg, 0.2))
    applyPress(btn)
    return btn
end

-- ScreenGui
local playerGui = player:WaitForChild("PlayerGui")
local oldGui = playerGui:FindFirstChild("CyberGameTool")
if oldGui then oldGui:Destroy() end
local oldGui2 = playerGui:FindFirstChild("AutofarmGUI")
if oldGui2 then oldGui2:Destroy() end

local ScreenGui = create("ScreenGui", {
    Name = "CyberGameTool",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 50,
}, playerGui)

-- MAIN FRAME
local MainFrame = create("Frame", {
    Name = "MainFrame",
    Size = UDim2.new(0, 760, 0, 320),
    Position = UDim2.new(0.5, -380, 0.5, -160),
    BackgroundColor3 = BG,
    BorderSizePixel = 0,
    ClipsDescendants = true,
}, ScreenGui)
addCorner(MainFrame, 10)
local mainStroke = addStroke(MainFrame, NEON, 2, 0.1)
animateGlow(mainStroke, 0.05, 0.6, 1.5)

-- Scanlines
local ScanContainer = create("Frame", {
    Name = "Scanlines",
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Active = false,
}, MainFrame)
for y = 20, 320, 20 do
    create("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.new(0, 0, 0, y),
        BackgroundColor3 = NEON,
        BackgroundTransparency = 0.85,
        BorderSizePixel = 0,
    }, ScanContainer)
end
local ScanSweep = create("Frame", {
    Size = UDim2.new(1, 0, 0, 3),
    Position = UDim2.new(0, 0, 0, 42),
    BackgroundColor3 = NEON,
    BackgroundTransparency = 0.88,
    BorderSizePixel = 0,
}, ScanContainer)
addGradient(ScanSweep, ColorSequence.new(DARKRED, NEON), 0)
TweenService:Create(
    ScanSweep,
    TweenInfo.new(3.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1, false),
    {Position = UDim2.new(0, 0, 0, 320)}
):Play()

-- TITLE BAR
local TitleBar = create("Frame", {
    Name = "TitleBar",
    Size = UDim2.new(1, 0, 0, 40),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
}, MainFrame)
addCorner(TitleBar, 10)
local titleSeq = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(90, 10, 25)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(215, 28, 55)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(90, 10, 25)),
})
addGradient(TitleBar, titleSeq, 0)

local TitleFill = create("Frame", {
    Size = UDim2.new(1, 0, 0, 10),
    Position = UDim2.new(0, 0, 1, -10),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
}, TitleBar)
addGradient(TitleFill, titleSeq, 0)

create("TextLabel", {
    Name = "TitleShadow",
    Text = "AUTOFARM v6.1 - by ADIEL",
    Position = UDim2.new(0, 16, 0, 5),
    Size = UDim2.new(1, -120, 0, 22),
    BackgroundTransparency = 1,
    TextColor3 = NEON,
    TextTransparency = 0.5,
    Font = Enum.Font.GothamBold,
    TextSize = 16,
    TextXAlignment = Enum.TextXAlignment.Left,
}, TitleBar)

local TitleText = create("TextLabel", {
    Name = "TitleText",
    Text = "AUTOFARM v6.1 - by ADIEL",
    Position = UDim2.new(0, 14, 0, 3),
    Size = UDim2.new(1, -120, 0, 22),
    BackgroundTransparency = 1,
    TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold,
    TextSize = 16,
    TextXAlignment = Enum.TextXAlignment.Left,
}, TitleBar)
addTextGlow(TitleText, NEON, 0.55)

local SubTitle = create("TextLabel", {
    Name = "SubTitle",
    Text = spaced("CYBER EDITION"),
    Position = UDim2.new(0, 14, 0, 25),
    Size = UDim2.new(1, -120, 0, 12),
    BackgroundTransparency = 1,
    TextColor3 = NEON,
    Font = Enum.Font.GothamBold,
    TextSize = 9,
    TextXAlignment = Enum.TextXAlignment.Left,
}, TitleBar)
create("UIStroke", {
    Color = Color3.fromRGB(20, 0, 5),
    Thickness = 1,
    Transparency = 0.3,
    ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
}, SubTitle)

local MinimizeBtn = create("TextButton", {
    Name = "MinimizeBtn",
    Text = "_",
    Position = UDim2.new(1, -72, 0, 8),
    Size = UDim2.new(0, 28, 0, 24),
    BackgroundColor3 = Color3.fromRGB(45, 45, 55),
    TextColor3 = MILK,
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    AutoButtonColor = false,
    BorderSizePixel = 0,
}, TitleBar)
addCorner(MinimizeBtn, 6)
addStroke(MinimizeBtn, Color3.fromRGB(90, 90, 105), 1, 0.2)
applyHover(MinimizeBtn, Color3.fromRGB(45, 45, 55), Color3.fromRGB(70, 70, 85))
applyPress(MinimizeBtn)

local CloseBtn = create("TextButton", {
    Name = "CloseBtn",
    Text = "X",
    Position = UDim2.new(1, -38, 0, 8),
    Size = UDim2.new(0, 28, 0, 24),
    BackgroundColor3 = NEON,
    TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    AutoButtonColor = false,
    BorderSizePixel = 0,
}, TitleBar)
addCorner(CloseBtn, 6)
local closeStroke = addStroke(CloseBtn, NEON, 2, 0.2)
animateGlow(closeStroke, 0.1, 0.7, 1.2)
applyHover(CloseBtn, NEON, lighten(NEON, 0.2))
applyPress(CloseBtn)

local TitleAccent = create("Frame", {
    Name = "TitleAccent",
    Size = UDim2.new(1, 0, 0, 2),
    Position = UDim2.new(0, 0, 0, 40),
    BackgroundColor3 = NEON,
    BorderSizePixel = 0,
}, MainFrame)
local accentStroke = create("UIStroke", {
    Color = NEON,
    Thickness = 2,
    Transparency = 0.2,
    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, TitleAccent)
animateGlow(accentStroke, 0.1, 0.8, 1.3)

task.spawn(function()
    while TitleText.Parent do
        TweenService:Create(TitleText, TweenInfo.new(0.08), {TextTransparency = 0.1}):Play()
        task.wait(0.08)
        TweenService:Create(TitleText, TweenInfo.new(0.08), {TextTransparency = 0}):Play()
        task.wait(1.84)
    end
end)

makeDraggable(MainFrame, TitleBar)

-- BODY
local Body = create("Frame", {
    Name = "Body",
    Position = UDim2.new(0, 0, 0, 42),
    Size = UDim2.new(1, 0, 1, -42),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
}, MainFrame)

local function makeColumn(name, x)
    local col = create("Frame", {
        Name = name,
        Position = UDim2.new(0, x, 0, 8),
        Size = UDim2.new(0, 240, 1, -16),
        BackgroundColor3 = PANEL,
        BackgroundTransparency = 0.25,
        BorderSizePixel = 0,
    }, Body)
    addCorner(col, 8)
    addStroke(col, DARKRED, 1, 0.5)
    return col
end

local function makeHeader(parent, text)
    local header = create("TextLabel", {
        Text = text,
        Position = UDim2.new(0, 10, 0, 8),
        Size = UDim2.new(1, -20, 0, 22),
        BackgroundTransparency = 1,
        TextColor3 = NEON,
        Font = Enum.Font.GothamBold,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, parent)
    addTextGlow(header, NEON, 0.6)
    local line = create("Frame", {
        Position = UDim2.new(0, 10, 0, 34),
        Size = UDim2.new(1, -20, 0, 2),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, parent)
    addGradient(line, ColorSequence.new(NEON, Color3.fromRGB(60, 8, 18)), 0)
    return header
end

local function makeStatLabel(parent, text, y, h, size, color, font, glow)
    local lbl = create("TextLabel", {
        Text = text,
        Position = UDim2.new(0, 10, 0, y),
        Size = UDim2.new(1, -20, 0, h),
        BackgroundTransparency = 1,
        TextColor3 = color,
        Font = font or Enum.Font.Gotham,
        TextSize = size,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, parent)
    if glow then
        addTextGlow(lbl, NEON, 0.5)
    end
    return lbl
end

local function makeInfoBlock(parent, text, y)
    local block = create("TextLabel", {
        Text = text,
        Position = UDim2.new(0, 10, 0, y),
        Size = UDim2.new(1, -20, 0, 52),
        BackgroundColor3 = Color3.fromRGB(50, 8, 18),
        BackgroundTransparency = 0.2,
        TextColor3 = MILK,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        BorderSizePixel = 0,
    }, parent)
    addCorner(block, 6)
    addStroke(block, NEON, 1, 0.5)
    create("UIPadding", {
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
    }, block)
    return block
end

-- KOLOM 1 - STATISTIK
local StatsCol = makeColumn("StatsColumn", 10)
makeHeader(StatsCol, "STATISTIK")

local KillsLabel = makeStatLabel(StatsCol, "Kills: 0", 42, 38, 28, Color3.new(1, 1, 1), Enum.Font.GothamBold, true)
local KPMLabel = makeStatLabel(StatsCol, "KPM: 0", 84, 20, 14, AMBER, Enum.Font.GothamBold)
local NPCCountLabel = makeStatLabel(StatsCol, "NPC Detected: 0", 106, 20, 14, Color3.fromRGB(190, 190, 200), Enum.Font.GothamBold)
local PlantCountLabel = makeStatLabel(StatsCol, "Plants: 0", 128, 20, 14, PINK, Enum.Font.GothamBold)
local RewardCountLabel = makeStatLabel(StatsCol, "Rewards: 0", 150, 20, 14, YELLOW, Enum.Font.GothamBold)

makeStatLabel(StatsCol, "HP", 174, 14, 11, GRAYTXT, Enum.Font.GothamBold)
local HPBarBack = create("Frame", {
    Name = "HPBarBack",
    Position = UDim2.new(0, 10, 0, 190),
    Size = UDim2.new(1, -20, 0, 12),
    BackgroundColor3 = Color3.fromRGB(22, 16, 30),
    BorderSizePixel = 0,
}, StatsCol)
addCorner(HPBarBack, 6)
addStroke(HPBarBack, DARKRED, 1, 0.4)
local HPBarFill = create("Frame", {
    Name = "HPBarFill",
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
}, HPBarBack)
addCorner(HPBarFill, 6)
addGradient(HPBarFill, ColorSequence.new(NEON, ORANGE), 0)

local StatusLabel = create("TextLabel", {
    Name = "StatusLabel",
    Text = "Farm: IDLE\nPlant: IDLE",
    Position = UDim2.new(0, 10, 0, 210),
    Size = UDim2.new(1, -20, 0, 40),
    BackgroundTransparency = 1,
    TextColor3 = GRAYTXT,
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
}, StatsCol)

-- KOLOM 2 - AUTOFARM
local FarmCol = makeColumn("FarmColumn", 260)
makeHeader(FarmCol, "AUTOFARM")

local btnSize = UDim2.new(1, -20, 0, 36)
local StartFarmBtn = makeButton(FarmCol, "START AUTOFARM", UDim2.new(0, 10, 0, 44), btnSize, "primary", 14)
local TeleportBtn = makeButton(FarmCol, "TELEPORT KE MOB", UDim2.new(0, 10, 0, 88), btnSize, "outlineRed", 13)
local ListNPCBtn = makeButton(FarmCol, "LIST NPC TARGET", UDim2.new(0, 10, 0, 132), btnSize, "outlineWhite", 13)
local RescanBtn = makeButton(FarmCol, "RESCAN NPC", UDim2.new(0, 10, 0, 176), btnSize, "gray", 13)
local ConsoleBtn = makeButton(FarmCol, "OPEN CONSOLE", UDim2.new(0, 10, 0, 220), btnSize, "darkRed", 13)

-- KOLOM 3 - PLANT COLLECTOR
local PlantCol = makeColumn("PlantColumn", 510)
makeHeader(PlantCol, "PLANT COLLECTOR")

local StartPlantBtn = makeButton(PlantCol, "START PLANT COLLECTOR", UDim2.new(0, 10, 0, 44), btnSize, "primary", 13)
local InstantCollectBtn = makeButton(PlantCol, "COLLECT SEKARANG", UDim2.new(0, 10, 0, 88), btnSize, "outlineRed", 13)
makeInfoBlock(PlantCol, "Plants: Ginseng, Spirit Grass, Essence Leaf", 136)
makeInfoBlock(PlantCol, "NPC: Scorpion, Tombguardian, Water Serpent", 196)

-- CONSOLE POPUP
ConsolePopup = create("Frame", {
    Name = "ConsolePopup",
    Size = UDim2.new(0, 360, 0, 280),
    Position = UDim2.new(0.5, -180, 0.5, -140),
    BackgroundColor3 = BG,
    BorderSizePixel = 0,
    Visible = false,
    ClipsDescendants = true,
    ZIndex = 20,
}, ScreenGui)
addCorner(ConsolePopup, 10)
local consoleStroke = addStroke(ConsolePopup, NEON, 2, 0.1)
animateGlow(consoleStroke, 0.05, 0.6, 1.5)

local ConsoleTitle = create("Frame", {
    Name = "ConsoleTitle",
    Size = UDim2.new(1, 0, 0, 30),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
    ZIndex = 21,
}, ConsolePopup)
addCorner(ConsoleTitle, 10)
addGradient(ConsoleTitle, titleSeq, 0)
local ConsoleTitleFill = create("Frame", {
    Size = UDim2.new(1, 0, 0, 10),
    Position = UDim2.new(0, 0, 1, -10),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
    ZIndex = 21,
}, ConsoleTitle)
addGradient(ConsoleTitleFill, titleSeq, 0)

local consoleText = create("TextLabel", {
    Text = "CONSOLE",
    Position = UDim2.new(0, 12, 0, 0),
    Size = UDim2.new(0, 120, 1, 0),
    BackgroundTransparency = 1,
    TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 22,
}, ConsoleTitle)
addTextGlow(consoleText, NEON, 0.5)

local ClearBtn = create("TextButton", {
    Name = "ClearBtn",
    Text = "CLEAR",
    Position = UDim2.new(1, -96, 0, 5),
    Size = UDim2.new(0, 54, 0, 20),
    BackgroundColor3 = DARKRED,
    BackgroundTransparency = 0.6,
    TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold,
    TextSize = 10,
    AutoButtonColor = false,
    BorderSizePixel = 0,
    ZIndex = 22,
}, ConsoleTitle)
addCorner(ClearBtn, 5)
addStroke(ClearBtn, NEON, 1, 0.2)
applyHover(ClearBtn, DARKRED, lighten(DARKRED, 0.2))
applyPress(ClearBtn)

local ConsoleCloseBtn = create("TextButton", {
    Name = "ConsoleCloseBtn",
    Text = "X",
    Position = UDim2.new(1, -34, 0, 5),
    Size = UDim2.new(0, 26, 0, 20),
    BackgroundColor3 = NEON,
    TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    AutoButtonColor = false,
    BorderSizePixel = 0,
    ZIndex = 22,
}, ConsoleTitle)
addCorner(ConsoleCloseBtn, 5)
addStroke(ConsoleCloseBtn, NEON, 1, 0.3)
applyHover(ConsoleCloseBtn, NEON, lighten(NEON, 0.2))
applyPress(ConsoleCloseBtn)

create("Frame", {
    Position = UDim2.new(0, 0, 0, 30),
    Size = UDim2.new(1, 0, 0, 2),
    BackgroundColor3 = NEON,
    BorderSizePixel = 0,
    ZIndex = 21,
}, ConsolePopup)

local LogContainer = create("Frame", {
    Name = "LogContainer",
    Position = UDim2.new(0, 8, 0, 40),
    Size = UDim2.new(1, -16, 1, -48),
    BackgroundColor3 = Color3.fromRGB(5, 4, 8),
    BorderSizePixel = 0,
    ZIndex = 21,
}, ConsolePopup)
addCorner(LogContainer, 6)
addStroke(LogContainer, DARKRED, 1, 0.4)

LogScroll = create("ScrollingFrame", {
    Name = "LogScroll",
    Position = UDim2.new(0, 4, 0, 4),
    Size = UDim2.new(1, -8, 1, -8),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = NEON,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ZIndex = 22,
}, LogContainer)
create("UIListLayout", {
    Padding = UDim.new(0, 2),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, LogScroll)

makeDraggable(ConsolePopup, ConsoleTitle)

-- FLOATING BUBBLE
local Bubble = create("TextButton", {
    Name = "Bubble",
    Text = "A",
    Size = UDim2.new(0, 50, 0, 50),
    Position = UDim2.new(0.5, -380, 0.5, -160),
    BackgroundColor3 = BG,
    TextColor3 = NEON,
    Font = Enum.Font.GothamBold,
    TextSize = 24,
    AutoButtonColor = false,
    BorderSizePixel = 0,
    Visible = false,
    ZIndex = 30,
}, ScreenGui)
addCorner(Bubble, 25)
addStroke(Bubble, MILK, 1, 0.3)

local BubbleGlow = create("Frame", {
    Name = "BubbleGlow",
    Position = UDim2.new(0, -4, 0, -4),
    Size = UDim2.new(1, 8, 1, 8),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Active = false,
    ZIndex = 29,
}, Bubble)
addCorner(BubbleGlow, 29)
local bubbleStroke = addStroke(BubbleGlow, NEON, 3, 0.1)
animateGlow(bubbleStroke, 0.05, 0.75, 1.0)

makeDraggable(Bubble, Bubble)

-- ============================================================
-- CALLBACK WIRING
-- ============================================================
StartFarmBtn.MouseButton1Click:Connect(function()
    if isRunning then
        stopAutoFarm()
        StartFarmBtn.Text = "START AUTOFARM"
        StartFarmBtn.BackgroundColor3 = NEON
        StartFarmBtn:SetAttribute("NormalColor", NEON)
        StartFarmBtn:SetAttribute("HoverColor", lighten(NEON, 0.2))
    else
        startAutoFarm()
        StartFarmBtn.Text = "STOP AUTOFARM"
        local dark = Color3.fromRGB(90, 12, 26)
        StartFarmBtn.BackgroundColor3 = dark
        StartFarmBtn:SetAttribute("NormalColor", dark)
        StartFarmBtn:SetAttribute("HoverColor", lighten(dark, 0.2))
    end
end)

TeleportBtn.MouseButton1Click:Connect(function()
    local npcs = getAllNPCs()
    if #npcs > 0 then
        teleportToNPC(npcs[1])
        TeleportBtn.Text = "OK: " .. npcs[1].model.Name
        task.wait(1)
        TeleportBtn.Text = "TELEPORT KE MOB"
    else
        TeleportBtn.Text = "NO NPC"
        task.wait(1)
        TeleportBtn.Text = "TELEPORT KE MOB"
    end
end)

ListNPCBtn.MouseButton1Click:Connect(function()
    local npcs = getAllNPCs()
    log("NPC List: " .. #npcs .. " found", Color3.fromRGB(0, 200, 255))
    for i, npc in ipairs(npcs) do
        log(string.format("%d. %s (HP: %d) [%.0f studs]",
            i, npc.model.Name, math.floor(npc.humanoid.Health), npc.distance))
    end
    ConsolePopup.Visible = true
end)

RescanBtn.MouseButton1Click:Connect(function()
    RescanBtn.Text = "SCANNING..."
    task.wait(0.1)
    local npcs = getAllNPCs()
    cachedNPCCount = #npcs
    NPCCountLabel.Text = "NPC Detected: " .. cachedNPCCount
    RescanBtn.Text = "RESCAN NPC"
end)

StartPlantBtn.MouseButton1Click:Connect(function()
    if isCollectingPlants then
        stopPlantCollector()
        StartPlantBtn.Text = "START PLANT COLLECTOR"
        StartPlantBtn.BackgroundColor3 = NEON
        StartPlantBtn:SetAttribute("NormalColor", NEON)
        StartPlantBtn:SetAttribute("HoverColor", lighten(NEON, 0.2))
    else
        startPlantCollector()
        StartPlantBtn.Text = "STOP PLANT COLLECTOR"
        local dark = Color3.fromRGB(90, 12, 26)
        StartPlantBtn.BackgroundColor3 = dark
        StartPlantBtn:SetAttribute("NormalColor", dark)
        StartPlantBtn:SetAttribute("HoverColor", lighten(dark, 0.2))
    end
end)

InstantCollectBtn.MouseButton1Click:Connect(function()
    InstantCollectBtn.Text = "COLLECTING..."
    local count, types = collectAllPlantsStealth()
    stats.collectedPlants = stats.collectedPlants + count
    InstantCollectBtn.Text = "+" .. count
    task.wait(1)
    InstantCollectBtn.Text = "COLLECT SEKARANG"
end)

-- Console toggle
ConsoleBtn.MouseButton1Click:Connect(function()
    ConsolePopup.Visible = not ConsolePopup.Visible
end)

ConsoleCloseBtn.MouseButton1Click:Connect(function()
    ConsolePopup.Visible = false
end)

ClearBtn.MouseButton1Click:Connect(function()
    for _, child in ipairs(LogScroll:GetChildren()) do
        if child:IsA("TextLabel") then
            child:Destroy()
        end
    end
    logOrder = 0
end)

-- Minimize
MinimizeBtn.MouseButton1Click:Connect(function()
    local info = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    if MainFrame.Size.Y.Offset > 50 then
        TweenService:Create(MainFrame, info, {Size = UDim2.new(0, 760, 0, 40)}):Play()
        MinimizeBtn.Text = "o"
    else
        TweenService:Create(MainFrame, info, {Size = UDim2.new(0, 760, 0, 320)}):Play()
        MinimizeBtn.Text = "_"
    end
end)

-- Close -> bubble
CloseBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = false
    Bubble.Position = MainFrame.Position
    Bubble.Visible = true
end)

Bubble.MouseButton1Click:Connect(function()
    if Bubble:GetAttribute("WasDragged") then
        return
    end
    MainFrame.Visible = true
    Bubble.Visible = false
end)

-- ============================================================
-- REAL-TIME STATS UPDATE
-- ============================================================
task.spawn(function()
    while task.wait(0.5) do
        if humanoid and humanoid.Parent then
            local ratio = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
            TweenService:Create(HPBarFill, TweenInfo.new(0.2), {Size = UDim2.new(ratio, 0, 1, 0)}):Play()
        end
        
        KillsLabel.Text = "Kills: " .. stats.kills
        PlantCountLabel.Text = "Plants: " .. stats.collectedPlants
        RewardCountLabel.Text = "Rewards: " .. stats.claimedRewards
        
        local kpm = 0
        if stats.startTime > 0 and isRunning then
            local elapsed = tick() - stats.startTime
            if elapsed > 5 then
                kpm = math.floor((stats.kills / elapsed) * 60)
            end
        end
        KPMLabel.Text = "KPM: " .. kpm
        
        StatusLabel.Text = "Farm: " .. (isRunning and "ACTIVE" or "IDLE")
            .. "\nPlant: " .. (isCollectingPlants and "ACTIVE" or "IDLE")
        StatusLabel.TextColor3 = (isRunning or isCollectingPlants) and NEON or GRAYTXT
    end
end)

task.spawn(function()
    while task.wait(CONFIG.SCAN_INTERVAL) do
        local npcs = getAllNPCs()
        cachedNPCCount = #npcs
        NPCCountLabel.Text = "NPC Detected: " .. cachedNPCCount
    end
end)

-- ============================================================
-- ANTI-AFK
-- ============================================================
player.Idled:Connect(function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end)

-- ============================================================
-- AUTO CLAIM PLAYTIME REWARDS (DUAL PATH)
-- ============================================================
local function pressButton(btn)
    for _, sig in ipairs({"MouseButton1Click", "Activated", "MouseButton1Down", "MouseButton1Up"}) do
        pcall(function()
            for _, c in ipairs(getconnections(btn[sig])) do
                c:Fire()
            end
        end)
    end
end

local function isClaimButton(obj)
    local nameLower = string.lower(obj.Name or "")
    local textLower = ""
    if obj:IsA("TextButton") then
        textLower = string.lower(obj.Text or "")
    end
    return string.find(nameLower, "claim") 
        or string.find(nameLower, "collect")
        or string.find(textLower, "claim")
        or string.find(textLower, "collect")
end

local function claimIn(obj)
    local claimed = 0
    if obj:IsA("GuiButton") then
        pressButton(obj)
        claimed = claimed + 1
    end
    for _, d in ipairs(obj:GetDescendants()) do
        if d:IsA("GuiButton") and isClaimButton(d) then
            pressButton(d)
            claimed = claimed + 1
        end
    end
    return claimed
end

task.spawn(function()
    while task.wait(CONFIG.CLAIM_INTERVAL) do
        pcall(function()
            local playerGuiRef = player:FindFirstChild("PlayerGui")
            if not playerGuiRef then return end
            local mainGui = playerGuiRef:FindFirstChild("Main")
            if not mainGui then return end
            local frames = mainGui:FindFirstChild("Frames")
            if not frames then return end
            
            local totalClaimed = 0
            
            -- Path 1: Events (Merits)
            pcall(function()
                local eventsFrame = frames:FindFirstChild("Events")
                if eventsFrame then
                    local container = eventsFrame:FindFirstChild("Container")
                    if container then
                        for _, folder in ipairs(container:GetChildren()) do
                            if string.find(folder.Name, "PlaytimeRewards") then
                                local claim = folder:FindFirstChild("Claim")
                                if claim then
                                    totalClaimed = totalClaimed + claimIn(claim)
                                end
                            end
                        end
                    end
                end
            end)
            
            -- Path 2: Shop (Time Reward)
            pcall(function()
                local shopFrame = frames:FindFirstChild("Shop")
                if shopFrame then
                    local playtimeRewards = shopFrame:FindFirstChild("PlaytimeRewards")
                    if playtimeRewards then
                        local shopContainer = playtimeRewards:FindFirstChild("Container")
                        if shopContainer then
                            for _, folder in ipairs(shopContainer:GetChildren()) do
                                if tonumber(folder.Name) then
                                    totalClaimed = totalClaimed + claimIn(folder)
                                end
                            end
                        end
                    end
                end
            end)
            
            if totalClaimed > 0 then
                stats.claimedRewards = stats.claimedRewards + totalClaimed
                log("Claimed " .. totalClaimed .. " reward button(s)", Color3.fromRGB(255, 220, 100))
            end
        end)
    end
end)

-- ============================================================
-- INITIAL SCAN
-- ============================================================
task.spawn(function()
    local npcs = getAllNPCs()
    cachedNPCCount = #npcs
    NPCCountLabel.Text = "NPC Detected: " .. cachedNPCCount
end)

-- ============================================================
-- DONE
-- ============================================================
print("=========================================")
print("  AUTOFARM v6.1 - ESSENCE LEAF EDITION")
print("  Script Created by ADIEL")
print("=========================================")
print("Target NPC: Scorpion, Tombguardian, Water Serpent")
print("Plant: Ginseng, Spirit Grass, Essence Leaf")
print("Reward Claim: Events + Shop PlaytimeRewards")
print("Anti-AFK: CaptureController")
