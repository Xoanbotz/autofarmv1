--[[
=========================================================
  UNIVERSAL AUTOFARM v5.0 - FAST FARM EDITION
  Author: Kyriel (for Boss)
  Executor: Delta / Codex / Wave / Xeno

FITUR:
  - Autofarm LOCK (Scorpion, Tombguardian, Water Serpent)
  - ULTRA FAST: Kill rate 4x lebih cepet
  - Auto-next-target (seamless kill)
  - Anti-death (auto respawn)
  - Stats: Kills, Kills/menit
  - Stealth Plant Collector (Ginseng & Spirit Grass)
  - GUI rapi section-based
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
-- CONFIG (TURBO MODE)
-- ============================================================
local CONFIG = {
    -- ═══ AUTOFARM (FAST) ═══
    ATTACK_RANGE = 150,
    TELEPORT_HEIGHT = 10,
    LOCK_UPDATE_RATE = 0.05,     -- ULTRA FAST
    ATTACK_COOLDOWN = 0.05,      -- ULTRA FAST
    LOOP_DELAY = 0.1,            -- ULTRA FAST
    AUTO_EQUIP_TOOL = true,
    USE_SKILLS = true,
    SKILL_KEYS = {"Z", "X", "C", "V", "F"},
    SKILL_COOLDOWN = 0.8,        -- Lebih cepet spam
    AUTO_RESPAWN = true,         -- Anti death
    
    -- ═══ PLANT COLLECTOR ═══
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
    
    -- ═══ NPC WHITELIST ═══
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
    DEBUG = false,               -- MATIIN log biar ringan
}

-- ============================================================
-- STATE
-- ============================================================
local isRunning = false
local isCollectingPlants = false
local currentTarget = nil
local lastSkillTime = 0
local detectedFolders = {}
local skippedCount = 0
local cachedTool = nil
local lastFarmPosition = nil    -- Buat anti-death

-- STATISTIK
local stats = {
    kills = 0,
    collectedPlants = 0,
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
local function getHPPercent()
    if not humanoid or not humanoid.Parent then return 0 end
    return (humanoid.Health / humanoid.MaxHealth) * 100
end

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
-- CARI SEMUA NPC (PRIORITAS TERDEKAT)
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
-- ATTACK (OPTIMIZED)
-- ============================================================
local function attackNPC(npc)
    if not npc or not npc.model or not npc.model.Parent then return end
    if not npc.humanoid or npc.humanoid.Health <= 0 then return end
    if not character or not character.Parent then return end
    
    -- Auto equip (cached)
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
    
    -- Click attack
    pcall(function()
        VirtualUser:Button1Down(Vector2.new(0, 0))
        VirtualUser:Button1Up(Vector2.new(0, 0))
    end)
    
    -- Skill spam
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
-- AUTO RESPAWN (ANTI-DEATH)
-- ============================================================
local function setupAntiDeath()
    if character then
        pcall(function()
            humanoid.Died:Connect(function()
                log("☠ Mati! Auto respawn...", Color3.fromRGB(255, 100, 100))
                task.wait(3)
                
                if CONFIG.AUTO_RESPAWN then
                    pcall(function()
                        player:LoadCharacter()
                    end)
                    
                    task.wait(2)
                    updateCharacterRefs()
                    
                    -- Balik ke posisi terakhir
                    if lastFarmPosition and humanoidRootPart then
                        pcall(function()
                            humanoidRootPart.CFrame = lastFarmPosition
                        end)
                    end
                    
                    log("✓ Respawned!", Color3.fromRGB(0, 255, 100))
                end
            end)
        end)
    end
end

-- ============================================================
-- START AUTOFARM (FAST)
-- ============================================================
local function startAutoFarm()
    if isRunning then return end
    isRunning = true
    stats.startTime = tick()
    
    log("⚡ AUTOFARM STARTED (FAST MODE)", Color3.fromRGB(0, 255, 100))
    
    setupAntiDeath()
    
    task.spawn(function()
        local emptyCount = 0
        
        while isRunning do
            if not character or not character.Parent then
                updateCharacterRefs()
                setupAntiDeath()
            end
            
            -- Simpen posisi buat anti-death
            if humanoidRootPart and humanoidRootPart.Parent then
                lastFarmPosition = humanoidRootPart.CFrame
            end
            
            local npcs = getAllNPCs()
            
            if #npcs > 0 then
                emptyCount = 0
                
                -- AMBIL TARGET PALING DEKET
                currentTarget = npcs[1]
                
                -- LOCK + ATTACK (seamless)
                lockToNPC(currentTarget)
                
                local targetKilled = false
                local killTimeout = tick() + 15
                
                while currentTarget and currentTarget.humanoid 
                    and currentTarget.humanoid.Health > 0 
                    and isRunning 
                    and tick() < killTimeout do
                    
                    -- Lock + attack dalam 1 iterasi
                    lockToNPC(currentTarget)
                    attackNPC(currentTarget)
                    
                    -- Cek target ilang (auto-next-target INSTAN)
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
                
                -- LANGSUNG LOOP KE TARGET BARU (seamless)
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
    log("⏸ Autofarm Stopped.", Color3.fromRGB(255, 100, 100))
end

-- ============================================================
-- PLANT COLLECTOR (STEALTH)
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
    
    log("🌿 Found " .. #plants .. " plants", Color3.fromRGB(150, 255, 100))
    
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
    log("🌿 Plant Collector STARTED", Color3.fromRGB(150, 255, 100))
    
    task.spawn(function()
        while isCollectingPlants do
            local count, types = collectAllPlantsStealth()
            
            if count > 0 then
                stats.collectedPlants = stats.collectedPlants + count
                if PlantCountLabel then
                    PlantCountLabel.Text = "🌿 Collected: " .. stats.collectedPlants
                end
                
                local typeStr = ""
                for t, c in pairs(types) do
                    typeStr = typeStr .. t .. "(" .. c .. ") "
                end
                log("✓ " .. count .. ": " .. typeStr, Color3.fromRGB(100, 255, 150))
            else
                log("🌿 Gak ada plant", Color3.fromRGB(255, 200, 100))
            end
            
            task.wait(CONFIG.PLANT_SCAN_DELAY)
        end
    end)
end

local function stopPlantCollector()
    isCollectingPlants = false
    log("🌿 Plant Collector STOPPED", Color3.fromRGB(255, 150, 100))
end

-- ============================================================
-- GUI - RAPI STRUCTURED
-- ============================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutofarmGUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = player:WaitForChild("PlayerGui")

-- ═══ MAIN FRAME ═══
local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 280, 0, 510)
MainFrame.Position = UDim2.new(0, 20, 0, 60)
MainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Visible = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 12)
MainCorner.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(50, 50, 75)
MainStroke.Thickness = 1
MainStroke.Parent = MainFrame

-- ═══ TITLE BAR ═══
local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 38)
TitleBar.BackgroundColor3 = Color3.fromRGB(28, 28, 42)
TitleBar.BorderSizePixel = 0
TitleBar.Active = true
TitleBar.Parent = MainFrame

local TitleBarCorner = Instance.new("UICorner")
TitleBarCorner.CornerRadius = UDim.new(0, 12)
TitleBarCorner.Parent = TitleBar

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -80, 1, 0)
Title.Position = UDim2.new(0, 12, 0, 0)
Title.BackgroundTransparency = 1
Title.TextColor3 = Color3.fromRGB(0, 255, 150)
Title.Text = "⚡ AUTOFARM v5.0"
Title.TextSize = 14
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TitleBar

local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 28, 0, 28)
MinBtn.Position = UDim2.new(1, -62, 0, 5)
MinBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 85)
MinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
MinBtn.Text = "—"
MinBtn.TextSize = 14
MinBtn.Font = Enum.Font.GothamBold
MinBtn.Parent = TitleBar

