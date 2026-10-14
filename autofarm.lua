--[[
=========================================================
  UNIVERSAL AUTOFARM v4.9 - AUTOFARM + PLANT COLLECTOR
  Author: Kyriel (for Boss)
  Executor: Delta / Codex / Wave / Xeno

FITUR:
  - Autofarm LOCK di atas kepala NPC (v4.8 - no lag)
  - AUTO COLLECT PLANT INSTANT (tanpa teleport!)
  - Plants: Ginseng, Lily, Essence Leaf, Spirit Grass, Lotus
  - Tombol terpisah buat autofarm & plant
=========================================================
]]

-- ============================================================
-- SERVICE
-- ============================================================
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
local humanoid = character:WaitForChild("Humanoid")

-- ============================================================
-- KONFIGURASI
-- ============================================================
local CONFIG = {
    -- AUTOFARM
    ATTACK_RANGE = 100,
    TELEPORT_HEIGHT = 10,
    LOCK_UPDATE_RATE = 0.1,
    ATTACK_COOLDOWN = 0.2,
    LOOP_DELAY = 0.5,
    AUTO_EQUIP_TOOL = true,
    USE_SKILLS = true,
    SKILL_KEYS = {"Z", "X", "C", "V", "F"},
    SKILL_COOLDOWN = 2.5,
    
    -- PLANT COLLECTOR
    PLANT_NAMES = {
        "Ginseng",
        "Lily",
        "Essence Leaf",
        "EssenceLeaf",
        "Spirit Grass",
        "SpiritGrass",
        "Lotus",
    },
    PLANT_SCAN_DELAY = 1,          -- Delay antar scan plant (detik)
    PLANT_MAX_DEPTH = 6,           -- Kedalaman scan plant
    FORCE_PROMPT_DISTANCE = true,  -- Paksa prompt biar bisa di-fire dari jauh
    
    -- NPC
    NPC_WHITELIST = {
        "Scorpion",
        "Tombguardian",
        "Water Serpent",
        "Tidecrusher Crab",
        "WaterSerpent",
        "TidecrusherCrab",
    },
    NPC_BLACKLIST = {},
    MAX_DEPTH = 4,
    LOG_LIMIT = 30,
    SCAN_INTERVAL = 10,
    DEBUG = true,
}

-- ============================================================
-- STATE
-- ============================================================
local isRunning = false
local currentTarget = nil
local lastSkillTime = 0
local detectedFolders = {}
local skippedCount = 0
local scanLog = {}
local logCount = 0
local cachedTool = nil

local isCollectingPlants = false
local collectedPlants = 0

-- ============================================================
-- LOG SYSTEM
-- ============================================================
local LogScroll = nil
local ConsolePopup = nil

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
        local first = nil
        for _, child in ipairs(LogScroll:GetChildren()) do
            if child:IsA("TextLabel") then
                first = child
                break
            end
        end
        if first then
            first:Destroy()
            logCount = logCount - 1
        end
    end
end

-- ============================================================
-- CHECK NPC
-- ============================================================
local function checkNPC(model)
    if not model or not model:IsA("Model") then
        return false, "not a model"
    end
    
    if Players:GetPlayerFromCharacter(model) then
        return false, "is player"
    end
    
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum then
        return false, "no humanoid"
    end
    
    if hum.Health <= 0 then
        return false, "dead"
    end
    
    if hum.MaxHealth <= 0 then
        return false, "MaxHealth=0"
    end
    if hum.MaxHealth == math.huge or hum.MaxHealth > 1e9 then
        return false, "invincible"
    end
    
    if hum:GetAttribute("Invincible") == true then return false, "invincible" end
    if hum:GetAttribute("IsQuestGiver") == true then return false, "questgiver" end
    if model:GetAttribute("Invincible") == true then return false, "invincible" end
    
    local nameLower = string.lower(model.Name)
    local isWhitelisted = false
    local matchedName = ""
    
    for _, target in ipairs(CONFIG.NPC_WHITELIST) do
        if string.find(nameLower, string.lower(target)) then
            isWhitelisted = true
            matchedName = target
            break
        end
    end
    
    if not isWhitelisted then
        return false, "not in whitelist"
    end
    
    local root = model:FindFirstChild("HumanoidRootPart")
    if not root then
        root = model:FindFirstChild("Head") 
            or model:FindFirstChild("Torso")
            or model:FindFirstChild("UpperTorso")
    end
    
    if not root then
        return false, "no root"
    end
    
    return true, matchedName
