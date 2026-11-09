local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Stats = game:GetService("Stats")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

local LP = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local function getGenv()
    if getgenv then return getgenv() end
    return _G
end
local GENV = getGenv()

local CONFIG = {
    KEY = Enum.KeyCode.F,
    UNLOAD_KEY = Enum.KeyCode.Delete,
    PANEL_KEY = Enum.KeyCode.Insert,
    AIM_PART = "Head",
    MODE = "Smooth",
    FOV = 220,
    SMOOTHNESS = 0.55,
    PREDICTION = 0.10,
    PREDICTION_ENABLED = true,
    PING_COMPENSATION = true,
    MAX_DISTANCE = 2000,
    TEAM_CHECK = true,
    WALL_CHECK = false,
    SHOW_FOV = true,
    AUTO_ENABLE = false,
    MOBILE_BUTTON = true,
    STICKY = true,
    SNAP_ON_LOCK = true,
    REACQUIRE = true,
    IGNORE_LIST = {},
    ESP = {
        Enabled = false,
        OnlyEnemies = true,
        MaxDistance = 1500,
        FillColor = Color3.fromRGB(255, 60, 60),
        FillAlpha = 0.35,
        OutlineColor = Color3.fromRGB(255, 255, 255),
        OutlineAlpha = 0.9,
        UseTeamColor = false,
    },
}

local enabled = CONFIG.AUTO_ENABLE
local unloaded = false
local locked = nil
local needRelock = true
local conns = {}
local espHighlights = {}
local silentInstalled = false

local function track(c)
    table.insert(conns, c)
    return c
end

local IGNORE_FILE = "PrensadoCamlock/ignore.json"

local function hasFileAPI()
    return type(writefile) == "function" and type(readfile) == "function"
        and type(isfile) == "function" and type(isfolder) == "function"
        and type(makefolder) == "function"
end

local function ensureFolder()
    if not hasFileAPI() then return false end
    pcall(function()
        if not isfolder("PrensadoCamlock") then
            makefolder("PrensadoCamlock")
        end
    end)
    return true
end

local function loadIgnoreList()
    if not ensureFolder() then return end
    pcall(function()
        if isfile(IGNORE_FILE) then
            local data = readfile(IGNORE_FILE)
            local ok, tbl = pcall(function()
                return HttpService:JSONDecode(data)
            end)
            if ok and type(tbl) == "table" then
                CONFIG.IGNORE_LIST = {}
                for _, v in ipairs(tbl) do
                    if type(v) == "string" and v ~= "" then
                        table.insert(CONFIG.IGNORE_LIST, v:lower())
                    end
                end
            end
        end
    end)
end

local function saveIgnoreList()
    if not ensureFolder() then return end
    pcall(function()
        writefile(IGNORE_FILE, HttpService:JSONEncode(CONFIG.IGNORE_LIST))
    end)
end

loadIgnoreList()

local function nameOf(plr)
    return (plr and plr.Name or ""):lower()
end

local function isIgnored(plr)
    local n = nameOf(plr)
    if n == "" then return false end
    for _, v in ipairs(CONFIG.IGNORE_LIST) do
        if v == n then return true end
    end
    return false
end

