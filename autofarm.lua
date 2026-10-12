--[[
=========================================================
  UNIVERSAL NPC DETECTOR + AUTOFARM
  Author: Kyriel (for Boss)
  Executor: Delta / Codex / Wave / Xeno
  Cara pakai: loadstring(game:HttpGet("URL_SCRIPT_LO"))()
=========================================================

FITUR:
  1. Auto-detect folder NPC di Workspace
  2. Teleport ke NPC terdekat
  3. Bunuh NPC sampe mati
  4. Loop otomatis cari NPC baru
  5. GUI toggle on/off
  6. Anti-AFK
=========================================================
]]

-- ============================================================
-- SERVICE & VARIABEL
-- ============================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
local humanoid = character:WaitForChild("Humanoid")

-- ============================================================
-- KONFIGURASI DEFAULT
-- ============================================================
local CONFIG = {
    NPC_FOLDER_NAME = "NPCs",       -- Bakal auto-detect, ini fallback
    NPC_ALIVE_FOLDER = nil,         -- Sub-folder NPC hidup (kalo ada)
    ATTACK_RANGE = 50,              -- Jarak maksimal buat nyerang (studs)
    TELEPORT_HEIGHT = 5,            -- Ketinggian teleport di atas NPC
    ATTACK_COOLDOWN = 0.1,          -- Jeda antar serangan (detik)
    LOOP_DELAY = 0.5,               -- Jeda antar loop (detik)
    AUTO_EQUIP_TOOL = true,         -- Auto equip tool/weapon
    USE_SKILLS = true,              -- Pake skill
    SKILL_KEYS = {"Z", "X", "C", "V"},
    SKILL_COOLDOWN = 2,             -- Cooldown skill (detik)
}

local isRunning = false
local currentTarget = nil
local lastSkillTime = 0
local detectedFolders = {}

-- ============================================================
-- FUNGSI: DETEKSI OTOMATIS FOLDER NPC
-- ============================================================
local function detectNPCFolders()
    local folderCount = {}
    
    local function scan(instance)
        for _, obj in ipairs(instance:GetChildren()) do
            if obj:IsA("Model") and obj:FindFirstChild("Humanoid") then
                -- Skip karakter player
                if not Players:GetPlayerFromCharacter(obj) then
                    local parentName = obj.Parent and obj.Parent.Name or "Workspace"
                    folderCount[parentName] = (folderCount[parentName] or 0) + 1
                end
            end
            if #obj:GetChildren() > 0 then
                scan(obj)
            end
        end
    end
    
    scan(workspace)
    
    -- Sort berdasarkan jumlah NPC terbanyak
    local sorted = {}
    for name, count in pairs(folderCount) do
        table.insert(sorted, {name = name, count = count})
    end
    table.sort(sorted, function(a, b) return a.count > b.count end)
    
    return sorted
end

-- ============================================================
-- FUNGSI: CARI SEMUA NPC
-- ============================================================
local function getAllNPCs()
    local npcs = {}
    local searchRoot = workspace
    local subFolder = nil
    
    -- Kalo folder udah ke-detect, pake itu
    if CONFIG.NPC_FOLDER_NAME then
        local found = workspace:FindFirstChild(CONFIG.NPC_FOLDER_NAME)
        if found then
            searchRoot = found
            -- Cek sub-folder
            if CONFIG.NPC_ALIVE_FOLDER and found:FindFirstChild(CONFIG.NPC_ALIVE_FOLDER) then
                subFolder = found:FindFirstChild(CONFIG.NPC_ALIVE_FOLDER)
            end
        end
    end
    
    local function scan(instance)
        for _, npc in ipairs(instance:GetChildren()) do
            if npc:IsA("Model") and npc:FindFirstChild("Humanoid") then
                -- Skip karakter player
                if not Players:GetPlayerFromCharacter(npc) then
                    local npcHumanoid = npc:FindFirstChildOfClass("Humanoid")
                    local npcRoot = npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChild("Head") or npc:FindFirstChild("Torso")
                    
                    if npcHumanoid and npcHumanoid.Health > 0 and npcRoot then
                        local dist = (humanoidRootPart.Position - npcRoot.Position).Magnitude
                        table.insert(npcs, {
                            model = npc,
                            humanoid = npcHumanoid,
                            root = npcRoot,
                            distance = dist
                        })
                    end
                end
            end
            -- Rekursif ke dalam folder
            if #npc:GetChildren() > 0 and not npc:FindFirstChildOfClass("Humanoid") then
                scan(npc)
            end
        end
    end
    
    scan(searchRoot)
    
    -- Sort dari yang terdekat
    table.sort(npcs, function(a, b) return a.distance < b.distance end)
    return npcs
