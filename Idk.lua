--// NEXUS UTILITY LIBRARY
--// WindUI Version
--// For your own Roblox Studio game

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

--//==================================================
--// WINDUI
--//==================================================

local WindUI = loadstring(game:HttpGet(
    "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"
))()

--//==================================================
--// SETTINGS
--//==================================================

local Settings = {
    Hitbox = false,
    TeamHighlights = false,
    FOV = false,
    KeyCard = false,
    KeyCardSpam = false,
    ResetButton = false,

    HitboxSize = 10,
    HitboxTransparency = 0.5,

    NormalFOV = 70,
    KeyCardDetectionRange = 1,
}

--//==================================================
--// LOCATIONS
--//==================================================

local Locations = {
    Cafeteria = {
        Position = Vector3.new(917, 100, 2370),
        Teams = nil
    },

    GuardsMilitary = {
        Position = Vector3.new(847, 99, 2230),
        Teams = {"Guards"}
    },

    CriminalsMilitary = {
        Position = Vector3.new(-903, 94, 2048),
        Teams = {"Guards", "Criminals"}
    },

    Tower = {
        Position = Vector3.new(824, 126, 2587),
        Teams = nil
    }
}

local KeyCardSpamPosition = Vector3.new(-933, 94, 2057)
local KeyCardSpamDelay = 0.3

--//==================================================
--// INTERNAL DATA
--//==================================================

local OriginalHitboxData = {}
local HighlightData = {}
local PlayerConnections = {}

local LastWeapon = nil
local AutoEquippedKeyCard = false
local KeyCardSpamRunning = false

-- Cache player character parts.
-- This prevents repeatedly scanning the entire workspace.
local PlayerCache = {}

--//==================================================
--// CHARACTER
--//==================================================

local Character
local Humanoid
local RootPart

local function SetupCharacter(NewCharacter)
    Character = NewCharacter

    Humanoid = NewCharacter:WaitForChild("Humanoid", 10)
    RootPart = NewCharacter:WaitForChild("HumanoidRootPart", 10)

    LastWeapon = nil
    AutoEquippedKeyCard = false
end

if LocalPlayer.Character then
    task.spawn(SetupCharacter, LocalPlayer.Character)
end

LocalPlayer.CharacterAdded:Connect(SetupCharacter)

--//==================================================
--// HITBOX EXPANDER
--//==================================================

local function CachePlayer(Player)
    if Player == LocalPlayer then
        return
    end

    local Data = PlayerCache[Player]

    if not Data then
        Data = {}
        PlayerCache[Player] = Data
    end

    local Char = Player.Character

    if Data.Character ~= Char then
        Data.Character = Char
        Data.Humanoid = nil
        Data.RootPart = nil
        Data.IsCarSeat = false
    end

    if not Char then
        return
    end

    if not Data.Humanoid then
        Data.Humanoid = Char:FindFirstChildOfClass("Humanoid")
    end

    if not Data.RootPart then
        Data.RootPart = Char:FindFirstChild("HumanoidRootPart")
    end
end

local function IsValidCharacter(Player)
    CachePlayer(Player)

    local Data = PlayerCache[Player]

    return Data
        and Data.Character
        and Data.Humanoid
        and Data.RootPart
end

local function SaveOriginalHitbox(Player, HRP)
    local Existing = OriginalHitboxData[Player]

    if not Existing or Existing.Character ~= Player.Character then
        OriginalHitboxData[Player] = {
            Character = Player.Character,
            Size = HRP.Size,
            Transparency = HRP.Transparency,
            Color = HRP.Color,
            Material = HRP.Material,
            CanCollide = HRP.CanCollide,
            CanTouch = HRP.CanTouch,
            CanQuery = HRP.CanQuery,
        }
    end
end

