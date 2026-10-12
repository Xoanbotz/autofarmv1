--[[
=========================================================
  UNIVERSAL AUTOFARM v4.1 - ON-SCREEN CONSOLE
  Author: Kyriel (for Boss)
  Executor: Delta / Codex / Wave / Xeno
=========================================================

FITUR:
  - Smart NPC detection (multi-layer filter)
  - Manual folder picker
  - ON-SCREEN CONSOLE (buat Android, gak perlu F9)
  - Floating bubble GUI
  - Anti-quest-giver
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
    DETECTION_MODE = "smart",
    NPC_WHITELIST = {},
    NPC_BLACKLIST = {},
}

local isRunning = false
local currentTarget = nil
local lastSkillTime = 0
local detectedFolders = {}
local skippedCount = 0
local scanLog = {}

-- ============================================================
-- LOG SYSTEM (KE CONSOLE + GUI)
-- ============================================================
local LogScroll = nil  -- Bakal diisi nanti pas GUI dibikin

local function log(msg, color)
    msg = tostring(msg)
    if CONFIG.DEBUG then
        print("[Autofarm] " .. msg)
    end
    
    -- Tampilin di GUI console kalo udah ada
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
        
        -- Auto-scroll ke bawah
        task.wait()
        LogScroll.CanvasPosition = Vector2.new(0, LogScroll.AbsoluteCanvasSize.Y)
        
        -- Limit 100 log
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
-- BLACKLIST KEYWORDS
-- ============================================================
local BLACKLIST_KEYWORDS = {
    "quest", "vendor", "shop", "merchant", "trader",
    "dialog", "interact", "friendly", "ally", "civilian",
    "npc_quest", "npcquest", "questgiver", "quest_giver",
    "shopkeeper", "blacksmith", "innkeeper", "healer",
    "trainer", "banker", "auctioneer", "guard"
}

-- ============================================================
-- SMART FILTER NPC
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
        return false, "no health (quest giver)"
    end
    
    if hum.MaxHealth == math.huge then
        return false, "invincible"
    end
    
    for _, attr in ipairs({"Invincible", "IsQuestGiver", "IsFriendly", "IsPassive", "NoDamage"}) do
        if hum:GetAttribute(attr) == true then
            return false, "attribute " .. attr
        end
        if model:GetAttribute(attr) == true then
            return false, "attribute " .. attr
        end
    end
    
    if hum:GetAttribute("CanBeDamaged") == false then
        return false, "CanBeDamaged=false"
    end
    if hum:GetAttribute("Damageable") == false then
        return false, "Damageable=false"
    end
    
    local nameLower = string.lower(model.Name)
    for _, keyword in ipairs(BLACKLIST_KEYWORDS) do
        if string.find(nameLower, keyword) then
            return false, "name contains '" .. keyword .. "'"
        end
    end
    for _, keyword in ipairs(CONFIG.NPC_BLACKLIST) do
        if string.find(nameLower, string.lower(keyword)) then
            return false, "blacklist: " .. keyword
        end
    end
    
    if model.Parent then
        local parentLower = string.lower(model.Parent.Name)
        for _, keyword in ipairs({"quest", "vendor", "shop", "friendly", "passive", "civilian"}) do
            if string.find(parentLower, keyword) then
                return false, "parent contains '" .. keyword .. "'"
            end
        end
    end
    
    local tags = CollectionService:GetTags(model)
    for _, tag in ipairs(tags) do
        local tagLower = string.lower(tag)
        for _, keyword in ipairs({"quest", "friendly", "passive", "vendor", "invincible"}) do
            if string.find(tagLower, keyword) then
                return false, "tag: " .. tag
            end
        end
    end
    
    local hasHealthBar = false
    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("BillboardGui") then
            for _, sub in ipairs(desc:GetDescendants()) do
                if sub:IsA("TextLabel") or sub:IsA("Frame") then
                    if string.find(string.lower(sub.Name), "health") 
                        or string.find(string.lower(sub.Name), "hp") then
                        hasHealthBar = true
                        break
                    end
                end
            end
        end
        if hasHealthBar then break end
    end
    
    local walkSpeed = hum.WalkSpeed
    
    local root = model:FindFirstChild("HumanoidRootPart") 
        or model:FindFirstChild("Head") 
        or model:FindFirstChild("Torso")
        or model:FindFirstChild("UpperTorso")
    
    if not root then
        return false, "no root part"
    end
    
    return true, "OK (HP:" .. math.floor(hum.Health) .. "/" .. math.floor(hum.MaxHealth) .. ", WS:" .. walkSpeed .. ", HPBar:" .. tostring(hasHealthBar) .. ")"
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
    local folderDetail = {}
    skippedCount = 0
    scanLog = {}
    
    local function scan(instance, depth)
        depth = depth or 0
        if depth > 5 then return end
        
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
        if depth > 5 then return end
        
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
    
    if CONFIG.DETECTION_MODE == "folder" and CONFIG.NPC_FOLDER_NAME then
        local folder = workspace:FindFirstChild(CONFIG.NPC_FOLDER_NAME)
        if folder then
            scan(folder, 0)
        else
            scan(workspace, 0)
        end
    else
        scan(workspace, 0)
    end
    
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
    log("Started!", Color3.fromRGB(0, 255, 100))
    
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
                
                teleportToNPC(currentTarget)
                task.wait(0.1)
                
                local killTimeout = tick() + 10
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
                
                log("NPC killed: " .. tostring(currentTarget and currentTarget.model and currentTarget.model.Name), Color3.fromRGB(100, 255, 100))
            else
                emptyCount = emptyCount + 1
                if emptyCount % 5 == 0 then
                    log("Gak ada NPC. Nunggu...", Color3.fromRGB(255, 200, 100))
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

-- Main Frame
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

-- Title Bar
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
Title.Text = "🎯 AUTOFARM v4.1"
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

-- Folder Label
local FolderLabel = Instance.new("TextLabel")
FolderLabel.Size = UDim2.new(1, -20, 0, 20)
FolderLabel.Position = UDim2.new(0, 10, 0, 42)
FolderLabel.BackgroundTransparency = 1
FolderLabel.TextColor3 = Color3.fromRGB(150, 150, 200)
FolderLabel.Text = "Folder: " .. tostring(CONFIG.NPC_FOLDER_NAME or "None")
FolderLabel.TextSize = 11
FolderLabel.Font = Enum.Font.Gotham
FolderLabel.TextXAlignment = Enum.TextXAlignment.Left
FolderLabel.Parent = MainFrame

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

-- Mode Label
local ModeLabel = Instance.new("TextLabel")
ModeLabel.Size = UDim2.new(1, -20, 0, 15)
ModeLabel.Position = UDim2.new(0, 10, 0, 185)
ModeLabel.BackgroundTransparency = 1
ModeLabel.TextColor3 = Color3.fromRGB(150, 150, 200)
ModeLabel.Text = "Detection Mode:"
ModeLabel.TextSize = 10
ModeLabel.Font = Enum.Font.Gotham
ModeLabel.TextXAlignment = Enum.TextXAlignment.Left
ModeLabel.Parent = MainFrame

local ModeBtn = Instance.new("TextButton")
ModeBtn.Size = UDim2.new(1, -20, 0, 25)
ModeBtn.Position = UDim2.new(0, 10, 0, 202)
ModeBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 80)
ModeBtn.TextColor3 = Color3.fromRGB(200, 200, 255)
ModeBtn.Text = "MODE: " .. string.upper(CONFIG.DETECTION_MODE)
ModeBtn.TextSize = 11
ModeBtn.Font = Enum.Font.GothamBold
ModeBtn.Parent = MainFrame