end

-- ============================================================
-- FUNGSI: TELEPORT KE NPC
-- ============================================================
local function teleportToNPC(npc)
    if not npc or not npc.root then return end
    local targetPos = npc.root.Position + Vector3.new(0, CONFIG.TELEPORT_HEIGHT, 0)
    humanoidRootPart.CFrame = CFrame.new(targetPos)
    humanoidRootPart.Velocity = Vector3.new(0, 0, 0)
end

-- ============================================================
-- FUNGSI: SERANG NPC
-- ============================================================
local function attackNPC(npc)
    if not npc or not npc.model or not npc.model.Parent then return end
    
    -- Auto equip tool
    if CONFIG.AUTO_EQUIP_TOOL then
        local tool = character:FindFirstChildOfClass("Tool")
        if not tool then
            for _, item in ipairs(player.Backpack:GetChildren()) do
                if item:IsA("Tool") then
                    item.Parent = character
                    break
                end
            end
        end
    end
    
    -- Aktifkan tool
    local tool = character:FindFirstChildOfClass("Tool")
    if tool then
        pcall(function() tool:Activate() end)
    end
    
    -- Pake skill
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
-- FUNGSI: START AUTOFARM
-- ============================================================
local function startAutoFarm()
    if isRunning then return end
    isRunning = true
    
    print("[Autofarm] Started!")
    
    task.spawn(function()
        while isRunning do
            local npcs = getAllNPCs()
            
            if #npcs > 0 then
                currentTarget = npcs[1]
                teleportToNPC(currentTarget)
                task.wait(0.1)
                
                while currentTarget and currentTarget.humanoid and currentTarget.humanoid.Health > 0 and isRunning do
                    attackNPC(currentTarget)
                    task.wait(CONFIG.ATTACK_COOLDOWN)
                    if not currentTarget.model or not currentTarget.model.Parent then
                        break
                    end
                end
            else
                task.wait(1)
            end
            
            task.wait(CONFIG.LOOP_DELAY)
        end
    end)
end

-- ============================================================
-- FUNGSI: STOP AUTOFARM
-- ============================================================
local function stopAutoFarm()
    isRunning = false
    currentTarget = nil
    print("[Autofarm] Stopped.")
end

-- ============================================================
-- DETEKSI AWAL
-- ============================================================
print("==================================================")
print("     NPC DETECTOR + AUTOFARM - SCANNING...")
print("==================================================")

detectedFolders = detectNPCFolders()

if #detectedFolders > 0 then
    print("✅ Folder NPC yang terdeteksi:")
    for i, folder in ipairs(detectedFolders) do
        print(string.format("   [%d] 📁 %s → %d NPC", i, folder.name, folder.count))
    end
    
    -- Auto-set folder NPC yang paling banyak
    CONFIG.NPC_FOLDER_NAME = detectedFolders[1].name
    print("")
    print("🎯 Auto-select folder: " .. CONFIG.NPC_FOLDER_NAME)
    print("==================================================")
else
    print("❌ Gak ada NPC yang terdeteksi. Coba cek manual ya Bos.")
    print("==================================================")
end

-- ============================================================
-- GUI
-- ============================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutofarmGUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = player:WaitForChild("PlayerGui")

