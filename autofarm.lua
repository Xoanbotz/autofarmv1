--[[
=========================================================
  UNIVERSAL AUTOFARM v5.4 - DUAL PATH CLAIM
  Author: Kyriel (for ADIEL)
  Executor: Delta / Codex / Wave / Xeno

FITUR:
  - Autofarm LOCK (Scorpion, Tombguardian, Water Serpent)
  - ULTRA FAST Kill rate
  - Auto-next-target (seamless kill)
  - Anti-death (auto respawn)
  - Stealth Plant Collector (Ginseng & Spirit Grass)
  - AUTO CLAIM PLAYTIME REWARDS (2 path: Events + Shop)
  - ANTI-AFK (CaptureController)
  - GUI HORIZONTAL + Dark + No Emoji
  - Script Created by ADIEL
=========================================================
]]

-- ============================================================
-- SERVICES
-- ============================================================
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")

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
    LOG_LIMIT = 30,
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
local logCount = 0

local function log(msg, color)
    if CONFIG.DEBUG then
        print("[Autofarm] " .. tostring(msg))
    end
    
    if not LogScroll or not LogScroll.Parent or not ConsolePopup or not ConsolePopup.Visible then
        return
    end
    
    local newLabel = Instance.new("TextLabel")
    newLabel.Size = UDim2.new(1, -6, 0, 0)
    newLabel.AutomaticSize = Enum.AutomaticSize.Y
    newLabel.BackgroundTransparency = 1
    newLabel.TextColor3 = color or Color3.fromRGB(150, 255, 150)
    newLabel.Text = "> " .. tostring(msg)
    newLabel.TextSize = 10
    newLabel.Font = Enum.Font.Code
    newLabel.TextXAlignment = Enum.TextXAlignment.Left
    newLabel.TextWrapped = true
    newLabel.Parent = LogScroll
    
    logCount = logCount + 1
    LogScroll.CanvasPosition = Vector2.new(0, LogScroll.AbsoluteCanvasSize.Y)
    
    if logCount > CONFIG.LOG_LIMIT then
        for _, child in ipairs(LogScroll:GetChildren()) do
            if child:IsA("TextLabel") then
                child:Destroy()
                logCount = logCount - 1
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
-- LOCK KE ATAS KEPALA NPC
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
                if PlantCountLabel then
                    PlantCountLabel.Text = "Plants: " .. stats.collectedPlants
                end
                
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
-- GUI
-- ============================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutofarmGUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = player:WaitForChild("PlayerGui")

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 720, 0, 300)
MainFrame.Position = UDim2.new(0.5, -360, 0.5, -150)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Visible = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(40, 40, 55)
MainStroke.Thickness = 1
MainStroke.Parent = MainFrame

-- TITLE BAR
local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 35)
TitleBar.BackgroundColor3 = Color3.fromRGB(22, 22, 32)
TitleBar.BorderSizePixel = 0
TitleBar.Active = true
TitleBar.Parent = MainFrame

local TitleBarCorner = Instance.new("UICorner")
TitleBarCorner.CornerRadius = UDim.new(0, 10)
TitleBarCorner.Parent = TitleBar

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -80, 1, 0)
Title.Position = UDim2.new(0, 12, 0, 0)
Title.BackgroundTransparency = 1
Title.TextColor3 = Color3.fromRGB(0, 220, 130)
Title.Text = "AUTOFARM v5.4 - Script Created by ADIEL"
Title.TextSize = 13
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TitleBar

local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 26, 0, 26)
MinBtn.Position = UDim2.new(1, -60, 0, 4)
MinBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
MinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
MinBtn.Text = "_"
MinBtn.TextSize = 14
MinBtn.Font = Enum.Font.GothamBold
MinBtn.Parent = TitleBar

local MinCorner = Instance.new("UICorner")
MinCorner.CornerRadius = UDim.new(0, 5)
MinCorner.Parent = MinBtn

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 26, 0, 26)
CloseBtn.Position = UDim2.new(1, -30, 0, 4)
CloseBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Text = "X"
CloseBtn.TextSize = 13
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.Parent = TitleBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 5)
CloseCorner.Parent = CloseBtn

-- COLUMN 1: STATS
local StatsFrame = Instance.new("Frame")
StatsFrame.Size = UDim2.new(0, 220, 1, -50)
StatsFrame.Position = UDim2.new(0, 12, 0, 42)
StatsFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
StatsFrame.BorderSizePixel = 0
StatsFrame.Parent = MainFrame