end

-- ============================================================
-- DETEKSI FOLDER NPC
-- ============================================================
local function detectNPCFolders()
    local folderCount = {}
    skippedCount = 0
    scanLog = {}
    
    local function scan(instance, depth)
        if depth > CONFIG.MAX_DEPTH then return end
        
        for _, obj in ipairs(instance:GetChildren()) do
            if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") then
                local ok, reason = checkNPC(obj)
                if ok then
                    local parentName = obj.Parent and obj.Parent.Name or "Workspace"
                    folderCount[parentName] = (folderCount[parentName] or 0) + 1
                else
                    skippedCount = skippedCount + 1
                    if #scanLog < 20 and reason ~= "not in whitelist" then
                        table.insert(scanLog, string.format("SKIP %s → %s", obj.Name, reason))
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
    
    if #scanLog > 0 then
        log("--- Skip Log ---", Color3.fromRGB(255, 200, 100))
        for _, entry in ipairs(scanLog) do
            log(entry, Color3.fromRGB(255, 150, 150))
        end
    end
    
    local sorted = {}
    for name, count in pairs(folderCount) do
        table.insert(sorted, {name = name, count = count})
    end
    table.sort(sorted, function(a, b) return a.count > b.count end)
    
    return sorted
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
                local ok = checkNPC(obj)
                if ok then
                    local hum = obj:FindFirstChildOfClass("Humanoid")
                    local root = obj:FindFirstChild("HumanoidRootPart") 
                        or obj:FindFirstChild("Head") 
                        or obj:FindFirstChild("Torso")
                        or obj:FindFirstChild("UpperTorso")
                    
                    if hum and root and hum.Health > 0 then
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
-- LOCK POSISI KE ATAS KEPALA NPC
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
-- SERANG NPC
-- ============================================================
local function attackNPC(npc)
    if not npc or not npc.model or not npc.model.Parent then return end
    if not npc.humanoid or npc.humanoid.Health <= 0 then return end
    if not character or not character.Parent then return end
    
    if CONFIG.AUTO_EQUIP_TOOL then
        local tool = character:FindFirstChildOfClass("Tool")
        if not tool and not cachedTool then
            for _, item in ipairs(player.Backpack:GetChildren()) do
                if item:IsA("Tool") then
                    item.Parent = character
                    cachedTool = item
                    break
                end
            end
        elseif tool then
            cachedTool = tool
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
-- START / STOP AUTOFARM
-- ============================================================
local function startAutoFarm()
    if isRunning then return end
    isRunning = true
    log("Started! Mode: LOCK di atas kepala", Color3.fromRGB(0, 255, 100))
    
    task.spawn(function()
        local emptyCount = 0
        
        while isRunning do
            if not character or not character.Parent then
                character = player.Character or player.CharacterAdded:Wait()
                humanoidRootPart = character:WaitForChild("HumanoidRootPart")
                humanoid = character:WaitForChild("Humanoid")
                cachedTool = nil
            end
            
            local npcs = getAllNPCs()
            
            if #npcs > 0 then
                emptyCount = 0
                currentTarget = npcs[1]
                
                local targetName = currentTarget.model.Name
                log("Target: " .. targetName, Color3.fromRGB(0, 200, 255))
                
                lockToNPC(currentTarget)
                task.wait(0.1)
                
                local killTimeout = tick() + 30
                while currentTarget and currentTarget.humanoid 
                    and currentTarget.humanoid.Health > 0 
                    and isRunning 
                    and tick() < killTimeout do
                    
                    lockToNPC(currentTarget)
                    attackNPC(currentTarget)
                    
                    if not currentTarget.model or not currentTarget.model.Parent then
                        break
                    end
                    
                    task.wait(CONFIG.LOCK_UPDATE_RATE)
                end
                
                log("✓ Killed: " .. targetName, Color3.fromRGB(100, 255, 100))
            else
                emptyCount = emptyCount + 1
                if emptyCount % 10 == 0 then
                    log("Nunggu NPC...", Color3.fromRGB(255, 200, 100))
                end
                task.wait(2)
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
-- PLANT COLLECTOR - INSTANT (TANPA TELEPORT)
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

-- Kumpulin semua ProximityPrompt & ClickDetector dari objek yang namanya plant
local function collectAllPlants()
    local collected = 0
    local foundTypes = {}
    
    for _, obj in ipairs(workspace:GetDescendants()) do
        local ok, plantType = isPlantName(obj.Name)
        if ok then
            local didCollect = false
            
            -- CARA 1: ProximityPrompt langsung
            pcall(function()
                local prompt = obj:FindFirstChildOfClass("ProximityPrompt")
                if prompt then
                    if CONFIG.FORCE_PROMPT_DISTANCE then
                        prompt.MaxActivationDistance = 9999
                        prompt.HoldDuration = 0
                    end
                    fireproximityprompt(prompt)
                    didCollect = true
                end
            end)
            
            -- CARA 2: ProximityPrompt di dalam (Model)
            if not didCollect then
                pcall(function()
                    local prompt = obj:FindFirstChildWhichIsA("ProximityPrompt", true)
                    if prompt then
                        if CONFIG.FORCE_PROMPT_DISTANCE then
                            prompt.MaxActivationDistance = 9999
                            prompt.HoldDuration = 0
                        end
                        fireproximityprompt(prompt)
                        didCollect = true
                    end
                end)
            end
            
            -- CARA 3: ClickDetector
            if not didCollect then
                pcall(function()
                    local cd = obj:FindFirstChildOfClass("ClickDetector")
                    if cd then
                        fireclickdetector(cd)
                        didCollect = true
                    end
                end)
            end
            
            -- CARA 4: ClickDetector di dalam
            if not didCollect then
                pcall(function()
                    local cd = obj:FindFirstChildWhichIsA("ClickDetector", true)
                    if cd then
                        fireclickdetector(cd)
                        didCollect = true
                    end
                end)
            end
            
            -- CARA 5: RemoteEvent Fire
            if not didCollect then
                pcall(function()
                    for _, child in ipairs(obj:GetDescendants()) do
                        if child:IsA("RemoteEvent") then
                            child:FireServer()
                            didCollect = true
                        end
                    end
                end)
            end
            
            if didCollect then
                collected = collected + 1
                foundTypes[plantType] = (foundTypes[plantType] or 0) + 1
            end
        end
    end
    
    return collected, foundTypes
end

local function startPlantCollector()
    if isCollectingPlants then return end
    isCollectingPlants = true
    log("🌿 Plant Collector: STARTED (INSTANT)", Color3.fromRGB(150, 255, 100))
    
    task.spawn(function()
        while isCollectingPlants do
            local count, types = collectAllPlants()
            
            if count > 0 then
                collectedPlants = collectedPlants + count
                if PlantCountLabel then
                    PlantCountLabel.Text = "🌿 Collected: " .. collectedPlants
                end
                
                local typeStr = ""
                for t, c in pairs(types) do
                    typeStr = typeStr .. t .. "(" .. c .. ") "
                end
                
                log("✓ Collected " .. count .. ": " .. typeStr, Color3.fromRGB(100, 255, 150))
            else
                log("🌿 Gak ada plant. Nunggu...", Color3.fromRGB(255, 200, 100))
            end
            
            task.wait(CONFIG.PLANT_SCAN_DELAY)
        end
    end)
end

local function stopPlantCollector()
    isCollectingPlants = false
    log("🌿 Plant Collector: STOPPED", Color3.fromRGB(255, 150, 100))
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
MainFrame.Size = UDim2.new(0, 270, 0, 480)  -- Lebih tinggi buat tombol plant
MainFrame.Position = UDim2.new(0, 20, 0, 80)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Visible = true
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 10)
UICorner.Parent = MainFrame