-- Main Frame
local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 220, 0, 180)
MainFrame.Position = UDim2.new(0, 20, 0, 20)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
MainFrame.BorderSizePixel = 0
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 10)
UICorner.Parent = MainFrame

-- Title
local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 35)
Title.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
Title.TextColor3 = Color3.fromRGB(0, 255, 150)
Title.Text = "🎯 AUTOFARM"
Title.TextSize = 16
Title.Font = Enum.Font.GothamBold
Title.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = Title

-- Info Label
local InfoLabel = Instance.new("TextLabel")
InfoLabel.Size = UDim2.new(1, -20, 0, 20)
InfoLabel.Position = UDim2.new(0, 10, 0, 40)
InfoLabel.BackgroundTransparency = 1
InfoLabel.TextColor3 = Color3.fromRGB(150, 150, 200)
InfoLabel.Text = "Folder: " .. tostring(CONFIG.NPC_FOLDER_NAME)
InfoLabel.TextSize = 11
InfoLabel.Font = Enum.Font.Gotham
InfoLabel.TextXAlignment = Enum.TextXAlignment.Left
InfoLabel.Parent = MainFrame

-- Start Button
local ToggleButton = Instance.new("TextButton")
ToggleButton.Size = UDim2.new(1, -20, 0, 45)
ToggleButton.Position = UDim2.new(0, 10, 0, 70)
ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
ToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleButton.Text = "▶ START AUTOFARM"
ToggleButton.TextSize = 14
ToggleButton.Font = Enum.Font.GothamBold
ToggleButton.Parent = MainFrame

local BtnCorner = Instance.new("UICorner")
BtnCorner.CornerRadius = UDim.new(0, 8)
BtnCorner.Parent = ToggleButton

-- Status Label
local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -20, 0, 20)
StatusLabel.Position = UDim2.new(0, 10, 0, 120)
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
RescanBtn.Position = UDim2.new(0, 10, 0, 145)
RescanBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 80)
RescanBtn.TextColor3 = Color3.fromRGB(200, 200, 255)
RescanBtn.Text = "🔄 RESCAN NPC FOLDER"
RescanBtn.TextSize = 11
RescanBtn.Font = Enum.Font.Gotham
RescanBtn.Parent = MainFrame

local RescanCorner = Instance.new("UICorner")
RescanCorner.CornerRadius = UDim.new(0, 6)
RescanCorner.Parent = RescanBtn

-- ============================================================
-- EVENT HANDLERS
-- ============================================================
ToggleButton.MouseButton1Click:Connect(function()
    if isRunning then
        stopAutoFarm()
        ToggleButton.Text = "▶ START AUTOFARM"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
        StatusLabel.Text = "Status: IDLE"
        StatusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
    else
        startAutoFarm()
        ToggleButton.Text = "⏸ STOP AUTOFARM"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(170, 0, 0)
        StatusLabel.Text = "Status: RUNNING"
        StatusLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
    end
end)

RescanBtn.MouseButton1Click:Connect(function()
    print("[Autofarm] Rescanning...")
    detectedFolders = detectNPCFolders()
    
    if #detectedFolders > 0 then
        CONFIG.NPC_FOLDER_NAME = detectedFolders[1].name
        InfoLabel.Text = "Folder: " .. CONFIG.NPC_FOLDER_NAME
        print("✅ New folder: " .. CONFIG.NPC_FOLDER_NAME)
    end
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
-- AUTO UPDATE POSITION
-- ============================================================
task.spawn(function()
    while task.wait(1) do
        if character and character.Parent then
            humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
            humanoid = character:FindFirstChildOfClass("Humanoid")
        else
            character = player.Character or player.CharacterAdded:Wait()
            humanoidRootPart = character:WaitForChild("HumanoidRootPart")
            humanoid = character:WaitForChild("Humanoid")
        end
    end
end)

-- ============================================================
-- DONE
-- ============================================================
print("==================================================")
print("✅ Script loaded! Klik tombol buat mulai autofarm.")
print("==================================================")