local StatsCorner = Instance.new("UICorner")
StatsCorner.CornerRadius = UDim.new(0, 8)
StatsCorner.Parent = StatsFrame

local StatsTitle = Instance.new("TextLabel")
StatsTitle.Size = UDim2.new(1, -16, 0, 20)
StatsTitle.Position = UDim2.new(0, 8, 0, 8)
StatsTitle.BackgroundTransparency = 1
StatsTitle.TextColor3 = Color3.fromRGB(0, 200, 255)
StatsTitle.Text = "STATISTIK"
StatsTitle.TextSize = 11
StatsTitle.Font = Enum.Font.GothamBold
StatsTitle.TextXAlignment = Enum.TextXAlignment.Left
StatsTitle.Parent = StatsFrame

local KillsLabel = Instance.new("TextLabel")
KillsLabel.Size = UDim2.new(1, -16, 0, 22)
KillsLabel.Position = UDim2.new(0, 8, 0, 32)
KillsLabel.BackgroundTransparency = 1
KillsLabel.TextColor3 = Color3.fromRGB(0, 220, 130)
KillsLabel.Text = "Kills: 0"
KillsLabel.TextSize = 13
KillsLabel.Font = Enum.Font.GothamBold
KillsLabel.TextXAlignment = Enum.TextXAlignment.Left
KillsLabel.Parent = StatsFrame

local KPM = Instance.new("TextLabel")
KPM.Size = UDim2.new(1, -16, 0, 20)
KPM.Position = UDim2.new(0, 8, 0, 56)
KPM.BackgroundTransparency = 1
KPM.TextColor3 = Color3.fromRGB(255, 180, 80)
KPM.Text = "KPM: 0"
KPM.TextSize = 12
KPM.Font = Enum.Font.GothamBold
KPM.TextXAlignment = Enum.TextXAlignment.Left
KPM.Parent = StatsFrame

local CountLabel = Instance.new("TextLabel")
CountLabel.Size = UDim2.new(1, -16, 0, 18)
CountLabel.Position = UDim2.new(0, 8, 0, 80)
CountLabel.BackgroundTransparency = 1
CountLabel.TextColor3 = Color3.fromRGB(140, 140, 180)
CountLabel.Text = "NPC Detected: 0"
CountLabel.TextSize = 11
CountLabel.Font = Enum.Font.Gotham
CountLabel.TextXAlignment = Enum.TextXAlignment.Left
CountLabel.Parent = StatsFrame

local PlantCountLabel = Instance.new("TextLabel")
PlantCountLabel.Size = UDim2.new(1, -16, 0, 18)
PlantCountLabel.Position = UDim2.new(0, 8, 0, 100)
PlantCountLabel.BackgroundTransparency = 1
PlantCountLabel.TextColor3 = Color3.fromRGB(140, 220, 140)
PlantCountLabel.Text = "Plants: 0"
PlantCountLabel.TextSize = 11
PlantCountLabel.Font = Enum.Font.Gotham
PlantCountLabel.TextXAlignment = Enum.TextXAlignment.Left
PlantCountLabel.Parent = StatsFrame

local RewardCountLabel = Instance.new("TextLabel")
RewardCountLabel.Size = UDim2.new(1, -16, 0, 18)
RewardCountLabel.Position = UDim2.new(0, 8, 0, 120)
RewardCountLabel.BackgroundTransparency = 1
RewardCountLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
RewardCountLabel.Text = "Rewards: 0"
RewardCountLabel.TextSize = 11
RewardCountLabel.Font = Enum.Font.Gotham
RewardCountLabel.TextXAlignment = Enum.TextXAlignment.Left
RewardCountLabel.Parent = StatsFrame

local HPText = Instance.new("TextLabel")
HPText.Size = UDim2.new(1, -16, 0, 16)
HPText.Position = UDim2.new(0, 8, 0, 148)
HPText.BackgroundTransparency = 1
HPText.TextColor3 = Color3.fromRGB(140, 140, 180)
HPText.Text = "HP"
HPText.TextSize = 11
HPText.Font = Enum.Font.Gotham
HPText.TextXAlignment = Enum.TextXAlignment.Left
HPText.Parent = StatsFrame

