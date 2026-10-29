-- Panda-UIX example 01: the smallest useful hub.
-- Swap the owner and repo in the URL below for wherever you pushed this.
local PandaUI = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/SkieHackerYT/Panda-UIX/main/Panda-UIX-V3/PandaUI.lua"))()

local Window = PandaUI:Window({
    Title = "MY HUB",
    Badge = "SOME GAME",
    Keybind = Enum.KeyCode.RightAlt,
})

local Main = Window:Tab({
    Name = "Main",
    Group = "OVERVIEW",
    Title = "MAIN MENU",
    Description = "Everything in one place.",
})

local Left = Main:Column("AUTOMATION")

Left:Toggle({
    Text = "Auto-Farm",
    Flag = "autoFarm",
    Callback = function(on)
        print("auto-farm:", on)
    end,
})

Left:Slider({
    Text = "Walk Speed",
    Min = 16,
    Max = 100,
    Default = 32,
    Flag = "walkSpeed",
    Callback = function(value)
        local character = game.Players.LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid then humanoid.WalkSpeed = value end
    end,
})

Left:Button({
    Text = "Reset Character",
    Callback = function()
        game.Players.LocalPlayer.Character:BreakJoints()
    end,
})

-- Settings are written to PandaHub/<username>.json and reapplied on load.
Window:Config({ Folder = "PandaHub", AutoSave = true })
Window:Load()
