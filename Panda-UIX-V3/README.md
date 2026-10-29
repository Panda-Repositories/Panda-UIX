# Panda-UIX-V3

A single-file Luau UI library for Roblox script hubs. One file gives you two
surfaces:

- **Key System GUI**: a key gate backed by **Panda PUSL-V4**.
- **Main GUI**: a tabbed hub window with toggles, sliders, dropdowns, grids,
  notifications, dialogs and per-username config saving.

The look is deliberately flat: square corners, 1px borders, an 8px blue offset
shadow, GothamBlack for titles and Code for anything that reads as data.

```
Panda-UIX-V3/
  PandaUI.lua                 the library, the only file you need
  README.md                   this file
  examples/
    01-minimal.lua            smallest useful hub
    02-key-system.lua         key gate plus hub
    03-every-element.lua      one of every element, as a visual reference
```

---

## Contents

- [Install](#install)
- [Quick start](#quick-start)
- [Key System GUI](#key-system-gui)
- [Main GUI](#main-gui)
  - [Window](#window)
  - [Tabs and columns](#tabs-and-columns)
  - [Elements](#elements)
  - [Notifications and dialogs](#notifications-and-dialogs)
  - [Config saving](#config-saving)
  - [Session helpers](#session-helpers)
- [Theme](#theme)
- [Behaviour you get for free](#behaviour-you-get-for-free)
- [Troubleshooting](#troubleshooting)
- [API reference](#api-reference)

---

## Install

`PandaUI.lua` returns the library table. Pull it in the same way you pull any
other dependency:

```lua
local PandaUI = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/SkieHackerYT/Panda-UIX/main/Panda-UIX-V3/PandaUI.lua"))()
```

Swap the owner and repo in that URL for wherever you push this. If you would
rather not depend on a second request at runtime, paste the file inline above
your script. It declares no globals other than `getgenv().PandaUIWindows`, which
it uses to replace a previous session instead of stacking a second window on top
of it.

The returned table is named `PandaUI`, which is what every example below calls
it.

Requirements:

| Need | Used for | If missing |
|---|---|---|
| `game:HttpGet` | downloading PUSL-V4 | pass `Provider` or inline the library |
| `request` / `http_request` | PUSL-V4 key validation | key system reports `NO_HTTP` |
| `writefile` / `readfile` / `isfile` | config and saved key | saving is skipped, UI still works |
| `setclipboard` | GET KEY, COPY HWID | the link is printed to the status bar instead |
| `gethwid` | hardware id display | shows "Unavailable on this executor" |

Everything optional is probed, never called blind, so a missing global degrades
to a softer feature rather than an error.

---

## Quick start

```lua
local PandaUI = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/SkieHackerYT/Panda-UIX/main/Panda-UIX-V3/PandaUI.lua"))()

-- 1. Gate. Blocks until the user authenticates or closes the window.
local ok, auth = PandaUI:KeySystem({
    Title     = "MY HUB",
    ServiceId = "YOUR_SERVICE_ID",
    Discord   = "https://discord.gg/yourinvite",
})
if not ok then return end

-- 2. Hub.
local Window = PandaUI:Window({ Title = "MY HUB", Badge = "SOME GAME" })
local Tab    = Window:Tab({ Name = "Main", Group = "GAME", Title = "MAIN", Description = "" })
local Col    = Tab:Column("AUTOMATION")

Col:Toggle({ Text = "Auto-Farm", Flag = "farm", Callback = function(on) print(on) end })
Col:Slider({ Text = "Speed", Min = 16, Max = 100, Default = 32, Flag = "speed" })

-- 3. Remember the user's choices.
Window:Config({ Folder = "MyHub" })
Window:Load()
```

Three runnable scripts live in [`examples/`](examples).

---

## Key System GUI

```lua
local ok, auth = PandaUI:KeySystem({
    Title      = "MY HUB",           -- ribbon title
    Badge      = "KEY SYSTEM",       -- small spaced label under it
    ServiceId  = "YOUR_SERVICE_ID",  -- your Panda service id
    Discord    = "https://discord.gg/yourinvite",
    Note       = "Paste the key from the checkpoint link.",
    Save       = true,               -- remember a working key (default true)
    SaveFolder = "MyHub",
    Attempts   = 4,                  -- retries, transient failures only
    OnSuccess  = function(info) end,
    OnFail     = function(reason, message) end,
})
```

It returns `ok, auth`:

```lua
auth = {
    Key          = "...",        -- the key that worked
    Premium      = false,
    Expiry       = "2026-11-05T22:15:00.000Z",  -- nil for a lifetime key
    ExpiryText   = "7d 0h 0m",   -- or "Lifetime" / "Expired"
    TimeLeft     = 604800,       -- seconds, nil for a lifetime key
    Hwid         = "...",
    Provider     = PUSL,         -- the live PUSL-V4 table, for session calls
    ProviderKind = "PUSL",       -- or "PandaAuthV4"
}
```

On failure `auth` is `{ Reason = "CLOSED" }` or the reason code that stopped it.

### Where the key is checked

Panda-UIX does not implement key validation. It fronts **PUSL-V4** and resolves
a provider in this order:

1. `opts.Provider`, if you pass a PUSL table yourself.
2. `PandaAuthV4`, the global the **Kryptic Vault loader** injects. If your script
   ships through the Vault you already have a validated session, and PandaUI
   uses it rather than re-authenticating.
3. A fresh download of `https://secure.pandauth.com/pv4/lib`, configured with
   your `ServiceId`. Override the URL with `LibUrl`.

### Failure reasons, and why the gate does not kick

The buttons map straight onto the PUSL-V4 reason codes:

| Reason | Shown as | Retried |
|---|---|---|
| `INVALID_KEY` | "That key is invalid, expired, or linked to another device." | no |
| `RATE_LIMITED` | "Too many attempts right now." | yes |
| `NETWORK` | "Could not reach the key server." | yes |
| `PROTOCOL` | "The key server returned something unexpected." | yes |
| `IDENTITY` | "Server identity check failed. Do not enter your key here." | no |
| `NO_SERVICE` | "This build has no service id configured." | no |
| `NO_KEY` | "Enter your key first." | no |
| `NO_HTTP` | "This executor has no HTTP request function." | no |

Only the three transient ones are retried, with a visible `5s / 10s / 15s`
backoff. **The gate never kicks the player.** A 429 or a dropped request is not a
bad key, and kicking on it punishes people on shared IPs, multi-instance setups
and flaky mobile connections. If you want a kick, do it yourself on
`OnFail` when `reason == "INVALID_KEY"`.

### Saved keys

With `Save = true` a working key is written to
`<SaveFolder>/key-<username>.json` as `{version, key, service, username, savedAt}`.
On the next run the gate prefills it and checks it quietly: the status bar reads
"Checking your saved key" and the panel closes itself if it passes.

A saved key that comes back `INVALID_KEY` is deleted automatically, so a user
whose key expired is not stuck on a dead record.

The hardware id is **never** written to the file. It is a local display value,
and a config file is the one thing a user is likely to share in a support thread.

`PandaUI:ClearSavedKey({ SaveFolder = "MyHub" })` removes it on demand; the
**FORGET SAVED KEY** button on the gate does the same thing.

### Running the gate without blocking

Pass `Async = true` and you get a polling table back instead of a blocked thread:

```lua
local gate = PandaUI:KeySystem({ ServiceId = "...", Async = true, OnSuccess = start })
-- gate.done, gate.ok, gate.reason, gate.info
```

---

## Main GUI

### Window

```lua
local Window = PandaUI:Window({
    Title        = "PANDA HUB",              -- ribbon title, also the opener label
    Badge        = "HEROES RNG",             -- spaced out automatically
    Size         = Vector2.new(1000, 580),
    Keybind      = Enum.KeyCode.RightAlt,    -- show / hide
    Status       = "Ready",
    SidebarWidth = 170,
    Metrics      = true,                     -- FPS and ping in the footer
    ConfirmClose = true,                     -- ask before tearing down
    GuiName      = "PandaUI_MyHub",          -- ScreenGui name, also the reuse key
})
```

| Method | Does |
|---|---|
| `Window:Tab(opts)` | adds a sidebar entry and its page |
| `Window:SelectTab(name)` | switches page |
| `Window:SetStatus(text)` | writes the footer status line |
| `Window:Notify(opts \| text)` | toast, bottom right |
| `Window:Dialog(opts)` | modal confirm over the panel |
| `Window:SetVisible(bool)` / `Window:ToggleVisible()` | show / hide |
| `Window:SetKeybind(key)` | rebind show / hide |
| `Window:Config(opts)` | enable saving, returns the file path |
| `Window:Save()` / `Window:Load()` | write / read that file |
| `Window:OnClose(fn)` | run `fn` during teardown |
| `Window:Destroy()` | teardown: handlers, connections, ScreenGui |

`Window.Flags` is a plain table of every flagged control's current value, and
`Window.Fps` / `Window.Ping` are the live metrics.

### Tabs and columns

```lua
local Tab = Window:Tab({
    Name        = "Automation",   -- sidebar label and lookup key
    Group       = "GAME",         -- sidebar group heading, repeats are collapsed
    Title       = "AUTOMATION",   -- large page heading
    Description = "Rolling, combat and progression controls.",
})

local Left  = Tab:Column("COMBAT & ROLLING")
local Right = Tab:Column("PROGRESSION")
```

Columns are equal fractions of the page, recomputed every time you add one: one
column fills the page, two are halves, three are thirds. Each scrolls on its own.
Pass no heading for a bare column.

### Elements

Every element is created on a column and returns a control with `:Set(value)`
and `:Get()` where that makes sense, plus `.Instance` if you need the raw
object.

```lua
Col:Toggle({ Text, Default, Flag, Callback })
Col:Slider({ Text, Min, Max, Default, Step, Suffix, Style, Segments, Flag, Callback })
Col:Dropdown({ Text, Options, Default, Multi, Search, Height, RowHeight,
               Collapsible, Open, CloseOnPick, Placeholder, Flag, Callback })
Col:Grid({ Items, Columns, CellHeight, Height, Search, Placeholder, Callback })
Col:TextBox({ Label, Placeholder, Default, ClearOnFocus, Flag, Callback })
Col:Keybind({ Text, Default, Flag, Callback })
Col:Button({ Text, Primary, Height, Callback })
Col:Info(caption, value, height)
Col:Label(text, size)
Col:Paragraph(text, height)
Col:Divider()
```

**Toggle** renders as the hub's `ON` / `OFF` pill with a blue accent bar.
A callback that **errors or returns `false`** reverts the pill and writes
"<name> unavailable; reverted" to the footer, so a feature that could not start
never reads as ON:

```lua
Col:Toggle({
    Text = "Extended Reach",
    Flag = "reach",
    Callback = function(on)
        if on and not workspace:FindFirstChild("Combat") then
            return false   -- pill goes back to OFF
        end
    end,
})
```

**Slider** has two looks. `Style = "Bar"` (the default) is the track, fill and
knob; `Style = "Segments"` is the blocky flight-speed bar, with `Segments`
setting the block count. `Step` quantises the value and `Suffix` is appended to
the readout.

**Dropdown** is a pinned header over an optional search box and a scrolling list.
Rebuild it at runtime with `picker:SetOptions(options)`; options are either plain
values or `{ Id = ..., Name = ... }`. With `Multi = true` the value is a set
(`{ [id] = true }`) instead of a single id. `SetOptions` repaints without firing
your callback.

**Grid** is a searchable wall of action cards, for lists like teleport
destinations where each entry is a one-shot action rather than a stored setting:

```lua
grid:SetItems({
    { Id = "spawn", Text = "Spawn",         Sub = "TELEPORT" },
    { Id = "caves", Text = "Crystal Caves", Sub = "LOCKED", Disabled = true },
})
```

**Info** is the caption-over-value row used throughout the overview page;
`row:Set(value)` updates it in place, which is what you want for a live counter.

### Notifications and dialogs

```lua
Window:Notify({ Title = "PANDA HUB", Text = "Loaded.", Good = true, Duration = 4 })
Window:Notify("Shorthand for a plain message")

Window:Dialog({
    Title   = "Reset cache?",
    Body    = "This clears locally cached data. Nothing on the server changes.",
    Confirm = "RESET",
    Cancel  = "CANCEL",
    OnConfirm = function() end,
    OnCancel  = function() end,
})
```

`Good = true` tints the toast accent green, `Bad = true` red, neither leaves it
blue. Only one dialog is open at a time; a second call replaces the first.

### Config saving

```lua
local path = Window:Config({
    Folder   = "MyHub",   -- created if it does not exist
    Name     = nil,       -- defaults to the sanitised Roblox username
    AutoSave = true,      -- save 0.7s after the last change
    Debounce = 0.7,
})
Window:Load()
```

Only flagged controls are persisted, and only their values. Saving writes
`{version, library, username, userId, gameId, activeTab, keybind, flags}` to
`<Folder>/<Name>.json`.

`Window:Load()` applies each saved value **through** the control, so your
callbacks run and the features actually turn on. Autosave is suppressed for the
duration and the file is left alone, so loading never rewrites what it just read.
A file whose `username` does not match the current player is refused rather than
applied, and an unreadable file leaves the current settings alone.

### Session helpers

```lua
local s = PandaUI:Session()
-- s.Username, s.DisplayName, s.UserId, s.PlaceId, s.JobId,
-- s.Executor, s.Hwid, s.MaxPlayers

s:GameName(function(name) gameRow:Set(name) end)   -- async, never blocks
s:Thumbnail(function(url) image.Image = url end)

PandaUI:Avatar(Column)   -- headshot + display name + @username block
```

---

## Theme

`PandaUI.Theme` is read on every draw, so assign before you build:

```lua
PandaUI.Theme.Blue = Color3.fromRGB(180, 70, 220)
```

| Token | Default | Used for |
|---|---|---|
| `Ink` | `13, 13, 15` | panel, header, footer, sidebar |
| `Blue` | `24, 115, 211` | ribbon, offset shadow, active tab, fills |
| `Paper` | `239, 239, 242` | primary text |
| `Muted` | `149, 149, 159` | captions, inactive tabs, help text |
| `Wash` | `21, 21, 24` | column cards, inputs, inactive pills |
| `Line` | `43, 43, 48` | borders and dividers |
| `ActiveWash` | `17, 33, 51` | an enabled toggle's body |
| `Good` / `Bad` | green / red | toast accents, gate status |
| `Dim` | `75, 75, 82` | header button borders, disabled buttons |
| `Track` | `60, 67, 82` | slider track |

---

## Behaviour you get for free

- **Re-execution replaces the session.** A second run destroys the previous
  window, disconnects its listeners and takes over the same `GuiName`. No
  stacked panels, no duplicate signals.
- **Every callback is wrapped.** A throwing callback reports to the footer and
  `warn()`, and the signal stays alive. One broken feature cannot take the panel
  with it.
- **Connections are owned.** `Window:Destroy()` disconnects everything the
  window created, runs your `OnClose` handlers and removes the ScreenGui.
- **It fits the screen.** A `UIScale` clamps the panel to the viewport on open
  and on every viewport change, down to 0.25 scale, so it is usable on a phone.
- **Dragging is bounded.** The panel cannot be dragged off-screen, and it is
  pulled back if the viewport shrinks.
- **Touch works.** Dragging the header and both slider styles accept touch input.
- **Shortcuts yield to typing.** The show/hide key is ignored while a TextBox has
  focus, and while a `Keybind` element is capturing.
- **Nothing is logged anywhere.** No telemetry, no beacons, no network calls
  beyond PUSL-V4 key validation and the optional library download.

---

## Troubleshooting

**The gate says "This executor has no HTTP request function."**
PUSL-V4 needs `request`, `http_request` or `http.request`. Nothing here can work
around that.

**The gate says "This build has no service id configured."**
`ServiceId` was empty and no `Provider` or `PandaAuthV4` was available.

**The gate says "Server identity check failed."**
PUSL-V4 could not verify the server's Ed25519 identity. Treat it as hostile: do
not retry, and do not enter the key again until you know why.

**Settings do not persist.**
`Window:Config(...)` must be called before `Window:Load()`, and only controls with
a `Flag` are saved. Check the footer after a change: it reads "Saved" with a
timestamp, or names the failure.

**A toggle snaps back to OFF on its own.**
Its callback errored or returned `false`. The footer names it, and `warn()` has
the full message.

**Two panels appeared.**
Two different `GuiName`s. The reuse key is `GuiName`, which defaults to
`"PandaUI_" .. Title` with non-alphanumerics stripped, so two windows with
different titles are two separate windows by design.

---

## API reference

### `PandaUI`

| Member | Signature |
|---|---|
| `PandaUI.Version` | string |
| `PandaUI.Theme` | table of `Color3`, see [Theme](#theme) |
| `PandaUI:KeySystem(opts)` | `-> ok, auth` (blocking) or `-> gate` (`Async`) |
| `PandaUI:Window(opts)` | `-> Window` |
| `PandaUI:Session()` | `-> info` with `:GameName(fn)`, `:Thumbnail(fn)` |
| `PandaUI:Avatar(column, opts)` | `-> { Instance, Image }` |
| `PandaUI:ClearSavedKey(opts)` | `-> boolean` |

### Control objects

| Control | Members |
|---|---|
| Toggle | `:Set(bool, silent)`, `:Get()`, `.Value`, `.Instance` |
| Slider | `:Set(number, silent)`, `:Get()`, `.Value`, `.Instance` |
| Dropdown | `:Set(value, silent)`, `:Get()`, `:SetOptions(list)`, `.Header` |
| Grid | `:SetItems(list)`, `.Instance` |
| TextBox | `:Set(string, silent)`, `:Get()`, `.Box` |
| Keybind | `:Set(name, silent)`, `:Get()`, `.Value` |
| Button | `:Set(text)`, `:SetEnabled(bool)`, `.Instance` |
| Info | `:Set(value)`, `:SetCaption(text)`, `.Value` |
| Label, Paragraph | `:Set(text)`, `.Instance` |

`silent = true` updates the control and its flag without firing the callback or
triggering an autosave. That is what `Window:Load()` does **not** do, on purpose:
loading runs your callbacks so the features match the UI.