local HPBarBG = Instance.new("Frame")
HPBarBG.Size = UDim2.new(1, -16, 0, 10)
HPBarBG.Position = UDim2.new(0, 8, 0, 168)
HPBarBG.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
HPBarBG.BorderSizePixel = 0
HPBarBG.Parent = StatsFrame

local HPBarBG_Corner = Instance.new("UICorner")
HPBarBG_Corner.CornerRadius = UDim.new(1, 0)
HPBarBG_Corner.Parent = HPBarBG

local HPBarFill = Instance.new("Frame")
HPBarFill.Size = UDim2.new(1, 0, 1, 0)
HPBarFill.BackgroundColor3 = Color3.fromRGB(0, 220, 100)
HPBarFill.BorderSizePixel = 0
HPBarFill.Parent = HPBarBG

local HPBarFill_Corner = Instance.new("UICorner")
HPBarFill_Corner.CornerRadius = UDim.new(1, 0)
HPBarFill_Corner.Parent = HPBarFill

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -16, 0, 40)
StatusLabel.Position = UDim2.new(0, 8, 0, 195)
StatusLabel.BackgroundTransparency = 1
StatusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
StatusLabel.Text = "Farm: IDLE\nPlant: IDLE"
StatusLabel.TextSize = 10
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.TextYAlignment = Enum.TextYAlignment.Top
StatusLabel.TextWrapped = true
StatusLabel.Parent = StatsFrame

-- COLUMN 2: AUTOFARM
local FarmFrame = Instance.new("Frame")
FarmFrame.Size = UDim2.new(0, 220, 1, -50)
FarmFrame.Position = UDim2.new(0, 244, 0, 42)
FarmFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
FarmFrame.BorderSizePixel = 0
FarmFrame.Parent = MainFrame

local FarmCorner = Instance.new("UICorner")
FarmCorner.CornerRadius = UDim.new(0, 8)
FarmCorner.Parent = FarmFrame

local FarmTitle = Instance.new("TextLabel")
FarmTitle.Size = UDim2.new(1, -16, 0, 20)
FarmTitle.Position = UDim2.new(0, 8, 0, 8)
FarmTitle.BackgroundTransparency = 1
FarmTitle.TextColor3 = Color3.fromRGB(0, 200, 255)
FarmTitle.Text = "AUTOFARM"
FarmTitle.TextSize = 11
FarmTitle.Font = Enum.Font.GothamBold
FarmTitle.TextXAlignment = Enum.TextXAlignment.Left
FarmTitle.Parent = FarmFrame

local ToggleButton = Instance.new("TextButton")
ToggleButton.Size = UDim2.new(1, -16, 0, 40)
ToggleButton.Position = UDim2.new(0, 8, 0, 32)
ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 160, 0)
ToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleButton.Text = "START AUTOFARM"
ToggleButton.TextSize = 13
ToggleButton.Font = Enum.Font.GothamBold
ToggleButton.Parent = FarmFrame

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(0, 6)
ToggleCorner.Parent = ToggleButton

local TeleportBtn = Instance.new("TextButton")
TeleportBtn.Size = UDim2.new(1, -16, 0, 32)
TeleportBtn.Position = UDim2.new(0, 8, 0, 80)
TeleportBtn.BackgroundColor3 = Color3.fromRGB(0, 110, 180)
TeleportBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
TeleportBtn.Text = "TELEPORT KE MOB"
TeleportBtn.TextSize = 12
TeleportBtn.Font = Enum.Font.GothamBold
TeleportBtn.Parent = FarmFrame

local TeleCorner = Instance.new("UICorner")
TeleCorner.CornerRadius = UDim.new(0, 6)
TeleCorner.Parent = TeleportBtn

local ListBtn = Instance.new("TextButton")
ListBtn.Size = UDim2.new(1, -16, 0, 32)
ListBtn.Position = UDim2.new(0, 8, 0, 120)
ListBtn.BackgroundColor3 = Color3.fromRGB(90, 50, 120)
ListBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ListBtn.Text = "LIST NPC TARGET"
ListBtn.TextSize = 12
ListBtn.Font = Enum.Font.GothamBold
ListBtn.Parent = FarmFrame

local ListCorner = Instance.new("UICorner")
ListCorner.CornerRadius = UDim.new(0, 6)
ListCorner.Parent = ListBtn