local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 35)
TitleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 55)
TitleBar.BorderSizePixel = 0
TitleBar.Active = true
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -60, 1, 0)
Title.Position = UDim2.new(0, 10, 0, 0)
Title.BackgroundTransparency = 1
Title.TextColor3 = Color3.fromRGB(0, 255, 150)
Title.Text = "🎯 v4.9 - FARM + PLANT"
Title.TextSize = 13
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TitleBar

local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 25, 0, 25)
MinBtn.Position = UDim2.new(1, -55, 0, 5)
MinBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 100)
MinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
MinBtn.Text = "—"
MinBtn.TextSize = 14
MinBtn.Font = Enum.Font.GothamBold
MinBtn.Parent = TitleBar

local MinCorner = Instance.new("UICorner")
MinCorner.CornerRadius = UDim.new(0, 5)
MinCorner.Parent = MinBtn

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 25, 0, 25)
CloseBtn.Position = UDim2.new(1, -28, 0, 5)
CloseBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Text = "×"
CloseBtn.TextSize = 16
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.Parent = TitleBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 5)
CloseCorner.Parent = CloseBtn

-- INFO LABEL
local WLInfo = Instance.new("TextLabel")
WLInfo.Size = UDim2.new(1, -20, 0, 20)
WLInfo.Position = UDim2.new(0, 10, 0, 42)
WLInfo.BackgroundTransparency = 1
WLInfo.TextColor3 = Color3.fromRGB(0, 200, 255)
WLInfo.Text = "🎯 FARM + 🌿 PLANT COLLECTOR"
WLInfo.TextSize = 10
WLInfo.Font = Enum.Font.GothamBold
WLInfo.TextXAlignment = Enum.TextXAlignment.Left
WLInfo.Parent = MainFrame

