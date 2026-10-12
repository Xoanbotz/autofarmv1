--[[
=========================================================
  UNIVERSAL AUTOFARM v4.3 - WHITELIST MODE
  Author: Kyriel (for Boss)
  Executor: Delta / Codex / Wave / Xeno
=========================================================

WHITELIST: Cuma serang NPC ini:
  - Scorpion
  - Tombguardian
  - Water Serpent
  - Tidecrusher Crab

Selain itu SKIP TOTAL.
=========================================================
]]

-- ============================================================
-- SERVICE
-- ============================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
local humanoid = character:WaitForChild("Humanoid")

-- ============================================================
-- KONFIGURASI
-- ============================================================
local CONFIG = {
    NPC_FOLDER_NAME = nil,
    ATTACK_RANGE = 100,
    TELEPORT_HEIGHT = 3,
    ATTACK_COOLDOWN = 0.15,
    LOOP_DELAY = 0.3,
    AUTO_EQUIP_TOOL = true,
    USE_SKILLS = true,
    SKILL_KEYS = {"Z", "X", "C", "V", "F"},
    SKILL_COOLDOWN = 1.5,
    DEBUG = true,
    -- WAJIB "whitelist" biar cuma serang 4 NPC itu
    DETECTION_MODE = "whitelist",
    -- WHITELIST: cuma serang NPC yang namanya ADA SALAH SATU kata ini
    NPC_WHITELIST = {
        "Scorpion",
        "Tombguardian",
        "TombGuardian",
        "Water Serpent",
        "WaterSerpent",
        "Tidecrusher Crab",
        "TidecrusherCrab",
        "Tidecrusher",
    },
    NPC_BLACKLIST = {},
}

local isRunning = false
local currentTarget = nil
local lastSkillTime = 0
local detectedFolders = {}
local skippedCount = 0
local scanLog = {}

-- ============================================================
-- LOG SYSTEM
-- ============================================================
local LogScroll = nil

local function log(msg, color)
    msg = tostring(msg)
    if CONFIG.DEBUG then
        print("[Autofarm] " .. msg)
    end
    
    if LogScroll and LogScroll.Parent then
        local newLabel = Instance.new("TextLabel")
        newLabel.Size = UDim2.new(1, -6, 0, 0)
        newLabel.AutomaticSize = Enum.AutomaticSize.Y
        newLabel.BackgroundTransparency = 1
        newLabel.TextColor3 = color or Color3.fromRGB(150, 255, 150)
        newLabel.Text = "> " .. msg
        newLabel.TextSize = 10
        newLabel.Font = Enum.Font.Code
        newLabel.TextXAlignment = Enum.TextXAlignment.Left
        newLabel.TextWrapped = true
        newLabel.Parent = LogScroll
        
        task.wait()
        LogScroll.CanvasPosition = Vector2.new(0, LogScroll.AbsoluteCanvasSize.Y)
        
        local count = 0
        for _, child in ipairs(LogScroll:GetChildren()) do
            if child:IsA("TextLabel") then count = count + 1 end
        end
        if count > 100 then
            for _, child in ipairs(LogScroll:GetChildren()) do
                if child:IsA("TextLabel") then
                    child:Destroy()
                    break
                end
            end
        end
    end
end

-- ============================================================
-- SMART FILTER NPC - WHITELIST MODE
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
    
    -- FILTER MaxHealth
    if hum.MaxHealth <= 0 then
        return false, "MaxHealth=0"
    end
    if hum.MaxHealth == math.huge or hum.MaxHealth > 1e9 then
        return false, "invincible"
    end
    
    -- FILTER ATRIBUT
    for _, attr in ipairs({"Invincible", "IsQuestGiver", "IsFriendly", "IsPassive", "NoDamage"}) do
        if hum:GetAttribute(attr) == true then
            return false, "attr " .. attr
        end
        if model:GetAttribute(attr) == true then
            return false, "attr " .. attr
        end
    end
    
    -- ========================================
    -- WHITELIST CHECK (INI YANG PALING PENTING)
    -- ========================================
    local modelName = model.Name
    local nameLower = string.lower(modelName)
    
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
    
    -- FILTER ROOT PART
    local root = model:FindFirstChild("HumanoidRootPart") 
        or model:FindFirstChild("Head") 
        or model:FindFirstChild("Torso")
        or model:FindFirstChild("UpperTorso")
    
    if not root then
        return false, "no root part"
    end
    
    -- LULUS
    return true, string.format("✅ %s (HP:%d)", matchedName, math.floor(hum.Health))