local function RestoreHitbox(Player)
    local Data = OriginalHitboxData[Player]

    if not Data then
        return
    end

    local Char = Player.Character

    if not Char or Data.Character ~= Char then
        OriginalHitboxData[Player] = nil
        return
    end

    local HRP = Char:FindFirstChild("HumanoidRootPart")

    if HRP then
        pcall(function()
            HRP.Size = Data.Size
            HRP.Transparency = Data.Transparency
            HRP.Color = Data.Color
            HRP.Material = Data.Material
            HRP.CanCollide = Data.CanCollide
            HRP.CanTouch = Data.CanTouch
            HRP.CanQuery = Data.CanQuery
        end)
    end

    OriginalHitboxData[Player] = nil
end

-- Only update a player's hitbox when something actually needs changing.
-- This removes the constant property writes that were causing the lag.
local function UpdatePlayerHitbox(Player)
    CachePlayer(Player)

    local Data = PlayerCache[Player]

    if not Data or not Data.Character or not Data.Humanoid or not Data.RootPart then
        return
    end

    local Hum = Data.Humanoid
    local HRP = Data.RootPart

    if Hum.Sit then
        RestoreHitbox(Player)
        return
    end

    if not Settings.Hitbox then
        RestoreHitbox(Player)
        return
    end

    SaveOriginalHitbox(Player, HRP)

    local Original = OriginalHitboxData[Player]

    if not Original or Original.Character ~= Data.Character then
        return
    end

    local TargetSize = Vector3.new(
        Settings.HitboxSize,
        Settings.HitboxSize,
        Settings.HitboxSize
    )

    -- Do not constantly write the same values every frame.
    if HRP.Size ~= TargetSize then
        HRP.Size = TargetSize
    end

    if HRP.Transparency ~= Settings.HitboxTransparency then
        HRP.Transparency = Settings.HitboxTransparency
    end

    -- Preserve the actual player's original appearance.
    if HRP.Color ~= Original.Color then
        HRP.Color = Original.Color
    end

    if HRP.Material ~= Original.Material then
        HRP.Material = Original.Material
    end

    if HRP.CanCollide then
        HRP.CanCollide = false
    end

    if not HRP.CanTouch then
        HRP.CanTouch = true
    end

    if not HRP.CanQuery then
        HRP.CanQuery = true
    end
end

local function UpdateHitboxes()
    -- Do nothing when disabled.
    if not Settings.Hitbox then
        return
    end

    for _, Player in ipairs(Players:GetPlayers()) do
        if Player ~= LocalPlayer then
            UpdatePlayerHitbox(Player)
        end
    end
end

--//==================================================
--// TEAM HIGHLIGHTS
--//==================================================

local function GetTeamColor(Player)
    if Player.Team then
        return Player.Team.TeamColor.Color
    end

    return Color3.fromRGB(255, 255, 255)
end

local function RemoveHighlight(Player)
    local Data = HighlightData[Player]

    if Data and Data.Highlight then
        pcall(function()
            Data.Highlight:Destroy()
        end)
    end

    HighlightData[Player] = nil
end

local function ApplyHighlight(Player)
    if Player == LocalPlayer then
        return
    end

    if not Settings.TeamHighlights then
        return
    end

    local Char = Player.Character

    if not Char then
        return
    end

    local HRP = Char:FindFirstChild("HumanoidRootPart")

    if not HRP then
        return
    end

    local Existing = HighlightData[Player]

    if Existing then
        if Existing.Character ~= Char
            or not Existing.Highlight
            or not Existing.Highlight.Parent
            or Existing.Highlight.Adornee ~= Char then

            RemoveHighlight(Player)
            Existing = nil
        end
    end

    if not Existing then
        local Highlight = Instance.new("Highlight")

        Highlight.Name = "NexusTeamHighlight"
        Highlight.Adornee = Char
        Highlight.Parent = Char
        Highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        Highlight.FillTransparency = 0.5
        Highlight.OutlineTransparency = 0

        HighlightData[Player] = {
            Highlight = Highlight,
            Character = Char
        }

        Existing = HighlightData[Player]
    end

    if Existing and Existing.Highlight then
        local TeamColor = GetTeamColor(Player)

        if Existing.Highlight.FillColor ~= TeamColor then
            Existing.Highlight.FillColor = TeamColor
        end

        if Existing.Highlight.OutlineColor ~= TeamColor then
            Existing.Highlight.OutlineColor = TeamColor
        end
    end