-- NPC COUNT
local CountLabel = Instance.new("TextLabel")
CountLabel.Size = UDim2.new(1, -20, 0, 20)
CountLabel.Position = UDim2.new(0, 10, 0, 65)
CountLabel.BackgroundTransparency = 1
CountLabel.TextColor3 = Color3.fromRGB(200, 200, 100)
CountLabel.Text = "NPC Target: 0"
CountLabel.TextSize = 11
CountLabel.Font = Enum.Font.Gotham
CountLabel.TextXAlignment = Enum.TextXAlignment.Left
CountLabel.Parent = MainFrame

-- PLANT COUNT
local PlantCountLabel = Instance.new("TextLabel")
PlantCountLabel.Size = UDim2.new(1, -20, 0, 20)
PlantCountLabel.Position = UDim2.new(0, 10, 0, 85)
PlantCountLabel.BackgroundTransparency = 1
PlantCountLabel.TextColor3 = Color3.fromRGB(150, 255, 100)
PlantCountLabel.Text = "🌿 Collected: 0"
PlantCountLabel.TextSize = 10
PlantCountLabel.Font = Enum.Font.Gotham
PlantCountLabel.TextXAlignment = Enum.TextXAlignment.Left
PlantCountLabel.Parent = MainFrame

-- HP LABEL
local HPLabel = Instance.new("TextLabel")
HPLabel.Size = UDim2.new(1, -20, 0, 20)
HPLabel.Position = UDim2.new(0, 10, 0, 105)
HPLabel.BackgroundTransparency = 1
HPLabel.TextColor3 = Color3.fromRGB(150, 255, 150)
HPLabel.Text = "HP: 100/100 (100%)"
HPLabel.TextSize = 10
HPLabel.Font = Enum.Font.Gotham
HPLabel.TextXAlignment = Enum.TextXAlignment.Left
HPLabel.Parent = MainFrame

