-- Panda-UIX-V3: flat ink-and-blue UI library for Roblox/Luau script hubs.
-- Ships two surfaces from one file: KeySystem (PUSL-V4 gate) and Window (hub UI).
-- The table this file returns is named PandaUI; see README.md for the API.
--
-- Every public callback runs inside xpcall. A failing callback reports to the
-- status bar and warn() instead of killing the signal, because a dead signal
-- leaves a toggle stuck in a state the user cannot clear.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Http = game:GetService("HttpService")
local Stats = game:GetService("Stats")

local PandaUI = {}
PandaUI.Version = "1.0.0"

local env = getgenv and getgenv() or _G
local me = Players.LocalPlayer
local playerGui = me:WaitForChild("PlayerGui")

PandaUI.Theme = {
    Ink = Color3.fromRGB(13, 13, 15),
    Blue = Color3.fromRGB(24, 115, 211),
    Paper = Color3.fromRGB(239, 239, 242),
    Muted = Color3.fromRGB(149, 149, 159),
    Wash = Color3.fromRGB(21, 21, 24),
    Line = Color3.fromRGB(43, 43, 48),
    ActiveWash = Color3.fromRGB(17, 33, 51),
    Good = Color3.fromRGB(56, 168, 104),
    Bad = Color3.fromRGB(208, 66, 66),
    Dim = Color3.fromRGB(75, 75, 82),
    Track = Color3.fromRGB(60, 67, 82),
}

local FONT = {
    Title = Enum.Font.GothamBlack,
    Bold = Enum.Font.GothamBold,
    Body = Enum.Font.Gotham,
    Mono = Enum.Font.Code,
}

-- ── primitives ───────────────────────────────────────────────────────────

local function new(class, props)
    local obj = Instance.new(class)
    for key, value in pairs(props or {}) do
        if key ~= "Parent" then obj[key] = value end
    end
    if props and props.Parent then obj.Parent = props.Parent end
    return obj
end

local function corner(obj, radius)
    new("UICorner", {CornerRadius = UDim.new(0, radius or 0), Parent = obj})
    return obj
end

local function outline(obj, color, width)
    new("UIStroke", {
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Color = color or PandaUI.Theme.Line,
        Thickness = width or 1,
        Parent = obj,
    })
    return obj
end

local function label(parent, value, size, font)
    return new("TextLabel", {
        BackgroundTransparency = 1,
        TextColor3 = PandaUI.Theme.Paper,
        Font = font or FONT.Body,
        TextSize = size or 12,
        Text = value or "",
        Parent = parent,
    })
end

local function viewport()
    local camera = workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

local function clip(value, limit)
    value = tostring(value)
    if #value > limit then return value:sub(1, limit - 1) .. "…" end
    return value
end

-- A pointer-driven horizontal drag that works for mouse and touch alike:
-- InputChanged fires with MouseMovement rather than the original MouseButton1
-- object, so the identity check has to accept both.
local function trackDrag(session, pad, onMove)
    session.connect(pad.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            session._pointer = input
            onMove(input.Position)
        end
    end)
    session.connect(Input.InputChanged, function(input)
        local pointer = session._pointer
        if not pointer then return end
        if input == pointer or (pointer.UserInputType == Enum.UserInputType.MouseButton1
            and input.UserInputType == Enum.UserInputType.MouseMovement) then
            onMove(input.Position)
        end
    end)
    session.connect(Input.InputEnded, function(input)
        if input == session._pointer or input.UserInputType == Enum.UserInputType.MouseButton1 then
            session._pointer = nil
        end
    end)
end

-- ── session: connection ownership and guarded callbacks ──────────────────

local function newSession(name)
    local session = {alive = true, connections = {}, name = name}

    function session.report(message)
        local line = clip(tostring(message), 200)
        warn("[PandaUI] " .. line)
        if session.onError then pcall(session.onError, line) end
        return line
    end

    -- Returns (ok, value): `ok` is false when the callback threw, `value` is
    -- whatever it returned. Controls that can refuse a change read `value`,
    -- so a callback returning false and a callback erroring both revert.
    function session.guard(callback, context)
        if type(callback) ~= "function" then return function() return true end end
        return function(...)
            if not session.alive then return true end
            local args = table.pack(...)
            local ok, result = xpcall(function()
                return callback(table.unpack(args, 1, args.n))
            end, tostring)
            if not ok then
                session.report((context or "callback") .. ": " .. tostring(result))
                return false, nil
            end
            return true, result
        end
    end

    function session.connect(signal, callback)
        local guarded = session.guard(callback, "signal")
        local c = signal:Connect(guarded)
        table.insert(session.connections, c)
        return c
    end

    function session.close()
        if not session.alive then return end
        session.alive = false
        for _, c in ipairs(session.connections) do pcall(function() c:Disconnect() end) end
        table.clear(session.connections)
    end

    return session
end

-- ── executor surface ─────────────────────────────────────────────────────
-- Every one of these is optional on a given executor, so each is probed
-- rather than called: a missing global must degrade, never error.

local function hasFile()
    return type(writefile) == "function" and type(readfile) == "function"
        and type(isfile) == "function"
end

local function ensureFolder(folder)
    if type(isfolder) ~= "function" or type(makefolder) ~= "function" then return false end
    local ok = pcall(function()
        if not isfolder(folder) then makefolder(folder) end
    end)
    return ok
end

local function readJson(path)
    if not hasFile() then return nil, "File storage unavailable" end
    local ok, data = pcall(function()
        if not isfile(path) then return nil end
        return Http:JSONDecode(readfile(path))
    end)
    if not ok then return nil, "Unreadable file" end
    if data ~= nil and type(data) ~= "table" then return nil, "Unexpected file contents" end
    return data
end

local function writeJson(path, value)
    if not hasFile() then return false, "File storage unavailable" end
    local folder = path:match("^(.*)/[^/]+$")
    if folder then ensureFolder(folder) end
    local ok = pcall(function() writefile(path, Http:JSONEncode(value)) end)
    return ok, ok and nil or "Write failed"
end

local function copyToClipboard(value)
    local setclip = setclipboard or toclipboard
    if not setclip then return false end
    return (pcall(setclip, tostring(value)))
end

local function localHwid()
    if type(gethwid) == "function" then
        local ok, value = pcall(gethwid)
        if ok and value and tostring(value) ~= "" then return tostring(value) end
    end
    return nil
end

local function executorName()
    if type(identifyexecutor) == "function" then
        local ok, value = pcall(identifyexecutor)
        if ok and type(value) == "string" and value ~= "" then return value end
    end
    return "Unknown"
end

local function safeProfileName()
    return me.Name:gsub("[^%w_%-]", "_")
end

-- ── shared chrome ────────────────────────────────────────────────────────
-- The blue offset shadow is a sibling of the panel, not a child: it has to
-- sit behind the panel while tracking its absolute size, which a child
-- cannot do once the panel is scaled by UIScale.