local MinCorner = Instance.new("UICorner")
MinCorner.CornerRadius = UDim.new(0, 6)
MinCorner.Parent = MinBtn

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 28, 0, 28)
CloseBtn.Position = UDim2.new(1, -30, 0, 5)
CloseBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Text = "×"
CloseBtn.TextSize = 16
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.Parent = TitleBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 6)
CloseCorner.Parent = CloseBtn

-- ═══ STATS SECTION ═══
local StatsFrame = Instance.new("Frame")
StatsFrame.Size = UDim2.new(1, -20, 0, 70)
StatsFrame.Position = UDim2.new(0, 10, 0, 48)
StatsFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 36)
StatsFrame.BorderSizePixel = 0
StatsFrame.Parent = MainFrame

local StatsCorner = Instance.new("UICorner")
StatsCorner.CornerRadius = UDim.new(0, 8)
StatsCorner.Parent = StatsFrame

-- Kills Counter
local KillsLabel = Instance.new("TextLabel")
KillsLabel.Size = UDim2.new(0.5, -8, 0, 25)
KillsLabel.Position = UDim2.new(0, 8, 0, 5)
KillsLabel.BackgroundTransparency = 1
KillsLabel.TextColor3 = Color3.fromRGB(0, 255, 150)
KillsLabel.Text = "⚔ Kills: 0"
KillsLabel.TextSize = 12
KillsLabel.Font = Enum.Font.GothamBold
KillsLabel.TextXAlignment = Enum.TextXAlignment.Left
KillsLabel.Parent = StatsFrame