local ModeCorner = Instance.new("UICorner")
ModeCorner.CornerRadius = UDim.new(0, 6)
ModeCorner.Parent = ModeBtn

-- Folder Selector
local FolderBtn = Instance.new("TextButton")
FolderBtn.Size = UDim2.new(1, -20, 0, 25)
FolderBtn.Position = UDim2.new(0, 10, 0, 230)
FolderBtn.BackgroundColor3 = Color3.fromRGB(60, 40, 80)
FolderBtn.TextColor3 = Color3.fromRGB(220, 200, 255)
FolderBtn.Text = "📁 SELECT FOLDER"
FolderBtn.TextSize = 11
FolderBtn.Font = Enum.Font.GothamBold
FolderBtn.Parent = MainFrame

local FolderCorner = Instance.new("UICorner")
FolderCorner.CornerRadius = UDim.new(0, 6)
FolderCorner.Parent = FolderBtn

-- Rescan Button
local RescanBtn = Instance.new("TextButton")
RescanBtn.Size = UDim2.new(1, -20, 0, 25)
RescanBtn.Position = UDim2.new(0, 10, 0, 260)
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
KillAllBtn.Size = UDim2.new(1, -20, 0, 25)
KillAllBtn.Position = UDim2.new(0, 10, 0, 290)
KillAllBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 50)
KillAllBtn.TextColor3 = Color3.fromRGB(255, 200, 200)
KillAllBtn.Text = "⚔ KILL SEMUA"
KillAllBtn.TextSize = 11
KillAllBtn.Font = Enum.Font.Gotham
KillAllBtn.Parent = MainFrame

