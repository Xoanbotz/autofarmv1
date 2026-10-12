--[[
=========================================================
  UNIVERSAL AUTOFARM v3.0 - FILTERED NPC + FLOATING BUBBLE
  Author: Kyriel (for Boss)
  Executor: Delta / Codex / Wave / Xeno
=========================================================

FITUR:
  - Filter NPC: cuma serang yang punya darah & bisa damage
  - Skip NPC quest giver, vendor, passive NPC
  - Floating bubble button (bisa digeser)
  - GUI bisa di-hide/show dari bubble
  - Real-time NPC counter
=========================================================
]]

-- ============================================================
-- SERVICE
-- ============================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local TweenService = game:GetService("TweenService")
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
}

local isRunning = false
local currentTarget = nil
local lastSkillTime = 0
local detectedFolders = {}
local skippedCount = 0

-- ============================================================
-- DEBUG LOG
-- ============================================================
local function log(msg)
    if CONFIG.DEBUG then
        print("[Autofarm] " .. tostring(msg))
    end
end

-- ============================================================
-- FILTER NPC: HANYA YANG PUNYA DARAH & DAMAGE-DEALING
-- ============================================================
local function isNPC(model)
    if not model or not model:IsA("Model") then return false end
    
    -- Skip karakter player
    if Players:GetPlayerFromCharacter(model) then return false end
    
    -- Harus punya Humanoid
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    
    -- FILTER 1: Harus hidup
    if hum.Health <= 0 then return false end
    
    -- FILTER 2: MaxHealth harus > 0 (skip quest giver / passive NPC)
    if hum.MaxHealth <= 0 then
        skippedCount = skippedCount + 1
        return false
    end
    
    -- FILTER 3: Cek atribut invincible / quest giver
    if hum:GetAttribute("Invincible") == true then return false end
    if hum:GetAttribute("IsQuestGiver") == true then return false end
    if hum:GetAttribute("CanBeDamaged") == false then return false end
    if hum:GetAttribute("Damageable") == false then return false end
    if model:GetAttribute("Invincible") == true then return false end
    if model:GetAttribute("IsQuestGiver") == true then return false end
    if model:GetAttribute("CanBeDamaged") == false then return false end
    
    -- FILTER 4: Skip berdasarkan nama (quest giver, vendor, dll)
    local nameLower = string.lower(model.Name)
    local blacklist = {
        "quest", "vendor", "shop", "merchant", "trader",
        "dialog", "interact", "friendly", "ally", "civilian",
        "npc_quest", "npcquest", "npcquestgiver", "questgiver",
        "quest_giver", "shopkeeper", "blacksmith", "innkeeper",
        "healer", "trainer", "banker", "auctioneer"
    }
    for _, keyword in ipairs(blacklist) do
        if string.find(nameLower, keyword) then
            skippedCount = skippedCount + 1
            return false
        end
    end
    
    -- FILTER 5: Skip kalo parent name ada keyword quest
    if model.Parent then
        local parentLower = string.lower(model.Parent.Name)
        local parentBlacklist = {"quest", "vendor", "shop", "friendly", "passive", "civilian"}
        for _, keyword in ipairs(parentBlacklist) do
            if string.find(parentLower, keyword) then
                skippedCount = skippedCount + 1
                return false
            end
        end
    end
    
    -- FILTER 6: Cek tag CollectionService
    local tags = CollectionService:GetTags(model)
    for _, tag in ipairs(tags) do
        local tagLower = string.lower(tag)
        if string.find(tagLower, "quest") 
            or string.find(tagLower, "friendly")
            or string.find(tagLower, "passive")
            or string.find(tagLower, "vendor")
            or string.find(tagLower, "invincible") then
            skippedCount = skippedCount + 1
            return false
        end
    end
    
    -- FILTER 7: Harus punya root part
    local root = model:FindFirstChild("HumanoidRootPart") 
        or model:FindFirstChild("Head") 
        or model:FindFirstChild("Torso")
        or model:FindFirstChild("UpperTorso")
    
    if not root then return false end
    
    return true
end