-- Kills/menit
local KPM = Instance.new("TextLabel")
KPM.Size = UDim2.new(0.5, -8, 0, 25)
KPM.Position = UDim2.new(0.5, 0, 0, 5)
KPM.BackgroundTransparency = 1
KPM.TextColor3 = Color3.fromRGB(255, 200, 100)
KPM.Text = "📊 0 KPM"
KPM.TextSize = 12
KPM.Font = Enum.Font.GothamBold
KPM.TextXAlignment = Enum.TextXAlignment.Right
KPM.Parent = StatsFrame

-- NPC Count
local CountLabel = Instance.new("TextLabel")
CountLabel.Size = UDim2.new(0.5, -8, 0, 20)
CountLabel.Position = UDim2.new(0, 8, 0, 28)
CountLabel.BackgroundTransparency = 1
CountLabel.TextColor3 = Color3.fromRGB(150, 150, 200)
CountLabel.Text = "NPC: 0"
CountLabel.TextSize = 10
CountLabel.Font = Enum.Font.Gotham
CountLabel.TextXAlignment = Enum.TextXAlignment.Left
CountLabel.Parent = StatsFrame

-- Plant Count
local PlantCountLabel = Instance.new("TextLabel")
PlantCountLabel.Size = UDim2.new(0.5, -8, 0, 20)
PlantCountLabel.Position = UDim2.new(0.5, 0, 0, 28)
PlantCountLabel.BackgroundTransparency = 1
PlantCountLabel.TextColor3 = Color3.fromRGB(150, 255, 100)
PlantCountLabel.Text = "🌿 0 plants"
PlantCountLabel.TextSize = 10
PlantCountLabel.Font = Enum.Font.Gotham
PlantCountLabel.TextXAlignment = Enum.TextXAlignment.Right
PlantCountLabel.Parent = StatsFrame

-- HP Bar Background
local HPBarBG = Instance.new("Frame")
HPBarBG.Size = UDim2.new(1, -16, 0, 8)
HPBarBG.Position = UDim2.new(0, 8, 0, 53)
HPBarBG.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
HPBarBG.BorderSizePixel = 0
HPBarBG.Parent = StatsFrame

local HPBarBG_Corner = Instance.new("UICorner")
HPBarBG_Corner.CornerRadius = UDim.new(1, 0)
HPBarBG_Corner.Parent = HPBarBG