end

local function isNPC(model)
    local result, reason = checkNPC(model)
    return result
end

-- ============================================================
-- DETEKSI FOLDER NPC
-- ============================================================
local function detectNPCFolders()
    local folderCount = {}
    skippedCount = 0
    scanLog = {}
    
    local function scan(instance, depth)
        depth = depth or 0
        if depth > 6 then return end
        
        for _, obj in ipairs(instance:GetChildren()) do
            if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") then
                local ok, reason = checkNPC(obj)
                if ok then
                    local parentName = obj.Parent and obj.Parent.Name or "Workspace"
                    folderCount[parentName] = (folderCount[parentName] or 0) + 1
                else
                    skippedCount = skippedCount + 1
                    if #scanLog < 30 then
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
        log("--- Skip Log (max 30) ---", Color3.fromRGB(255, 200, 100))
        for _, entry in ipairs(scanLog) do
            log(entry, Color3.fromRGB(255, 150, 150))
        end
        log("--- End Skip Log ---", Color3.fromRGB(255, 200, 100))
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
        depth = depth or 0
        if depth > 6 then return end
        
        for _, obj in ipairs(instance:GetChildren()) do
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
            
            if obj:IsA("Folder") or obj:IsA("Model") then
                if #obj:GetChildren() > 0 and not obj:FindFirstChildOfClass("Humanoid") then
                    scan(obj, depth + 1)
                end
            end
        end
    end
    
    scan(workspace, 0)
    
    table.sort(npcs, function(a, b) return a.distance < b.distance end)
    return npcs
end

-- ============================================================
-- TELEPORT
-- ============================================================
local function teleportToNPC(npc)
    if not npc or not npc.root or not npc.root.Parent then return false end
    
    if not character or not character.Parent then
        character = player.Character or player.CharacterAdded:Wait()
        humanoidRootPart = character:WaitForChild("HumanoidRootPart")
        humanoid = character:WaitForChild("Humanoid")
    end
    
    if not humanoidRootPart or not humanoidRootPart.Parent then return false end
    
    local targetPos = npc.root.Position + Vector3.new(0, CONFIG.TELEPORT_HEIGHT, 0)
    
    pcall(function()
        humanoidRootPart.CFrame = CFrame.new(targetPos)
        humanoidRootPart.Velocity = Vector3.new(0, 0, 0)
    end)
    
    return true
end

-- ============================================================
-- SERANG
-- ============================================================
local function attackNPC(npc)
    if not npc or not npc.model or not npc.model.Parent then return end
    if not npc.humanoid or npc.humanoid.Health <= 0 then return end
    
    if CONFIG.AUTO_EQUIP_TOOL then
        local tool = character:FindFirstChildOfClass("Tool")
        if not tool then
            for _, item in ipairs(player.Backpack:GetChildren()) do
                if item:IsA("Tool") then
                    item.Parent = character
                    task.wait(0.05)
                    break
                end
            end
        end
    end
    
    local tool = character:FindFirstChildOfClass("Tool")
    if tool then
        pcall(function() tool:Activate() end)
    end
    
    pcall(function()
        VirtualUser:Button1Down(Vector2.new(0, 0))
        task.wait(0.03)
        VirtualUser:Button1Up(Vector2.new(0, 0))
    end)
    
    if CONFIG.USE_SKILLS and tick() - lastSkillTime > CONFIG.SKILL_COOLDOWN then
        for _, key in ipairs(CONFIG.SKILL_KEYS) do
            pcall(function()
                VirtualUser:Button1Down(Vector2.new(0, 0))
                task.wait(0.05)
                VirtualUser:Button1Up(Vector2.new(0, 0))
            end)
        end
        lastSkillTime = tick()
    end
end