end

local function UpdateHighlights()
    if not Settings.TeamHighlights then
        return
    end

    for _, Player in ipairs(Players:GetPlayers()) do
        if Player ~= LocalPlayer then
            ApplyHighlight(Player)
        end
    end
end

local function SetupHighlightTracking(Player)
    if Player == LocalPlayer then
        return
    end

    if PlayerConnections[Player] then
        for _, Connection in pairs(PlayerConnections[Player]) do
            if Connection then
                Connection:Disconnect()
            end
        end
    end

    PlayerConnections[Player] = {}

    table.insert(
        PlayerConnections[Player],
        Player.CharacterAdded:Connect(function()
            RemoveHighlight(Player)
            OriginalHitboxData[Player] = nil

            PlayerCache[Player] = {
                Character = nil
            }

            task.wait(0.15)

            CachePlayer(Player)

            if Settings.TeamHighlights then
                ApplyHighlight(Player)
            end
        end)
    )

    table.insert(
        PlayerConnections[Player],
        Player:GetPropertyChangedSignal("Team"):Connect(function()
            if Settings.TeamHighlights then
                ApplyHighlight(Player)
            end
        end)
    )
end

for _, Player in ipairs(Players:GetPlayers()) do
    CachePlayer(Player)
    SetupHighlightTracking(Player)
end

Players.PlayerAdded:Connect(function(Player)
    CachePlayer(Player)
    SetupHighlightTracking(Player)
end)

Players.PlayerRemoving:Connect(function(Player)
    RemoveHighlight(Player)

    RestoreHitbox(Player)

    PlayerCache[Player] = nil
    OriginalHitboxData[Player] = nil

    if PlayerConnections[Player] then
        for _, Connection in pairs(PlayerConnections[Player]) do
            if Connection then
                Connection:Disconnect()
            end
        end
    end

    PlayerConnections[Player] = nil
end)

--//==================================================
--// KEY CARD
--//==================================================

local function IsKeyCard(Tool)
    return Tool
        and Tool:IsA("Tool")
        and Tool.Name:lower() == "keycard"
end

local function GetKeyCard()
    if not Character then
        return nil
    end

    local Backpack = LocalPlayer:FindFirstChildOfClass("Backpack")

    if Backpack then
        for _, Item in ipairs(Backpack:GetChildren()) do
            if IsKeyCard(Item) then
                return Item
            end
        end
    end

    for _, Item in ipairs(Character:GetChildren()) do
        if IsKeyCard(Item) then
            return Item
        end
    end

    return nil
end

local function GetEquippedNonKeyCard()
    if not Character then
        return nil
    end

    for _, Item in ipairs(Character:GetChildren()) do
        if Item:IsA("Tool") and not IsKeyCard(Item) then
            return Item
        end
    end

    return nil
end

local function RestoreLastWeapon()
    if not Character or not Humanoid then
        return
    end

    if LastWeapon and LastWeapon.Parent then
        pcall(function()
            Humanoid:EquipTool(LastWeapon)
        end)
    end
end

local function GetClosestPointOnPart(Part, Position)
    local LocalPosition = Part.CFrame:PointToObjectSpace(Position)
    local HalfSize = Part.Size / 2

    local Clamped = Vector3.new(
        math.clamp(LocalPosition.X, -HalfSize.X, HalfSize.X),
        math.clamp(LocalPosition.Y, -HalfSize.Y, HalfSize.Y),
        math.clamp(LocalPosition.Z, -HalfSize.Z, HalfSize.Z)
    )

    return Part.CFrame:PointToWorldSpace(Clamped)
end

local function GetDoorDistance()
    if not RootPart then
        return math.huge
    end

    local Doors = workspace:FindFirstChild("Doors")

    if not Doors then
        return math.huge
    end

    local ClosestDistance = math.huge

    for _, Object in ipairs(Doors:GetDescendants()) do
        if Object:IsA("BasePart") then
            local Point = GetClosestPointOnPart(
                Object,
                RootPart.Position
            )

            local Distance = (RootPart.Position - Point).Magnitude

            if Distance < ClosestDistance then
                ClosestDistance = Distance
            end
        end
    end

    return ClosestDistance
