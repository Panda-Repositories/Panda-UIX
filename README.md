# Panda UIX

UI libraries for Roblox script hubs, in the flat ink-and-blue Panda style.

| Version | Folder | What it is |
|---|---|---|
| V3 | [`Panda-UIX-V3/`](Panda-UIX-V3) | Single-file Luau library. Key System GUI (Panda PUSL-V4) + tabbed hub Window. |

Start with [**Panda-UIX-V3/README.md**](Panda-UIX-V3/README.md) for install,
the full API and three runnable examples.

```lua
local PandaUI = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/SkieHackerYT/Panda-UIX/main/Panda-UIX-V3/PandaUI.lua"))()

local ok = PandaUI:KeySystem({ Title = "MY HUB", ServiceId = "YOUR_SERVICE_ID" })
if not ok then return end

local Window = PandaUI:Window({ Title = "MY HUB", Badge = "SOME GAME" })
local Tab    = Window:Tab({ Name = "Main", Group = "GAME", Title = "MAIN" })
Tab:Column("AUTOMATION"):Toggle({ Text = "Auto-Farm", Flag = "farm" })
```