-- ============================================================
-- START / STOP
-- ============================================================
local function startAutoFarm()
    if isRunning then return end
    isRunning = true
    log("Started! Cari: Scorpion, Tombguardian, Water Serpent, Tidecrusher Crab", Color3.fromRGB(0, 255, 100))
    
    task.spawn(function()
        local emptyCount = 0
        
        while isRunning do
            if not character or not character.Parent then
                character = player.Character or player.CharacterAdded:Wait()
                humanoidRootPart = character:WaitForChild("HumanoidRootPart")
                humanoid = character:WaitForChild("Humanoid")
            end
            
            local npcs = getAllNPCs()
            
            if #npcs > 0 then
                emptyCount = 0
                currentTarget = npcs[1]
                
                local targetName = currentTarget.model.Name
                log("Target: " .. targetName, Color3.fromRGB(0, 200, 255))
                
                teleportToNPC(currentTarget)
                task.wait(0.1)
                
                local killTimeout = tick() + 15
                while currentTarget and currentTarget.humanoid 
                    and currentTarget.humanoid.Health > 0 
                    and isRunning 
                    and tick() < killTimeout do
                    
                    attackNPC(currentTarget)
                    task.wait(CONFIG.ATTACK_COOLDOWN)
                    
                    if not currentTarget.model or not currentTarget.model.Parent then
                        break
                    end
                    
                    if currentTarget.root and currentTarget.root.Parent then
                        local dist = (humanoidRootPart.Position - currentTarget.root.Position).Magnitude
                        if dist > CONFIG.ATTACK_RANGE then
                            teleportToNPC(currentTarget)
                        end
                    end
                end
                
                log("✓ Killed: " .. targetName, Color3.fromRGB(100, 255, 100))
            else
                emptyCount = emptyCount + 1
                if emptyCount % 5 == 0 then
                    log("Gak ada NPC target. Nunggu...", Color3.fromRGB(255, 200, 100))
                end
                task.wait(1)
            end
            
            task.wait(CONFIG.LOOP_DELAY)
        end
    end)
end

local function stopAutoFarm()
    isRunning = false
    currentTarget = nil
    log("Stopped.", Color3.fromRGB(255, 100, 100))
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
MainFrame.Size = UDim2.new(0, 260, 0, 375)
MainFrame.Position = UDim2.new(0, 20, 0, 100)
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
Title.Text = "🎯 AUTOFARM v4.3"
Title.TextSize = 14
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

-- Whitelist Info
local WLInfo = Instance.new("TextLabel")
WLInfo.Size = UDim2.new(1, -20, 0, 20)
WLInfo.Position = UDim2.new(0, 10, 0, 42)
WLInfo.BackgroundTransparency = 1
WLInfo.TextColor3 = Color3.fromRGB(0, 200, 255)
WLInfo.Text = "🎯 WHITELIST: 4 NPC"
WLInfo.TextSize = 11
WLInfo.Font = Enum.Font.GothamBold
WLInfo.TextXAlignment = Enum.TextXAlignment.Left
WLInfo.Parent = MainFrame

-- NPC Count
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

-- Skipped Count
local SkipLabel = Instance.new("TextLabel")
SkipLabel.Size = UDim2.new(1, -20, 0, 20)
SkipLabel.Position = UDim2.new(0, 10, 0, 85)
SkipLabel.BackgroundTransparency = 1
SkipLabel.TextColor3 = Color3.fromRGB(150, 100, 150)
SkipLabel.Text = "Skipped: 0"
SkipLabel.TextSize = 10
SkipLabel.Font = Enum.Font.Gotham
SkipLabel.TextXAlignment = Enum.TextXAlignment.Left
SkipLabel.Parent = MainFrame

-- Start Button
local ToggleButton = Instance.new("TextButton")
ToggleButton.Size = UDim2.new(1, -20, 0, 45)
ToggleButton.Position = UDim2.new(0, 10, 0, 110)
ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
ToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleButton.Text = "▶ START"
ToggleButton.TextSize = 14
ToggleButton.Font = Enum.Font.GothamBold
ToggleButton.Parent = MainFrame

local BtnCorner = Instance.new("UICorner")
BtnCorner.CornerRadius = UDim.new(0, 8)
BtnCorner.Parent = ToggleButton

-- Status Label
local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -20, 0, 20)
StatusLabel.Position = UDim2.new(0, 10, 0, 160)
StatusLabel.BackgroundTransparency = 1
StatusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
StatusLabel.Text = "Status: IDLE"
StatusLabel.TextSize = 11
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Parent = MainFrame

-- Info NPC List
local NPCListLabel = Instance.new("TextLabel")
NPCListLabel.Size = UDim2.new(1, -20, 0, 15)
NPCListLabel.Position = UDim2.new(0, 10, 0, 185)
NPCListLabel.BackgroundTransparency = 1
NPCListLabel.TextColor3 = Color3.fromRGB(150, 150, 200)
NPCListLabel.Text = "Scorpion | Tombguardian | Water Serpent | Tidecrusher Crab"
NPCListLabel.TextSize = 8
NPCListLabel.Font = Enum.Font.Gotham
NPCListLabel.TextXAlignment = Enum.TextXAlignment.Left
NPCListLabel.TextWrapped = true
NPCListLabel.Parent = MainFrame