local function buildShell(session, opts)
    local theme = PandaUI.Theme
    local width, height = opts.width, opts.height

    local existing = playerGui:FindFirstChild(opts.guiName)
    if existing then existing:Destroy() end

    local gui = new("ScreenGui", {
        Name = opts.guiName,
        ResetOnSpawn = false,
        DisplayOrder = opts.displayOrder or 1000,
        IgnoreGuiInset = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        Parent = playerGui,
    })

    local panel = new("Frame", {
        Name = "Panel",
        Size = UDim2.fromOffset(width, height),
        Position = opts.position or UDim2.new(0.5, -width / 2, 0.13, 0),
        BackgroundColor3 = theme.Ink,
        BorderSizePixel = 0,
        ZIndex = 2,
        Parent = gui,
    })
    outline(panel, theme.Ink, 2)
    new("UISizeConstraint", {MaxSize = Vector2.new(width, height), Parent = panel})
    local scale = new("UIScale", {Parent = panel})

    local function fit()
        local size = viewport()
        local inset = GuiService:GetGuiInset()
        scale.Scale = math.max(0.25, math.min(1,
            (size.X - 40) / width,
            (size.Y - inset.Y - 40) / height))
    end
    fit()
    if workspace.CurrentCamera then
        session.connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), fit)
    end

    local shadow = new("Frame", {
        Name = "BlueOffsetShadow",
        BackgroundColor3 = theme.Blue,
        BorderSizePixel = 0,
        ZIndex = 1,
        Parent = gui,
    })
    local function syncShadow()
        shadow.Position = panel.Position + UDim2.fromOffset(8, 8)
        shadow.Size = UDim2.fromOffset(panel.AbsoluteSize.X, panel.AbsoluteSize.Y)
    end
    session.connect(panel:GetPropertyChangedSignal("AbsolutePosition"), syncShadow)
    session.connect(panel:GetPropertyChangedSignal("AbsoluteSize"), syncShadow)
    syncShadow()

    local header = new("Frame", {
        Name = "Header",
        BackgroundColor3 = theme.Ink,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 58),
        Parent = panel,
    })
    local ribbonWidth = math.min(194, math.floor(width * 0.42))
    new("Frame", {
        Name = "BrandRibbon",
        Size = UDim2.fromOffset(ribbonWidth, 58),
        BackgroundColor3 = theme.Blue,
        BorderSizePixel = 0,
        Parent = header,
    })
    -- Rotated ink wedge cuts the ribbon on a slant; cheaper and sharper than
    -- an image, and it scales with the panel because it is a plain Frame.
    new("Frame", {
        Name = "RibbonCut",
        Size = UDim2.fromOffset(30, 78),
        Position = UDim2.fromOffset(ribbonWidth - 11, -9),
        BackgroundColor3 = theme.Ink,
        BorderSizePixel = 0,
        Rotation = 18,
        Parent = header,
    })

    local title = label(header, (opts.title or "PANDA"):upper(), 23, FONT.Title)
    title.Name = "Title"
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextTruncate = Enum.TextTruncate.AtEnd
    title.Position = UDim2.fromOffset(18, 7)
    title.Size = UDim2.fromOffset(ribbonWidth - 34, 28)

    local badgeText = (opts.badge or ""):upper():gsub("", " "):sub(2, -2)
    local badge = label(header, badgeText, 9, FONT.Mono)
    badge.Name = "Badge"
    badge.TextXAlignment = Enum.TextXAlignment.Left
    badge.TextTruncate = Enum.TextTruncate.AtEnd
    badge.Position = UDim2.fromOffset(18, 34)
    badge.Size = UDim2.fromOffset(ribbonWidth - 34, 16)

    local function headerButton(glyph, x, accent)
        local b = new("TextButton", {
            Size = UDim2.fromOffset(26, 26),
            Position = UDim2.new(1, x, 0, 15),
            Text = glyph,
            TextSize = 22,
            Font = FONT.Body,
            BackgroundColor3 = accent and theme.Blue or theme.Ink,
            TextColor3 = theme.Paper,
            BorderSizePixel = 0,
            ZIndex = 5,
            Parent = header,
        })
        outline(b, theme.Dim)
        return b
    end

    local drag = new("TextButton", {
        Name = "DragHandle",
        Text = "",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -80, 1, 0),
        ZIndex = 4,
        Parent = header,
    })

    local function clampPanel(x, y)
        local size = viewport()
        local inset = GuiService:GetGuiInset()
        local maxX = math.max(8, size.X - panel.AbsoluteSize.X - 16)
        local maxY = math.max(8, size.Y - inset.Y - panel.AbsoluteSize.Y - 16)
        panel.Position = UDim2.fromOffset(math.clamp(x, 8, maxX), math.clamp(y, 8, maxY))
    end

    local pointerStart, panelStart
    local dragSession = {connect = session.connect}
    trackDrag(dragSession, drag, function(position)
        if not pointerStart then
            pointerStart, panelStart = position, panel.AbsolutePosition
        end
        local delta = position - pointerStart
        clampPanel(panelStart.X + delta.X, panelStart.Y + delta.Y)
    end)
    session.connect(Input.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            pointerStart, panelStart = nil, nil
        end
    end)
    session.connect(panel:GetPropertyChangedSignal("AbsoluteSize"), function()
        if not dragSession._pointer then
            clampPanel(panel.AbsolutePosition.X, panel.AbsolutePosition.Y)
        end
    end)

    return {
        gui = gui,
        panel = panel,
        shadow = shadow,
        header = header,
        title = title,
        badge = badge,
        ribbonWidth = ribbonWidth,
        headerButton = headerButton,
        fit = fit,
        clamp = clampPanel,
    }
end

local function buildFooter(session, panel, opts)
    local theme = PandaUI.Theme
    local footer = new("Frame", {
        Name = "Footer",
        BackgroundColor3 = theme.Ink,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 1, -38),
        Size = UDim2.new(1, 0, 0, 38),
        Parent = panel,
    })
    local left = label(footer, opts.left or "", 10, FONT.Mono)
    left.Name = "LeftSlot"
    left.TextXAlignment = Enum.TextXAlignment.Left
    left.Position = UDim2.fromOffset(12, 4)
    left.Size = UDim2.fromOffset(170, 30)

    local status = label(footer, opts.status or "Ready", 11, FONT.Mono)
    status.Name = "Status"
    status.Position = UDim2.fromOffset(192, 4)
    status.Size = UDim2.new(1, -390, 0, 30)
    status.TextWrapped = true

    local right = label(footer, opts.right or "", 10, FONT.Mono)
    right.Name = "RightSlot"
    right.TextXAlignment = Enum.TextXAlignment.Right
    right.Position = UDim2.new(1, -190, 0, 4)
    right.Size = UDim2.fromOffset(176, 30)

    return {frame = footer, left = left, status = status, right = right}
end

-- ── Column: the element host ─────────────────────────────────────────────

local Column = {}
Column.__index = Column

local function nextOrder(column)
    column._order = column._order + 1
    return column._order
end

local function mount(column, instance)
    instance.LayoutOrder = nextOrder(column)
    instance.Parent = column.Content
    return instance
end

local function menuButton(parent, caption, height)
    local b = new("TextButton", {
        Text = caption,
        Size = UDim2.new(1, -8, 0, height or 34),
        BackgroundColor3 = PandaUI.Theme.Ink,
        TextColor3 = PandaUI.Theme.Paper,
        BorderSizePixel = 0,
        Font = FONT.Mono,
        TextSize = 12,
        TextWrapped = true,
        Parent = parent,
    })
    corner(b)
    return b
end

function Column:Label(value, size)
    local l = label(nil, value, size or 13, FONT.Bold)
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Size = UDim2.new(1, -8, 0, (size or 13) + 11)
    mount(self, l)
    return {Instance = l, Set = function(_, v) l.Text = tostring(v) end}
end

function Column:Paragraph(value, height)
    local l = label(nil, value, 11, FONT.Body)
    l.TextColor3 = PandaUI.Theme.Muted
    l.TextWrapped = true
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Top
    l.Size = UDim2.new(1, -8, 0, height or 42)
    mount(self, l)
    return {Instance = l, Set = function(_, v) l.Text = tostring(v) end}
end

function Column:Divider()
    local holder = new("Frame", {Size = UDim2.new(1, -8, 0, 9), BackgroundTransparency = 1})
    new("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.fromOffset(0, 4),
        BackgroundColor3 = PandaUI.Theme.Line,
        BorderSizePixel = 0,
        Parent = holder,
    })
    mount(self, holder)
    return {Instance = holder}
end

function Column:Info(caption, value, height)
    local row = new("Frame", {
        Size = UDim2.new(1, -8, 0, height or 46),
        BackgroundTransparency = 1,
    })
    local cap = label(row, tostring(caption):upper(), 9, FONT.Mono)
    cap.TextColor3 = PandaUI.Theme.Muted
    cap.TextXAlignment = Enum.TextXAlignment.Left
    cap.Size = UDim2.new(1, 0, 0, 14)
    local body = label(row, tostring(value or "-"), 13, FONT.Body)
    body.TextXAlignment = Enum.TextXAlignment.Left
    body.TextYAlignment = Enum.TextYAlignment.Top
    body.TextWrapped = true
    body.Position = UDim2.fromOffset(0, 18)
    body.Size = UDim2.new(1, 0, 1, -18)
    mount(self, row)
    return {
        Instance = row,
        Value = body,
        Set = function(_, v) body.Text = tostring(v) end,
        SetCaption = function(_, v) cap.Text = tostring(v):upper() end,
    }
end

function Column:Button(opts)
    opts = opts or {}
    local b = menuButton(nil, (opts.Text or "BUTTON"):upper(), opts.Height or 36)
    if opts.Primary == false then
        outline(b, PandaUI.Theme.Line)
    else
        b.BackgroundColor3 = PandaUI.Theme.Blue
    end
    mount(self, b)
    local session = self.Session
    session.connect(b.Activated, function()
        session.guard(opts.Callback, opts.Text or "Button")()
    end)
    return {
        Instance = b,
        Set = function(_, v) b.Text = tostring(v):upper() end,
        SetEnabled = function(_, on)
            b.Active = on ~= false
            b.AutoButtonColor = on ~= false
            b.TextColor3 = on ~= false and PandaUI.Theme.Paper or PandaUI.Theme.Muted
        end,
    }
end

function Column:Toggle(opts)
    opts = opts or {}
    local theme = PandaUI.Theme
    local text = opts.Text or "Toggle"
    local b = new("TextButton", {
        Name = text:gsub("%s", "") .. "Toggle",
        Size = UDim2.new(1, -8, 0, 40),
        Font = FONT.Bold,
        TextSize = 13,
        Text = "",
        BorderSizePixel = 0,
        AutoButtonColor = false,
        BackgroundColor3 = theme.Wash,
    })
    b:SetAttribute("Label", text)
    corner(b)
    outline(b, theme.Line)

    local caption = label(b, text, 13, FONT.Bold)
    caption.Name = "LabelText"
    caption.TextXAlignment = Enum.TextXAlignment.Left
    caption.TextTruncate = Enum.TextTruncate.AtEnd
    caption.Position = UDim2.fromOffset(12, 0)
    caption.Size = UDim2.new(1, -69, 1, 0)

    local flag = label(b, "OFF", 11, FONT.Mono)
    flag.Name = "Flag"
    flag.BackgroundTransparency = 0
    flag.BackgroundColor3 = theme.Wash
    flag.TextColor3 = theme.Muted
    flag.Size = UDim2.fromOffset(36, 22)
    flag.Position = UDim2.new(1, -46, 0.5, -11)

    local accent = new("Frame", {
        Name = "Accent",
        Size = UDim2.new(0, 3, 1, 0),
        BorderSizePixel = 0,
        BackgroundColor3 = theme.Blue,
        Visible = false,
        Parent = b,
    })

    mount(self, b)

    local window, session = self.Window, self.Session
    local control = {Instance = b, Value = false, Flag = opts.Flag}

    local function paint()
        flag.Text = control.Value and "ON" or "OFF"
        flag.BackgroundColor3 = control.Value and theme.Blue or theme.Wash
        flag.TextColor3 = control.Value and theme.Paper or theme.Muted
        b.BackgroundColor3 = control.Value and theme.ActiveWash or theme.Wash
        accent.Visible = control.Value
    end

    -- A callback that errors must not leave the pill reading ON while the
    -- feature it drives is off, so the visual state reverts with it.
    function control:Set(value, silent)
        local previous = self.Value
        self.Value = value == true
        paint()
        if opts.Flag then window.Flags[opts.Flag] = self.Value end
        if silent then return true end
        local ok, refused = session.guard(opts.Callback, text)(self.Value)
        if not ok or refused == false then
            self.Value = previous
            paint()
            if opts.Flag then window.Flags[opts.Flag] = previous end
            window:SetStatus(text .. " unavailable; reverted")
            return false
        end
        window:SetStatus(text .. (self.Value and " enabled" or " disabled"))
        window:_autosave()
        return true
    end

    function control:Get() return self.Value end

    session.connect(b.Activated, function() control:Set(not control.Value) end)
    control:Set(opts.Default == true, true)
    if opts.Flag then window._controls[opts.Flag] = control end
    return control