local function addIgnore(name)
    name = tostring(name or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return false end
    for _, v in ipairs(CONFIG.IGNORE_LIST) do
        if v == name then return false end
    end
    table.insert(CONFIG.IGNORE_LIST, name)
    saveIgnoreList()
    return true
end

local function removeIgnore(name)
    name = tostring(name or ""):lower()
    for i = #CONFIG.IGNORE_LIST, 1, -1 do
        if CONFIG.IGNORE_LIST[i] == name then
            table.remove(CONFIG.IGNORE_LIST, i)
            saveIgnoreList()
            return true
        end
    end
    return false
end

local function getPing()
    local ok, ping = pcall(function()
        return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    if ok and type(ping) == "number" and ping > 0 then
        return math.clamp(ping / 1000, 0, 0.5)
    end
    return 0
end

local function getVelocity(part, char)
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local vel = part and part.AssemblyLinearVelocity
    if (not vel or vel.Magnitude < 1) and root then
        vel = root.AssemblyLinearVelocity
    end
    return vel or Vector3.zero
end

local function predictPosition(part, char)
    if not CONFIG.PREDICTION_ENABLED or not part then
        return part and part.Position or Vector3.zero
    end
    local t = CONFIG.PREDICTION
    if CONFIG.PING_COMPENSATION then
        t = t + getPing()
    end
    return part.Position + getVelocity(part, char) * t
end

local function isAlive(plr)
    local char = plr and plr.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return (hum and hum.Health > 0) and true or false
end

local function getPart(char)
    if not char then return nil end
    local name = CONFIG.AIM_PART
    if name == "Torso" then name = "HumanoidRootPart" end
    if name == "Random" then
        name = (math.random() < 0.5) and "Head" or "HumanoidRootPart"
    end
    if name ~= "Closest" then
        return char:FindFirstChild(name) or char:FindFirstChild("HumanoidRootPart")
    end
    local best, bestD
    for _, v in ipairs(char:GetChildren()) do
        if v:IsA("BasePart") then
            local d = (v.Position - Camera.CFrame.Position).Magnitude
            if not bestD or d < bestD then
                best, bestD = v, d
            end
        end
    end
    return best
end

local function findTarget()
    local best, bestScore
    local center = Camera.ViewportSize / 2
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and not isIgnored(plr) then
            local char = plr.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local ok = true
                if CONFIG.TEAM_CHECK and LP.Team and plr.Team == LP.Team then
                    ok = false
                end
                if ok then
                    local part = getPart(char)
                    if part then
                        local worldPos = predictPosition(part, char)
                        local sp, onScreen = Camera:WorldToViewportPoint(worldPos)
                        if onScreen and sp.Z > 0 then
                            local off = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                            if off <= CONFIG.FOV / 2 then
                                if CONFIG.WALL_CHECK then
                                    local rp = RaycastParams.new()
                                    rp.FilterType = Enum.RaycastFilterType.Exclude
                                    rp.FilterDescendantsInstances = { LP.Character, char }
                                    local hit = Workspace:Raycast(Camera.CFrame.Position,
                                        worldPos - Camera.CFrame.Position, rp)
                                    if hit then ok = false end
                                end
                                if ok then
                                    local dist = (part.Position - Camera.CFrame.Position).Magnitude
                                    if dist <= CONFIG.MAX_DISTANCE then
                                        local score = off + dist * 0.05
                                        if not bestScore or score < bestScore then
                                            best, bestScore = plr, score
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

local circle
if Drawing and Drawing.new then
    circle = Drawing.new("Circle")
    circle.Thickness = 1.5
    circle.NumSides = 64
    circle.Filled = false
    circle.Color = Color3.fromRGB(0, 255, 140)
    circle.Transparency = 0.65
end

local function snapTo(plr)
    local char = plr and plr.Character
    local part = char and getPart(char)
    if not part then return end
    Camera.CFrame = CFrame.lookAt(Camera.CFrame.Position, predictPosition(part, char))
end

local function acquire()
    local t = findTarget()
    if not t then return end
    locked = t
    if CONFIG.SNAP_ON_LOCK then snapTo(t) end
end

local function tryInstallSilent()
    if silentInstalled then return end
    if type(getrawmetatable) ~= "function" then return end
    if type(setreadonly) ~= "function" then return end
    if type(newcclosure) ~= "function" then return end
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local ok, mt = pcall(getrawmetatable, cam)
    if not ok or not mt then return end
    local oldIndex = mt.__index
    if not oldIndex then return end
    pcall(function() setreadonly(mt, false) end)
    mt.__index = newcclosure(function(self, key)
        if key == "CFrame" and CONFIG.MODE == "Silent" and GENV.PrensadoSilentCF then
            return GENV.PrensadoSilentCF
        end
        return oldIndex(self, key)
    end)
    pcall(function() setreadonly(mt, true) end)
    silentInstalled = true
end

local function makeHighlight(plr)
    local char = plr.Character
    if not char then return end
    local h = espHighlights[plr]
    if not h or not h.Parent then
        h = Instance.new("Highlight")
        h.Name = "PrensadoESP"
        h.Adornee = char
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.Parent = char
        espHighlights[plr] = h
    else
        h.Adornee = char
    end
    return h
end

local function clearHighlight(plr)
    local h = espHighlights[plr]
    if h then
        pcall(function() h:Destroy() end)
        espHighlights[plr] = nil
    end
end

local function clearAllHighlights()
    for plr, h in pairs(espHighlights) do
        pcall(function() h:Destroy() end)
    end
    espHighlights = {}
end

local function shouldESP(plr)
    if plr == LP or not isAlive(plr) then return false end
    if isIgnored(plr) then return false end
    local esp = CONFIG.ESP
    if not esp.Enabled then return false end
    if esp.OnlyEnemies and CONFIG.TEAM_CHECK and LP.Team and plr.Team == LP.Team then
        return false
    end
    local char = plr.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if root then
        local d = (root.Position - Camera.CFrame.Position).Magnitude
        if d > esp.MaxDistance then return false end
    end
    return true
end

local function refreshESPOne(plr)
    local esp = CONFIG.ESP
    if not esp.Enabled or not shouldESP(plr) then
        clearHighlight(plr)
        return
    end
    local h = makeHighlight(plr)
    if not h then return end
    local fill, outline
    if esp.UseTeamColor and plr.Team then
        fill = plr.Team.TeamColor.Color
        outline = fill:Lerp(Color3.new(1, 1, 1), 0.5)
    else
        fill = esp.FillColor
        outline = esp.OutlineColor
    end
    h.FillColor = fill
    h.FillTransparency = math.clamp(1 - esp.FillAlpha, 0, 1)
    h.OutlineColor = outline
    h.OutlineTransparency = math.clamp(1 - esp.OutlineAlpha, 0, 1)
end

local function refreshESPAll()
    for _, plr in ipairs(Players:GetPlayers()) do
        refreshESPOne(plr)
    end
end

local function hookCharacter(plr)
    local function bind(char)
        if not char then return end
        track(char.ChildAdded:Connect(function()
            task.defer(function() refreshESPOne(plr) end)
        end))
        track(char.AncestryChanged:Connect(function()
            if not char:IsDescendantOf(Workspace) then
                clearHighlight(plr)
            end
        end))
        task.defer(function() refreshESPOne(plr) end)
    end
    track(plr.CharacterAdded:Connect(bind))
    if plr.Character then bind(plr.Character) end
end

for _, plr in ipairs(Players:GetPlayers()) do
    hookCharacter(plr)
end

track(Players.PlayerAdded:Connect(function(plr)
    hookCharacter(plr)
    track(plr.CharacterAdded:Connect(function()
        task.wait(0.2)
        refreshESPOne(plr)
    end))
end))

track(Players.PlayerRemoving:Connect(function(plr)
    clearHighlight(plr)
end))

track(RunService.Heartbeat:Connect(function()
    if unloaded then return end
    if not CONFIG.ESP.Enabled then return end
    for _, plr in ipairs(Players:GetPlayers()) do
        refreshESPOne(plr)
    end
end))

RunService:BindToRenderStep("PrensadoCamlock",
    Enum.RenderPriority.Camera.Value + 1, function()
    if unloaded then return end
    Camera = Workspace.CurrentCamera

    if circle then
        circle.Position = Camera.ViewportSize / 2
        circle.Radius = CONFIG.FOV / 2
        circle.Visible = CONFIG.SHOW_FOV and enabled
        circle.Color = locked and Color3.fromRGB(0, 255, 140)
            or (enabled and Color3.fromRGB(255, 200, 60)
                or Color3.fromRGB(120, 120, 130))
    end

    if not enabled then
        GENV.PrensadoSilentCF = nil
        return
    end

    if locked then
        local char = locked.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local part = char and getPart(char)
        if not (hum and hum.Health > 0 and part) or isIgnored(locked) then
            locked = nil
            needRelock = CONFIG.REACQUIRE
        end
    end

    if needRelock and not locked then
        acquire()
        if locked then needRelock = false end
    end

    if not locked then
        GENV.PrensadoSilentCF = nil
        return
    end

    local char = locked.Character
    local part = char and getPart(char)
    if not part then
        GENV.PrensadoSilentCF = nil
        return
    end

    if not CONFIG.STICKY then
        local sp, onScreen = Camera:WorldToViewportPoint(part.Position)
        local center = Camera.ViewportSize / 2
        if not onScreen or sp.Z <= 0
            or (Vector2.new(sp.X, sp.Y) - center).Magnitude > CONFIG.FOV / 2 then
            locked = nil
            needRelock = true
            GENV.PrensadoSilentCF = nil
            return
        end
    end

    local goal = predictPosition(part, char)
    local goalCF = CFrame.lookAt(Camera.CFrame.Position, goal)

    if CONFIG.MODE == "Silent" then
        GENV.PrensadoSilentCF = goalCF
        tryInstallSilent()
    else
        GENV.PrensadoSilentCF = nil
        if CONFIG.MODE == "Snap" then
            Camera.CFrame = goalCF
        else
            Camera.CFrame = Camera.CFrame:Lerp(goalCF, CONFIG.SMOOTHNESS)
        end
    end
end)

local gui = Instance.new("ScreenGui")
gui.Name = "PrensadoUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = CoreGui

local function mkBtn(parent, text, w, h, x, y)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(w, h)
    b.Position = UDim2.fromOffset(x, y)
    b.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
    b.TextColor3 = Color3.fromRGB(232, 232, 238)
    b.Font = Enum.Font.GothamMedium
    b.TextSize = 12
    b.Text = text
    b.BorderSizePixel = 0
    b.AutoButtonColor = true
    b.Parent = parent
    local c = Instance.new("UICorner", b)
    c.CornerRadius = UDim.new(0, 6)
    return b
end

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(250, 500)
panel.Position = UDim2.fromOffset(30, 50)
panel.BackgroundColor3 = Color3.fromRGB(18, 18, 21)
panel.BorderSizePixel = 0
panel.Active = true
panel.Parent = gui
local pc = Instance.new("UICorner", panel)
pc.CornerRadius = UDim.new(0, 10)
local ps = Instance.new("UIStroke", panel)
ps.Color = Color3.fromRGB(60, 60, 68)
ps.Thickness = 1

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, 0, 1, -40)
scroll.Position = UDim2.fromOffset(0, 36)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -40, 0, 32)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "  PRENSADO CAMLOCK v5"
title.Parent = panel