local RescanBtn = Instance.new("TextButton")
RescanBtn.Size = UDim2.new(1, -16, 0, 32)
RescanBtn.Position = UDim2.new(0, 8, 0, 160)
RescanBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 70)
RescanBtn.TextColor3 = Color3.fromRGB(200, 200, 255)
RescanBtn.Text = "RESCAN NPC"
RescanBtn.TextSize = 12
RescanBtn.Font = Enum.Font.GothamBold
RescanBtn.Parent = FarmFrame

local RescanCorner = Instance.new("UICorner")
RescanCorner.CornerRadius = UDim.new(0, 6)
RescanCorner.Parent = RescanBtn

local ConsoleBtn = Instance.new("TextButton")
ConsoleBtn.Size = UDim2.new(1, -16, 0, 32)
ConsoleBtn.Position = UDim2.new(0, 8, 0, 200)
ConsoleBtn.BackgroundColor3 = Color3.fromRGB(35, 60, 35)
ConsoleBtn.TextColor3 = Color3.fromRGB(150, 220, 150)
ConsoleBtn.Text = "OPEN CONSOLE"
ConsoleBtn.TextSize = 12
ConsoleBtn.Font = Enum.Font.GothamBold
ConsoleBtn.Parent = FarmFrame

local ConsoleCorner = Instance.new("UICorner")
ConsoleCorner.CornerRadius = UDim.new(0, 6)
ConsoleCorner.Parent = ConsoleBtn

-- COLUMN 3: PLANT
local PlantFrame = Instance.new("Frame")
PlantFrame.Size = UDim2.new(0, 220, 1, -50)
PlantFrame.Position = UDim2.new(0, 476, 0, 42)
PlantFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
PlantFrame.BorderSizePixel = 0
PlantFrame.Parent = MainFrame

local PlantCorner = Instance.new("UICorner")
PlantCorner.CornerRadius = UDim.new(0, 8)
PlantCorner.Parent = PlantFrame

local PlantTitle = Instance.new("TextLabel")
PlantTitle.Size = UDim2.new(1, -16, 0, 20)
PlantTitle.Position = UDim2.new(0, 8, 0, 8)
PlantTitle.BackgroundTransparency = 1
PlantTitle.TextColor3 = Color3.fromRGB(150, 220, 100)
PlantTitle.Text = "PLANT COLLECTOR"
PlantTitle.TextSize = 11
PlantTitle.Font = Enum.Font.GothamBold
PlantTitle.TextXAlignment = Enum.TextXAlignment.Left
PlantTitle.Parent = PlantFrame

local PlantToggleBtn = Instance.new("TextButton")
PlantToggleBtn.Size = UDim2.new(1, -16, 0, 40)
PlantToggleBtn.Position = UDim2.new(0, 8, 0, 32)
PlantToggleBtn.BackgroundColor3 = Color3.fromRGB(0, 130, 70)
PlantToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
PlantToggleBtn.Text = "START PLANT COLLECTOR"
PlantToggleBtn.TextSize = 12
PlantToggleBtn.Font = Enum.Font.GothamBold
PlantToggleBtn.Parent = PlantFrame

local PlantToggleCorner = Instance.new("UICorner")
PlantToggleCorner.CornerRadius = UDim.new(0, 6)
PlantToggleCorner.Parent = PlantToggleBtn

local InstantCollectBtn = Instance.new("TextButton")
InstantCollectBtn.Size = UDim2.new(1, -16, 0, 32)
InstantCollectBtn.Position = UDim2.new(0, 8, 0, 80)
InstantCollectBtn.BackgroundColor3 = Color3.fromRGB(70, 160, 50)
InstantCollectBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
InstantCollectBtn.Text = "COLLECT SEKARANG"
InstantCollectBtn.TextSize = 12
InstantCollectBtn.Font = Enum.Font.GothamBold
InstantCollectBtn.Parent = PlantFrame

local InstCorner = Instance.new("UICorner")
InstCorner.CornerRadius = UDim.new(0, 6)
InstCorner.Parent = InstantCollectBtn

local PlantInfo = Instance.new("TextLabel")
PlantInfo.Size = UDim2.new(1, -16, 0, 80)
PlantInfo.Position = UDim2.new(0, 8, 0, 120)
PlantInfo.BackgroundTransparency = 1
PlantInfo.TextColor3 = Color3.fromRGB(140, 140, 180)
PlantInfo.Text = "Plants:\nGinseng\nSpirit Grass"
PlantInfo.TextSize = 11
PlantInfo.Font = Enum.Font.Gotham
PlantInfo.TextXAlignment = Enum.TextXAlignment.Left
PlantInfo.TextYAlignment = Enum.TextYAlignment.Top
PlantInfo.TextWrapped = true
PlantInfo.Parent = PlantFrame