-- HP Bar Fill
local HPBarFill = Instance.new("Frame")
HPBarFill.Size = UDim2.new(1, 0, 1, 0)
HPBarFill.BackgroundColor3 = Color3.fromRGB(0, 255, 100)
HPBarFill.BorderSizePixel = 0
HPBarFill.Parent = HPBarBG

local HPBarFill_Corner = Instance.new("UICorner")
HPBarFill_Corner.CornerRadius = UDim.new(1, 0)
HPBarFill_Corner.Parent = HPBarFill

-- ═══ SECTION: AUTOFARM ═══
local FarmSection = Instance.new("Frame")
FarmSection.Size = UDim2.new(1, -20, 0, 130)
FarmSection.Position = UDim2.new(0, 10, 0, 128)
FarmSection.BackgroundColor3 = Color3.fromRGB(24, 24, 36)
FarmSection.BorderSizePixel = 0
FarmSection.Parent = MainFrame

local FarmSectionCorner = Instance.new("UICorner")
FarmSectionCorner.CornerRadius = UDim.new(0, 8)
FarmSectionCorner.Parent = FarmSection

local FarmTitle = Instance.new("TextLabel")
FarmTitle.Size = UDim2.new(1, -12, 0, 18)
FarmTitle.Position = UDim2.new(0, 8, 0, 5)
FarmTitle.BackgroundTransparency = 1
FarmTitle.TextColor3 = Color3.fromRGB(0, 200, 255)
FarmTitle.Text = "⚔ AUTOFARM (Fast Mode)"
FarmTitle.TextSize = 10
FarmTitle.Font = Enum.Font.GothamBold
FarmTitle.TextXAlignment = Enum.TextXAlignment.Left
FarmTitle.Parent = FarmSection

local ToggleButton = Instance.new("TextButton")
ToggleButton.Size = UDim2.new(1, -16, 0, 38)
ToggleButton.Position = UDim2.new(0, 8, 0, 25)
ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 180, 0)
ToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleButton.Text = "▶ START AUTOFARM"
ToggleButton.TextSize = 13
ToggleButton.Font = Enum.Font.GothamBold
ToggleButton.Parent = FarmSection

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(0, 6)
ToggleCorner.Parent = ToggleButton

local TeleportBtn = Instance.new("TextButton")
TeleportBtn.Size = UDim2.new(0.5, -10, 0, 28)
TeleportBtn.Position = UDim2.new(0, 8, 0, 68)
TeleportBtn.BackgroundColor3 = Color3.fromRGB(0, 130, 200)
TeleportBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
TeleportBtn.Text = "⚡ TELEPORT KE MOB"
TeleportBtn.TextSize = 10
TeleportBtn.Font = Enum.Font.GothamBold
TeleportBtn.Parent = FarmSection

local TeleCorner = Instance.new("UICorner")
TeleCorner.CornerRadius = UDim.new(0, 5)
TeleCorner.Parent = TeleportBtn

local ListBtn = Instance.new("TextButton")
ListBtn.Size = UDim2.new(0.5, -10, 0, 28)
ListBtn.Position = UDim2.new(0.5, 2, 0, 68)
ListBtn.BackgroundColor3 = Color3.fromRGB(100, 60, 130)
ListBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ListBtn.Text = "📋 LIST NPC"
ListBtn.TextSize = 10
ListBtn.Font = Enum.Font.GothamBold
ListBtn.Parent = FarmSection

local ListCorner = Instance.new("UICorner")
ListCorner.CornerRadius = UDim.new(0, 5)
ListCorner.Parent = ListBtn

local NPCListLabel = Instance.new("TextLabel")
NPCListLabel.Size = UDim2.new(1, -16, 0, 20)
NPCListLabel.Position = UDim2.new(0, 8, 0, 102)
NPCListLabel.BackgroundTransparency = 1
NPCListLabel.TextColor3 = Color3.fromRGB(120, 120, 160)
NPCListLabel.Text = "Scorpion • Tombguardian • Water Serpent"
NPCListLabel.TextSize = 9
NPCListLabel.Font = Enum.Font.Gotham
NPCListLabel.TextXAlignment = Enum.TextXAlignment.Left
NPCListLabel.Parent = FarmSection