local closeBtn = mkBtn(panel, "X", 24, 24, 216, 4)
closeBtn.MouseButton1Click:Connect(function()
    panel.Visible = false
end)

local toggleBtn = mkBtn(scroll, "DESACTIVADO  [" .. CONFIG.KEY.Name .. "]", 220, 30, 14, 6)
toggleBtn.TextSize = 13
toggleBtn.BackgroundColor3 = Color3.fromRGB(52, 34, 34)

local function refreshToggle()
    toggleBtn.Text = (enabled and "ACTIVADO  [" or "DESACTIVADO  [") .. CONFIG.KEY.Name .. "]"
    toggleBtn.BackgroundColor3 = enabled and Color3.fromRGB(24, 74, 48)
        or Color3.fromRGB(52, 34, 34)
end

local function setEnabled(v)
    enabled = v
    locked = nil
    needRelock = v
    refreshToggle()
end

toggleBtn.MouseButton1Click:Connect(function()
    setEnabled(not enabled)
end)

local relockBtn = mkBtn(scroll, "RE-LOCK (cambiar objetivo)", 220, 24, 14, 40)
relockBtn.MouseButton1Click:Connect(function()
    if enabled then
        locked = nil
        needRelock = true
    end
end)

local partRow = { "Head", "Torso", "Random", "Closest" }
local partBtns = {}
for i, name in ipairs(partRow) do
    local b = mkBtn(scroll, name, 49, 24, 14 + (i - 1) * 52, 70)
    partBtns[name] = b
    b.BackgroundColor3 = (CONFIG.AIM_PART == name) and Color3.fromRGB(24, 74, 48)
        or Color3.fromRGB(30, 30, 34)
    b.MouseButton1Click:Connect(function()
        CONFIG.AIM_PART = name
        for n, bb in pairs(partBtns) do
            bb.BackgroundColor3 = (n == name) and Color3.fromRGB(24, 74, 48)
                or Color3.fromRGB(30, 30, 34)
        end
    end)