local NPCInfo = Instance.new("TextLabel")
NPCInfo.Size = UDim2.new(1, -16, 0, 60)
NPCInfo.Position = UDim2.new(0, 8, 0, 200)
NPCInfo.BackgroundTransparency = 1
NPCInfo.TextColor3 = Color3.fromRGB(140, 140, 180)
NPCInfo.Text = "NPC:\nScorpion, Tombguardian,\nWater Serpent"
NPCInfo.TextSize = 10
NPCInfo.Font = Enum.Font.Gotham
NPCInfo.TextXAlignment = Enum.TextXAlignment.Left
NPCInfo.TextYAlignment = Enum.TextYAlignment.Top
NPCInfo.TextWrapped = true
NPCInfo.Parent = PlantFrame

-- CONSOLE POPUP
ConsolePopup = Instance.new("Frame")
ConsolePopup.Size = UDim2.new(0, 340, 0, 260)
ConsolePopup.Position = UDim2.new(0.5, -170, 0.5, -130)
ConsolePopup.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
ConsolePopup.BorderSizePixel = 0
ConsolePopup.Visible = false
ConsolePopup.ZIndex = 20
ConsolePopup.Active = true
ConsolePopup.Parent = ScreenGui

local ConsolePopupCorner = Instance.new("UICorner")
ConsolePopupCorner.CornerRadius = UDim.new(0, 10)
ConsolePopupCorner.Parent = ConsolePopup

local ConsoleTitle = Instance.new("Frame")
ConsoleTitle.Size = UDim2.new(1, 0, 0, 30)
ConsoleTitle.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
ConsoleTitle.BorderSizePixel = 0
ConsoleTitle.ZIndex = 21
ConsoleTitle.Active = true
ConsoleTitle.Parent = ConsolePopup

local ConsoleTitleCorner = Instance.new("UICorner")
ConsoleTitleCorner.CornerRadius = UDim.new(0, 10)
ConsoleTitleCorner.Parent = ConsoleTitle

local ConsoleTitleLabel = Instance.new("TextLabel")
ConsoleTitleLabel.Size = UDim2.new(1, -100, 1, 0)
ConsoleTitleLabel.Position = UDim2.new(0, 10, 0, 0)
ConsoleTitleLabel.BackgroundTransparency = 1
ConsoleTitleLabel.TextColor3 = Color3.fromRGB(0, 220, 130)
ConsoleTitleLabel.Text = "CONSOLE"
ConsoleTitleLabel.TextSize = 12
ConsoleTitleLabel.Font = Enum.Font.GothamBold
ConsoleTitleLabel.TextXAlignment = Enum.TextXAlignment.Left
ConsoleTitleLabel.ZIndex = 22
ConsoleTitleLabel.Parent = ConsoleTitle

local ClearBtn = Instance.new("TextButton")
ClearBtn.Size = UDim2.new(0, 50, 0, 22)
ClearBtn.Position = UDim2.new(1, -85, 0, 4)
ClearBtn.BackgroundColor3 = Color3.fromRGB(70, 45, 45)
ClearBtn.TextColor3 = Color3.fromRGB(255, 200, 200)
ClearBtn.Text = "CLEAR"
ClearBtn.TextSize = 10
ClearBtn.Font = Enum.Font.GothamBold
ClearBtn.ZIndex = 22
ClearBtn.Parent = ConsoleTitle

local ClearCorner = Instance.new("UICorner")
ClearCorner.CornerRadius = UDim.new(0, 4)
ClearCorner.Parent = ClearBtn

local ConsoleClose = Instance.new("TextButton")
ConsoleClose.Size = UDim2.new(0, 25, 0, 22)
ConsoleClose.Position = UDim2.new(1, -28, 0, 4)
ConsoleClose.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
ConsoleClose.TextColor3 = Color3.fromRGB(255, 255, 255)
ConsoleClose.Text = "X"
ConsoleClose.TextSize = 12
ConsoleClose.Font = Enum.Font.GothamBold
ConsoleClose.ZIndex = 22
ConsoleClose.Parent = ConsoleTitle