-- ============================================================
-- DETEKSI FOLDER NPC
-- ============================================================
local function detectNPCFolders()
    local folderCount = {}
    skippedCount = 0
    
    local function scan(instance, depth)
        depth = depth or 0
        if depth > 5 then return end
        
        for _, obj in ipairs(instance:GetChildren()) do
            if isNPC(obj) then
                local parentName = obj.Parent and obj.Parent.Name or "Workspace"
                folderCount[parentName] = (folderCount[parentName] or 0) + 1
            end
            
            if obj:IsA("Folder") or obj:IsA("Model") or obj:IsA("Workspace") then
                if #obj:GetChildren() > 0 then
                    scan(obj, depth + 1)
                end
            end
        end
    end
    
    scan(workspace, 0)
    
    local sorted = {}
    for name, count in pairs(folderCount) do
        table.insert(sorted, {name = name, count = count})
    end
    table.sort(sorted, function(a, b) return a.count > b.count end)
    
    return sorted
end

-- ============================================================
-- CARI SEMUA NPC (FILTERED)
-- ============================================================
local function getAllNPCs()
    local npcs = {}
    
    local function scan(instance, depth)
        depth = depth or 0
        if depth > 5 then return end
        
        for _, obj in ipairs(instance:GetChildren()) do
            if isNPC(obj) then
                local hum = obj:FindFirstChildOfClass("Humanoid")
                local root = obj:FindFirstChild("HumanoidRootPart") 
                    or obj:FindFirstChild("Head") 
                    or obj:FindFirstChild("Torso")
                    or obj:FindFirstChild("UpperTorso")
                
                if hum and root and hum.Health > 0 and hum.MaxHealth > 0 then
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
-- TELEPORT KE NPC
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
-- SERANG NPC
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
-- START AUTOFARM
-- ============================================================
local function startAutoFarm()
    if isRunning then return end
    isRunning = true
    log("Started!")
    
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
                
                log("NPC killed. Cari target baru...")
            else
                emptyCount = emptyCount + 1
                if emptyCount % 5 == 0 then
                    log("Gak ada NPC. Nunggu...")
                end
                task.wait(1)
            end
            
            task.wait(CONFIG.LOOP_DELAY)
        end
    end)
end

-- ============================================================
-- STOP AUTOFARM
-- ============================================================
local function stopAutoFarm()
    isRunning = false
    currentTarget = nil
    log("Stopped.")
end

-- ============================================================
-- SCAN AWAL
-- ============================================================
log("==================================================")
log("     AUTOFARM v3.0 - FILTERED NPC + BUBBLE")
log("==================================================")

detectedFolders = detectNPCFolders()

if #detectedFolders > 0 then
    log("Folder NPC yang terdeteksi:")
    for i, folder in ipairs(detectedFolders) do
        log(string.format("   [%d] %s -> %d NPC", i, folder.name, folder.count))
    end
    CONFIG.NPC_FOLDER_NAME = detectedFolders[1].name
    log("Auto-select: " .. CONFIG.NPC_FOLDER_NAME)
else
    log("WARNING: Gak ada NPC terdeteksi!")
end

log("==================================================")

-- ============================================================
-- GUI SETUP
-- ============================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutofarmGUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = player:WaitForChild("PlayerGui")

-- ============================================================
-- MAIN FRAME (GUI UTAMA)
-- ============================================================
local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 240, 0, 260)
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
Title.Text = "🎯 AUTOFARM v3.0"
Title.TextSize = 14
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TitleBar

-- Minimize Button
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

-- Close Button (Hide ke bubble)
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

-- Info Label
local InfoLabel = Instance.new("TextLabel")
InfoLabel.Size = UDim2.new(1, -20, 0, 20)
InfoLabel.Position = UDim2.new(0, 10, 0, 42)
InfoLabel.BackgroundTransparency = 1
InfoLabel.TextColor3 = Color3.fromRGB(150, 150, 200)
InfoLabel.Text = "Folder: " .. tostring(CONFIG.NPC_FOLDER_NAME or "None")
InfoLabel.TextSize = 11
InfoLabel.Font = Enum.Font.Gotham
InfoLabel.TextXAlignment = Enum.TextXAlignment.Left
InfoLabel.Parent = MainFrame

-- NPC Count Label
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

-- Skipped Label
local SkipLabel = Instance.new("TextLabel")
SkipLabel.Size = UDim2.new(1, -20, 0, 20)
SkipLabel.Position = UDim2.new(0, 10, 0, 85)
SkipLabel.BackgroundTransparency = 1
SkipLabel.TextColor3 = Color3.fromRGB(150, 100, 150)
SkipLabel.Text = "Skipped: 0 (Quest/Passive)"
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

-- Rescan Button
local RescanBtn = Instance.new("TextButton")
RescanBtn.Size = UDim2.new(1, -20, 0, 30)
RescanBtn.Position = UDim2.new(0, 10, 0, 185)
RescanBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 80)
RescanBtn.TextColor3 = Color3.fromRGB(200, 200, 255)
RescanBtn.Text = "🔄 RESCAN NPC"
RescanBtn.TextSize = 11
RescanBtn.Font = Enum.Font.Gotham
RescanBtn.Parent = MainFrame