end

local modeRow = { "Smooth", "Snap", "Silent" }
local modeBtns = {}
for i, name in ipairs(modeRow) do
    local b = mkBtn(scroll, name, 68, 24, 14 + (i - 1) * 72, 100)
    modeBtns[name] = b
    b.BackgroundColor3 = (CONFIG.MODE == name) and Color3.fromRGB(24, 74, 48)
        or Color3.fromRGB(30, 30, 34)
    b.MouseButton1Click:Connect(function()
        CONFIG.MODE = name
        for n, bb in pairs(modeBtns) do
            bb.BackgroundColor3 = (n == name) and Color3.fromRGB(24, 74, 48)
                or Color3.fromRGB(30, 30, 34)
        end
    end)
end

local function mkStepper(label, y, get, set, step, min, max)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.fromOffset(110, 24)
    l.Position = UDim2.fromOffset(14, y)
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.Gotham
    l.TextSize = 12
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextColor3 = Color3.fromRGB(190, 190, 200)
    l.Text = label
    l.Parent = scroll

    local minus = mkBtn(scroll, "-", 26, 24, 126, y)
    local val = Instance.new("TextLabel")
    val.Size = UDim2.fromOffset(56, 24)
    val.Position = UDim2.fromOffset(156, y)
    val.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
    val.Font = Enum.Font.GothamMedium
    val.TextSize = 12
    val.TextColor3 = Color3.fromRGB(240, 240, 245)
    val.Text = tostring(get())
    val.Parent = scroll
    local vc = Instance.new("UICorner", val)
    vc.CornerRadius = UDim.new(0, 6)
    local plus = mkBtn(scroll, "+", 26, 24, 196, y)

    local function upd()
        val.Text = string.format("%.2f", get())
    end

    minus.MouseButton1Click:Connect(function()
        set(math.max(min, get() - step))
        upd()
    end)
    plus.MouseButton1Click:Connect(function()
        set(math.min(max, get() + step))
        upd()
    end)
    return upd