end

function Column:Slider(opts)
    opts = opts or {}
    local theme = PandaUI.Theme
    local text = opts.Text or "Value"
    local min = opts.Min or 0
    local max = opts.Max or 100
    local step = opts.Step or 1
    local suffix = opts.Suffix or ""
    local segmented = opts.Style == "Segments"
    local span = math.max(max - min, 1e-6)

    local holder = new("Frame", {
        Size = UDim2.new(1, -8, 0, segmented and 58 or 64),
        BackgroundColor3 = theme.Ink,
        BackgroundTransparency = segmented and 1 or 0,
        BorderSizePixel = 0,
    })
    if not segmented then corner(holder) end

    local caption = label(holder, text, segmented and 11 or 12, FONT.Mono)
    caption.TextXAlignment = Enum.TextXAlignment.Left
    caption.Size = UDim2.new(1, -20, 0, segmented and 22 or 26)
    caption.Position = UDim2.fromOffset(segmented and 0 or 10, segmented and 0 or 2)

    local pad, fill, knob, blocks
    if segmented then
        pad = new("TextButton", {
            Text = "",
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(0, 28),
            Size = UDim2.new(1, 0, 0, 22),
            Parent = holder,
        })
        blocks = {}
        local count = opts.Segments or 18
        for i = 1, count do
            table.insert(blocks, new("Frame", {
                BorderSizePixel = 0,
                BackgroundColor3 = theme.Line,
                Position = UDim2.new((i - 1) / count, 0, 0, 4),
                Size = UDim2.new(1 / count, -3, 0, 14),
                Parent = pad,
            }))
        end
    else
        pad = new("TextButton", {
            Name = "Bar",
            Text = "",
            AutoButtonColor = false,
            Size = UDim2.new(1, -28, 0, 10),
            Position = UDim2.fromOffset(14, 38),
            BackgroundColor3 = theme.Track,
            Parent = holder,
        })
        corner(pad, 5)
        fill = new("Frame", {BackgroundColor3 = theme.Blue, BorderSizePixel = 0, Parent = pad})
        corner(fill, 5)
        knob = new("Frame", {
            Size = UDim2.fromOffset(18, 18),
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = Color3.new(1, 1, 1),
            Parent = pad,
        })
        corner(knob, 9)
    end

    mount(self, holder)

    local window, session = self.Window, self.Session
    local control = {Instance = holder, Value = min, Flag = opts.Flag}

    local function paint()
        local alpha = (control.Value - min) / span
        if segmented then
            for i, block in ipairs(blocks) do
                block.BackgroundColor3 = (i - 1) / #blocks <= alpha and theme.Blue or theme.Line
            end
            caption.Text = text:upper() .. "  /  " .. control.Value .. suffix
        else
            fill.Size = UDim2.fromScale(alpha, 1)
            knob.Position = UDim2.fromScale(alpha, 0.5)
            caption.Text = text .. ": " .. control.Value .. suffix
                .. "  " .. string.char(226, 128, 162) .. "  range " .. min .. " to " .. max
        end
    end

    function control:Set(value, silent)
        local number = tonumber(value)
        -- NaN fails every comparison, so clamp would pass it straight through.
        if not number or number ~= number then return false end
        number = math.clamp(number, min, max)
        self.Value = math.clamp(min + math.floor((number - min) / step + 0.5) * step, min, max)
        paint()
        if opts.Flag then window.Flags[opts.Flag] = self.Value end
        if not silent then
            session.guard(opts.Callback, text)(self.Value)
            window:_autosave()
        end
        return true
    end

    function control:Get() return self.Value end

    local dragState = {connect = session.connect}
    trackDrag(dragState, pad, function(position)
        if pad.AbsoluteSize.X <= 0 then return end
        local alpha = math.clamp((position.X - pad.AbsolutePosition.X) / pad.AbsoluteSize.X, 0, 1)
        control:Set(min + alpha * span)
    end)

    control:Set(opts.Default or min, true)
    if opts.Flag then window._controls[opts.Flag] = control end
    return control
end

function Column:TextBox(opts)
    opts = opts or {}
    local theme = PandaUI.Theme
    local holder = new("Frame", {
        Size = UDim2.new(1, -8, 0, opts.Label and 56 or 34),
        BackgroundTransparency = 1,
    })
    local top = 0
    if opts.Label then
        local caption = label(holder, tostring(opts.Label):upper(), 9, FONT.Mono)
        caption.TextColor3 = theme.Muted
        caption.TextXAlignment = Enum.TextXAlignment.Left
        caption.Size = UDim2.new(1, 0, 0, 14)
        top = 20
    end
    local box = new("TextBox", {
        Size = UDim2.new(1, 0, 0, 34),
        Position = UDim2.fromOffset(0, top),
        BackgroundColor3 = theme.Wash,
        TextColor3 = theme.Paper,
        PlaceholderColor3 = theme.Muted,
        PlaceholderText = opts.Placeholder or "",
        Text = opts.Default or "",
        ClearTextOnFocus = opts.ClearOnFocus == true,
        Font = FONT.Mono,
        TextSize = 12,
        BorderSizePixel = 0,
        Parent = holder,
    })
    corner(box)
    outline(box, theme.Line)
    local stroke = box:FindFirstChildOfClass("UIStroke")
    mount(self, holder)

    local window, session = self.Window, self.Session
    local control = {Instance = holder, Box = box, Flag = opts.Flag}

    session.connect(box.Focused, function() stroke.Color = theme.Blue end)
    session.connect(box.FocusLost, function(enter)
        stroke.Color = theme.Line
        if opts.Flag then window.Flags[opts.Flag] = box.Text end
        session.guard(opts.Callback, opts.Label or "TextBox")(box.Text, enter)
        window:_autosave()
    end)

    function control:Set(value, silent)
        box.Text = tostring(value or "")
        if opts.Flag then window.Flags[opts.Flag] = box.Text end
        if not silent then session.guard(opts.Callback, "TextBox")(box.Text, false) end
        return true
    end
    function control:Get() return box.Text end

    if opts.Flag then
        window.Flags[opts.Flag] = box.Text
        window._controls[opts.Flag] = control
    end
    return control
end

function Column:Keybind(opts)
    opts = opts or {}
    local text = opts.Text or "Keybind"
    local b = menuButton(nil, "", opts.Height or 42)
    b.BackgroundColor3 = PandaUI.Theme.Blue
    mount(self, b)

    local window, session = self.Window, self.Session
    local control = {Instance = b, Value = opts.Default or "RightAlt", Flag = opts.Flag}
    local capturing = false

    local function paint()
        b.Text = text:upper() .. ":  " .. tostring(control.Value):upper()
    end

    function control:Set(name, silent)
        local ok, key = pcall(function() return Enum.KeyCode[tostring(name)] end)
        if not ok or not key or key == Enum.KeyCode.Unknown or key == Enum.KeyCode.Escape then
            return false
        end
        self.Value = key.Name
        paint()
        if opts.Flag then window.Flags[opts.Flag] = self.Value end
        if not silent then
            session.guard(opts.Callback, text)(key)
            window:_autosave()
        end
        return true
    end
    function control:Get() return self.Value end

    -- While capturing, the window's own show/hide shortcut must stand down or
    -- binding that same key would hide the panel on the keystroke that set it.
    local function setCapturing(on)
        capturing = on
        window._capturing = (window._capturing or 0) + (on and 1 or -1)
        if window._capturing < 0 then window._capturing = 0 end
    end

    session.connect(b.Activated, function()
        if capturing then return end
        setCapturing(true)
        b.Text = "PRESS A KEY  /  ESC TO CANCEL"
    end)
    session.connect(Input.InputBegan, function(input)
        if not capturing or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        if input.KeyCode == Enum.KeyCode.Escape then
            setCapturing(false)
            paint()
        elseif control:Set(input.KeyCode.Name) then
            setCapturing(false)
        end
    end)

    control:Set(control.Value, true)
    if opts.Flag then window._controls[opts.Flag] = control end
    return control
end