-- Rescan Button
local RescanBtn = Instance.new("TextButton")
RescanBtn.Size = UDim2.new(1, -20, 0, 30)
RescanBtn.Position = UDim2.new(0, 10, 0, 205)
RescanBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 80)
RescanBtn.TextColor3 = Color3.fromRGB(200, 200, 255)
RescanBtn.Text = "🔄 RESCAN"
RescanBtn.TextSize = 11
RescanBtn.Font = Enum.Font.Gotham
RescanBtn.Parent = MainFrame

local RescanCorner = Instance.new("UICorner")
RescanCorner.CornerRadius = UDim.new(0, 6)
RescanCorner.Parent = RescanBtn

-- Kill All Button
local KillAllBtn = Instance.new("TextButton")
KillAllBtn.Size = UDim2.new(1, -20, 0, 30)
KillAllBtn.Position = UDim2.new(0, 10, 0, 240)
KillAllBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 50)
KillAllBtn.TextColor3 = Color3.fromRGB(255, 200, 200)
KillAllBtn.Text = "⚔ KILL SEMUA TARGET"
KillAllBtn.TextSize = 11
KillAllBtn.Font = Enum.Font.Gotham
KillAllBtn.Parent = MainFrame

local KillCorner = Instance.new("UICorner")
KillCorner.CornerRadius = UDim.new(0, 6)
KillCorner.Parent = KillAllBtn

-- Show List Button
local ListBtn = Instance.new("TextButton")
ListBtn.Size = UDim2.new(1, -20, 0, 30)
ListBtn.Position = UDim2.new(0, 10, 0, 275)
ListBtn.BackgroundColor3 = Color3.fromRGB(60, 40, 80)
ListBtn.TextColor3 = Color3.fromRGB(220, 200, 255)
ListBtn.Text = "📋 LIHAT NPC TARGET"
ListBtn.TextSize = 11
ListBtn.Font = Enum.Font.Gotham
ListBtn.Parent = MainFrame

local ListCorner = Instance.new("UICorner")
ListCorner.CornerRadius = UDim.new(0, 6)
ListCorner.Parent = ListBtn

-- Console Button
local ConsoleBtn = Instance.new("TextButton")
ConsoleBtn.Size = UDim2.new(1, -20, 0, 30)
ConsoleBtn.Position = UDim2.new(0, 10, 0, 310)
ConsoleBtn.BackgroundColor3 = Color3.fromRGB(40, 60, 40)
ConsoleBtn.TextColor3 = Color3.fromRGB(150, 255, 150)
ConsoleBtn.Text = "📋 OPEN CONSOLE"
ConsoleBtn.TextSize = 11
ConsoleBtn.Font = Enum.Font.GothamBold
ConsoleBtn.Parent = MainFrame

local ConsoleCorner = Instance.new("UICorner")
ConsoleCorner.CornerRadius = UDim.new(0, 6)
ConsoleCorner.Parent = ConsoleBtn

-- Credit
local Credit = Instance.new("TextLabel")
Credit.Size = UDim2.new(1, 0, 0, 15)
Credit.Position = UDim2.new(0, 0, 1, -15)
Credit.BackgroundTransparency = 1
Credit.TextColor3 = Color3.fromRGB(80, 80, 100)
Credit.Text = "by Kyriel v4.3 - Whitelist Mode"
Credit.TextSize = 9
Credit.Font = Enum.Font.Gotham
Credit.Parent = MainFrame

-- ============================================================
-- CONSOLE POPUP
-- ============================================================
local ConsolePopup = Instance.new("Frame")
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
ListPopup.Size = UDim2.new(0, 300, 0, 250)
ListPopup.Position = UDim2.new(0.5, -150, 0.5, -125)
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
ListTitleLabel.Text = "🎯 NPC TARGET AKTIF"
ListTitleLabel.TextSize = 12
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
ListLayout.Padding = UDim.new(0, 2)
ListLayout.Parent = ListScroll