end

mkStepper("FOV (px)", 134,
    function() return CONFIG.FOV end,
    function(v) CONFIG.FOV = v end, 25, 50, 900)
mkStepper("Suavizado", 164,
    function() return CONFIG.SMOOTHNESS end,
    function(v) CONFIG.SMOOTHNESS = v end, 0.05, 0.05, 1)
mkStepper("Predicción (s)", 194,
    function() return CONFIG.PREDICTION end,
    function(v) CONFIG.PREDICTION = v end, 0.02, 0, 1)

local function mkCheck(parent, label, y, get, set)
    local b = mkBtn(parent, label, 220, 24, 14, y)
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.Text = "  " .. label
    local function paint()
        b.BackgroundColor3 = get() and Color3.fromRGB(24, 74, 48)
            or Color3.fromRGB(30, 30, 34)
    end
    paint()
    b.MouseButton1Click:Connect(function()
        set(not get())
        paint()
    end)
    return b
end

mkCheck(scroll, "Team check", 224,
    function() return CONFIG.TEAM_CHECK end,
    function(v) CONFIG.TEAM_CHECK = v end)
mkCheck(scroll, "Wall check", 252,
    function() return CONFIG.WALL_CHECK end,
    function(v) CONFIG.WALL_CHECK = v end)
mkCheck(scroll, "Círculo de FOV", 280,
    function() return CONFIG.SHOW_FOV end,
    function(v) CONFIG.SHOW_FOV = v end)
mkCheck(scroll, "Predicción ON", 308,
    function() return CONFIG.PREDICTION_ENABLED end,
    function(v) CONFIG.PREDICTION_ENABLED = v end)
