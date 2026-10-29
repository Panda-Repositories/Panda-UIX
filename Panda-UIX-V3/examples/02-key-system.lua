-- Panda-UIX example 02: gate the hub behind a Panda key.
--
-- KeySystem blocks until the user authenticates or closes the window, so the
-- rest of the script simply never runs for an unauthenticated user. It does
-- NOT kick on a rate limit or a dropped request: those are retried, because
-- neither one means the key is bad.
local PandaUI = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/SkieHackerYT/Panda-UIX/main/Panda-UIX-V3/PandaUI.lua"))()

local ok, auth = PandaUI:KeySystem({
    Title = "MY HUB",
    Badge = "KEY SYSTEM",
    ServiceId = "YOUR_SERVICE_ID",
    Discord = "https://discord.gg/yourinvite",
    Save = true,
    SaveFolder = "MyHub",
})

if not ok then
    -- auth.Reason is "CLOSED", "INVALID_KEY", "NETWORK", and so on.
    return warn("[MyHub] Not authenticated: " .. tostring(auth.Reason))
end

local Window = PandaUI:Window({
    Title = "MY HUB",
    Badge = "SOME GAME",
    Status = "Key valid " .. auth.ExpiryText,
})

local Main = Window:Tab({
    Name = "Main",
    Group = "OVERVIEW",
    Title = "MAIN MENU",
    Description = "Your profile and this key at a glance.",
})

local Profile = Main:Column("PLAYER PROFILE")
PandaUI:Avatar(Profile)
Profile:Info("ROBLOX USER ID", game.Players.LocalPlayer.UserId)
Profile:Info("EXECUTOR", PandaUI:Session().Executor)

local Licence = Main:Column("LICENCE")
Licence:Info("PLAN", auth.Premium and "Premium" or "Standard")
Licence:Info("EXPIRES", auth.ExpiryText)
Licence:Info("HARDWARE ID", auth.Hwid or "Unavailable", 76)
Licence:Paragraph(
    "The key is checked once per execution. Closing this panel ends the "
    .. "session; re-run the script to open it again.", 54)

local Features = Window:Tab({
    Name = "Features",
    Group = "GAME",
    Title = "FEATURES",
    Description = "Premium entries unlock with a premium key.",
})

local Free = Features:Column("INCLUDED")
Free:Toggle({ Text = "Auto-Collect", Flag = "collect", Callback = function(on) print(on) end })

local Paid = Features:Column("PREMIUM")
Paid:Toggle({
    Text = "Auto-Prestige",
    Flag = "prestige",
    Callback = function(on)
        -- Returning false reverts the pill, so a locked feature cannot be
        -- left reading ON.
        if not auth.Premium then
            Window:Notify({ Title = "PREMIUM", Text = "Upgrade your key to use this.", Bad = true })
            return false
        end
        print("prestige:", on)
    end,
})

if not auth.Premium then
    Paid:Paragraph("These need a premium key. Use GET KEY on the gate to upgrade.", 46)
end