local ConsoleCloseCorner = Instance.new("UICorner")
ConsoleCloseCorner.CornerRadius = UDim.new(0, 4)
ConsoleCloseCorner.Parent = ConsoleClose

LogScroll = Instance.new("ScrollingFrame")
LogScroll.Size = UDim2.new(1, -10, 1, -40)
LogScroll.Position = UDim2.new(0, 5, 0, 35)
LogScroll.BackgroundTransparency = 1
LogScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
LogScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
LogScroll.ScrollBarThickness = 4
LogScroll.ZIndex = 21
LogScroll.Parent = ConsolePopup

local LogList = Instance.new("UIListLayout")
LogList.Padding = UDim.new(0, 2)
LogList.Parent = LogScroll

-- NPC LIST POPUP
local ListPopup = Instance.new("Frame")
ListPopup.Size = UDim2.new(0, 280, 0, 280)
ListPopup.Position = UDim2.new(0.5, -140, 0.5, -140)
ListPopup.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
ListPopup.BorderSizePixel = 0
ListPopup.Visible = false
ListPopup.ZIndex = 20
ListPopup.Active = true
ListPopup.Parent = ScreenGui

local ListPopupCorner = Instance.new("UICorner")
ListPopupCorner.CornerRadius = UDim.new(0, 10)
ListPopupCorner.Parent = ListPopup

local ListTitle = Instance.new("Frame")
ListTitle.Size = UDim2.new(1, 0, 0, 30)
ListTitle.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
ListTitle.BorderSizePixel = 0
ListTitle.ZIndex = 21
ListTitle.Active = true
ListTitle.Parent = ListPopup

local ListTitleCorner = Instance.new("UICorner")
ListTitleCorner.CornerRadius = UDim.new(0, 10)
ListTitleCorner.Parent = ListTitle

local ListTitleLabel = Instance.new("TextLabel")
ListTitleLabel.Size = UDim2.new(1, -40, 1, 0)
ListTitleLabel.Position = UDim2.new(0, 10, 0, 0)
ListTitleLabel.BackgroundTransparency = 1
ListTitleLabel.TextColor3 = Color3.fromRGB(0, 220, 130)
ListTitleLabel.Text = "NPC TARGET - TAP TO TELEPORT"
ListTitleLabel.TextSize = 11
ListTitleLabel.Font = Enum.Font.GothamBold
ListTitleLabel.TextXAlignment = Enum.TextXAlignment.Left
ListTitleLabel.ZIndex = 22
ListTitleLabel.Parent = ListTitle

local ListClose = Instance.new("TextButton")
ListClose.Size = UDim2.new(0, 25, 0, 22)
ListClose.Position = UDim2.new(1, -28, 0, 4)
ListClose.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
ListClose.TextColor3 = Color3.fromRGB(255, 255, 255)
ListClose.Text = "X"
ListClose.TextSize = 12
ListClose.Font = Enum.Font.GothamBold
ListClose.ZIndex = 22
ListClose.Parent = ListTitle

local ListCloseCorner = Instance.new("UICorner")
ListCloseCorner.CornerRadius = UDim.new(0, 4)
ListCloseCorner.Parent = ListClose

local ListScroll = Instance.new("ScrollingFrame")
ListScroll.Size = UDim2.new(1, -10, 1, -40)
ListScroll.Position = UDim2.new(0, 5, 0, 35)
ListScroll.BackgroundTransparency = 1
ListScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
ListScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
ListScroll.ScrollBarThickness = 4
ListScroll.ZIndex = 21
ListScroll.Parent = ListPopup

local ListLayout = Instance.new("UIListLayout")
ListLayout.Padding = UDim.new(0, 3)
ListLayout.Parent = ListScroll