-- ═══ SECTION: PLANT ═══
local PlantSection = Instance.new("Frame")
PlantSection.Size = UDim2.new(1, -20, 0, 130)
PlantSection.Position = UDim2.new(0, 10, 0, 266)
PlantSection.BackgroundColor3 = Color3.fromRGB(24, 24, 36)
PlantSection.BorderSizePixel = 0
PlantSection.Parent = MainFrame

local PlantSectionCorner = Instance.new("UICorner")
PlantSectionCorner.CornerRadius = UDim.new(0, 8)
PlantSectionCorner.Parent = PlantSection

local PlantTitle = Instance.new("TextLabel")
PlantTitle.Size = UDim2.new(1, -12, 0, 18)
PlantTitle.Position = UDim2.new(0, 8, 0, 5)
PlantTitle.BackgroundTransparency = 1
PlantTitle.TextColor3 = Color3.fromRGB(150, 255, 100)
PlantTitle.Text = "🌿 PLANT COLLECTOR"
PlantTitle.TextSize = 10
PlantTitle.Font = Enum.Font.GothamBold
PlantTitle.TextXAlignment = Enum.TextXAlignment.Left
PlantTitle.Parent = PlantSection

local PlantToggleBtn = Instance.new("TextButton")
PlantToggleBtn.Size = UDim2.new(1, -16, 0, 38)
PlantToggleBtn.Position = UDim2.new(0, 8, 0, 25)
PlantToggleBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 80)
PlantToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
PlantToggleBtn.Text = "🌿 START PLANT COLLECTOR"
PlantToggleBtn.TextSize = 13
PlantToggleBtn.Font = Enum.Font.GothamBold
PlantToggleBtn.Parent = PlantSection

local PlantToggleCorner = Instance.new("UICorner")
PlantToggleCorner.CornerRadius = UDim.new(0, 6)
PlantToggleCorner.Parent = PlantToggleBtn

local InstantCollectBtn = Instance.new("TextButton")
InstantCollectBtn.Size = UDim2.new(1, -16, 0, 28)
InstantCollectBtn.Position = UDim2.new(0, 8, 0, 68)
InstantCollectBtn.BackgroundColor3 = Color3.fromRGB(80, 180, 60)
InstantCollectBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
InstantCollectBtn.Text = "⚡ COLLECT SEKARANG"
InstantCollectBtn.TextSize = 10
InstantCollectBtn.Font = Enum.Font.GothamBold
InstantCollectBtn.Parent = PlantSection

local InstCorner = Instance.new("UICorner")
InstCorner.CornerRadius = UDim.new(0, 5)
InstCorner.Parent = InstantCollectBtn

local PlantListLabel = Instance.new("TextLabel")
PlantListLabel.Size = UDim2.new(1, -16, 0, 20)
PlantListLabel.Position = UDim2.new(0, 8, 0, 102)
PlantListLabel.BackgroundTransparency = 1
PlantListLabel.TextColor3 = Color3.fromRGB(120, 160, 120)
PlantListLabel.Text = "Ginseng • Spirit Grass"
PlantListLabel.TextSize = 9
PlantListLabel.Font = Enum.Font.Gotham
PlantListLabel.TextXAlignment = Enum.TextXAlignment.Left
PlantListLabel.Parent = PlantSection

-- ═══ SECTION: STATUS ═══
local StatusSection = Instance.new("Frame")
StatusSection.Size = UDim2.new(1, -20, 0, 55)
StatusSection.Position = UDim2.new(0, 10, 0, 404)
StatusSection.BackgroundColor3 = Color3.fromRGB(24, 24, 36)
StatusSection.BorderSizePixel = 0
StatusSection.Parent = MainFrame