mkCheck(scroll, "Compensar ping", 336,
    function() return CONFIG.PING_COMPENSATION end,
    function(v) CONFIG.PING_COMPENSATION = v end)

local ignoreLabel = Instance.new("TextLabel")
ignoreLabel.Size = UDim2.fromOffset(220, 22)
ignoreLabel.Position = UDim2.fromOffset(14, 366)
ignoreLabel.BackgroundTransparency = 1
ignoreLabel.Font = Enum.Font.GothamBold
ignoreLabel.TextSize = 12
ignoreLabel.TextColor3 = Color3.fromRGB(255, 200, 120)
ignoreLabel.TextXAlignment = Enum.TextXAlignment.Left
ignoreLabel.Text = "  Ignorados (no camlock)"
ignoreLabel.Parent = scroll

local ignoreFrame = Instance.new("Frame")
ignoreFrame.Size = UDim2.fromOffset(220, 130)
ignoreFrame.Position = UDim2.fromOffset(14, 390)
ignoreFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
ignoreFrame.BorderSizePixel = 0
ignoreFrame.Parent = scroll
local ifc = Instance.new("UICorner", ignoreFrame)
ifc.CornerRadius = UDim.new(0, 8)

local ignoreBox = Instance.new("TextBox")
ignoreBox.Size = UDim2.fromOffset(150, 24)
ignoreBox.Position = UDim2.fromOffset(8, 6)
ignoreBox.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
ignoreBox.TextColor3 = Color3.fromRGB(240, 240, 245)
ignoreBox.PlaceholderText = "Nombre..."
ignoreBox.PlaceholderColor3 = Color3.fromRGB(140, 140, 150)
ignoreBox.Font = Enum.Font.Gotham
ignoreBox.TextSize = 12
ignoreBox.Text = ""
ignoreBox.ClearTextOnFocus = false
ignoreBox.Parent = ignoreFrame
local ibc = Instance.new("UICorner", ignoreBox)
ibc.CornerRadius = UDim.new(0, 6)

local addBtn = mkBtn(ignoreFrame, "+", 44, 24, 164, 6)
addBtn.MouseButton1Click:Connect(function()
    if addIgnore(ignoreBox.Text) then
        ignoreBox.Text = ""
        if rebuildIgnoreList then rebuildIgnoreList() end
    end
end)

local listScroll = Instance.new("ScrollingFrame")
listScroll.Size = UDim2.new(1, -16, 1, -40)
listScroll.Position = UDim2.fromOffset(8, 36)
listScroll.BackgroundTransparency = 1
listScroll.BorderSizePixel = 0
listScroll.ScrollBarThickness = 4
listScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
listScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
listScroll.Parent = ignoreFrame

local listHolder = Instance.new("Frame")
listHolder.Size = UDim2.new(1, 0, 0, 0)
listHolder.BackgroundTransparency = 1
listHolder.AutomaticSize = Enum.AutomaticSize.Y
listHolder.Parent = listScroll
local ll = Instance.new("UIListLayout", listHolder)
ll.Padding = UDim.new(0, 4)
ll.SortOrder = Enum.SortOrder.LayoutOrder

function rebuildIgnoreList()
    for _, c in ipairs(listHolder:GetChildren()) do
        if c:IsA("TextButton") then
            c:Destroy()
        end
    end
    table.sort(CONFIG.IGNORE_LIST)
    for i, name in ipairs(CONFIG.IGNORE_LIST) do
        local row = mkBtn(listHolder, "X   " .. name, 194, 22, 0, 0)
        row.LayoutOrder = i
        row.TextXAlignment = Enum.TextXAlignment.Left
        row.BackgroundColor3 = Color3.fromRGB(52, 34, 34)
        row.MouseButton1Click:Connect(function()
            removeIgnore(name)
            rebuildIgnoreList()
            refreshESPAll()
        end)
    end
end

rebuildIgnoreList()