-- AUTOFARM BUTTON
local ToggleButton = Instance.new("TextButton")
ToggleButton.Size = UDim2.new(1, -20, 0, 40)
ToggleButton.Position = UDim2.new(0, 10, 0, 130)
ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
ToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleButton.Text = "▶ START AUTOFARM"
ToggleButton.TextSize = 13
ToggleButton.Font = Enum.Font.GothamBold
ToggleButton.Parent = MainFrame

local BtnCorner = Instance.new("UICorner")
BtnCorner.CornerRadius = UDim.new(0, 8)
BtnCorner.Parent = ToggleButton

-- PLANT COLLECTOR BUTTON
local PlantToggleBtn = Instance.new("TextButton")
PlantToggleBtn.Size = UDim2.new(1, -20, 0, 40)
PlantToggleBtn.Position = UDim2.new(0, 10, 0, 175)
PlantToggleBtn.BackgroundColor3 = Color3.fromRGB(0, 130, 80)
PlantToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
PlantToggleBtn.Text = "🌿 START PLANT COLLECTOR"
PlantToggleBtn.TextSize = 13
PlantToggleBtn.Font = Enum.Font.GothamBold
PlantToggleBtn.Parent = MainFrame

local PlantBtnCorner = Instance.new("UICorner")
PlantBtnCorner.CornerRadius = UDim.new(0, 8)
PlantBtnCorner.Parent = PlantToggleBtn

-- STATUS
local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -20, 0, 20)
StatusLabel.Position = UDim2.new(0, 10, 0, 220)
StatusLabel.BackgroundTransparency = 1
StatusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
StatusLabel.Text = "Farm: IDLE | Plant: IDLE"
StatusLabel.TextSize = 10
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Parent = MainFrame

-- NPC LIST INFO
local NPCListLabel = Instance.new("TextLabel")
NPCListLabel.Size = UDim2.new(1, -20, 0, 15)
NPCListLabel.Position = UDim2.new(0, 10, 0, 242)
NPCListLabel.BackgroundTransparency = 1
NPCListLabel.TextColor3 = Color3.fromRGB(150, 150, 200)
NPCListLabel.Text = "NPC: Scorpion|Tombguardian|Water Serpent|Tidecrusher"
NPCListLabel.TextSize = 8
NPCListLabel.Font = Enum.Font.Gotham
NPCListLabel.TextXAlignment = Enum.TextXAlignment.Left
NPCListLabel.TextWrapped = true
NPCListLabel.Parent = MainFrame

-- PLANT LIST INFO
local PlantListLabel = Instance.new("TextLabel")
PlantListLabel.Size = UDim2.new(1, -20, 0, 15)
PlantListLabel.Position = UDim2.new(0, 10, 0, 258)
PlantListLabel.BackgroundTransparency = 1
PlantListLabel.TextColor3 = Color3.fromRGB(150, 255, 150)
PlantListLabel.Text = "Plant: Ginseng|Lily|Essence Leaf|Spirit Grass|Lotus"
PlantListLabel.TextSize = 8
PlantListLabel.Font = Enum.Font.Gotham
PlantListLabel.TextXAlignment = Enum.TextXAlignment.Left
PlantListLabel.TextWrapped = true
PlantListLabel.Parent = MainFrame

-- TELEPORT BUTTON
local TeleportBtn = Instance.new("TextButton")
TeleportBtn.Size = UDim2.new(1, -20, 0, 28)
TeleportBtn.Position = UDim2.new(0, 10, 0, 278)
TeleportBtn.BackgroundColor3 = Color3.fromRGB(0, 130, 200)
TeleportBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
TeleportBtn.Text = "⚡ TELEPORT KE MOB"
TeleportBtn.TextSize = 11
TeleportBtn.Font = Enum.Font.GothamBold
TeleportBtn.Parent = MainFrame