end

local function SetupKeyCardTracking(Char)
    Char.ChildAdded:Connect(function(Item)
        if Item:IsA("Tool") and not IsKeyCard(Item) then
            LastWeapon = Item
        end
    end)
end

if Character then
    SetupKeyCardTracking(Character)
end

LocalPlayer.CharacterAdded:Connect(function(Char)
    SetupKeyCardTracking(Char)
end)

local function UpdateKeyCard()
    if not Settings.KeyCard then
        return
    end

    if not Character or not Humanoid or not RootPart then
        return
    end

    local Card = GetKeyCard()

    if not Card then
        return
    end

    local Distance = GetDoorDistance()

    if Distance <= Settings.KeyCardDetectionRange then
        if not IsKeyCard(Character:FindFirstChildOfClass("Tool")) then
            local Equipped = GetEquippedNonKeyCard()

            if Equipped then
                LastWeapon = Equipped
            end

            pcall(function()
                Humanoid:EquipTool(Card)
            end)

            AutoEquippedKeyCard = true
        end
    else
        if AutoEquippedKeyCard then
            AutoEquippedKeyCard = false

            pcall(function()
                Humanoid:UnequipTools()
            end)

            task.defer(RestoreLastWeapon)
        end
    end
end

--//==================================================
--// KEY CARD SPAM
--//==================================================

local function StartKeyCardSpam()
    if KeyCardSpamRunning then
        return
    end

    KeyCardSpamRunning = true

    task.spawn(function()
        while Settings.KeyCardSpam do
            local Team = LocalPlayer.Team

            if not Team or Team.Name ~= "Guards" then
                break
            end

            local Char = LocalPlayer.Character
            local Hum = Char and Char:FindFirstChildOfClass("Humanoid")
            local HRP = Char and Char:FindFirstChild("HumanoidRootPart")

            if not Hum or not HRP then
                task.wait(0.2)
                continue
            end

            HRP.CFrame = CFrame.new(KeyCardSpamPosition)

            task.wait(KeyCardSpamDelay)

            if not Settings.KeyCardSpam then
                break
            end

            Hum.Health = 0

            local NewCharacter

            local Connection
            Connection = LocalPlayer.CharacterAdded:Connect(function(Char)
                NewCharacter = Char
            end)

            local Start = os.clock()

            while Settings.KeyCardSpam
                and not NewCharacter
                and os.clock() - Start < 10 do

                task.wait(0.1)
            end

            Connection:Disconnect()

            if not Settings.KeyCardSpam then
                break
            end

            if NewCharacter then
                local NewRoot = NewCharacter:WaitForChild(
                    "HumanoidRootPart",
                    5
                )

                if NewRoot then
                    NewRoot.CFrame = CFrame.new(
                        KeyCardSpamPosition
                    )
                end
            end

            task.wait(KeyCardSpamDelay)
        end

        KeyCardSpamRunning = false
    end)
end

--//==================================================
--// RESET BUTTON
--//==================================================

local ResetGui = Instance.new("ScreenGui")
ResetGui.Name = "NexusResetButton"
ResetGui.ResetOnSpawn = false
ResetGui.IgnoreGuiInset = true
ResetGui.Enabled = false
ResetGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local ResetFrame = Instance.new("Frame")
ResetFrame.Name = "ResetFrame"
ResetFrame.Size = UDim2.fromOffset(145, 75)
ResetFrame.Position = UDim2.fromScale(0.72, 0.65)
ResetFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
ResetFrame.BorderSizePixel = 0
ResetFrame.Parent = ResetGui

local ResetCorner = Instance.new("UICorner")
ResetCorner.CornerRadius = UDim.new(0, 12)
ResetCorner.Parent = ResetFrame

local ResetStroke = Instance.new("UIStroke")
ResetStroke.Color = Color3.fromRGB(100, 60, 180)
ResetStroke.Thickness = 1
ResetStroke.Parent = ResetFrame