local function refreshNPCList()
    for _, child in ipairs(ListScroll:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end
    
    local npcs = getAllNPCs()
    
    if #npcs == 0 then
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -6, 0, 20)
        lbl.BackgroundTransparency = 1
        lbl.TextColor3 = Color3.fromRGB(255, 150, 150)
        lbl.Text = "No NPC target found"
        lbl.TextSize = 11
        lbl.Font = Enum.Font.Gotham
        lbl.Parent = ListScroll
        return
    end
    
    for i, npc in ipairs(npcs) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -6, 0, 28)
        btn.BackgroundColor3 = Color3.fromRGB(35, 50, 70)
        btn.TextColor3 = Color3.fromRGB(150, 220, 200)
        btn.Text = string.format("%d. %s (HP: %d)", i, npc.model.Name, math.floor(npc.humanoid.Health))
        btn.TextSize = 11
        btn.Font = Enum.Font.Code
        btn.ZIndex = 22
        btn.Parent = ListScroll
        
        local bc = Instance.new("UICorner")
        bc.CornerRadius = UDim.new(0, 4)
        bc.Parent = btn
        
        btn.MouseButton1Click:Connect(function()
            if npc.model and npc.model.Parent then
                teleportToNPC(npc)
                log("Teleport ke: " .. npc.model.Name, Color3.fromRGB(0, 200, 255))
                ListPopup.Visible = false
            end
        end)
    end
end

-- FLOATING BUBBLE
local Bubble = Instance.new("TextButton")
Bubble.Name = "FloatingBubble"
Bubble.Size = UDim2.new(0, 50, 0, 50)
Bubble.Position = UDim2.new(0, 20, 0, 100)
Bubble.BackgroundColor3 = Color3.fromRGB(0, 160, 90)
Bubble.TextColor3 = Color3.fromRGB(255, 255, 255)
Bubble.Text = "A"
Bubble.TextSize = 20
Bubble.Font = Enum.Font.GothamBold
Bubble.Visible = false
Bubble.Active = true
Bubble.Parent = ScreenGui

local BubbleCorner = Instance.new("UICorner")
BubbleCorner.CornerRadius = UDim.new(1, 0)
BubbleCorner.Parent = Bubble

local BubbleStroke = Instance.new("UIStroke")
BubbleStroke.Color = Color3.fromRGB(0, 220, 130)
BubbleStroke.Thickness = 2
BubbleStroke.Parent = Bubble

-- DRAGGABLE
local function makeDraggable(frame, dragHandle)
    dragHandle = dragHandle or frame
    
    local dragging = false
    local dragStart = nil
    local startPos = nil
    
    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            
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
            frame.Position = UDim2.new(
                startPos.X.Scale, 
                startPos.X.Offset + delta.X,
                startPos.Y.Scale, 
                startPos.Y.Offset + delta.Y
            )
        end
    end)
end

makeDraggable(MainFrame, TitleBar)
makeDraggable(Bubble, Bubble)
makeDraggable(ConsolePopup, ConsoleTitle)
makeDraggable(ListPopup, ListTitle)

-- REAL-TIME STATS UPDATE
task.spawn(function()
    while task.wait(0.5) do
        if humanoid and humanoid.Parent then
            local hpPct = humanoid.Health / humanoid.MaxHealth
            HPBarFill.Size = UDim2.new(math.max(0, hpPct), 0, 1, 0)
            
            if hpPct < 0.3 then
                HPBarFill.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
            elseif hpPct < 0.6 then
                HPBarFill.BackgroundColor3 = Color3.fromRGB(220, 180, 60)
            else
                HPBarFill.BackgroundColor3 = Color3.fromRGB(0, 220, 100)
            end
        end
        
        KillsLabel.Text = "Kills: " .. stats.kills
        PlantCountLabel.Text = "Plants: " .. stats.collectedPlants
        RewardCountLabel.Text = "Rewards: " .. stats.claimedRewards
        
        if stats.startTime > 0 and isRunning then
            local elapsed = tick() - stats.startTime
            if elapsed > 5 then
                local kpm = math.floor((stats.kills / elapsed) * 60)
                KPM.Text = "KPM: " .. kpm
            end
        else
            KPM.Text = "KPM: 0"
        end
    end
end)

task.spawn(function()
    while task.wait(CONFIG.SCAN_INTERVAL) do
        local npcs = getAllNPCs()
        CountLabel.Text = "NPC Detected: " .. #npcs
    end
end)

-- EVENT HANDLERS
ToggleButton.MouseButton1Click:Connect(function()
    if isRunning then
        stopAutoFarm()
        ToggleButton.Text = "START AUTOFARM"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 160, 0)
        StatusLabel.Text = "Farm: IDLE\nPlant: " .. (isCollectingPlants and "RUNNING" or "IDLE")
        StatusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
    else
        startAutoFarm()
        ToggleButton.Text = "STOP AUTOFARM"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(160, 0, 0)
        StatusLabel.Text = "Farm: RUNNING\nPlant: " .. (isCollectingPlants and "RUNNING" or "IDLE")
        StatusLabel.TextColor3 = Color3.fromRGB(0, 220, 100)
    end