local RescanCorner = Instance.new("UICorner")
RescanCorner.CornerRadius = UDim.new(0, 6)
RescanCorner.Parent = RescanBtn

-- Kill All Button
local KillAllBtn = Instance.new("TextButton")
KillAllBtn.Size = UDim2.new(1, -20, 0, 30)
KillAllBtn.Position = UDim2.new(0, 10, 0, 220)
KillAllBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 50)
KillAllBtn.TextColor3 = Color3.fromRGB(255, 200, 200)
KillAllBtn.Text = "⚔ KILL SEMUA NPC"
KillAllBtn.TextSize = 11
KillAllBtn.Font = Enum.Font.Gotham
KillAllBtn.Parent = MainFrame

local KillCorner = Instance.new("UICorner")
KillCorner.CornerRadius = UDim.new(0, 6)
KillCorner.Parent = KillAllBtn

-- ============================================================
-- FLOATING BUBBLE (buat show/hide GUI)
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
Bubble.Visible = false  -- Awalnya hidden
Bubble.Active = true
Bubble.Parent = ScreenGui

local BubbleCorner = Instance.new("UICorner")
BubbleCorner.CornerRadius = UDim.new(1, 0)  -- Full circle
BubbleCorner.Parent = Bubble

local BubbleStroke = Instance.new("UIStroke")
BubbleStroke.Color = Color3.fromRGB(0, 255, 150)
BubbleStroke.Thickness = 2
BubbleStroke.Parent = Bubble

-- ============================================================
-- DRAGGABLE FUNCTION (REUSABLE)
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

-- Bikin draggable
makeDraggable(MainFrame, TitleBar)
makeDraggable(Bubble, Bubble)

-- ============================================================
-- REAL-TIME UPDATE
-- ============================================================
task.spawn(function()
    while task.wait(2) do
        skippedCount = 0
        local npcs = getAllNPCs()
        CountLabel.Text = "NPC Target: " .. #npcs
        SkipLabel.Text = "Skipped: " .. skippedCount .. " (Quest/Passive)"
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
    log("Rescanning...")
    RescanBtn.Text = "🔄 SCANNING..."
    RescanBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 50)
    
    task.wait(0.1)
    detectedFolders = detectNPCFolders()
    
    if #detectedFolders > 0 then
        CONFIG.NPC_FOLDER_NAME = detectedFolders[1].name
        InfoLabel.Text = "Folder: " .. CONFIG.NPC_FOLDER_NAME
        log("New folder: " .. CONFIG.NPC_FOLDER_NAME)
    else
        InfoLabel.Text = "Folder: NONE"
    end
    
    RescanBtn.Text = "🔄 RESCAN NPC"
    RescanBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 80)
end)

KillAllBtn.MouseButton1Click:Connect(function()
    log("Kill all mode...")
    KillAllBtn.Text = "⚔ KILLING..."
    KillAllBtn.BackgroundColor3 = Color3.fromRGB(170, 50, 50)
    
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
        
        KillAllBtn.Text = "⚔ KILL SEMUA NPC"
        KillAllBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 50)
        log("Kill all done!")
    end)
end)

-- Minimize Button (collapse ke title bar)
MinBtn.MouseButton1Click:Connect(function()
    if MainFrame.Size.Y.Offset > 50 then
        MainFrame.Size = UDim2.new(0, 240, 0, 35)
        MinBtn.Text = "□"
    else
        MainFrame.Size = UDim2.new(0, 240, 0, 260)
        MinBtn.Text = "—"
    end
end)

-- Close Button (hide GUI, show bubble)
CloseBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = false
    Bubble.Position = MainFrame.Position  -- Bubble muncul di posisi terakhir GUI
    Bubble.Visible = true
    log("GUI hidden. Klik bubble buat munculin lagi.")
end)

-- Bubble Click (show GUI, hide bubble)
Bubble.MouseButton1Click:Connect(function()
    MainFrame.Visible = true
    Bubble.Visible = false
    log("GUI shown.")
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
log("✅ Script loaded!")
log("💡 Klik × buat hide GUI → muncul bubble 🎯")
log("💡 Klik bubble 🎯 buat munculin GUI lagi")
log("💡 Bubble bisa digeser ke mana aja")
log("💡 Drag title bar buat mindahin GUI")