-- Dropdown: a pinned header plus an optional search box over a scrolling
-- list. Options are rebuildable at runtime (player lists change mid-session),
-- so the rows are torn down and re-made rather than diffed.
function Column:Dropdown(opts)
    opts = opts or {}
    local theme = PandaUI.Theme
    local text = opts.Text or "Select"
    local multi = opts.Multi == true
    local searchable = opts.Search ~= false

    local header = menuButton(nil, "", 34)
    mount(self, header)

    local container = new("Frame", {
        Size = UDim2.new(1, -8, 0, opts.Height or 180),
        BackgroundTransparency = 1,
        Visible = opts.Open ~= false,
    })
    mount(self, container)

    local listTop = 0
    local search
    if searchable then
        search = new("TextBox", {
            Size = UDim2.new(1, -4, 0, 30),
            BackgroundColor3 = theme.Wash,
            TextColor3 = theme.Paper,
            PlaceholderColor3 = theme.Muted,
            PlaceholderText = "Search " .. text:lower() .. "...",
            Text = "",
            ClearTextOnFocus = false,
            Font = FONT.Mono,
            TextSize = 12,
            BorderSizePixel = 0,
            Parent = container,
        })
        corner(search)
        listTop = 35
    end

    local list = new("ScrollingFrame", {
        Position = UDim2.fromOffset(0, listTop),
        Size = UDim2.new(1, 0, 1, -listTop),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = theme.Blue,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        Parent = container,
    })
    new("UIListLayout", {
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = list,
    })

    local window, session = self.Window, self.Session
    local control = {
        Instance = container,
        Header = header,
        Value = multi and {} or nil,
        Flag = opts.Flag,
        _options = {},
        _rows = {},
    }

    local function selectedNames()
        local names = {}
        for _, option in ipairs(control._options) do
            if multi then
                if control.Value[option.Id] then table.insert(names, option.Name) end
            elseif control.Value == option.Id then
                return option.Name
            end
        end
        if multi then
            if #names == 0 then return "None" end
            if #names > 2 then return #names .. " selected" end
            return table.concat(names, ", ")
        end
        return opts.Placeholder or "None"
    end

    local function paint()
        header.Text = text .. ": " .. selectedNames() .. "  " .. string.char(226, 150, 190)
        for _, row in ipairs(control._rows) do
            local on = multi and control.Value[row.id] == true or control.Value == row.id
            row.button.BackgroundColor3 = on and theme.Blue or theme.Ink
            row.button.TextColor3 = on and theme.Paper or theme.Muted
        end
    end

    local function fire(silent)
        if opts.Flag then
            window.Flags[opts.Flag] = multi and table.clone(control.Value) or control.Value
        end
        paint()
        if not silent then
            session.guard(opts.Callback, text)(control.Value)
            window:_autosave()
        end
    end

    function control:SetOptions(options)
        for _, row in ipairs(self._rows) do row.button:Destroy() end
        table.clear(self._rows)
        self._options = {}
        for index, raw in ipairs(options or {}) do
            local option
            if type(raw) == "table" then
                option = {Id = raw.Id or raw.id or raw.Name or raw.name, Name = tostring(raw.Name or raw.name or raw.Id or raw.id)}
            else
                option = {Id = raw, Name = tostring(raw)}
            end
            table.insert(self._options, option)
            local b = menuButton(list, option.Name, opts.RowHeight or 30)
            b.LayoutOrder = index
            b.TextXAlignment = Enum.TextXAlignment.Center
            table.insert(self._rows, {button = b, id = option.Id, search = option.Name:lower()})
            session.connect(b.Activated, function()
                if multi then
                    self.Value[option.Id] = not self.Value[option.Id] or nil
                else
                    self.Value = option.Id
                    if opts.CloseOnPick then container.Visible = false end
                end
                fire(false)
            end)
        end
        -- Rebuilding the option list is not a user choice, so it repaints and
        -- updates the flag without firing the callback.
        fire(true)
        return self
    end

    -- A value restored from a config file has been through JSON, which spells
    -- every table key as a string. A set of numeric ids would therefore never
    -- match the live options again, so both branches resolve by string.
    function control:Set(value, silent)
        if multi then
            local wanted = {}
            if type(value) == "table" then
                for k, v in pairs(value) do
                    if v == true then
                        wanted[tostring(k)] = true
                    elseif type(k) == "number" then
                        wanted[tostring(v)] = true
                    end
                end
            end
            self.Value = {}
            for _, option in ipairs(self._options) do
                if wanted[tostring(option.Id)] then self.Value[option.Id] = true end
            end
        else
            self.Value = value
            if value ~= nil then
                for _, option in ipairs(self._options) do
                    if tostring(option.Id) == tostring(value) then
                        self.Value = option.Id
                        break
                    end
                end
            end
        end
        fire(silent == true)
        return true
    end

    function control:Get() return self.Value end

    if searchable then
        session.connect(search:GetPropertyChangedSignal("Text"), function()
            local query = search.Text:lower()
            for _, row in ipairs(control._rows) do
                row.button.Visible = row.search:find(query, 1, true) ~= nil
            end
        end)
    end
    session.connect(header.Activated, function()
        if opts.Collapsible ~= false then container.Visible = not container.Visible end
    end)

    control:SetOptions(opts.Options)
    if opts.Default ~= nil then control:Set(opts.Default, true) end
    if opts.Flag then window._controls[opts.Flag] = control end
    return control
end

-- Grid: a searchable card wall, for things like a teleport destination list
-- where every entry is an action rather than a persisted setting.
function Column:Grid(opts)
    opts = opts or {}
    local theme = PandaUI.Theme
    local columns = opts.Columns or 2
    local cellHeight = opts.CellHeight or 48

    local holder = new("Frame", {
        Size = UDim2.new(1, -8, 0, opts.Height or 240),
        BackgroundTransparency = 1,
    })
    local gridTop = 0
    local search
    if opts.Search ~= false then
        search = new("TextBox", {
            Size = UDim2.new(1, 0, 0, 34),
            BackgroundColor3 = theme.Wash,
            TextColor3 = theme.Paper,
            PlaceholderColor3 = theme.Muted,
            PlaceholderText = opts.Placeholder or "Search...",
            Text = "",
            ClearTextOnFocus = false,
            Font = FONT.Mono,
            TextSize = 13,
            BorderSizePixel = 0,
            Parent = holder,
        })
        corner(search)
        gridTop = 42
    end

    local wall = new("ScrollingFrame", {
        Position = UDim2.fromOffset(0, gridTop),
        Size = UDim2.new(1, 0, 1, -gridTop),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = theme.Blue,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        Parent = holder,
    })
    new("UIGridLayout", {
        CellSize = UDim2.new(1 / columns, -10, 0, cellHeight),
        CellPadding = UDim2.fromOffset(10, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = wall,
    })

    mount(self, holder)

    local window, session = self.Window, self.Session
    local control = {Instance = holder, _rows = {}}

    local function applyFilter()
        local query = search and search.Text:lower() or ""
        for _, row in ipairs(control._rows) do
            row.button.Visible = row.search:find(query, 1, true) ~= nil
        end
    end

    function control:SetItems(items)
        for _, row in ipairs(self._rows) do row.button:Destroy() end
        table.clear(self._rows)
        for index, item in ipairs(items or {}) do
            local caption = tostring(item.Text or item.text or "?")
            local sub = item.Sub or item.sub
            local b = menuButton(wall, sub and (caption .. "\n" .. sub) or caption, cellHeight)
            b.Size = UDim2.new()
            b.LayoutOrder = item.Order or index
            if item.Disabled then
                b.TextColor3 = theme.Muted
                b.AutoButtonColor = false
            elseif item.Primary then
                b.BackgroundColor3 = theme.Blue
            end
            table.insert(self._rows, {button = b, search = (caption .. " " .. tostring(sub or "")):lower()})
            if not item.Disabled then
                session.connect(b.Activated, function()
                    session.guard(item.Callback or opts.Callback, caption)(item.Id or caption, item)
                end)
            end
        end
        applyFilter()
        return self
    end

    if search then
        session.connect(search:GetPropertyChangedSignal("Text"), applyFilter)
    end

    control:SetItems(opts.Items)
    return control
end

-- ── Tab ──────────────────────────────────────────────────────────────────

local Tab = {}
Tab.__index = Tab

-- Columns are equal halves, thirds and so on, recomputed whenever one is
-- added so a tab can grow a third column without the caller doing maths.
local COLUMN_GAP = 14

local function relayoutColumns(tab)
    local count = #tab.Columns
    for index, column in ipairs(tab.Columns) do
        column.Card.Size = UDim2.new(1 / count, -(count - 1) * COLUMN_GAP / count, 1, 0)
        column.Card.Position = UDim2.new((index - 1) / count, (index - 1) * COLUMN_GAP / count, 0, 0)
    end
end

function Tab:Column(heading)
    local theme = PandaUI.Theme
    local card = new("Frame", {
        Name = tostring(heading or "Column"):gsub("[^%w]", ""),
        BackgroundColor3 = theme.Wash,
        BorderSizePixel = 0,
        Parent = self.Page,
    })
    outline(card, theme.Line)

    local content = new("ScrollingFrame", {
        Name = "Content",
        Position = UDim2.fromOffset(12, 10),
        Size = UDim2.new(1, -24, 1, -20),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = theme.Blue,
        Parent = card,
    })
    new("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        Parent = content,
    })

    local column = setmetatable({
        Card = card,
        Content = content,
        Window = self.Window,
        Session = self.Session,
        Tab = self,
        _order = 0,
    }, Column)

    if heading then
        local head = label(content, tostring(heading):upper(), 13, FONT.Bold)
        head.TextXAlignment = Enum.TextXAlignment.Left
        head.Size = UDim2.new(1, -8, 0, 24)
        head.LayoutOrder = nextOrder(column)
    end

    table.insert(self.Columns, column)
    relayoutColumns(self)
    return column