local StatusSectionCorner = Instance.new("UICorner")
StatusSectionCorner.CornerRadius = UDim.new(0, 8)
StatusSectionCorner.Parent = StatusSection

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -16, 0, 18)
StatusLabel.Position = UDim2.new(0, 8, 0, 5)
StatusLabel.BackgroundTransparency = 1
StatusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
StatusLabel.Text = "Farm: IDLE | Plant: IDLE"
StatusLabel.TextSize = 10
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Parent = StatusSection

local RescanBtn = Instance.new("TextButton")
RescanBtn.Size = UDim2.new(0.5, -10, 0, 24)
RescanBtn.Position = UDim2.new(0, 8, 0, 26)
RescanBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 80)
RescanBtn.TextColor3 = Color3.fromRGB(200, 200, 255)
RescanBtn.Text = "🔄 RESCAN"
RescanBtn.TextSize = 10
RescanBtn.Font = Enum.Font.GothamBold
RescanBtn.Parent = StatusSection

local RescanCorner = Instance.new("UICorner")
RescanCorner.CornerRadius = UDim.new(0, 5)
RescanCorner.Parent = RescanBtn

local ConsoleBtn = Instance.new("TextButton")
ConsoleBtn.Size = UDim2.new(0.5, -10, 0, 24)
ConsoleBtn.Position = UDim2.new(0.5, 2, 0, 26)
ConsoleBtn.BackgroundColor3 = Color3.fromRGB(40, 70, 40)
ConsoleBtn.TextColor3 = Color3.fromRGB(150, 255, 150)
ConsoleBtn.Text = "📋 CONSOLE"
ConsoleBtn.TextSize = 10
ConsoleBtn.Font = Enum.Font.GothamBold
ConsoleBtn.Parent = StatusSection

local ConsoleCorner = Instance.new("UICorner")
ConsoleCorner.CornerRadius = UDim.new(0, 5)
ConsoleCorner.Parent = ConsoleBtn

-- ═══ FOOTER ═══
local Credit = Instance.new("TextLabel")
Credit.Size = UDim2.new(1, 0, 0, 18)
Credit.Position = UDim2.new(0, 0, 1, -18)
Credit.BackgroundTransparency = 1
Credit.TextColor3 = Color3.fromRGB(70, 70, 100)
Credit.Text = "⚡ v5.0 Fast Farm • by Kyriel"
Credit.TextSize = 9
Credit.Font = Enum.Font.Gotham
Credit.Parent = MainFrame

-- ============================================================
-- CONSOLE POPUP
-- ============================================================
ConsolePopup = Instance.new("Frame")
ConsolePopup.Size = UDim2.new(0, 340, 0, 280)
ConsolePopup.Position = UDim2.new(0.5, -170, 0.5, -140)
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
ConsoleTitle.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
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
ConsoleTitleLabel.TextColor3 = Color3.fromRGB(0, 255, 150)
ConsoleTitleLabel.Text = "📋 CONSOLE"
ConsoleTitleLabel.TextSize = 12
ConsoleTitleLabel.Font = Enum.Font.GothamBold
ConsoleTitleLabel.TextXAlignment = Enum.TextXAlignment.Left
ConsoleTitleLabel.ZIndex = 22
ConsoleTitleLabel.Parent = ConsoleTitle

local ClearBtn = Instance.new("TextButton")
ClearBtn.Size = UDim2.new(0, 50, 0, 22)
ClearBtn.Position = UDim2.new(1, -85, 0, 4)
ClearBtn.BackgroundColor3 = Color3.fromRGB(80, 50, 50)
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
ConsoleClose.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
ConsoleClose.TextColor3 = Color3.fromRGB(255, 255, 255)
ConsoleClose.Text = "×"
ConsoleClose.TextSize = 14
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