local KillCorner = Instance.new("UICorner")
KillCorner.CornerRadius = UDim.new(0, 6)
KillCorner.Parent = KillAllBtn

-- Console Button
local ConsoleBtn = Instance.new("TextButton")
ConsoleBtn.Size = UDim2.new(1, -20, 0, 25)
ConsoleBtn.Position = UDim2.new(0, 10, 0, 320)
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
Credit.Text = "by Kyriel"
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
ConsoleTitleLabel.Text = "📋 CONSOLE - Debug Log"
ConsoleTitleLabel.TextSize = 12
ConsoleTitleLabel.Font = Enum.Font.GothamBold
ConsoleTitleLabel.TextXAlignment = Enum.TextXAlignment.Left
ConsoleTitleLabel.ZIndex = 22
ConsoleTitleLabel.Parent = ConsoleTitle

-- Clear Button
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

-- Close Button
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

-- Log Scroll
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

-- ============================================================
-- SCAN AWAL (SEKARANG BISA MUNCUL DI GUI CONSOLE)
-- ============================================================
log("==================================================", Color3.fromRGB(0, 200, 255))
log("     AUTOFARM v4.1 - SMART NPC DETECTION", Color3.fromRGB(0, 200, 255))
log("==================================================", Color3.fromRGB(0, 200, 255))

detectedFolders = detectNPCFolders()

if #detectedFolders > 0 then
    log("Folder NPC yang terdeteksi:", Color3.fromRGB(150, 255, 150))
    for i, folder in ipairs(detectedFolders) do
        log(string.format("   [%d] %s -> %d NPC", i, folder.name, folder.count), Color3.fromRGB(200, 200, 100))
    end
    CONFIG.NPC_FOLDER_NAME = detectedFolders[1].name
    log("Auto-select: " .. CONFIG.NPC_FOLDER_NAME, Color3.fromRGB(0, 255, 100))
    log("Total skipped: " .. skippedCount, Color3.fromRGB(200, 150, 200))
else
    log("WARNING: Gak ada NPC musuh terdeteksi!", Color3.fromRGB(255, 100, 100))
    log("Tips: Coba mode 'folder' atau cek Skip Log di atas.", Color3.fromRGB(255, 200, 100))
end

log("==================================================", Color3.fromRGB(0, 200, 255))