local TeleCorner = Instance.new("UICorner")
TeleCorner.CornerRadius = UDim.new(0, 6)
TeleCorner.Parent = TeleportBtn

-- INSTANT COLLECT BUTTON (buat manual collect sekali)
local InstantCollectBtn = Instance.new("TextButton")
InstantCollectBtn.Size = UDim2.new(1, -20, 0, 28)
InstantCollectBtn.Position = UDim2.new(0, 10, 0, 310)
InstantCollectBtn.BackgroundColor3 = Color3.fromRGB(80, 180, 60)
InstantCollectBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
InstantCollectBtn.Text = "⚡ COLLECT ALL SEKARANG"
InstantCollectBtn.TextSize = 11
InstantCollectBtn.Font = Enum.Font.GothamBold
InstantCollectBtn.Parent = MainFrame

local InstCorner = Instance.new("UICorner")
InstCorner.CornerRadius = UDim.new(0, 6)
InstCorner.Parent = InstantCollectBtn

-- RESCAN BUTTON
local RescanBtn = Instance.new("TextButton")
RescanBtn.Size = UDim2.new(1, -20, 0, 28)
RescanBtn.Position = UDim2.new(0, 10, 0, 342)
RescanBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 80)
RescanBtn.TextColor3 = Color3.fromRGB(200, 200, 255)
RescanBtn.Text = "🔄 RESCAN NPC"
RescanBtn.TextSize = 11
RescanBtn.Font = Enum.Font.Gotham
RescanBtn.Parent = MainFrame

local RescanCorner = Instance.new("UICorner")
RescanCorner.CornerRadius = UDim.new(0, 6)
RescanCorner.Parent = RescanBtn

-- LIST BUTTON
local ListBtn = Instance.new("TextButton")
ListBtn.Size = UDim2.new(1, -20, 0, 28)
ListBtn.Position = UDim2.new(0, 10, 0, 374)
ListBtn.BackgroundColor3 = Color3.fromRGB(60, 40, 80)
ListBtn.TextColor3 = Color3.fromRGB(220, 200, 255)
ListBtn.Text = "📋 LIHAT NPC TARGET"
ListBtn.TextSize = 11
ListBtn.Font = Enum.Font.Gotham
ListBtn.Parent = MainFrame

local ListCorner = Instance.new("UICorner")
ListCorner.CornerRadius = UDim.new(0, 6)
ListCorner.Parent = ListBtn

-- CONSOLE BUTTON
local ConsoleBtn = Instance.new("TextButton")
ConsoleBtn.Size = UDim2.new(1, -20, 0, 28)
ConsoleBtn.Position = UDim2.new(0, 10, 0, 406)
ConsoleBtn.BackgroundColor3 = Color3.fromRGB(40, 60, 40)
ConsoleBtn.TextColor3 = Color3.fromRGB(150, 255, 150)
ConsoleBtn.Text = "📋 OPEN CONSOLE"
ConsoleBtn.TextSize = 11
ConsoleBtn.Font = Enum.Font.GothamBold
ConsoleBtn.Parent = MainFrame

local ConsoleCorner = Instance.new("UICorner")
ConsoleCorner.CornerRadius = UDim.new(0, 6)
ConsoleCorner.Parent = ConsoleBtn

-- CREDIT
local Credit = Instance.new("TextLabel")
Credit.Size = UDim2.new(1, 0, 0, 15)
Credit.Position = UDim2.new(0, 0, 1, -15)
Credit.BackgroundTransparency = 1
Credit.TextColor3 = Color3.fromRGB(80, 80, 100)
Credit.Text = "by Kyriel v4.9 - Farm + Plant"
Credit.TextSize = 9
Credit.Font = Enum.Font.Gotham
Credit.Parent = MainFrame