local function refreshNPCList()
    for _, child in ipairs(ListScroll:GetChildren()) do
        if child:IsA("TextLabel") then
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
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -6, 0, 20)
        lbl.BackgroundTransparency = 1
        lbl.TextColor3 = Color3.fromRGB(150, 255, 150)
        lbl.Text = string.format("%d. %s (HP: %d) [%.0f studs]", 
            i, npc.model.Name, math.floor(npc.humanoid.Health), npc.distance)
        lbl.TextSize = 11
        lbl.Font = Enum.Font.Code
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = ListScroll
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
log("  AUTOFARM v4.3 - WHITELIST MODE", Color3.fromRGB(0, 200, 255))
log("  Target: Scorpion, Tombguardian,", Color3.fromRGB(0, 200, 255))
log("          Water Serpent, Tidecrusher Crab", Color3.fromRGB(0, 200, 255))
log("==================================================", Color3.fromRGB(0, 200, 255))

detectedFolders = detectNPCFolders()

if #detectedFolders > 0 then
    log("NPC target ketemu di folder:", Color3.fromRGB(150, 255, 150))
    for i, folder in ipairs(detectedFolders) do
        log(string.format("   [%d] %s -> %d NPC", i, folder.name, folder.count), Color3.fromRGB(200, 200, 100))
    end
    CONFIG.NPC_FOLDER_NAME = detectedFolders[1].name
    log("Total skipped: " .. skippedCount, Color3.fromRGB(200, 150, 200))
else
    log("WARNING: Gak ada NPC target terdeteksi!", Color3.fromRGB(255, 100, 100))
    log("Coba pake RESCAN atau pastikan nama NPC-nya bener.", Color3.fromRGB(255, 200, 100))
end

log("==================================================", Color3.fromRGB(0, 200, 255))

-- ============================================================
-- REAL-TIME UPDATE
-- ============================================================
task.spawn(function()
    while task.wait(2) do
        local npcs = getAllNPCs()
        CountLabel.Text = "NPC Target: " .. #npcs
        SkipLabel.Text = "Skipped: " .. skippedCount
    end
end)

-- ============================================================
-- EVENT HANDLERS
-- ============================================================
ToggleButton.MouseButton1Click:Connect(function()
    if isRunning then
        stopAutoFarm()
        ToggleButton.Text = "▶ START"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
        StatusLabel.Text = "Status: IDLE"
        StatusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
    else
        startAutoFarm()
        ToggleButton.Text = "⏸ STOP"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(170, 0, 0)
        StatusLabel.Text = "Status: RUNNING"
        StatusLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
    end
end)

RescanBtn.MouseButton1Click:Connect(function()
    log("Rescanning...", Color3.fromRGB(0, 200, 255))
    RescanBtn.Text = "🔄 SCANNING..."
    task.wait(0.1)
    detectedFolders = detectNPCFolders()
    
    if #detectedFolders > 0 then
        CONFIG.NPC_FOLDER_NAME = detectedFolders[1].name
        log("Rescan done. Total skipped: " .. skippedCount, Color3.fromRGB(0, 255, 100))
    end
    
    RescanBtn.Text = "🔄 RESCAN"
end)

KillAllBtn.MouseButton1Click:Connect(function()
    log("Kill all target mode...", Color3.fromRGB(255, 150, 100))
    KillAllBtn.Text = "⚔ KILLING..."
    
    task.spawn(function()
        local npcs = getAllNPCs()
        for _, npc in ipairs(npcs) do
            if not isRunning then break end
            teleportToNPC(npc)
            task.wait(0.05)
            
            local timeout = tick() + 5
            while npc.humanoid and npc.humanoid.Health > 0 and tick() < timeout do
                attackNPC(npc)
                task.wait(0.1)
                if not npc.model or not npc.model.Parent then break end
            end
        end
        
        KillAllBtn.Text = "⚔ KILL SEMUA TARGET"
        log("Kill all done!", Color3.fromRGB(0, 255, 100))
    end)
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
end)

ConsoleClose.MouseButton1Click:Connect(function()
    ConsolePopup.Visible = false
end)

MinBtn.MouseButton1Click:Connect(function()
    if MainFrame.Size.Y.Offset > 50 then
        MainFrame.Size = UDim2.new(0, 260, 0, 35)
        MinBtn.Text = "□"
    else
        MainFrame.Size = UDim2.new(0, 260, 0, 375)
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
log("💡 Cuma serang: Scorpion, Tombguardian, Water Serpent, Tidecrusher Crab", Color3.fromRGB(200, 200, 100))
log("💡 Klik '📋 LIHAT NPC TARGET' buat liat NPC yang ke-detect", Color3.fromRGB(200, 200, 100))