-- ============================================================
-- REAL-TIME UPDATE
-- ============================================================
task.spawn(function()
    while task.wait(2) do
        skippedCount = 0
        local npcs = getAllNPCs()
        CountLabel.Text = "NPC Target: " .. #npcs
        SkipLabel.Text = "Skipped: " .. skippedCount
    end
end)

-- ============================================================
-- FOLDER DROPDOWN
-- ============================================================
local FolderDropdown = Instance.new("ScrollingFrame")
FolderDropdown.Size = UDim2.new(0, 200, 0, 150)
FolderDropdown.Position = UDim2.new(0, 30, 0, 340)
FolderDropdown.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
FolderDropdown.BorderSizePixel = 0
FolderDropdown.Visible = false
FolderDropdown.ZIndex = 10
FolderDropdown.Parent = ScreenGui

local FdCorner = Instance.new("UICorner")
FdCorner.CornerRadius = UDim.new(0, 8)
FdCorner.Parent = FolderDropdown

local FdList = Instance.new("UIListLayout")
FdList.Padding = UDim.new(0, 3)
FdList.Parent = FolderDropdown

local function refreshFolderDropdown()
    for _, child in ipairs(FolderDropdown:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end
    
    for i, folder in ipairs(detectedFolders) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -6, 0, 25)
        btn.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
        btn.TextColor3 = Color3.fromRGB(220, 220, 255)
        btn.Text = string.format("%s (%d NPC)", folder.name, folder.count)
        btn.TextSize = 11
        btn.Font = Enum.Font.Gotham
        btn.ZIndex = 11
        btn.Parent = FolderDropdown
        
        local bc = Instance.new("UICorner")
        bc.CornerRadius = UDim.new(0, 4)
        bc.Parent = btn
        
        btn.MouseButton1Click:Connect(function()
            CONFIG.NPC_FOLDER_NAME = folder.name
            FolderLabel.Text = "Folder: " .. folder.name
            FolderDropdown.Visible = false
            log("Folder selected: " .. folder.name, Color3.fromRGB(0, 255, 100))
        end)
    end
end

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

ModeBtn.MouseButton1Click:Connect(function()
    if CONFIG.DETECTION_MODE == "smart" then
        CONFIG.DETECTION_MODE = "folder"
    else
        CONFIG.DETECTION_MODE = "smart"
    end
    ModeBtn.Text = "MODE: " .. string.upper(CONFIG.DETECTION_MODE)
    log("Mode changed to: " .. CONFIG.DETECTION_MODE, Color3.fromRGB(0, 200, 255))
end)

FolderBtn.MouseButton1Click:Connect(function()
    refreshFolderDropdown()
    FolderDropdown.Visible = not FolderDropdown.Visible
end)

RescanBtn.MouseButton1Click:Connect(function()
    log("Rescanning...", Color3.fromRGB(0, 200, 255))
    RescanBtn.Text = "🔄 SCANNING..."
    task.wait(0.1)
    detectedFolders = detectNPCFolders()
    
    if #detectedFolders > 0 then
        CONFIG.NPC_FOLDER_NAME = detectedFolders[1].name
        FolderLabel.Text = "Folder: " .. CONFIG.NPC_FOLDER_NAME
        log("Rescan done. Folder: " .. CONFIG.NPC_FOLDER_NAME, Color3.fromRGB(0, 255, 100))
    else
        FolderLabel.Text = "Folder: NONE"
    end
    
    RescanBtn.Text = "🔄 RESCAN"
end)

KillAllBtn.MouseButton1Click:Connect(function()
    log("Kill all mode...", Color3.fromRGB(255, 150, 100))
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
        
        KillAllBtn.Text = "⚔ KILL SEMUA"
        log("Kill all done!", Color3.fromRGB(0, 255, 100))
    end)
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
log("💡 Klik '📋 OPEN CONSOLE' buat liat log", Color3.fromRGB(200, 200, 100))
log("💡 Kalo NPC salah target, cek Skip Log", Color3.fromRGB(200, 200, 100))