end)

PlantToggleBtn.MouseButton1Click:Connect(function()
    if isCollectingPlants then
        stopPlantCollector()
        PlantToggleBtn.Text = "START PLANT COLLECTOR"
        PlantToggleBtn.BackgroundColor3 = Color3.fromRGB(0, 130, 70)
        StatusLabel.Text = "Farm: " .. (isRunning and "RUNNING" or "IDLE") .. "\nPlant: IDLE"
    else
        startPlantCollector()
        PlantToggleBtn.Text = "STOP PLANT COLLECTOR"
        PlantToggleBtn.BackgroundColor3 = Color3.fromRGB(130, 60, 0)
        StatusLabel.Text = "Farm: " .. (isRunning and "RUNNING" or "IDLE") .. "\nPlant: RUNNING"
    end
end)

InstantCollectBtn.MouseButton1Click:Connect(function()
    InstantCollectBtn.Text = "COLLECTING..."
    InstantCollectBtn.BackgroundColor3 = Color3.fromRGB(50, 100, 30)
    
    local count, types = collectAllPlantsStealth()
    stats.collectedPlants = stats.collectedPlants + count
    PlantCountLabel.Text = "Plants: " .. stats.collectedPlants
    
    InstantCollectBtn.Text = "+" .. count
    task.wait(1)
    InstantCollectBtn.Text = "COLLECT SEKARANG"
    InstantCollectBtn.BackgroundColor3 = Color3.fromRGB(70, 160, 50)
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

ListBtn.MouseButton1Click:Connect(function()
    refreshNPCList()
    ListPopup.Visible = not ListPopup.Visible
end)

ListClose.MouseButton1Click:Connect(function()
    ListPopup.Visible = false
end)

RescanBtn.MouseButton1Click:Connect(function()
    RescanBtn.Text = "SCANNING..."
    task.wait(0.1)
    local npcs = getAllNPCs()
    CountLabel.Text = "NPC Detected: " .. #npcs
    RescanBtn.Text = "RESCAN NPC"
end)

ConsoleBtn.MouseButton1Click:Connect(function()
    ConsolePopup.Visible = not ConsolePopup.Visible
end)

ClearBtn.MouseButton1Click:Connect(function()
    for _, child in ipairs(LogScroll:GetChildren()) do
        if child:IsA("TextLabel") then
            child:Destroy()
        end
    end
    logCount = 0
end)

ConsoleClose.MouseButton1Click:Connect(function()
    ConsolePopup.Visible = false
end)

MinBtn.MouseButton1Click:Connect(function()
    if MainFrame.Size.Y.Offset > 50 then
        MainFrame.Size = UDim2.new(0, 720, 0, 35)
        MinBtn.Text = "o"
    else
        MainFrame.Size = UDim2.new(0, 720, 0, 300)
        MinBtn.Text = "_"
    end
end)

CloseBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = false
    Bubble.Position = MainFrame.Position
    Bubble.Visible = true
end)

Bubble.MouseButton1Click:Connect(function()
    MainFrame.Visible = true
    Bubble.Visible = false
end)

-- ============================================================
-- ANTI-AFK (VERSI LO)
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
            local playerGui = player:FindFirstChild("PlayerGui")
            if not playerGui then return end
            
            local mainGui = playerGui:FindFirstChild("Main")
            if not mainGui then return end
            
            local frames = mainGui:FindFirstChild("Frames")
            if not frames then return end
            
            local totalClaimed = 0
            
            -- PATH 1: Events (Merits) - PlaytimeRewards folder
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
            
            -- PATH 2: Shop (Time Reward) - numeric folder names
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

-- INITIAL SCAN
local npcs = getAllNPCs()
CountLabel.Text = "NPC Detected: " .. #npcs

-- DONE
print("=========================================")
print("  AUTOFARM v5.4 - DUAL PATH CLAIM")
print("  Script Created by ADIEL")
print("=========================================")
print("Target NPC: Scorpion, Tombguardian, Water Serpent")
print("Plant: Ginseng, Spirit Grass")
print("Reward Claim: Events + Shop PlaytimeRewards")
print("Anti-AFK: CaptureController")