local ResetTitle = Instance.new("TextLabel")
ResetTitle.Size = UDim2.new(1, -10, 0, 25)
ResetTitle.Position = UDim2.fromOffset(5, 3)
ResetTitle.BackgroundTransparency = 1
ResetTitle.Text = "Nexus Reset"
ResetTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
ResetTitle.TextSize = 14
ResetTitle.Font = Enum.Font.GothamBold
ResetTitle.Parent = ResetFrame

local ResetButton = Instance.new("TextButton")
ResetButton.Size = UDim2.new(1, -16, 0, 32)
ResetButton.Position = UDim2.fromOffset(8, 35)
ResetButton.BackgroundColor3 = Color3.fromRGB(75, 45, 130)
ResetButton.BorderSizePixel = 0
ResetButton.Text = "RESET"
ResetButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ResetButton.TextSize = 13
ResetButton.Font = Enum.Font.GothamBold
ResetButton.Parent = ResetFrame

local ResetButtonCorner = Instance.new("UICorner")
ResetButtonCorner.CornerRadius = UDim.new(0, 8)
ResetButtonCorner.Parent = ResetButton

ResetButton.MouseButton1Click:Connect(function()
    if Humanoid then
        Humanoid.Health = 0
    end
end)

local Dragging = false
local DragStart
local StartPosition

ResetTitle.InputBegan:Connect(function(Input)
    if Input.UserInputType == Enum.UserInputType.MouseButton1
        or Input.UserInputType == Enum.UserInputType.Touch then

        Dragging = true
        DragStart = Input.Position
        StartPosition = ResetFrame.Position
    end
end)

UIS.InputChanged:Connect(function(Input)
    if not Dragging then
        return
    end

    if Input.UserInputType ~= Enum.UserInputType.MouseMovement
        and Input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    local Delta = Input.Position - DragStart

    ResetFrame.Position = UDim2.new(
        StartPosition.X.Scale,
        StartPosition.X.Offset + Delta.X,
        StartPosition.Y.Scale,
        StartPosition.Y.Offset + Delta.Y
    )
end)

UIS.InputEnded:Connect(function(Input)
    if Input.UserInputType == Enum.UserInputType.MouseButton1
        or Input.UserInputType == Enum.UserInputType.Touch then

        Dragging = false
    end
end)

--//==================================================
--// WINDUI WINDOW
--//==================================================

local Window = WindUI:CreateWindow({
    Title = "Nexus Utility",
    Icon = "wrench",
    Author = "Nexus",
    Folder = "Nexus Utility",
    Size = UDim2.fromOffset(580, 460),
    Transparent = false,
    Theme = "Dark",
    Resizable = true,
    SideBarWidth = 170
})

--//==================================================
--// TABS
--//==================================================

local MainTab = Window:Tab({
    Title = "Main",
    Icon = "wrench"
})

local VisualTab = Window:Tab({
    Title = "Visuals",
    Icon = "eye"
})

local CameraTab = Window:Tab({
    Title = "Camera",
    Icon = "camera"
})

local ButtonsTab = Window:Tab({
    Title = "Buttons",
    Icon = "mouse-pointer-2"
})

local TeleportTab = Window:Tab({
    Title = "Teleports",
    Icon = "map-pin"
})

--//==================================================
--// MAIN
--//==================================================

MainTab:Toggle({
    Title = "Hitbox Expander",
    Desc = "Expand players' HumanoidRootParts",
    Value = Settings.Hitbox,

    Callback = function(Value)
        Settings.Hitbox = Value

        if not Value then
            for Player in pairs(OriginalHitboxData) do
                RestoreHitbox(Player)
            end
        end
    end
})

MainTab:Slider({
    Title = "Hitbox Size",
    Desc = "Size of the expanded HumanoidRootPart",

    Value = {
        Min = 1,
        Max = 20,
        Default = Settings.HitboxSize
    },

    Callback = function(Value)
        Settings.HitboxSize = tonumber(Value) or 10
    end
})

MainTab:Toggle({
    Title = "Key Card Auto-Equip",
    Desc = "Automatically equips KeyCard near Doors",
    Value = Settings.KeyCard,

    Callback = function(Value)
        Settings.KeyCard = Value

        if not Value then
            AutoEquippedKeyCard = false
        end
    end
})