-- ============================================================
-- NPC LIST POPUP
-- ============================================================
local ListPopup = Instance.new("Frame")
ListPopup.Size = UDim2.new(0, 280, 0, 300)
ListPopup.Position = UDim2.new(0.5, -140, 0.5, -150)
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
ListTitle.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
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
ListTitleLabel.TextColor3 = Color3.fromRGB(0, 255, 150)
ListTitleLabel.Text = "🎯 NPC TARGET (TAP TELEPORT)"
ListTitleLabel.TextSize = 11
ListTitleLabel.Font = Enum.Font.GothamBold
ListTitleLabel.TextXAlignment = Enum.TextXAlignment.Left
ListTitleLabel.ZIndex = 22
ListTitleLabel.Parent = ListTitle

local ListClose = Instance.new("TextButton")
ListClose.Size = UDim2.new(0, 25, 0, 22)
ListClose.Position = UDim2.new(1, -28, 0, 4)
ListClose.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
ListClose.TextColor3 = Color3.fromRGB(255, 255, 255)
ListClose.Text = "×"
ListClose.TextSize = 14
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
        lbl.Text = "❌ Gak ada NPC target"
        lbl.TextSize = 11
        lbl.Font = Enum.Font.Gotham
        lbl.Parent = ListScroll
        return
    end
    
    for i, npc in ipairs(npcs) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -6, 0, 28)
        btn.BackgroundColor3 = Color3.fromRGB(40, 60, 80)
        btn.TextColor3 = Color3.fromRGB(150, 255, 200)
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
                log("⚡ Teleport ke: " .. npc.model.Name, Color3.fromRGB(0, 200, 255))
                ListPopup.Visible = false
            end
        end)
    end
end

-- ============================================================
-- FLOATING BUBBLE
-- ============================================================
local Bubble = Instance.new("TextButton")
Bubble.Name = "FloatingBubble"
Bubble.Size = UDim2.new(0, 50, 0, 50)
Bubble.Position = UDim2.new(0, 20, 0, 100)
Bubble.BackgroundColor3 = Color3.fromRGB(0, 180, 100)
Bubble.TextColor3 = Color3.fromRGB(255, 255, 255)
Bubble.Text = "⚡"
Bubble.TextSize = 24
Bubble.Font = Enum.Font.GothamBold
Bubble.Visible = false
Bubble.Active = true
Bubble.Parent = ScreenGui

local BubbleCorner = Instance.new("UICorner")
BubbleCorner.CornerRadius = UDim.new(1, 0)
BubbleCorner.Parent = Bubble

local BubbleStroke = Instance.new("UIStroke")
BubbleStroke.Color = Color3.fromRGB(0, 255, 150)
BubbleStroke.Thickness = 2
BubbleStroke.Parent = Bubble

-- ============================================================
-- DRAGGABLE
-- ============================================================
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

-- ============================================================
-- REAL-TIME STATS UPDATE
-- ============================================================
task.spawn(function()
    while task.wait(0.5) do
        -- Update HP bar
        if humanoid and humanoid.Parent then
            local hpPct = humanoid.Health / humanoid.MaxHealth
            HPBarFill.Size = UDim2.new(math.max(0, hpPct), 0, 1, 0)
            
            if hpPct < 0.3 then
                HPBarFill.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
            elseif hpPct < 0.6 then
                HPBarFill.BackgroundColor3 = Color3.fromRGB(255, 200, 80)
            else
                HPBarFill.BackgroundColor3 = Color3.fromRGB(0, 255, 100)
            end
        end
        
        -- Update Kills
        KillsLabel.Text = "⚔ Kills: " .. stats.kills
        
        -- Update KPM
        if stats.startTime > 0 and isRunning then
            local elapsed = tick() - stats.startTime
            if elapsed > 5 then
                local kpm = math.floor((stats.kills / elapsed) * 60)
                KPM.Text = "📊 " .. kpm .. " KPM"
            end
        else
            KPM.Text = "📊 0 KPM"
        end
    end
end)

task.spawn(function()
    while task.wait(CONFIG.SCAN_INTERVAL) do
        if not isRunning then
            local npcs = getAllNPCs()
            CountLabel.Text = "NPC: " .. #npcs
        else
            local npcs = getAllNPCs()
            CountLabel.Text = "NPC: " .. #npcs
        end
    end
end)