-- ============================================================
-- CONSOLE POPUP
-- ============================================================
ConsolePopup = Instance.new("Frame")
ConsolePopup.Size = UDim2.new(0, 340, 0, 300)
ConsolePopup.Position = UDim2.new(0.5, -170, 0.5, -150)
ConsolePopup.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
ConsolePopup.BorderSizePixel = 0
ConsolePopup.Visible = false
ConsolePopup.ZIndex = 20
ConsolePopup.Active = true
ConsolePopup.Parent = ScreenGui

local ConsoleCorner2 = Instance.new("UICorner")
ConsoleCorner2.CornerRadius = UDim.new(0, 10)
ConsoleCorner2.Parent = ConsolePopup

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
ListPopup.Size = UDim2.new(0, 300, 0, 300)
ListPopup.Position = UDim2.new(0.5, -150, 0.5, -150)
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
        lbl.Text = "❌ Gak ada NPC target saat ini"
        lbl.TextSize = 11
        lbl.Font = Enum.Font.Gotham
        lbl.Parent = ListScroll
        return
    end
    
    for i, npc in ipairs(npcs) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -6, 0, 30)
        btn.BackgroundColor3 = Color3.fromRGB(40, 60, 80)
        btn.TextColor3 = Color3.fromRGB(150, 255, 200)
        btn.Text = string.format("%d. %s (HP: %d) [%.0f]", 
            i, npc.model.Name, math.floor(npc.humanoid.Health), npc.distance)
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
            else
                log("❌ NPC udah ilang", Color3.fromRGB(255, 100, 100))
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
Bubble.BackgroundColor3 = Color3.fromRGB(0, 170, 100)
Bubble.TextColor3 = Color3.fromRGB(255, 255, 255)
Bubble.Text = "🎯"
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
-- SCAN AWAL
-- ============================================================
log("==================================================", Color3.fromRGB(0, 200, 255))
log("  AUTOFARM v4.9 - FARM + PLANT", Color3.fromRGB(0, 200, 255))
log("  Plant: Ginseng, Lily, Essence Leaf,", Color3.fromRGB(0, 200, 255))
log("         Spirit Grass, Lotus", Color3.fromRGB(0, 200, 255))
log("==================================================", Color3.fromRGB(0, 200, 255))

detectedFolders = detectNPCFolders()

if #detectedFolders > 0 then
    for i, folder in ipairs(detectedFolders) do
        log(string.format("[%d] %s -> %d NPC", i, folder.name, folder.count), Color3.fromRGB(200, 200, 100))
    end
else
    log("WARNING: Gak ada NPC target terdeteksi!", Color3.fromRGB(255, 100, 100))
end

-- ============================================================
-- REAL-TIME UPDATE
-- ============================================================
task.spawn(function()
    while task.wait(2) do
        if humanoid and humanoid.Parent then
            local hpPct = math.floor((humanoid.Health / humanoid.MaxHealth) * 100)
            HPLabel.Text = string.format("HP: %d/%d (%d%%)", 
                math.floor(humanoid.Health), 
                math.floor(humanoid.MaxHealth), 
                hpPct)
            
            if hpPct < 30 then
                HPLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
            elseif hpPct < 60 then
                HPLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
            else
                HPLabel.TextColor3 = Color3.fromRGB(150, 255, 150)
            end
        end
    end
end)

task.spawn(function()
    while task.wait(CONFIG.SCAN_INTERVAL) do
        if not isRunning then
            local npcs = getAllNPCs()
            CountLabel.Text = "NPC Target: " .. #npcs
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
        ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
        StatusLabel.Text = "Farm: IDLE | Plant: " .. (isCollectingPlants and "RUNNING" or "IDLE")
        StatusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
    else
        startAutoFarm()
        ToggleButton.Text = "⏸ STOP AUTOFARM"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(170, 0, 0)
        StatusLabel.Text = "Farm: LOCKED | Plant: " .. (isCollectingPlants and "RUNNING" or "IDLE")
        StatusLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
    end
end)