end

function Tab:Select()
    self.Window:SelectTab(self.Name)
    return self
end

-- ── Window ───────────────────────────────────────────────────────────────

local Window = {}
Window.__index = Window

function Window:SetStatus(message)
    if not self.Session.alive then return self end
    self.Footer.status.Text = tostring(message)
    return self
end

function Window:SetVisible(visible)
    self.Visible = visible == true
    self.Shell.panel.Visible = self.Visible
    self.Shell.shadow.Visible = self.Visible
    self.Opener.Visible = not self.Visible
    return self
end

function Window:ToggleVisible()
    return self:SetVisible(not self.Visible)
end

function Window:SetKeybind(key)
    local ok, code = pcall(function()
        return typeof(key) == "EnumItem" and key or Enum.KeyCode[tostring(key)]
    end)
    if not ok or not code or code == Enum.KeyCode.Unknown then return false end
    self.Keybind = code
    self.Footer.left.Text = code.Name:upper() .. "  /  SHOW " .. string.char(194, 183) .. " HIDE"
    return true
end

function Window:SelectTab(name)
    local tab = self.Tabs[name]
    if not tab then return self end
    self.ActiveTab = name
    self.PageTitle.Text = tab.Title
    self.PageDescription.Text = tab.Description
    for id, other in pairs(self.Tabs) do
        local selected = id == name
        other.Page.Visible = selected
        other.Button.BackgroundColor3 = selected and PandaUI.Theme.Blue or PandaUI.Theme.Ink
        other.Button.TextColor3 = selected and PandaUI.Theme.Paper or PandaUI.Theme.Muted
        other.Underline.Visible = selected
    end
    return self
end