--//==================================================
--// VISUALS
--//==================================================

VisualTab:Toggle({
    Title = "Teams Highlight",
    Desc = "Highlight players using their team color",
    Value = Settings.TeamHighlights,

    Callback = function(Value)
        Settings.TeamHighlights = Value

        if not Value then
            for _, Player in ipairs(Players:GetPlayers()) do
                RemoveHighlight(Player)
            end
        else
            UpdateHighlights()
        end
    end
})

--//==================================================
--// CAMERA
--//==================================================

CameraTab:Toggle({
    Title = "FOV 120",
    Desc = "Change camera field of view to 120",
    Value = Settings.FOV,

    Callback = function(Value)
        Settings.FOV = Value

        local Camera = workspace.CurrentCamera

        if Camera then
            Camera.FieldOfView = Value and 120 or Settings.NormalFOV
        end
    end
})

--//==================================================
--// BUTTONS
--//==================================================

ButtonsTab:Toggle({
    Title = "Reset Button",
    Desc = "Show the draggable Nexus Reset button",
    Value = Settings.ResetButton,

    Callback = function(Value)
        Settings.ResetButton = Value
        ResetGui.Enabled = Value
    end
})

--//==================================================
--// TELEPORTS
--//==================================================

TeleportTab:Button({
    Title = "Cafeteria",
    Desc = "Teleport to Cafeteria",

    Callback = function()
        if RootPart then
            RootPart.CFrame = CFrame.new(
                Locations.Cafeteria.Position
            )
        end
    end
})

TeleportTab:Button({
    Title = "Guards Military",
    Desc = "Teleport to Guards Military",

    Callback = function()
        if RootPart then
            RootPart.CFrame = CFrame.new(
                Locations.GuardsMilitary.Position
            )
        end
    end
})

TeleportTab:Button({
    Title = "Criminals Military",
    Desc = "Teleport to Criminals Military",

    Callback = function()
        if RootPart then
            RootPart.CFrame = CFrame.new(
                Locations.CriminalsMilitary.Position
            )
        end
    end
})

TeleportTab:Button({
    Title = "Tower",
    Desc = "Teleport to Tower",

    Callback = function()
        if RootPart then
            RootPart.CFrame = CFrame.new(
                Locations.Tower.Position
            )
        end
    end
})

TeleportTab:Toggle({
    Title = "Key Card Spam",
    Desc = "Guard-only KeyCard spam loop",
    Value = Settings.KeyCardSpam,

    Callback = function(Value)
        Settings.KeyCardSpam = Value

        if Value then
            StartKeyCardSpam()
        end
    end
})

--//==================================================
--// LOW-LAG UPDATE LOOP
--//==================================================

local HitboxUpdateTimer = 0
local HighlightUpdateTimer = 0
local KeyCardUpdateTimer = 0

RunService.Heartbeat:Connect(function(DeltaTime)
    -- Hitboxes only need a small periodic check.
    -- This avoids hammering every player's properties every frame.
    if Settings.Hitbox then
        HitboxUpdateTimer += DeltaTime

        if HitboxUpdateTimer >= 0.08 then
            HitboxUpdateTimer = 0
            UpdateHitboxes()
        end
    end

    -- Highlights do not need constant rebuilding.
    if Settings.TeamHighlights then
        HighlightUpdateTimer += DeltaTime

        if HighlightUpdateTimer >= 0.25 then
            HighlightUpdateTimer = 0
            UpdateHighlights()
        end
    end

    -- KeyCard detection is also throttled.
    if Settings.KeyCard then
        KeyCardUpdateTimer += DeltaTime

        if KeyCardUpdateTimer >= 0.1 then
            KeyCardUpdateTimer = 0
            UpdateKeyCard()
        end
    end
end)

RunService.RenderStepped:Connect(function()
    if Settings.FOV then
        local Camera = workspace.CurrentCamera

        if Camera and Camera.FieldOfView ~= 120 then
            Camera.FieldOfView = 120
        end
    end
end)
