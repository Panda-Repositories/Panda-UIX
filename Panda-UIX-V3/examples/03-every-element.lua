-- Panda-UIX example 03: one of every element. Useful as a visual reference
-- while building a hub.
local Players = game:GetService("Players")
local PandaUI = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/SkieHackerYT/Panda-UIX/main/Panda-UIX-V3/PandaUI.lua"))()

local Window = PandaUI:Window({
    Title = "PANDA HUB",
    Badge = "HEROES RNG",
    Size = Vector2.new(1000, 580),
    Keybind = Enum.KeyCode.RightAlt,
})

-- ── Overview ─────────────────────────────────────────────────────────────
local Main = Window:Tab({
    Name = "Main",
    Group = "OVERVIEW",
    Title = "MAIN MENU",
    Description = "Your profile and live session at a glance.",
})

local Profile = Main:Column("PLAYER PROFILE")
PandaUI:Avatar(Profile)
Profile:Info("ROBLOX USER ID", Players.LocalPlayer.UserId)
Profile:Info("EXECUTOR", PandaUI:Session().Executor)
Profile:Info("HARDWARE ID  /  LOCAL DISPLAY", PandaUI:Session().Hwid or "Unavailable", 76)

local Live = Main:Column("LIVE SESSION")
local gameRow = Live:Info("GAME", "Loading...", 62)
local playersRow = Live:Info("TOTAL PLAYERS", "0", 38)
PandaUI:Session():GameName(function(name) gameRow:Set(name) end)

task.spawn(function()
    while true do
        playersRow:Set(#Players:GetPlayers() .. " / " .. Players.MaxPlayers)
        task.wait(2)
    end
end)

-- ── Automation: toggles ──────────────────────────────────────────────────
local Automation = Window:Tab({
    Name = "Automation",
    Group = "GAME",
    Title = "AUTOMATION",
    Description = "Rolling, combat and progression controls.",
})

local Combat = Automation:Column("COMBAT & ROLLING")
Combat:Toggle({ Text = "Auto-Roll", Flag = "roll", Callback = function(on) print("roll", on) end })
Combat:Toggle({ Text = "Auto-Pick Best Heroes", Flag = "best" })
Combat:Toggle({ Text = "Auto-Farm Nearby Mobs", Flag = "farm" })
Combat:Paragraph("Choose specific mobs and bosses in TARGETS.\nFarming follows nearby enemies.", 40)

local Progress = Automation:Column("PROGRESSION & EVENTS")
Progress:Toggle({ Text = "Auto-Upgrade", Flag = "upgrade" })
Progress:Toggle({
    Text = "Auto-Prestige",
    Flag = "prestige",
    Callback = function(on)
        -- Returning false reverts the pill and leaves a reason in the footer.
        if on and Players.LocalPlayer:GetAttribute("Level") == nil then return false end
    end,
})
Progress:Divider()
Progress:Label("MAINTENANCE", 12)
Progress:Button({
    Text = "Reset Progress Cache",
    Primary = false,
    Callback = function()
        Window:Dialog({
            Title = "Reset cache?",
            Body = "This clears the locally cached progression data. Nothing on the server changes.",
            Confirm = "RESET",
            OnConfirm = function() Window:Notify({ Title = "CACHE", Text = "Cache cleared.", Good = true }) end,
        })
    end,
})

-- ── Movement: sliders ────────────────────────────────────────────────────
local Universal = Window:Tab({
    Name = "Universal",
    Group = "PLAYER",
    Title = "UNIVERSAL",
    Description = "Movement, flight and teleporting to a player.",
})

local Movement = Universal:Column("MOVEMENT")
Movement:Toggle({ Text = "Movement Speed", Flag = "speed" })
Movement:Slider({
    Text = "Speed",
    Min = 16, Max = 100, Default = 32,
    Flag = "walkSpeed",
    Callback = function(value) print("speed", value) end,
})
Movement:Toggle({ Text = "Fly", Flag = "fly" })
Movement:Slider({
    Text = "Fly Speed",
    Style = "Segments",
    Min = 10, Max = 150, Default = 40, Segments = 18,
    Flag = "flySpeed",
})
Movement:Paragraph("Fly: WASD moves, Space rises, Ctrl descends.", 34)

-- ── Dropdowns, rebuilt when the player list changes ──────────────────────
local PlayerPick = Universal:Column("TELEPORT TO PLAYER")
local picker = PlayerPick:Dropdown({
    Text = "Player",
    Search = true,
    Height = 190,
    Callback = function(userId) print("picked", userId) end,
})

local function refreshPlayers()
    local options = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= Players.LocalPlayer then
            table.insert(options, { Id = player.UserId, Name = player.DisplayName .. " (@" .. player.Name .. ")" })
        end
    end
    picker:SetOptions(options)
end
refreshPlayers()
Players.PlayerAdded:Connect(refreshPlayers)
Players.PlayerRemoving:Connect(function() task.defer(refreshPlayers) end)

PlayerPick:Button({
    Text = "Teleport To Selected",
    Callback = function()
        local target = Players:GetPlayerByUserId(picker:Get())
        local root = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
        if not root then return Window:SetStatus("Waiting for that player's character") end
        Players.LocalPlayer.Character:PivotTo(root.CFrame * CFrame.new(4, 1, 0))
    end,
})

-- ── A searchable action grid ─────────────────────────────────────────────
local Teleport = Window:Tab({
    Name = "Teleport",
    Group = "WORLD",
    Title = "TELEPORT",
    Description = "Travel to a verified location.",
})
local Places = Teleport:Column()
local grid = Places:Grid({
    Columns = 2,
    CellHeight = 48,
    Height = 330,
    Placeholder = "Search places",
    Callback = function(id) print("teleport to", id) end,
})
grid:SetItems({
    { Id = "spawn",  Text = "Spawn",        Sub = "TELEPORT" },
    { Id = "tower",  Text = "Tower",        Sub = "TELEPORT" },
    { Id = "boss",   Text = "Boss Arena",   Sub = "TELEPORT", Primary = true },
    { Id = "caves",  Text = "Crystal Caves", Sub = "LOCKED",  Disabled = true },
})

-- ── Text input and a rebindable shortcut ─────────────────────────────────
local Settings = Window:Tab({
    Name = "Settings",
    Group = "SYSTEM",
    Title = "SETTINGS",
    Description = "Shortcut, webhook and saved configuration.",
})

local Keys = Settings:Column("SHOW / HIDE WINDOW")
Keys:Keybind({
    Text = "Show / hide key",
    Default = "RightAlt",
    Flag = "hotkey",
    Callback = function(key) Window:SetKeybind(key) end,
})
Keys:Paragraph("Click above, then press your preferred key. Shortcuts pause while you type in a search box.", 50)

local Store = Settings:Column("CONFIGURATION")
Store:TextBox({
    Label = "Webhook URL",
    Placeholder = "https://discord.com/api/webhooks/...",
    Flag = "webhook",
})
Store:Info("CONFIG FILE", Window:Config({ Folder = "PandaHub", AutoSave = true }), 54)
Store:Button({ Text = "Save Now", Callback = function() Window:Save() end })
Store:Button({ Text = "Reload Saved Settings", Primary = false, Callback = function() Window:Load() end })

Window:Load()
Window:SelectTab("Main")
Window:Notify({ Title = "PANDA HUB", Text = "Loaded. Press RightAlt to hide.", Good = true })