function Window:Tab(opts)
    opts = opts or {}
    local theme = PandaUI.Theme
    local name = opts.Name or ("Tab" .. (#self.TabOrder + 1))
    if self.Tabs[name] then return self.Tabs[name] end

    local group = opts.Group and tostring(opts.Group):upper() or nil
    if group and group ~= self._lastGroup then
        local head = label(self.Sidebar, group, 9, FONT.Mono)
        head.TextXAlignment = Enum.TextXAlignment.Left
        head.TextColor3 = theme.Muted
        head.Position = UDim2.fromOffset(14, self._sidebarY)
        head.Size = UDim2.fromOffset(150, 20)
        self._sidebarY = self._sidebarY + 24
        self._lastGroup = group
    end

    local page = new("Frame", {
        Name = name .. "Page",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
        Parent = self.Body,
    })

    local index = #self.TabOrder + 1
    local button = new("TextButton", {
        Name = name .. "Tab",
        Size = UDim2.new(1, -6, 0, 32),
        Position = UDim2.fromOffset(0, self._sidebarY),
        BorderSizePixel = 0,
        AutoButtonColor = false,
        BackgroundColor3 = theme.Ink,
        TextColor3 = theme.Muted,
        Font = FONT.Mono,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = string.format("  %02d  %s", index, name:upper()),
        Parent = self.Sidebar,
    })
    self._sidebarY = self._sidebarY + 34
    local underline = new("Frame", {
        Name = "Underline",
        BorderSizePixel = 0,
        BackgroundColor3 = theme.Paper,
        Size = UDim2.new(0, 3, 1, 0),
        Visible = false,
        Parent = button,
    })

    local tab = setmetatable({
        Name = name,
        Title = (opts.Title or name):upper(),
        Description = opts.Description or "",
        Page = page,
        Button = button,
        Underline = underline,
        Columns = {},
        Window = self,
        Session = self.Session,
    }, Tab)

    self.Tabs[name] = tab
    table.insert(self.TabOrder, name)
    self.Session.connect(button.Activated, function() self:SelectTab(name) end)
    if #self.TabOrder == 1 then self:SelectTab(name) end
    return tab
end

-- ── notifications and dialogs ────────────────────────────────────────────

function Window:Notify(opts)
    if not self.Session.alive then return end
    if type(opts) == "string" then opts = {Text = opts} end
    opts = opts or {}
    local theme = PandaUI.Theme

    local card = new("Frame", {
        Size = UDim2.fromOffset(300, 64),
        BackgroundColor3 = theme.Ink,
        BorderSizePixel = 0,
        Parent = self.ToastLayer,
    })
    outline(card, theme.Line)
    new("Frame", {
        Size = UDim2.new(0, 3, 1, 0),
        BorderSizePixel = 0,
        BackgroundColor3 = opts.Bad and theme.Bad or (opts.Good and theme.Good or theme.Blue),
        Parent = card,
    })
    local title = label(card, tostring(opts.Title or "PANDA"):upper(), 10, FONT.Mono)
    title.TextColor3 = theme.Muted
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Position = UDim2.fromOffset(14, 8)
    title.Size = UDim2.new(1, -24, 0, 14)
    local body = label(card, tostring(opts.Text or ""), 12, FONT.Body)
    body.TextXAlignment = Enum.TextXAlignment.Left
    body.TextYAlignment = Enum.TextYAlignment.Top
    body.TextWrapped = true
    body.Position = UDim2.fromOffset(14, 24)
    body.Size = UDim2.new(1, -24, 0, 34)

    task.delay(opts.Duration or 4, function()
        if card.Parent then card:Destroy() end
    end)
    return card
end

function Window:Dialog(opts)
    opts = opts or {}
    local theme = PandaUI.Theme
    if self._dialog then self._dialog:Destroy() end

    local veil = new("TextButton", {
        Name = "DialogVeil",
        Text = "",
        AutoButtonColor = false,
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 0.45,
        BorderSizePixel = 0,
        ZIndex = 20,
        Parent = self.Shell.panel,
    })
    self._dialog = veil

    local card = new("Frame", {
        Size = UDim2.fromOffset(380, 190),
        Position = UDim2.new(0.5, -190, 0.5, -95),
        BackgroundColor3 = theme.Ink,
        BorderSizePixel = 0,
        ZIndex = 21,
        Parent = veil,
    })
    outline(card, theme.Blue, 2)
    local head = label(card, tostring(opts.Title or "CONFIRM"):upper(), 15, FONT.Title)
    head.TextXAlignment = Enum.TextXAlignment.Left
    head.Position = UDim2.fromOffset(18, 16)
    head.Size = UDim2.new(1, -36, 0, 24)
    local body = label(card, tostring(opts.Body or ""), 12, FONT.Body)
    body.TextColor3 = theme.Muted
    body.TextWrapped = true
    body.TextXAlignment = Enum.TextXAlignment.Left
    body.TextYAlignment = Enum.TextYAlignment.Top
    body.Position = UDim2.fromOffset(18, 48)
    body.Size = UDim2.new(1, -36, 0, 74)

    local function close()
        if self._dialog == veil then self._dialog = nil end
        veil:Destroy()
    end

    local confirm = menuButton(card, (opts.Confirm or "CONFIRM"):upper(), 36)
    confirm.Size = UDim2.new(0.5, -22, 0, 36)
    confirm.Position = UDim2.fromOffset(18, 134)
    confirm.BackgroundColor3 = theme.Blue
    self.Session.connect(confirm.Activated, function()
        close()
        self.Session.guard(opts.OnConfirm, "Dialog confirm")()
    end)

    local cancel = menuButton(card, (opts.Cancel or "CANCEL"):upper(), 36)
    cancel.Size = UDim2.new(0.5, -22, 0, 36)
    cancel.Position = UDim2.new(0.5, 4, 0, 134)
    outline(cancel, theme.Line)
    self.Session.connect(cancel.Activated, function()
        close()
        self.Session.guard(opts.OnCancel, "Dialog cancel")()
    end)

    return {Instance = veil, Close = close}
end

-- ── config ───────────────────────────────────────────────────────────────
-- Only flagged controls are persisted, and only their values. The hardware
-- id is deliberately never written: it is a local display value, and a
-- config file is the one place a user is likely to share.

function Window:Config(opts)
    opts = opts or {}
    local folder = opts.Folder or "PandaUI"
    local name = opts.Name or safeProfileName()
    self._config = {
        folder = folder,
        path = folder .. "/" .. name .. ".json",
        autosave = opts.AutoSave ~= false,
        delay = opts.Debounce or 0.7,
    }
    return self._config.path
end

function Window:Save()
    if not self._config then return false, "Config not enabled" end
    local snapshot = {
        version = 1,
        library = PandaUI.Version,
        username = me.Name,
        userId = me.UserId,
        gameId = game.GameId,
        activeTab = self.ActiveTab,
        keybind = self.Keybind and self.Keybind.Name or nil,
        flags = self.Flags,
    }
    local ok, err = writeJson(self._config.path, snapshot)
    if ok then
        self:SetStatus("Saved " .. string.char(226, 128, 162) .. " " .. os.date("%H:%M:%S"))
    else
        self:SetStatus("Save failed: " .. tostring(err))
    end
    return ok, err
end

function Window:Load()
    if not self._config then return false, "Config not enabled" end
    local data, err = readJson(self._config.path)
    if err then
        self:SetStatus("Config unreadable; current settings kept")
        return false, err
    end
    if not data then
        self:SetStatus("New profile " .. string.char(226, 128, 162) .. " auto-save ready")
        return true
    end
    if data.version ~= 1 or data.username ~= me.Name then
        self:SetStatus("Config profile does not match this username")
        return false, "Profile mismatch"
    end

    -- Applying a saved value must not re-trigger a save per control, so the
    -- whole apply runs with autosave suppressed and saves once at the end.
    self._loading = true
    local applied = pcall(function()
        if type(data.flags) == "table" then
            for flag, value in pairs(data.flags) do
                local control = self._controls[flag]
                if control and control.Set then control:Set(value, false) end
            end
        end
        if data.keybind then self:SetKeybind(data.keybind) end
        if data.activeTab and self.Tabs[data.activeTab] then self:SelectTab(data.activeTab) end
    end)
    self._loading = false
    if not applied then
        self:SetStatus("Some saved settings could not be applied")
        return false, "Apply failed"
    end
    self:SetStatus("Loaded for @" .. me.Name)
    return true
end

function Window:_autosave()
    if self._loading or not self._config or not self._config.autosave then return end
    if not self.Session.alive then return end
    self._saveGeneration = (self._saveGeneration or 0) + 1
    local generation = self._saveGeneration
    task.delay(self._config.delay, function()
        if self.Session.alive and generation == self._saveGeneration then self:Save() end
    end)
end

function Window:OnClose(callback)
    table.insert(self._closeHandlers, callback)
    return self
end

function Window:Destroy()
    if not self.Session.alive then return end
    local guiName = self.Shell.gui and self.Shell.gui.Name
    for _, handler in ipairs(self._closeHandlers) do pcall(handler) end
    self.Session.close()
    if self.Shell.gui then self.Shell.gui:Destroy() end
    if guiName and env.PandaUIWindows then env.PandaUIWindows[guiName] = nil end
end

-- ── PandaUI:Window ───────────────────────────────────────────────────────

function PandaUI:Window(opts)
    opts = opts or {}
    local theme = PandaUI.Theme
    local guiName = opts.GuiName or ("PandaUI_" .. tostring(opts.Title or "Window"):gsub("[^%w]", ""))

    -- Re-executing a script must replace the previous session, not stack a
    -- second window with live listeners on top of it.
    env.PandaUIWindows = env.PandaUIWindows or {}
    local previous = env.PandaUIWindows[guiName]
    if previous then
        pcall(function() previous:Destroy() end)
        task.wait()
    end

    local size = opts.Size or Vector2.new(1000, 580)
    local session = newSession(guiName)
    local shell = buildShell(session, {
        guiName = guiName,
        title = opts.Title or "PANDA",
        badge = opts.Badge,
        width = math.floor(size.X),
        height = math.floor(size.Y),
        displayOrder = opts.DisplayOrder,
    })

    local sidebarWidth = opts.SidebarWidth or 170
    local sidebar = new("Frame", {
        Name = "Sidebar",
        Position = UDim2.fromOffset(0, 58),
        Size = UDim2.new(0, sidebarWidth, 1, -96),
        BackgroundColor3 = theme.Ink,
        BorderSizePixel = 0,
        Parent = shell.panel,
    })

    local contentLeft = sidebarWidth + 18
    local pageTitle = label(shell.panel, "", 23, FONT.Title)
    pageTitle.Name = "PageTitle"
    pageTitle.TextXAlignment = Enum.TextXAlignment.Left
    pageTitle.TextTruncate = Enum.TextTruncate.AtEnd
    pageTitle.Position = UDim2.fromOffset(contentLeft, 70)
    pageTitle.Size = UDim2.new(1, -contentLeft - 16, 0, 28)

    local pageDescription = label(shell.panel, "", 11, FONT.Body)
    pageDescription.Name = "PageDescription"
    pageDescription.TextColor3 = theme.Muted
    pageDescription.TextXAlignment = Enum.TextXAlignment.Left
    pageDescription.TextTruncate = Enum.TextTruncate.AtEnd
    pageDescription.Position = UDim2.fromOffset(contentLeft, 99)
    pageDescription.Size = UDim2.new(1, -contentLeft - 16, 0, 17)

    local body = new("Frame", {
        Name = "Pages",
        Position = UDim2.fromOffset(contentLeft, 124),
        Size = UDim2.new(1, -contentLeft - 16, 1, -170),
        BackgroundTransparency = 1,
        Parent = shell.panel,
    })

    local footer = buildFooter(session, shell.panel, {
        left = "RIGHTALT  /  SHOW " .. string.char(194, 183) .. " HIDE",
        status = opts.Status or "Ready",
        right = opts.Metrics == false and (opts.FooterRight or "") or "MEASURING",
    })

    local toastLayer = new("Frame", {
        Name = "Toasts",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -18, 1, -56),
        Size = UDim2.fromOffset(300, 300),
        BackgroundTransparency = 1,
        ZIndex = 30,
        Parent = shell.panel,
    })
    new("UIListLayout", {
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        Parent = toastLayer,
    })

    local opener = new("TextButton", {
        Name = "Opener",
        Size = UDim2.fromOffset(132, 38),
        Position = opts.OpenerPosition or UDim2.new(0, 18, 0.5, -19),
        Text = ((opts.Title or "PANDA"):upper()) .. "  /  OPEN",
        Font = FONT.Bold,
        TextSize = 13,
        TextTruncate = Enum.TextTruncate.AtEnd,
        BackgroundColor3 = theme.Blue,
        TextColor3 = theme.Paper,
        BorderSizePixel = 0,
        Visible = false,
        Parent = shell.gui,
    })

    local window = setmetatable({
        Session = session,
        Shell = shell,
        Sidebar = sidebar,
        Body = body,
        Footer = footer,
        PageTitle = pageTitle,
        PageDescription = pageDescription,
        ToastLayer = toastLayer,
        Opener = opener,
        Tabs = {},
        TabOrder = {},
        Flags = {},
        Visible = true,
        ActiveTab = nil,
        Keybind = nil,
        _controls = {},
        _closeHandlers = {},
        _sidebarY = 8,
        _lastGroup = nil,
        _loading = false,
    }, Window)

    session.onError = function(line)
        window:SetStatus(clip(line, 110))
    end

    window:SetKeybind(opts.Keybind or Enum.KeyCode.RightAlt)
    env.PandaUIWindows[guiName] = window

    local minimize = shell.headerButton(string.char(226, 136, 146), -64, false)
    minimize.Name = "Minimize"
    local close = shell.headerButton(string.char(195, 151), -32, true)
    close.Name = "Close"

    session.connect(minimize.Activated, function() window:SetVisible(false) end)
    session.connect(opener.Activated, function() window:SetVisible(true) end)
    session.connect(close.Activated, function()
        if opts.ConfirmClose == false then
            window:Destroy()
            return
        end
        window:Dialog({
            Title = "Close " .. (opts.Title or "panel") .. "?",
            Body = "This ends the session and disconnects every listener it owns. "
                .. "Re-run the script to open it again.",
            Confirm = "CLOSE",
            OnConfirm = function() window:Destroy() end,
        })
    end)

    -- A shortcut that fires while the user is typing in a search box would
    -- hide the panel mid-word, so a focused TextBox suppresses it.
    session.connect(Input.InputBegan, function(input, processed)
        if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        if Input:GetFocusedTextBox() then return end
        if (window._capturing or 0) > 0 then return end
        if window.Keybind and input.KeyCode == window.Keybind then window:ToggleVisible() end
    end)

    if opts.Metrics ~= false then
        local elapsed, frames = 0, 0
        session.connect(RunService.RenderStepped, function(dt)
            frames = frames + 1
            elapsed = elapsed + dt
            if elapsed < 1 then return end
            window.Fps = math.floor(frames / elapsed + 0.5)
            frames, elapsed = 0, 0
            local ok, ping = pcall(function()
                return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
            end)
            window.Ping = (ok and type(ping) == "number")
                and (math.floor(ping + 0.5) .. " ms") or "no ping"
            footer.right.Text = window.Fps .. " FPS  " .. string.char(194, 183) .. "  " .. window.Ping
        end)
    end

    return window
end

-- ── session facts, for an overview tab ───────────────────────────────────

function PandaUI:Session()
    local info = {
        Username = me.Name,
        DisplayName = me.DisplayName,
        UserId = me.UserId,
        PlaceId = game.PlaceId,
        JobId = game.JobId,
        Executor = executorName(),
        Hwid = localHwid(),
        MaxPlayers = Players.MaxPlayers,
    }
    function info:Thumbnail(onReady)
        task.spawn(function()
            local ok, url = pcall(function()
                return Players:GetUserThumbnailAsync(me.UserId,
                    Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size180x180)
            end)
            if ok then pcall(onReady, url) end
        end)
        return self
    end
    function info:GameName(onReady)
        task.spawn(function()
            local ok, product = pcall(function()
                return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
            end)
            pcall(onReady, ok and product and product.Name or "Game name unavailable")
        end)
        return self
    end
    return info
end

function PandaUI:Avatar(column, opts)
    opts = opts or {}
    local theme = PandaUI.Theme
    local holder = new("Frame", {Size = UDim2.new(1, -8, 0, 96), BackgroundTransparency = 1})
    local image = new("ImageLabel", {
        Name = "Avatar",
        Size = UDim2.fromOffset(88, 88),
        BackgroundColor3 = theme.Ink,
        BorderSizePixel = 0,
        Parent = holder,
    })
    outline(image, theme.Blue)
    local display = label(holder, me.DisplayName, 19, FONT.Bold)
    display.TextXAlignment = Enum.TextXAlignment.Left
    display.TextTruncate = Enum.TextTruncate.AtEnd
    display.Position = UDim2.fromOffset(102, 16)
    display.Size = UDim2.new(1, -102, 0, 28)
    local handle = label(holder, "@" .. me.Name, 12, FONT.Body)
    handle.TextColor3 = theme.Muted
    handle.TextXAlignment = Enum.TextXAlignment.Left
    handle.Position = UDim2.fromOffset(102, 48)
    handle.Size = UDim2.new(1, -102, 0, 22)
    mount(column, holder)
    PandaUI:Session():Thumbnail(function(url) image.Image = url end)
    return {Instance = holder, Image = image}
end

-- ── key system ───────────────────────────────────────────────────────────
-- Fronts Panda PUSL-V4. The reason codes PUSL returns are the whole point of
-- this screen: a 429 or a dropped request is not a bad key, and treating it
-- like one locks out legitimate users on shared IPs and flaky mobile links.

local DEFAULT_LIB_URL = "https://secure.pandauth.com/pv4/lib"

local REASON_COPY = {
    OK = "Key accepted",
    INVALID_KEY = "That key is invalid, expired, or linked to another device.",
    RATE_LIMITED = "Too many attempts right now.",
    NETWORK = "Could not reach the key server. Check your connection.",
    NO_SERVICE = "This build has no service id configured.",
    NO_KEY = "Enter your key first.",
    NO_HTTP = "This executor has no HTTP request function.",
    IDENTITY = "Server identity check failed. Do not enter your key here.",
    PROTOCOL = "The key server returned something unexpected.",
    UNKNOWN = "The key could not be checked.",
}

-- Only these are worth retrying. Everything else is a definite answer, and
-- retrying it just burns the server's rate budget.
local TRANSIENT = {RATE_LIMITED = true, NETWORK = true, PROTOCOL = true}

local function fetchPusl(url)
    local ok, source = pcall(function() return game:HttpGet(url) end)
    if not ok or type(source) ~= "string" or source == "" then
        return nil, "Could not download the key library."
    end
    local chunk = loadstring or load
    if not chunk then return nil, "This executor cannot load the key library." end
    local built, err = chunk(source)
    if not built then return nil, "Key library failed to compile: " .. tostring(err) end
    local loaded, result = pcall(built)
    if not loaded or type(result) ~= "table" or type(result.configure) ~= "function" then
        return nil, "Key library failed to initialise."
    end
    return result
end

-- Two shapes reach this: the standalone PUSL-V4 module (lowercase, returns a
-- result table) and PandaAuthV4 injected by the Kryptic Vault loader
-- (PascalCase, returns ok/reason/premium). Both collapse to one interface.
local function adaptProvider(raw, serviceId)
    if type(raw) ~= "table" then return nil, "No key provider available." end

    if type(raw.validate) == "function" and type(raw.configure) == "function" then
        if type(serviceId) ~= "string" or serviceId == "" then
            return nil, "PUSL-V4 needs a ServiceId; none was supplied."
        end
        local ok = pcall(raw.configure, {serviceId = serviceId})
        if not ok then return nil, "Key provider rejected the service id." end
        return {
            kind = "PUSL",
            raw = raw,
            validate = function(key)
                local result = raw.validate(key)
                if type(result) ~= "table" then
                    return {ok = false, reason = "PROTOCOL", message = "Empty result"}
                end
                return {
                    ok = result.success == true,
                    reason = result.reason or (result.success and "OK" or "UNKNOWN"),
                    message = result.error,
                    premium = result.isPremium == true,
                    expiry = result.expiresAt,
                    timeLeft = result.timeLeft,
                }
            end,
            expiryText = function()
                local okCall, value = pcall(raw.getExpiryFormatted)
                return okCall and value or nil
            end,
            keyUrl = function()
                local okCall, value = pcall(raw.getKeyUrl)
                return okCall and value or nil
            end,
            hwid = function()
                local okCall, value = pcall(raw.hwid)
                return okCall and value or localHwid()
            end,
        }
    end

    if type(raw.ValidateEx) == "function" or type(raw.Validate) == "function" then
        return {
            kind = "PandaAuthV4",
            raw = raw,
            validate = function(key)
                if type(raw.ValidateEx) == "function" then
                    local accepted, reason, premium, message = raw.ValidateEx(key)
                    return {
                        ok = accepted == true,
                        reason = reason or (accepted and "OK" or "UNKNOWN"),
                        message = message,
                        premium = premium == true,
                    }
                end
                local accepted = raw.Validate(key) == true
                return {
                    ok = accepted,
                    reason = accepted and "OK" or "INVALID_KEY",
                    premium = type(raw.Validate_Premium) == "function"
                        and raw.Validate_Premium(key) == true or false,
                }
            end,
            expiryText = function()
                local okCall, value = pcall(raw.GetExpiryFormatted)
                return okCall and value or nil
            end,
            keyUrl = function()
                local okCall, value = pcall(raw.GetKey)
                return okCall and value or nil
            end,
            hwid = function()
                local okCall, value = pcall(raw.GetIdentity)
                if okCall and value and tostring(value) ~= "" then return tostring(value) end
                return localHwid()
            end,
        }
    end

    return nil, "Unrecognised key provider."
end

local function keyFilePath(opts)
    if opts.SaveFile then return opts.SaveFile end
    return (opts.SaveFolder or "PandaUI") .. "/key-" .. safeProfileName() .. ".json"
end

function PandaUI:ClearSavedKey(opts)
    opts = opts or {}
    local path = keyFilePath(opts)
    if type(delfile) == "function" and type(isfile) == "function" then
        local ok = pcall(function() if isfile(path) then delfile(path) end end)
        if ok then return true end
    end
    -- No delfile on this executor: blank the record instead, because loadKey
    -- treats an empty key as "nothing saved".
    return (writeJson(path, {version = 1, key = ""}))
end

function PandaUI:KeySystem(opts)
    opts = opts or {}
    local theme = PandaUI.Theme
    local guiName = opts.GuiName or "PandaUI_KeySystem"
    local savePath = keyFilePath(opts)
    local persist = opts.Save ~= false

    local session = newSession(guiName)
    local shell = buildShell(session, {
        guiName = guiName,
        title = opts.Title or "PANDA",
        badge = opts.Badge or "KEY SYSTEM",
        width = 540,
        height = 472,
        position = UDim2.new(0.5, -270, 0.5, -236),
        displayOrder = opts.DisplayOrder or 1100,
    })

    local tag = label(shell.header, "KEY SYSTEM", 9, FONT.Mono)
    tag.TextColor3 = theme.Muted
    tag.TextXAlignment = Enum.TextXAlignment.Right
    tag.Position = UDim2.new(1, -170, 0, 24)
    tag.Size = UDim2.fromOffset(130, 16)

    local close = shell.headerButton(string.char(195, 151), -32, true)
    close.Name = "Close"

    -- A marquee rather than a percentage bar: validate() has no progress to
    -- report, only "still working", and a fake percentage would be a lie.
    local progressTrack = new("Frame", {
        Name = "Progress",
        Position = UDim2.fromOffset(0, 58),
        Size = UDim2.new(1, 0, 0, 3),
        BackgroundColor3 = theme.Line,
        BorderSizePixel = 0,
        Visible = false,
        Parent = shell.panel,
    })
    local progressHead = new("Frame", {
        Size = UDim2.new(0.28, 0, 1, 0),
        BackgroundColor3 = theme.Blue,
        BorderSizePixel = 0,
        Parent = progressTrack,
    })

    local content = new("Frame", {
        Name = "Content",
        Position = UDim2.fromOffset(20, 76),
        Size = UDim2.new(1, -40, 1, -124),
        BackgroundTransparency = 1,
        Parent = shell.panel,
    })

    local heading = label(content, "01", 17, FONT.Title)
    heading.TextColor3 = theme.Blue
    heading.TextXAlignment = Enum.TextXAlignment.Left
    heading.Size = UDim2.fromOffset(28, 24)
    local headingText = label(content, "AUTHENTICATION", 12, FONT.Mono)
    headingText.TextXAlignment = Enum.TextXAlignment.Left
    headingText.Position = UDim2.fromOffset(32, 0)
    headingText.Size = UDim2.new(1, -32, 0, 24)

    local intro = label(content, opts.Note
        or "Paste the key from the checkpoint link. It is checked against the Panda key server, not stored on this device unless you let it save.",
        11, FONT.Body)
    intro.TextColor3 = theme.Muted
    intro.TextWrapped = true
    intro.TextXAlignment = Enum.TextXAlignment.Left
    intro.TextYAlignment = Enum.TextYAlignment.Top
    intro.Position = UDim2.fromOffset(0, 30)
    intro.Size = UDim2.new(1, 0, 0, 46)

    local box = new("TextBox", {
        Name = "KeyInput",
        Position = UDim2.fromOffset(0, 86),
        Size = UDim2.new(1, 0, 0, 44),
        BackgroundColor3 = theme.Wash,
        TextColor3 = theme.Paper,
        PlaceholderColor3 = theme.Muted,
        PlaceholderText = opts.Placeholder or "Paste your key",
        Text = "",
        ClearTextOnFocus = false,
        Font = FONT.Mono,
        TextSize = 14,
        BorderSizePixel = 0,
        Parent = content,
    })
    corner(box)
    outline(box, theme.Line)
    local boxStroke = box:FindFirstChildOfClass("UIStroke")
    session.connect(box.Focused, function() boxStroke.Color = theme.Blue end)
    session.connect(box.FocusLost, function() boxStroke.Color = theme.Line end)

    local checkButton = menuButton(content, "CHECK KEY", 42)
    checkButton.Name = "CheckKey"
    checkButton.Position = UDim2.fromOffset(0, 140)
    checkButton.Size = UDim2.new(1, 0, 0, 42)
    checkButton.BackgroundColor3 = theme.Blue
    checkButton.Font = FONT.Bold
    checkButton.TextSize = 13

    local function secondaryRow(y, entries)
        local count = #entries
        if count == 0 then return end
        for index, entry in ipairs(entries) do
            local b = menuButton(content, entry.text, 34)
            b.Position = UDim2.new((index - 1) / count, (index - 1) * 8 / count, 0, y)
            b.Size = UDim2.new(1 / count, -(count - 1) * 8 / count, 0, 34)
            outline(b, theme.Line)
            session.connect(b.Activated, entry.run)
        end
    end

    local info = new("Frame", {
        Position = UDim2.fromOffset(0, 236),
        Size = UDim2.new(1, 0, 0, 58),
        BackgroundTransparency = 1,
        Parent = content,
    })
    local hwidCaption = label(info, "HARDWARE ID  /  LOCAL DISPLAY", 9, FONT.Mono)
    hwidCaption.TextColor3 = theme.Muted
    hwidCaption.TextXAlignment = Enum.TextXAlignment.Left
    hwidCaption.Size = UDim2.new(1, 0, 0, 14)
    local hwidValue = label(info, "Unavailable", 11, FONT.Mono)
    hwidValue.TextXAlignment = Enum.TextXAlignment.Left
    hwidValue.TextYAlignment = Enum.TextYAlignment.Top
    hwidValue.TextWrapped = true
    hwidValue.Position = UDim2.fromOffset(0, 18)
    hwidValue.Size = UDim2.new(1, 0, 0, 40)

    local footer = buildFooter(session, shell.panel, {
        left = "PUSL-V4",
        status = "Preparing the key check",
        right = executorName():upper(),
    })
    footer.status.Position = UDim2.fromOffset(100, 4)
    footer.status.Size = UDim2.new(1, -250, 0, 30)
    footer.left.Size = UDim2.fromOffset(90, 30)

    local outcome = {done = false, ok = false, reason = nil, info = nil}
    local busy = false

    local function setStatus(message, tone)
        footer.status.Text = tostring(message)
        footer.status.TextColor3 = tone or theme.Paper
    end
    session.onError = function(line) setStatus(clip(line, 90), theme.Bad) end

    local function setBusy(on)
        busy = on == true
        progressTrack.Visible = busy
        checkButton.Active = not busy
        checkButton.AutoButtonColor = not busy
        checkButton.Text = busy and "CHECKING..." or "CHECK KEY"
        checkButton.BackgroundColor3 = busy and theme.Dim or theme.Blue
    end

    session.connect(RunService.RenderStepped, function()
        if not progressTrack.Visible then return end
        local phase = (os.clock() * 0.9) % 1
        progressHead.Position = UDim2.fromScale(phase * 1.28 - 0.28, 0)
    end)

    local function finish(ok, reason, result)
        if outcome.done then return end
        outcome.ok, outcome.reason, outcome.info = ok == true, reason, result
        outcome.done = true
    end

    -- Provider resolution order: an explicitly passed one, the Vault loader's
    -- injected PandaAuthV4, then a fresh download of PUSL-V4.
    local provider, providerError
    do
        local raw = opts.Provider or env.PandaAuthV4 or (rawget(_G, "PandaAuthV4"))
        if not raw then
            local serviceId = opts.ServiceId
            if type(serviceId) ~= "string" or serviceId == "" then
                providerError = "No service id supplied to KeySystem."
            else
                local fetched, err = fetchPusl(opts.LibUrl or DEFAULT_LIB_URL)
                raw = fetched
                providerError = err
            end
        end
        if raw then provider, providerError = adaptProvider(raw, opts.ServiceId) end
    end

    if provider then
        local id = provider.hwid()
        hwidValue.Text = id or "Unavailable on this executor"
        footer.left.Text = provider.kind == "PandaAuthV4" and "VAULT AUTH" or "PUSL-V4"
        setStatus("Waiting for a key")
    else
        hwidValue.Text = localHwid() or "Unavailable on this executor"
        setStatus(providerError or "Key provider unavailable", theme.Bad)
        setBusy(false)
        checkButton.Active = false
        checkButton.BackgroundColor3 = theme.Dim
    end

    local function saveKey(key)
        if not persist then return end
        writeJson(savePath, {
            version = 1,
            key = key,
            service = opts.ServiceId,
            username = me.Name,
            savedAt = os.time(),
        })
    end

    local function loadKey()
        if not persist then return nil end
        local data = readJson(savePath)
        if type(data) ~= "table" then return nil end
        if data.version ~= 1 or type(data.key) ~= "string" or data.key == "" then return nil end
        if data.username ~= me.Name then return nil end
        if opts.ServiceId and data.service and data.service ~= opts.ServiceId then return nil end
        return data.key
    end

    local function succeed(key, result)
        saveKey(key)
        local expiryText = provider.expiryText() or (result.timeLeft and "Timed key" or "Lifetime")
        setStatus("Key accepted  /  " .. expiryText
            .. (result.premium and "  /  PREMIUM" or ""), theme.Good)
        checkButton.Text = "AUTHENTICATED"
        checkButton.BackgroundColor3 = theme.Good
        setBusy(false)
        finish(true, "OK", {
            Key = key,
            Premium = result.premium == true,
            Expiry = result.expiry,
            ExpiryText = expiryText,
            TimeLeft = result.timeLeft,
            Provider = provider.raw,
            ProviderKind = provider.kind,
            Hwid = provider.hwid(),
        })
    end

    -- Retries are only ever spent on transient reasons, and the user can see
    -- the wait tick down instead of staring at a frozen button.
    local function attempt(key, silent)
        if busy or not provider or outcome.done then return end
        key = tostring(key or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if key == "" then
            setStatus(REASON_COPY.NO_KEY, theme.Bad)
            return
        end
        setBusy(true)
        task.spawn(function()
            local tries = math.max(1, opts.Attempts or 4)
            for try = 1, tries do
                if not session.alive or outcome.done then return end
                setStatus(silent and "Checking your saved key" or
                    (try == 1 and "Checking your key" or ("Retrying (" .. try .. "/" .. tries .. ")")))
                local okCall, result = pcall(provider.validate, key)
                if not okCall then
                    session.report("validate: " .. tostring(result))
                    setBusy(false)
                    return
                end
                if result.ok then
                    succeed(key, result)
                    return
                end
                local reason = result.reason or "UNKNOWN"
                local copy = REASON_COPY[reason] or REASON_COPY.UNKNOWN
                if reason == "INVALID_KEY" and silent then
                    PandaUI:ClearSavedKey(opts)
                    box.Text = ""
                end
                if not TRANSIENT[reason] or try == tries then
                    setStatus(copy .. (result.message and ("  (" .. clip(result.message, 60) .. ")") or ""),
                        theme.Bad)
                    setBusy(false)
                    if opts.OnFail then session.guard(opts.OnFail, "OnFail")(reason, result.message) end
                    return
                end
                local wait = try * 5
                for remaining = wait, 1, -1 do
                    if not session.alive or outcome.done then return end
                    setStatus(copy .. "  Retrying in " .. remaining .. "s")
                    task.wait(1)
                end
            end
            setBusy(false)
        end)
    end

    local secondary = {}
    table.insert(secondary, {
        text = "GET KEY",
        run = function()
            local url = provider and provider.keyUrl()
            if not url or url == "" then
                setStatus("No checkpoint link available in this build", theme.Bad)
                return
            end
            setStatus(copyToClipboard(url)
                and "Checkpoint link copied to your clipboard"
                or ("Open: " .. clip(url, 70)))
        end,
    })
    table.insert(secondary, {
        text = "COPY HWID",
        run = function()
            local id = provider and provider.hwid() or localHwid()
            if not id then
                setStatus("No hardware id available on this executor", theme.Bad)
                return
            end
            setStatus(copyToClipboard(id) and "Hardware id copied" or "Clipboard unavailable")
        end,
    })
    if opts.Discord and opts.Discord ~= "" then
        table.insert(secondary, {
            text = "DISCORD",
            run = function()
                setStatus(copyToClipboard(opts.Discord)
                    and "Discord invite copied"
                    or ("Join: " .. clip(opts.Discord, 70)))
            end,
        })
    end
    secondaryRow(190, secondary)

    if persist then
        secondaryRow(302, {{
            text = "FORGET SAVED KEY",
            run = function()
                PandaUI:ClearSavedKey(opts)
                box.Text = ""
                setStatus("Saved key removed from this device")
            end,
        }})
    end

    session.connect(checkButton.Activated, function() attempt(box.Text, false) end)
    session.connect(box.FocusLost, function(enter)
        if enter then attempt(box.Text, false) end
    end)
    session.connect(close.Activated, function() finish(false, "CLOSED") end)

    local saved = loadKey()
    if saved and provider then
        box.Text = saved
        attempt(saved, true)
    end

    local function teardown()
        session.close()
        if shell.gui then shell.gui:Destroy() end
    end

    -- The accepted state is held briefly so the user sees why it closed, then
    -- the gate is gone before OnSuccess builds anything on top of it.
    local function settle()
        if outcome.ok then task.wait(0.8) end
        teardown()
        if outcome.ok and opts.OnSuccess then pcall(opts.OnSuccess, outcome.info) end
    end

    if opts.Async then
        task.spawn(function()
            repeat task.wait() until outcome.done or not session.alive
            settle()
        end)
        return outcome
    end

    repeat task.wait() until outcome.done or not session.alive
    settle()
    return outcome.ok, outcome.info or {Reason = outcome.reason}
end

return PandaUI