PlantToggleBtn.MouseButton1Click:Connect(function()
    if isCollectingPlants then
        stopPlantCollector()
        PlantToggleBtn.Text = "🌿 START PLANT COLLECTOR"
        PlantToggleBtn.BackgroundColor3 = Color3.fromRGB(0, 130, 80)
        StatusLabel.Text = "Farm: " .. (isRunning and "LOCKED" or "IDLE") .. " | Plant: IDLE"
    else
        startPlantCollector()
        PlantToggleBtn.Text = "⏸ STOP PLANT COLLECTOR"
        PlantToggleBtn.BackgroundColor3 = Color3.fromRGB(130, 60, 0)
        StatusLabel.Text = "Farm: " .. (isRunning and "LOCKED" or "IDLE") .. " | Plant: RUNNING"
    end
end)

InstantCollectBtn.MouseButton1Click:Connect(function()
    log("⚡ Manual collect...", Color3.fromRGB(0, 255, 200))
    InstantCollectBtn.Text = "⚡ COLLECTING..."
    InstantCollectBtn.BackgroundColor3 = Color3.fromRGB(50, 100, 30)
    
    local count, types = collectAllPlants()
    collectedPlants = collectedPlants + count
    PlantCountLabel.Text = "🌿 Collected: " .. collectedPlants
    
    if count > 0 then
        log("✓ Collected " .. count .. " plant", Color3.fromRGB(100, 255, 150))
    else
        log("❌ Gak ada plant ditemukan", Color3.fromRGB(255, 100, 100))
    end
    
    InstantCollectBtn.Text = "✓ +" .. count
    task.wait(1)
    InstantCollectBtn.Text = "⚡ COLLECT ALL SEKARANG"
    InstantCollectBtn.BackgroundColor3 = Color3.fromRGB(80, 180, 60)
end)

TeleportBtn.MouseButton1Click:Connect(function()
    local npcs = getAllNPCs()
    if #npcs > 0 then
        local target = npcs[1]
        teleportToNPC(target)
        log("⚡ Teleport ke: " .. target.model.Name, Color3.fromRGB(0, 200, 255))
        TeleportBtn.Text = "✓ KE " .. target.model.Name
        task.wait(1)
        TeleportBtn.Text = "⚡ TELEPORT KE MOB"
    else
        log("❌ Gak ada NPC target!", Color3.fromRGB(255, 100, 100))
        TeleportBtn.Text = "❌ GAK ADA NPC"
        task.wait(1)
        TeleportBtn.Text = "⚡ TELEPORT KE MOB"
    end
end)

RescanBtn.MouseButton1Click:Connect(function()
    log("Rescanning NPC...", Color3.fromRGB(0, 200, 255))
    RescanBtn.Text = "🔄 SCANNING..."
    task.wait(0.1)
    detectedFolders = detectNPCFolders()
    
    if #detectedFolders > 0 then
        log("Rescan done.", Color3.fromRGB(0, 255, 100))
    end
    
    RescanBtn.Text = "🔄 RESCAN NPC"
end)

ListBtn.MouseButton1Click:Connect(function()
    refreshNPCList()
    ListPopup.Visible = not ListPopup.Visible
end)

ListClose.MouseButton1Click:Connect(function()
    ListPopup.Visible = false
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
        MainFrame.Size = UDim2.new(0, 270, 0, 35)
        MinBtn.Text = "□"
    else
        MainFrame.Size = UDim2.new(0, 270, 0, 480)
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
-- DONE
-- ============================================================
log("✅ Script loaded!", Color3.fromRGB(0, 255, 100))
log("💡 Farm: Klik START AUTOFARM", Color3.fromRGB(200, 200, 100))
log("💡 Plant: Klik START PLANT COLLECTOR", Color3.fromRGB(200, 200, 100))
log("💡 Manual: Klik COLLECT ALL SEKARANG", Color3.fromRGB(200, 200, 100))