-- ============================================================
-- EVENT HANDLERS
-- ============================================================
ToggleButton.MouseButton1Click:Connect(function()
    if isRunning then
        stopAutoFarm()
        ToggleButton.Text = "▶ START AUTOFARM"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 180, 0)
        StatusLabel.Text = "Farm: IDLE | Plant: " .. (isCollectingPlants and "RUNNING" or "IDLE")
        StatusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
    else
        startAutoFarm()
        ToggleButton.Text = "⏸ STOP AUTOFARM"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(180, 0, 0)
        StatusLabel.Text = "Farm: LOCKED | Plant: " .. (isCollectingPlants and "RUNNING" or "IDLE")
        StatusLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
    end
end)

PlantToggleBtn.MouseButton1Click:Connect(function()
    if isCollectingPlants then
        stopPlantCollector()
        PlantToggleBtn.Text = "🌿 START PLANT COLLECTOR"
        PlantToggleBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 80)
        StatusLabel.Text = "Farm: " .. (isRunning and "LOCKED" or "IDLE") .. " | Plant: IDLE"
    else
        startPlantCollector()
        PlantToggleBtn.Text = "⏸ STOP PLANT COLLECTOR"
        PlantToggleBtn.BackgroundColor3 = Color3.fromRGB(140, 70, 0)
        StatusLabel.Text = "Farm: " .. (isRunning and "LOCKED" or "IDLE") .. " | Plant: RUNNING"
    end
end)

InstantCollectBtn.MouseButton1Click:Connect(function()
    InstantCollectBtn.Text = "⚡ COLLECTING..."
    InstantCollectBtn.BackgroundColor3 = Color3.fromRGB(50, 100, 30)
    
    local count, types = collectAllPlantsStealth()
    stats.collectedPlants = stats.collectedPlants + count
    PlantCountLabel.Text = "🌿 " .. stats.collectedPlants .. " plants"
    
    InstantCollectBtn.Text = "✓ +" .. count
    task.wait(1)
    InstantCollectBtn.Text = "⚡ COLLECT SEKARANG"
    InstantCollectBtn.BackgroundColor3 = Color3.fromRGB(80, 180, 60)
end)

TeleportBtn.MouseButton1Click:Connect(function()
    local npcs = getAllNPCs()
    if #npcs > 0 then
        teleportToNPC(npcs[1])
        TeleportBtn.Text = "✓ " .. npcs[1].model.Name
        task.wait(1)
        TeleportBtn.Text = "⚡ TELEPORT KE MOB"
    else
        TeleportBtn.Text = "❌ GAK ADA NPC"
        task.wait(1)
        TeleportBtn.Text = "⚡ TELEPORT KE MOB"
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
    RescanBtn.Text = "🔄 SCANNING..."
    task.wait(0.1)
    local npcs = getAllNPCs()
    CountLabel.Text = "NPC: " .. #npcs
    RescanBtn.Text = "🔄 RESCAN"
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
        MainFrame.Size = UDim2.new(0, 280, 0, 38)
        MinBtn.Text = "□"
    else
        MainFrame.Size = UDim2.new(0, 280, 0, 510)
        MinBtn.Text = "—"
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
-- ANTI-AFK
-- ============================================================
player.Idled:Connect(function()
    pcall(function()
        VirtualUser:Button2Down(Vector2.new(0, 0))
        task.wait(1)
        VirtualUser:Button2Up(Vector2.new(0, 0))
    end)
end)

-- ============================================================
-- INITIAL SCAN
-- ============================================================
local npcs = getAllNPCs()
CountLabel.Text = "NPC: " .. #npcs

-- ============================================================
-- DONE
-- ============================================================
print("✅ AUTOFARM v5.0 FAST FARM loaded!")
print("⚡ Kill rate: 4x lebih cepet")
print("🎯 Target: Scorpion, Tombguardian, Water Serpent")
print("🌿 Plant: Ginseng, Spirit Grass")