local espTitle = Instance.new("TextLabel")
espTitle.Size = UDim2.fromOffset(220, 22)
espTitle.Position = UDim2.fromOffset(14, 528)
espTitle.BackgroundTransparency = 1
espTitle.Font = Enum.Font.GothamBold
espTitle.TextSize = 12
espTitle.TextColor3 = Color3.fromRGB(120, 220, 255)
espTitle.TextXAlignment = Enum.TextXAlignment.Left
espTitle.Text = "  ESP / Chams"
espTitle.Parent = scroll

mkCheck(scroll, "ESP activado", 552,
    function() return CONFIG.ESP.Enabled end,
    function(v) CONFIG.ESP.Enabled = v; refreshESPAll() end)
mkCheck(scroll, "Solo enemigos", 580,
    function() return CONFIG.ESP.OnlyEnemies end,
    function(v) CONFIG.ESP.OnlyEnemies = v; refreshESPAll() end)
mkCheck(scroll, "Usar color de equipo", 608,
    function() return CONFIG.ESP.UseTeamColor end,
    function(v) CONFIG.ESP.UseTeamColor = v; refreshESPAll() end)

mkStepper("ESP Distancia", 636,
    function() return CONFIG.ESP.MaxDistance end,
    function(v) CONFIG.ESP.MaxDistance = v; refreshESPAll() end, 50, 50, 5000)
mkStepper("ESP Relleno", 666,
    function() return CONFIG.ESP.FillAlpha end,
    function(v) CONFIG.ESP.FillAlpha = v; refreshESPAll() end, 0.05, 0, 1)
mkStepper("ESP Contorno", 696,
    function() return CONFIG.ESP.OutlineAlpha end,
    function(v) CONFIG.ESP.OutlineAlpha = v; refreshESPAll() end, 0.05, 0, 1)

local function mkColorRow(label, y, getColor, setColor)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.fromOffset(90, 24)
    l.Position = UDim2.fromOffset(14, y)
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.Gotham
    l.TextSize = 12
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextColor3 = Color3.fromRGB(190, 190, 200)
    l.Text = label
    l.Parent = scroll

    local function mkColorStep(offX, channel)
        local minus = mkBtn(scroll, "-", 22, 24, 106 + offX, y)
        local val = Instance.new("TextLabel")
        val.Size = UDim2.fromOffset(36, 24)
        val.Position = UDim2.fromOffset(130 + offX, y)
        val.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
        val.Font = Enum.Font.GothamMedium
        val.TextSize = 11
        val.TextColor3 = Color3.fromRGB(240, 240, 245)
        val.Text = tostring(math.floor(getColor()[channel] * 255))
        val.Parent = scroll
        local vc = Instance.new("UICorner", val)
        vc.CornerRadius = UDim.new(0, 6)
        local plus = mkBtn(scroll, "+", 22, 24, 168 + offX, y)

        local function upd()
            val.Text = tostring(math.floor(getColor()[channel] * 255))
        end

        minus.MouseButton1Click:Connect(function()
            local c = getColor()
            local n = math.clamp(c[channel] - 0.05, 0, 1)
            setColor(Color3.new(
                channel == "R" and n or c.R,
                channel == "G" and n or c.G,
                channel == "B" and n or c.B
            ))
            upd()
        end)
        plus.MouseButton1Click:Connect(function()
            local c = getColor()
            local n = math.clamp(c[channel] + 0.05, 0, 1)
            setColor(Color3.new(
                channel == "R" and n or c.R,
                channel == "G" and n or c.G,
                channel == "B" and n or c.B
            ))
            upd()
        end)
    end

    mkColorStep(0, "R")
    mkColorStep(72, "G")
    mkColorStep(144, "B")
end

mkColorRow("Color relleno", 728,
    function() return CONFIG.ESP.FillColor end,
    function(c) CONFIG.ESP.FillColor = c; refreshESPAll() end)
mkColorRow("Color contorno", 758,
    function() return CONFIG.ESP.OutlineColor end,
    function(c) CONFIG.ESP.OutlineColor = c; refreshESPAll() end)

local dragging, dragStart, startPos
track(panel.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
        dragging, dragStart, startPos = true, i.Position