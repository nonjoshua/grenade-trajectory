-- Grenade trajectory preview (for executors with a partial Roblox API, e.g. Matcha)
-- Shows automatically while a grenade is equipped, and calibrates itself from your real throws.

-- unload any copy that's already running, so re-running this replaces it
if type(_G.stopTrajectory) == "function" then pcall(_G.stopTrajectory) end

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService
pcall(function() RunService = game:GetService("RunService") end)

local LocalPlayer = Players.LocalPlayer

local CONFIG = {
    -- "Equipped" = always visible while a grenade is in hand
    -- "Hold"     = only while holding the button below
    -- "Toggle"   = press the button to turn it on/off
    ShowMode           = "Equipped",
    UseMouse           = true,
    MouseButton        = 2,
    KeyCode            = 0x47,   -- G
    UnloadKey          = 0x58,   -- X: removes the script (try 120 or 88 if it doesn't fire)

    -- measured from a real throw in this game (grenade part "Slide" in Workspace.Debris)
    -- fixed model, fitted to 3 tracked flights of the real grenade (flat + 2 high throws, ~0.7 stud error):
    -- spawns 2.5 studs ahead of your head along the camera direction, flies straight along the camera
    -- direction at 152 studs/s, falls at 117 studs/s^2, no drag
    ThrowSpeed         = 152,
    Gravity            = 117,
    UpBias             = 0,
    SpawnForward       = 2.5,    -- studs ahead of the head, along where the camera looks (tilts with it)
    OriginShift        = Vector3.new(0, 0, 0), -- world offset from the launch point
    -- the grenade first shows up ahead of your hand (camera-relative: right, up, forward studs)
    SpawnOffset        = Vector3.new(0, 0, 0), -- extra (right, up, forward) nudge; not needed for this game

    -- after the first impact the grenade bounces and rolls (measured: keeps ~65% speed, ~24 studs of roll)
    PredictRoll        = true,
    BounceKeep         = 0.62,   -- share of horizontal speed kept after the first bounce (measured)
    RollFriction       = 160,    -- studs/sec^2 the roll slows down by (measured)
    RollColor          = Color3.fromRGB(255, 200, 90),

    -- blast radius ring drawn on the ground around where the grenade ends up, colored by outcome
    ShowBlastRadius    = true,
    BlastRadius        = 15,     -- studs; replaced by the size of the game's explosion when one is seen
    BlastRadiusFromGame = true,  -- measure the radius from the GrenadeExplosion part (a measurement, not a guess)
    BlastSegments      = 40,
    ColorClear         = Color3.fromRGB(80, 220, 110),  -- lands on a floor/ground and settles
    ColorWall          = Color3.fromRGB(255, 200, 60),  -- hits a wall: it will drop/bounce off, spot less certain
    ColorDanger        = Color3.fromRGB(255, 60, 60),   -- you are inside the blast radius
    ColorNoLanding     = Color3.fromRGB(150, 150, 150), -- no landing found within the arc

    -- wall bounces (measured from your logs: almost no bounce-back, keeps ~half its speed along the wall)
    WallBounce         = true,
    MaxWallBounces     = 3,
    WallRestitution    = 0,      -- share of speed INTO the wall that comes back out (measured 0% on 4 wall hits: it drops straight down the wall)
    WallSlideKeep      = 0.6,    -- share of speed ALONG the wall that is kept (fitted to your logged wall hit)

    -- fuse: the grenade explodes this long after you release it (it hangs ~0.15s before flying)
    Fuse               = 3,
    FuseStart          = "Throw", -- "Throw" = counts from release; "Pin" = counts from pulling the pin (cooking)
    LaunchDelay        = 0.15,   -- seconds it hangs in front of you before it starts flying
    ColorAirburst      = Color3.fromRGB(180, 100, 255), -- explodes in the air before landing
    ColorRolling       = Color3.fromRGB(80, 220, 220),  -- explodes while still rolling

    -- depth cues on the 3D arc: crossbars every TickSeconds (wide up close, small far away)
    ArcTicks           = true,
    TickSeconds        = 0.25,
    TickWidth          = 1.2,    -- studs, half-width of each crossbar

    -- humanoids (players and NPCs) inside the blast ring
    ShowInBlast        = true,
    InBlastColor       = Color3.fromRGB(255, 120, 255),
    InBlastScanHz      = 2,      -- how often the list of humanoids is refreshed (positions update every frame)
    InBlastMax         = 8,      -- most names shown
    InBlastHud         = true,   -- show the names at a fixed spot on screen (not attached to the landing spot)
    BlastNeedsLineOfSight = true, -- walls/roofs/floors between the blast and a person shield them
    CoverColor         = Color3.fromRGB(150, 150, 150),
    InBlastHudPos      = Vector2.new(0.5, 0.58), -- where, as a fraction of the screen (0.5, 0.58 = just below the crosshair)
    LaunchFrom         = "Head", -- "Head", "Hand", "Camera" or "Root": the spot the arc is anchored to.
                                 -- Head is steady; Hand moves with the wind-up animation (calibration never changes this)
    ResetKey           = 0x52,   -- R: throw away all calibration and go back to the defaults above

    AutoCalibrate      = false,  -- true = let throws change the numbers above (off: the model is fixed)
    ReportAccuracy     = true,   -- after each throw, print how far the prediction was from the real landing
    CalibrateSeconds   = 3,      -- how long to track a thrown grenade (flight is cut at the first bounce; the rest measures the roll)
    LogThrows          = true,   -- print the real flight path of every throw to the console
    LogSeconds         = 4,      -- how long to keep printing a flight (covers bounces / landing)
    GrenadeNameMatch   = "grenade",
    Debug              = true,   -- print equip / throw / new-object events
    -- folders to look in for the flying grenade ("" = Workspace itself, "Camera" = CurrentCamera)
    ProjectileFolders  = { "Filter", "Debris", "", "Camera" },
    ProjectileSkip     = { Map = true, Terrain = true, Audio = true },
    WatchHz            = 20,     -- how often the watched folders are checked while a grenade is held
    ProjectileMinSpeed = 15,     -- studs/sec a part must move away from your hand to count
    ProjectileMaxSize  = 4,      -- ignore parts bigger than this (studs) - grenades are small
    ProjectileMaxSpeed = 300,    -- ignore anything faster (bullets)
    -- known grenade body, by folder path -> part name: tracked right away.
    -- ("Slide" in Debris is the spoon that pops off - not the grenade)
    ProjectilePaths    = { ["Debris/VParts"] = "Handle" },
    ProjectileNames    = {},     -- extra part names to track anywhere (by name only)
    DeepScanKey        = 0x4A,   -- J: one-off full search for anything named like a grenade (may hitch once)

    Steps              = 50,
    TimeStep           = 0.06,

    -- performance limiter
    PhysicsHz          = 20,     -- how often the arc is re-simulated (raycasts); drawing stays every frame
    DrawHz             = 60,     -- how often lines are re-projected to the screen (0 = every frame)
    LogHz              = 20,     -- flight-log samples per second
    AimDistance        = 60,
    FallbackGroundDrop = 3,
    -- Raycast doesn't work in Matcha, so the arc needs a ground height.
    -- "Learned" = the height where your grenades actually land (learned per map, falls back to feet)
    -- "Feet"    = the floor you're standing on
    GroundMode         = "Feet",
    GroundY            = nil,    -- set a number to force the ground height (e.g. 1)

    -- map collision without Raycast: the script reads the map's parts once (spread over frames)
    -- and does its own wall / roof hit tests
    MapCollision       = true,
    MapFolders         = { "Map" }, -- Workspace folders that hold the buildings ({} = all of Workspace)
    MapScanPerFrame    = 4000,   -- hard cap on instances read per frame while building the map cache
    MapMsPerFrame      = 6,      -- milliseconds per frame spent reading the map (more = faster load, more stutter)
    MapRefreshKey      = 0x4D,   -- M: re-read the map (the map is remembered between reloads on the same server)
    MapMaxParts        = 200000,

    -- side view: the arc seen from the side, with buildings cut along the throw line
    SidePanel          = true,
    PanelSize          = Vector2.new(320, 160),
    PanelMargin        = Vector2.new(20, 140), -- from the bottom-right corner of the screen

    -- top-down view of the landing area (your throw direction points up)
    TopPanel           = true,
    TopPanelSize       = 260,    -- pixels (square)
    TopPanelMargin     = Vector2.new(20, 340), -- from the bottom-right corner (sits above the side view)
    TopViewRange       = 45,     -- studs from the landing spot to the panel edge (shows 90 x 90 studs)
    TopMaxBoxes        = 70,     -- most map parts outlined
    TopColorLow        = Color3.fromRGB(90, 90, 100),    -- parts at/below the landing height
    TopColorHigh       = Color3.fromRGB(220, 220, 230),  -- parts well above it (walls, roofs)
    Color              = Color3.fromRGB(90, 210, 255),
    LandColor          = Color3.fromRGB(255, 90, 90),
    Thickness          = 2,
    MarkerSides        = 28,
    LabelSize          = 14,
}

-- settings from the loader: set _G.TrajectoryConfig = { ... } before loadstring to override any of the above
-- e.g.  _G.TrajectoryConfig = { Debug = false, LogThrows = false, TopViewRange = 60 }
do
    local user = _G.TrajectoryConfig
    if type(user) == "table" then
        local n = 0
        for k, v in pairs(user) do
            if CONFIG[k] ~= nil or k == "GroundY" then
                CONFIG[k] = v
                n = n + 1
            else
                print("[Trajectory] unknown setting in TrajectoryConfig: " .. tostring(k))
            end
        end
        print("[Trajectory] applied " .. n .. " setting(s) from _G.TrajectoryConfig")
    end
end

-- defaults, so R can undo calibration
local DEFAULTS = {}
for _, k in ipairs({ "ThrowSpeed", "Gravity", "UpBias", "OriginShift", "SpawnOffset", "LaunchFrom",
    "BounceKeep", "RollFriction" }) do DEFAULTS[k] = CONFIG[k] end

local learnedGround = {}  -- heights where grenades came to rest (ground height without Raycast)
local hold = { pressT = nil, lastHold = nil, pinT = nil, timer = nil, pin = nil } -- wind-up tracking

-- ---------- API check ----------
local env = getfenv and getfenv() or _G
local function has(name) return type(env[name]) == "function" or type(_G[name]) == "function" end
local missing = {}
for _, name in ipairs({ "WorldToScreen", "ismouse1pressed", "ismouse2pressed", "iskeypressed" }) do
    if not has(name) then table.insert(missing, name) end
end
if type(Drawing) ~= "table" or type(Drawing.new) ~= "function" then table.insert(missing, "Drawing.new") end
local canRaycast = pcall(function() Workspace:Raycast(Vector3.new(0, 1000, 0), Vector3.new(0, -1, 0)) end)
if not canRaycast then table.insert(missing, "Workspace:Raycast (flat-ground fallback)") end
if #missing > 0 then print("[Trajectory] missing/unsupported: " .. table.concat(missing, ", ")) end
if not has("WorldToScreen") or type(Drawing) ~= "table" then
    print("[Trajectory] cannot run without WorldToScreen and Drawing - aborting")
    return
end

local now = (os and os.clock) or tick

-- ---------- helpers ----------
local function v3(x, y, z) return Vector3.new(x, y, z) end
local function clamp(x, lo, hi) if x < lo then return lo elseif x > hi then return hi end return x end
local function isGrenadeName(n) return string.find(string.lower(n), CONFIG.GrenadeNameMatch, 1, true) ~= nil end

local function isDescendant(inst, ancestor)
    local ok, res = pcall(function() return inst:IsDescendantOf(ancestor) end)
    if ok then return res end
    local p = inst
    while p do if p == ancestor then return true end p = p.Parent end
    return false
end

-- walks up by ClassName, because Matcha hands back new object copies that don't compare equal
local function inWorkspace(inst)
    local p, n = inst, 0
    while p and n < 50 do
        if p.ClassName == "Workspace" then return true end
        p, n = p.Parent, n + 1
    end
    return false
end

local function getGrenadeTool(char)
    for _, c in ipairs(char:GetChildren()) do
        if c.ClassName == "Tool" and isGrenadeName(c.Name) then return c end
    end
    return nil
end

local function getHand(char)
    return char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm") or char:FindFirstChild("Head")
end

-- ---------- drawing ----------
local MAX_LINES = CONFIG.Steps
local lines = {}
for i = 1, MAX_LINES do
    local l = Drawing.new("Line")
    l.Color, l.Thickness, l.Transparency, l.Visible = CONFIG.Color, CONFIG.Thickness, 1, false
    lines[i] = l
end
local bounceDots = {}
for i = 1, 3 do
    local c = Drawing.new("Circle")
    c.Color, c.Thickness, c.Filled, c.NumSides, c.Radius, c.Transparency, c.Visible = CONFIG.RollColor, 2, false, 12, 5, 1, false
    bounceDots[i] = c
end
local ticks = {}
for i = 1, 24 do
    local l = Drawing.new("Line")
    l.Color, l.Thickness, l.Transparency, l.Visible = CONFIG.Color, 2, 1, false
    ticks[i] = l
end
local blastRing = {}
for i = 1, CONFIG.BlastSegments do
    local l = Drawing.new("Line")
    l.Thickness, l.Transparency, l.Visible = 2, 1, false
    blastRing[i] = l
end
local inBlastMarks = {}
for i = 1, CONFIG.InBlastMax do
    local c = Drawing.new("Circle")
    c.Color, c.Thickness, c.Filled, c.NumSides, c.Transparency, c.Visible = CONFIG.InBlastColor, 2, false, 16, 1, false
    inBlastMarks[i] = c
end
local inBlastText = Drawing.new("Text")
inBlastText.Size, inBlastText.Center, inBlastText.Outline, inBlastText.Color, inBlastText.Visible =
    CONFIG.LabelSize + 4, true, true, CONFIG.InBlastColor, false
local status = Drawing.new("Text")
status.Size, status.Center, status.Outline, status.Visible = CONFIG.LabelSize, true, true, false
local marker = Drawing.new("Circle")
marker.Color, marker.Thickness, marker.Filled = CONFIG.LandColor, 2, false
marker.NumSides, marker.Transparency, marker.Visible = CONFIG.MarkerSides, 1, false
local rollLine = Drawing.new("Line")
rollLine.Color, rollLine.Thickness, rollLine.Transparency, rollLine.Visible = CONFIG.RollColor, CONFIG.Thickness, 1, false
local impactDot = Drawing.new("Circle")
impactDot.Color, impactDot.Thickness, impactDot.Filled = CONFIG.Color, 2, true
impactDot.NumSides, impactDot.Radius, impactDot.Transparency, impactDot.Visible = 12, 4, 1, false
local panel = { lines = {}, cols = {}, bg = nil, ground = nil, title = nil }
if CONFIG.SidePanel then
    panel.bg = Drawing.new("Square")
    panel.bg.Filled, panel.bg.Color, panel.bg.Transparency, panel.bg.Visible = true, Color3.fromRGB(15, 15, 20), 0.55, false
    panel.title = Drawing.new("Text")
    panel.title.Size, panel.title.Color, panel.title.Outline, panel.title.Visible = 13, Color3.fromRGB(230, 230, 230), true, false
    for i = 1, MAX_LINES do
        local l = Drawing.new("Line")
        l.Color, l.Thickness, l.Transparency, l.Visible = CONFIG.Color, 2, 1, false
        panel.lines[i] = l
    end
    for i = 1, 160 do
        local l = Drawing.new("Line")
        l.Color, l.Thickness, l.Transparency, l.Visible = Color3.fromRGB(150, 150, 150), 2, 1, false
        panel.cols[i] = l
    end
    panel.ground = Drawing.new("Line")
    panel.ground.Color, panel.ground.Thickness, panel.ground.Transparency, panel.ground.Visible = Color3.fromRGB(90, 160, 90), 1, 1, false
    panel.blast = Drawing.new("Line")
    panel.blast.Thickness, panel.blast.Transparency, panel.blast.Visible = 4, 0.8, false
    panel.land = Drawing.new("Circle")
    panel.land.Color, panel.land.Radius, panel.land.Filled, panel.land.Transparency, panel.land.Visible = CONFIG.LandColor, 4, true, 1, false
end
local function hidePanel()
    if not panel.bg then return end
    panel.bg.Visible, panel.title.Visible, panel.ground.Visible, panel.land.Visible = false, false, false, false
    panel.blast.Visible = false
    for _, l in ipairs(panel.lines) do l.Visible = false end
    for _, l in ipairs(panel.cols) do l.Visible = false end
end
local function removePanel()
    if not panel.bg then return end
    panel.bg:Remove() panel.title:Remove() panel.ground:Remove() panel.land:Remove() panel.blast:Remove()
    for _, l in ipairs(panel.lines) do l:Remove() end
    for _, l in ipairs(panel.cols) do l:Remove() end
end
local label = Drawing.new("Text")
label.Color, label.Size, label.Center, label.Outline, label.Visible = CONFIG.LandColor, CONFIG.LabelSize, true, true, false

-- ---------- top-down panel objects ----------
local top = { boxLines = {}, arc = {}, people = {}, names = {}, bounces = {} }
if CONFIG.TopPanel then
    local function newLine(color, th)
        local l = Drawing.new("Line")
        l.Color, l.Thickness, l.Transparency, l.Visible = color, th or 1, 1, false
        return l
    end
    local function newCircle(color, r, filled)
        local c = Drawing.new("Circle")
        c.Color, c.Radius, c.Filled, c.Thickness, c.NumSides, c.Transparency, c.Visible = color, r, filled, 2, 24, 1, false
        return c
    end
    top.bg = Drawing.new("Square")
    top.bg.Filled, top.bg.Color, top.bg.Transparency, top.bg.Visible = true, Color3.fromRGB(15, 15, 20), 0.6, false
    top.border = Drawing.new("Square")
    top.border.Filled, top.border.Color, top.border.Thickness, top.border.Transparency, top.border.Visible =
        false, Color3.fromRGB(120, 120, 130), 1, 1, false
    top.title = Drawing.new("Text")
    top.title.Size, top.title.Color, top.title.Outline, top.title.Visible = 13, Color3.fromRGB(230, 230, 230), true, false
    for i = 1, CONFIG.TopMaxBoxes * 4 do top.boxLines[i] = newLine(CONFIG.TopColorLow, 1) end
    for i = 1, 40 do top.arc[i] = newLine(CONFIG.Color, 2) end
    top.roll = newLine(CONFIG.RollColor, 2)
    top.ring = newCircle(CONFIG.ColorClear, 10, false)
    top.land = newCircle(CONFIG.ColorClear, 4, true)
    top.impact = newCircle(CONFIG.Color, 3, true)
    top.me = newCircle(Color3.fromRGB(90, 170, 255), 4, true)
    for i = 1, 3 do top.bounces[i] = newCircle(CONFIG.RollColor, 3, false) end
    for i = 1, 14 do
        top.people[i] = newCircle(Color3.fromRGB(255, 255, 255), 3, true)
        local t = Drawing.new("Text")
        t.Size, t.Outline, t.Center, t.Visible = 12, true, false, false
        top.names[i] = t
    end
end
local function topAll(fn)
    if not top.bg then return end
    for _, o in ipairs({ top.bg, top.border, top.title, top.roll, top.ring, top.land, top.impact, top.me }) do fn(o) end
    for _, l in ipairs(top.boxLines) do fn(l) end
    for _, l in ipairs(top.arc) do fn(l) end
    for _, c in ipairs(top.people) do fn(c) end
    for _, t in ipairs(top.names) do fn(t) end
    for _, c in ipairs(top.bounces) do fn(c) end
end
local function hideTop() topAll(function(o) o.Visible = false end) end

local function hideAll()
    for i = 1, MAX_LINES do lines[i].Visible = false end
    marker.Visible, label.Visible = false, false
    rollLine.Visible, impactDot.Visible = false, false
    for _, l in ipairs(blastRing) do l.Visible = false end
    for _, l in ipairs(ticks) do l.Visible = false end
    for _, c in ipairs(bounceDots) do c.Visible = false end
    status.Visible = false
    for _, c in ipairs(inBlastMarks) do c.Visible = false end
    inBlastText.Visible = false
    hidePanel()
    hideTop()
end

-- ---------- input ----------
local function buttonDown()
    if CONFIG.UseMouse then
        if CONFIG.MouseButton == 1 then return ismouse1pressed() end
        return ismouse2pressed()
    end
    return iskeypressed(CONFIG.KeyCode)
end

local toggledOn, lastButton = false, false
local function wantsShow()
    if CONFIG.ShowMode == "Equipped" then return true end
    local b = buttonDown()
    if CONFIG.ShowMode == "Hold" then return b end
    if b and not lastButton then toggledOn = not toggledOn end
    lastButton = b
    return toggledOn
end

-- ---------- physics ----------
-- Some executors let Workspace:Raycast run but always return nil. Verify it once with a
-- ray straight down from the character; if that finds nothing, treat Raycast as broken.
local raycastVerified = nil

local legacyRay = nil -- set once we know which API works
local function rayHit(from, dir, char)
    if legacyRay ~= true then
        local ok, hit = pcall(function() return Workspace:Raycast(from, dir) end)
        if ok and hit and hit.Instance and not isDescendant(hit.Instance, char) then return hit.Position end
        if legacyRay == false then return nil end
    end
    -- older API: FindPartOnRayWithIgnoreList(Ray.new(origin, direction), {character})
    local ok2, part, pos = pcall(function()
        return Workspace:FindPartOnRayWithIgnoreList(Ray.new(from, dir), { char })
    end)
    if ok2 and part and pos then return pos end
    return nil
end

local function verifyRaycast(char)
    if raycastVerified ~= nil or not canRaycast then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local okNew, hitNew = pcall(function() return Workspace:Raycast(root.Position + v3(0, -2.5, 0), v3(0, -20, 0)) end)
    if okNew and hitNew then
        legacyRay, raycastVerified = false, true
    else
        local okOld, part = pcall(function()
            return Workspace:FindPartOnRayWithIgnoreList(Ray.new(root.Position, v3(0, -20, 0)), { char })
        end)
        if okOld and part then
            legacyRay, raycastVerified = true, true
            print("[Trajectory] using FindPartOnRay for collisions (walls, roofs, slopes)")
        else
            raycastVerified = false
        end
    end
    if not raycastVerified then
        print("[Trajectory] Raycast returns nothing on this executor - using flat-ground fallback")
    end
end

-- ---------- map cache + collision ----------
-- Each solid part is stored as an oriented box (center, 3 axes, half sizes) in a 2D grid (x,z).
local CELL = 16
local map = { ready = false, building = false, queue = nil, qi = 1, cells = {}, big = {}, n = 0, seen = 0 }

local function cellKey(cx, cz) return cx * 100003 + cz end

local function addPart(p)
    local okS, size = pcall(function() return p.Size end)
    if not okS or not size then return end
    local okC, cf = pcall(function() return p.CFrame end)
    local cx, cy, cz, r, u, l
    if okC and cf then
        local okA = pcall(function()
            local pos = cf.Position
            cx, cy, cz = pos.X, pos.Y, pos.Z
            local R, U, L = cf.RightVector, cf.UpVector, cf.LookVector
            r = { R.X, R.Y, R.Z }; u = { U.X, U.Y, U.Z }; l = { -L.X, -L.Y, -L.Z }
        end)
        if not okA then cx = nil end
    end
    if not cx then
        local okP, pos = pcall(function() return p.Position end)
        if not okP or not pos then return end
        cx, cy, cz = pos.X, pos.Y, pos.Z
        r, u, l = { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 }
    end
    local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
    local box = { cx, cy, cz, r, u, l, hx, hy, hz }
    -- world-space extents for the grid
    local ex = math.abs(r[1]) * hx + math.abs(u[1]) * hy + math.abs(l[1]) * hz
    local ez = math.abs(r[3]) * hx + math.abs(u[3]) * hy + math.abs(l[3]) * hz
    box.top = cy + math.abs(r[2]) * hx + math.abs(u[2]) * hy + math.abs(l[2]) * hz
    local x0, x1 = math.floor((cx - ex) / CELL), math.floor((cx + ex) / CELL)
    local z0, z1 = math.floor((cz - ez) / CELL), math.floor((cz + ez) / CELL)
    if (x1 - x0 + 1) * (z1 - z0 + 1) > 400 then
        map.big[#map.big + 1] = box
    else
        for gx = x0, x1 do
            for gz = z0, z1 do
                local k = cellKey(gx, gz)
                local c = map.cells[k]
                if not c then c = {} map.cells[k] = c end
                c[#c + 1] = box
            end
        end
    end
    map.n = map.n + 1
end

local SKIP_TOP = { Characters = true, Debris = true, Filter = true, Camera = true, Terrain = true, Audio = true }
local function mapCacheKey()
    local okP, pid = pcall(function() return game.PlaceId end)
    local okJ, jid = pcall(function() return game.JobId end)
    return tostring(okP and pid or "?") .. ":" .. tostring(okJ and jid or "?") .. ":" .. table.concat(CONFIG.MapFolders, ",")
end

local function startMapBuild(force)
    -- reuse the map read by an earlier load of this script on the same server
    local cache = _G.TrajectoryMapCache
    if not force and cache and cache.key == mapCacheKey() and cache.n > 0 then
        map.cells, map.big, map.n = cache.cells, cache.big, cache.n
        map.building, map.ready = false, true
        print(string.format("[Trajectory] map collision ready instantly: %d parts (remembered from last load, M = re-read)", map.n))
        return
    end
    map.building, map.ready, map.cells, map.big, map.n, map.seen = true, false, {}, {}, 0, 0
    -- explicit head/tail indexes: '#' is unreliable once the front of the queue is cleared
    map.queue, map.qi, map.qn = {}, 1, 0
    local function push(x) map.qn = map.qn + 1 map.queue[map.qn] = x end
    map.push = push
    local found = false
    for _, name in ipairs(CONFIG.MapFolders) do
        local f = Workspace:FindFirstChild(name)
        if f then push(f) found = true end
    end
    if not found then
        for _, c in ipairs(Workspace:GetChildren()) do
            if not SKIP_TOP[c.Name] and c.ClassName ~= "Camera" and c.ClassName ~= "Terrain" then
                push(c)
            end
        end
    end
    print("[Trajectory] reading map parts for collision...")
end

local PART_CLASS_SET = { Part = true, MeshPart = true, UnionOperation = true, WedgePart = true,
                         CornerWedgePart = true, TrussPart = true, SpawnLocation = true, Seat = true }
local function stepMapBuild()
    if not map.building then return end
    local budget = CONFIG.MapScanPerFrame
    local tEnd = now() + CONFIG.MapMsPerFrame / 1000
    while budget > 0 and map.qi <= map.qn and (budget % 25 ~= 0 or now() < tEnd) do
        local inst = map.queue[map.qi]
        map.queue[map.qi] = nil
        map.qi = map.qi + 1
        budget = budget - 1
        map.seen = map.seen + 1
        local okC, cls = pcall(function() return inst.ClassName end)
        if okC then
            if PART_CLASS_SET[cls] then
                local okCC, cc = pcall(function() return inst.CanCollide end)
                if not (okCC and cc == false) then addPart(inst) end
            elseif cls ~= "Humanoid" and cls ~= "Sound" and cls ~= "Script" and cls ~= "LocalScript"
                and not (cls == "Model" and select(2, pcall(function() return inst:FindFirstChild("Humanoid") end))) then
                -- (models with a Humanoid are characters/NPCs: they move, so they're not walls)
                local okK, kids = pcall(function() return inst:GetChildren() end)
                if okK then
                    for _, k in ipairs(kids) do map.push(k) end
                end
            end
        end
        if map.n >= CONFIG.MapMaxParts then map.qi = map.qn + 1 end
    end
    if map.qi > map.qn then
        map.building, map.ready, map.queue = false, true, nil
        print(string.format("[Trajectory] map collision ready: %d parts", map.n))
        _G.TrajectoryMapCache = { key = mapCacheKey(), cells = map.cells, big = map.big, n = map.n }
    end
end

-- segment p0->p1 against an oriented box: returns entry t (0..1) or nil; also exit t
local function segBox(b, x0, y0, z0, dx, dy, dz, grow)
    local px, py, pz = x0 - b[1], y0 - b[2], z0 - b[3]
    local tmin, tmax = 0, 1
    local enterAxis, enterSign = nil, nil
    local axes, half = { b[4], b[5], b[6] }, { b[7], b[8], b[9] }
    for i = 1, 3 do
        local a = axes[i]
        local o = px * a[1] + py * a[2] + pz * a[3]
        local d = dx * a[1] + dy * a[2] + dz * a[3]
        local h = half[i]
        if grow and i ~= 2 then h = h + grow end -- widen sideways only (side-panel columns)
        if math.abs(d) < 1e-9 then
            if o < -h or o > h then return nil end
        else
            local t1, t2 = (-h - o) / d, (h - o) / d
            if t1 > t2 then t1, t2 = t2, t1 end
            if t1 > tmin then tmin, enterAxis, enterSign = t1, i, (d > 0) and -1 or 1 end
            if t2 < tmax then tmax = t2 end
            if tmin > tmax then return nil end
        end
    end
    -- enterAxis/enterSign: which face was hit (outward normal = axes[enterAxis] * enterSign);
    -- nil when the segment starts inside the box
    return tmin, tmax, enterAxis, enterSign
end

local function boxesNear(x0, z0, x1, z1)
    local out, seen = {}, {}
    local gx0, gx1 = math.floor(math.min(x0, x1) / CELL), math.floor(math.max(x0, x1) / CELL)
    local gz0, gz1 = math.floor(math.min(z0, z1) / CELL), math.floor(math.max(z0, z1) / CELL)
    for gx = gx0, gx1 do
        for gz = gz0, gz1 do
            local c = map.cells[cellKey(gx, gz)]
            if c then
                for _, b in ipairs(c) do
                    if not seen[b] then seen[b] = true out[#out + 1] = b end
                end
            end
        end
    end
    for _, b in ipairs(map.big) do out[#out + 1] = b end
    return out
end

local function mapHit(from, to)
    if not map.ready and map.n == 0 then return nil end -- (partial map is used while it loads)
    local dx, dy, dz = to.X - from.X, to.Y - from.Y, to.Z - from.Z
    local best, bestBox, bestAxis, bestSign = nil, nil, nil, nil
    for _, b in ipairs(boxesNear(from.X, from.Z, to.X, to.Z)) do
        local t, _, ax, sg = segBox(b, from.X, from.Y, from.Z, dx, dy, dz)
        if t and ax and (not best or t < best) then best, bestBox, bestAxis, bestSign = t, b, ax, sg end
    end
    if best then
        local y = from.Y + dy * best
        local a = bestBox[3 + bestAxis]
        local normal = v3(a[1] * bestSign, a[2] * bestSign, a[3] * bestSign)
        -- floor/roof when the face points up; otherwise a wall (or a ceiling)
        local isFloor = normal.Y > 0.6
        return v3(from.X + dx * best, y, from.Z + dz * best), isFloor, normal
    end
    return nil
end

-- solid vertical spans [bottom, top] at a map position (for the side panel)
local function columnSpans(x, z, yTop, yBot, grow)
    local spans = {}
    if not map.ready and map.n == 0 then return spans end
    local dy = yBot - yTop
    local g = grow or 0
    for _, b in ipairs(boxesNear(x - g, z - g, x + g, z + g)) do
        local t0, t1 = segBox(b, x, yTop, z, 0, dy, 0, grow)
        if t0 then spans[#spans + 1] = { yTop + dy * t1, yTop + dy * t0 } end
    end
    return spans
end

local function castSegment(from, to, char, groundY)
    if raycastVerified then
        local p = rayHit(from, to - from, char)
        if p then return p end
    elseif CONFIG.MapCollision then
        local p, isFloor, normal = mapHit(from, to)
        if p then return p, isFloor, normal end
    end
    -- flat floor under the player: the only collision without Raycast, and a safety net with it
    if to.Y <= groundY and from.Y > groundY then
        local t = (from.Y - groundY) / (from.Y - to.Y)
        return from + (to - from) * t
    end
    return nil
end

-- the grenade leaves from the hand: bottom of the R6 arm, or the R15 hand
local function handPosition(char)
    local r15 = char:FindFirstChild("RightHand")
    if r15 then return r15.Position end
    local arm = char:FindFirstChild("Right Arm")
    if arm then
        local ok, p = pcall(function() return arm.Position - arm.CFrame.UpVector * (arm.Size.Y * 0.5) end)
        if ok then return p end
        return arm.Position
    end
    local head = char:FindFirstChild("Head")
    return head and head.Position or nil
end

-- the point the spawn offset is measured from. Head by default: the hand moves with the
-- wind-up animation, but the game spawns the grenade at a steady spot
local function anchorPosition(char, camera)
    local base
    if CONFIG.LaunchFrom == "Camera" then
        base = camera.CFrame.Position
    elseif CONFIG.LaunchFrom == "Head" then
        local h = char:FindFirstChild("Head")
        base = h and h.Position
    elseif CONFIG.LaunchFrom == "Root" then
        local r = char:FindFirstChild("HumanoidRootPart")
        base = r and r.Position
    else
        base = handPosition(char)
    end
    return base or handPosition(char) or camera.CFrame.Position
end

-- returns origin, aim direction (unit) for the current frame
local function launchFrame(camera, char)
    local cf, look = camera.CFrame, camera.CFrame.LookVector
    local base = anchorPosition(char, camera)
    local fwd = v3(look.X, 0, look.Z)
    fwd = (fwd.Magnitude > 0.01) and fwd.Unit or v3(0, 0, -1)
    local right = v3(-fwd.Z, 0, fwd.X)
    local so = CONFIG.SpawnOffset
    local origin = base + look * CONFIG.SpawnForward + CONFIG.OriginShift
        + right * so.X + v3(0, so.Y, 0) + fwd * so.Z
    -- the game throws straight along the camera direction
    return origin, look
end

-- project a world segment, cutting off any part behind the camera
-- (points behind the camera project to garbage and cause the long stray lines)
local NEAR = 2 -- anything closer than this to the camera isn't drawn (first person stretched the first segment)
local function dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
local function projectSegment(a, b, camPos, look)
    local da = dot(a - camPos, look)
    local db = dot(b - camPos, look)
    if da < NEAR and db < NEAR then return nil end
    if da < NEAR then a = a + (b - a) * ((NEAR - da) / (db - da)) da = NEAR end
    if db < NEAR then b = b + (a - b) * ((NEAR - db) / (da - db)) db = NEAR end
    local sa = WorldToScreen(a)
    local sb = WorldToScreen(b)
    return sa, sb, (da + db) * 0.5
end

-- cached arc (world space), re-simulated at PhysicsHz
local arcPts, arcLand, arcRoot, arcRest = {}, nil, nil, nil
local arcFloor = true
local arcAir, arcRollBurst, arcTimes, arcTickPts, arcAirHeight = nil, false, {}, {}, nil
local arcBounces = {}
local arcProfile = nil

local function simulate(camera, char)
    verifyRaycast(char)
    local origin, dir = launchFrame(camera, char)
    local vel   = dir * CONFIG.ThrowSpeed + v3(0, CONFIG.ThrowSpeed * CONFIG.UpBias, 0)
    local gStep = v3(0, -CONFIG.Gravity * CONFIG.TimeStep, 0)

    local root = char:FindFirstChild("HumanoidRootPart")
    local groundY = root and (root.Position.Y - CONFIG.FallbackGroundDrop) or (origin.Y - 5)
    if map.ready and map.n > 0 then
        groundY = -1e6 -- the map's own parts are the ground; no fake floor at your feet
    end
    if CONFIG.GroundY then
        groundY = CONFIG.GroundY
    elseif CONFIG.GroundMode == "Learned" and #learnedGround > 0 then
        local arr = {}
        for i, v in ipairs(learnedGround) do arr[i] = v end
        table.sort(arr)
        groundY = arr[math.floor((#arr + 1) / 2)]
    end

    -- exact parabola p(t) = origin + v*t - g*t^2/2 (no step-by-step drift)
    local g = CONFIG.Gravity
    local function at(t) return origin + vel * t + v3(0, -0.5 * g * t * t, 0) end
    -- how long it can fly before the fuse runs out
    local fuseLeft = CONFIG.Fuse
    if CONFIG.FuseStart == "Pin" and hold.pinT then fuseLeft = CONFIG.Fuse - (now() - hold.pinT) end
    local flightBudget = fuseLeft - CONFIG.LaunchDelay

    -- the flight is a chain of parabolas: a new one starts at every wall bounce
    local segs = { { o = origin, v = vel, t0 = 0 } }
    local cur = segs[1]
    local pts, pos, landPos, landFloor = { origin }, origin, nil, true
    local tPrev, tHit, airburst = 0, nil, nil -- tPrev: time since the current parabola started
    local bounces, bouncePts = 0, {}
    local vImpact = vel
    local dt = CONFIG.TimeStep
    local function segAt(s, tau) return s.o + s.v * tau + v3(0, -0.5 * g * tau * tau, 0) end
    for _ = 1, CONFIG.Steps * 2 do
        local tau = tPrev + dt
        local cut = false
        if cur.t0 + tau >= flightBudget then tau, cut = math.max(flightBudget - cur.t0, 0), true end
        local nextPos = segAt(cur, tau)
        local hitPos, isFloor, normal = castSegment(pos, nextPos, char, groundY)
        if hitPos then
            local seg = (nextPos - pos).Magnitude
            local frac = seg > 0 and (hitPos - pos).Magnitude / seg or 1
            local tauHit = tPrev + (tau - tPrev) * frac
            local vHit = cur.v + v3(0, -g * tauHit, 0)
            if CONFIG.WallBounce and isFloor == false and normal and bounces < CONFIG.MaxWallBounces then
                -- wall (or ceiling): kill most of the speed into it, keep part of the slide along it
                local vn = normal * dot(vHit, normal)
                local vt = vHit - vn
                local newV = vt * CONFIG.WallSlideKeep - vn * CONFIG.WallRestitution
                bounces = bounces + 1
                bouncePts[#bouncePts + 1] = hitPos
                pts[#pts + 1] = hitPos
                local start = hitPos + normal * 0.15 -- step off the wall so we don't hit it again at once
                cur = { o = start, v = newV, t0 = cur.t0 + tauHit }
                segs[#segs + 1] = cur
                cur.wall = true
                pos, tPrev = start, 0
            else
                tHit = cur.t0 + tauHit
                vImpact = vHit
                landPos, landFloor = hitPos, isFloor ~= false
                pts[#pts + 1] = hitPos
                break
            end
        else
            if cut then airburst = nextPos end -- fuse runs out mid-air
            pts[#pts + 1] = nextPos
            pos, tPrev = nextPos, tau
            if airburst then break end
            if cur.t0 + tau > CONFIG.Steps * dt then break end
        end
    end
    vel = vImpact -- velocity at impact
    local restPos, rollBurst = nil, false
    if landPos and CONFIG.PredictRoll and landFloor then
        local vh = v3(vel.X, 0, vel.Z)
        local sp = vh.Magnitude * CONFIG.BounceKeep
        if sp > 0.5 then
            local f = CONFIG.RollFriction
            local dist = sp * sp / (2 * f)
            -- fuse may run out while it's still rolling
            local tRoll = flightBudget - (tHit or tPrev)
            if tRoll < sp / f then
                dist = math.max(sp * tRoll - 0.5 * f * tRoll * tRoll, 0)
                rollBurst = true
            end
            restPos = landPos + vh.Unit * dist
            -- the roll stops at walls
            local lift = v3(0, 0.5, 0)
            local wallHit = mapHit(landPos + lift, restPos + lift)
            if wallHit then restPos = wallHit - lift end
        end
    end
    arcPts, arcLand, arcRoot, arcRest = pts, landPos, root and root.Position, restPos
    arcAir, arcRollBurst = airburst, rollBurst
    arcAirHeight = nil
    if airburst then
        local below = mapHit(airburst, airburst - v3(0, 2000, 0))
        local gy = below and below.Y or (groundY > -1e5 and groundY) or nil
        arcAirHeight = gy and (airburst.Y - gy) or nil
    end
    arcTimes = { land = tHit and (tHit + CONFIG.LaunchDelay), fuse = fuseLeft }
    arcBounces = bouncePts
    arcTickPts = {}
    if CONFIG.ArcTicks then
        local endT = tHit or (cur.t0 + tPrev)
        local k = CONFIG.TickSeconds
        while k < endT and #arcTickPts < #ticks do
            local s = segs[1]
            for _, sg in ipairs(segs) do if sg.t0 <= k then s = sg end end
            arcTickPts[#arcTickPts + 1] = segAt(s, k - s.t0)
            k = k + CONFIG.TickSeconds
        end
    end
    arcFloor = landFloor

    -- side profile for the panel: distance along the throw vs height, plus buildings cut on that line
    if CONFIG.SidePanel then
        local o, last = pts[1], pts[#pts]
        local hd = v3(last.X - o.X, 0, last.Z - o.Z)
        if hd.Magnitude < 0.1 then hd = v3(dir.X, 0, dir.Z) end
        if hd.Magnitude < 0.01 then hd = v3(0, 0, -1) end
        hd = hd.Unit
        local function along(p) return (p.X - o.X) * hd.X + (p.Z - o.Z) * hd.Z end
        -- (groundY is a far-away placeholder when the map is the ground: don't scale to it)
        local realGround = groundY > -1e5 and groundY or nil
        local arc2, minY, maxY = {}, math.huge, -math.huge
        for i, p in ipairs(pts) do
            arc2[i] = { along(p), p.Y }
            if p.Y < minY then minY = p.Y end
            if p.Y > maxY then maxY = p.Y end
        end
        if restPos and restPos.Y < minY then minY = restPos.Y end
        if realGround and realGround < minY and realGround > minY - 50 then minY = realGround end
        local shownGround = realGround or (landPos and landPos.Y) or minY
        local maxD = arc2[#arc2][1]
        if restPos then maxD = math.max(maxD, along(restPos)) end
        maxD = math.max(maxD + 10, 20)
        local cols = {}
        if map.ready or map.n > 0 then
            local N = 80
            for k = 1, N do
                local d = maxD * k / N
                local x, z = o.X + hd.X * d, o.Z + hd.Z * d
                local spans = columnSpans(x, z, maxY + 40, minY - 10, maxD / N * 0.55)
                for _, sp in ipairs(spans) do
                    if sp[2] > maxY then maxY = math.min(sp[2], maxY + 40) end
                end
                cols[#cols + 1] = { d, spans }
            end
        end
        arcProfile = { arc = arc2, cols = cols, maxD = maxD, minY = minY - 3, maxY = maxY + 5, groundY = shownGround,
                       land = landPos and { along(landPos), landPos.Y }, rest = restPos and { along(restPos), restPos.Y },
                       air = airburst and { along(airburst), airburst.Y } }
    end
end

local function drawPanel(camera)
    if not panel.bg or not arcProfile then return end
    local okV, vp = pcall(function() return camera.ViewportSize end)
    local W, H = 1920, 1080
    if okV and vp then W, H = vp.X, vp.Y end
    local size, margin = CONFIG.PanelSize, CONFIG.PanelMargin
    local x0, y0 = W - margin.X - size.X, H - margin.Y - size.Y
    local P = arcProfile
    local sx = size.X / P.maxD
    -- keep proportions close to real: height is stretched at most 3x relative to distance
    local sy = math.min(size.Y / math.max(P.maxY - P.minY, 1), sx * 3)
    local function pt(d, y)
        y = clamp(y, P.minY, P.maxY)
        return Vector2.new(x0 + d * sx, y0 + size.Y - (y - P.minY) * sy)
    end
    panel.bg.Position, panel.bg.Size, panel.bg.Visible = Vector2.new(x0 - 6, y0 - 20), Vector2.new(size.X + 12, size.Y + 26), true
    panel.title.Position = Vector2.new(x0, y0 - 18)
    panel.title.Text = string.format("side view  (%d studs)%s", math.floor(P.maxD),
        map.ready and "" or (map.building and "  - reading map..." or "  - no map data"))
    panel.title.Visible = true
    panel.ground.From, panel.ground.To, panel.ground.Visible = pt(0, P.groundY), pt(P.maxD, P.groundY), true

    local ci = 0
    for _, col in ipairs(P.cols) do
        for _, sp in ipairs(col[2]) do
            if ci < #panel.cols then
                ci = ci + 1
                local l = panel.cols[ci]
                l.From, l.To = pt(col[1], sp[1]), pt(col[1], sp[2])
                l.Thickness = math.max(2, size.X / 80)
                l.Visible = true
            end
        end
    end
    for i = ci + 1, #panel.cols do if panel.cols[i].Visible then panel.cols[i].Visible = false end end

    local li = 0
    for i = 1, #P.arc - 1 do
        if li < #panel.lines then
            li = li + 1
            local l = panel.lines[li]
            l.From, l.To, l.Color, l.Visible = pt(P.arc[i][1], P.arc[i][2]), pt(P.arc[i + 1][1], P.arc[i + 1][2]), CONFIG.Color, true
        end
    end
    if P.land and P.rest and li < #panel.lines then
        li = li + 1
        local l = panel.lines[li]
        l.From, l.To, l.Color, l.Visible = pt(P.land[1], P.land[2]), pt(P.rest[1], P.rest[2]), CONFIG.RollColor, true
    end
    for i = li + 1, #panel.lines do if panel.lines[i].Visible then panel.lines[i].Visible = false end end
    local fin = P.air or P.rest or P.land
    if fin then panel.land.Position, panel.land.Visible = pt(fin[1], fin[2]), true else panel.land.Visible = false end
    if fin and CONFIG.ShowBlastRadius then
        local R = CONFIG.BlastRadius
        panel.blast.From, panel.blast.To = pt(math.max(fin[1] - R, 0), fin[2]), pt(math.min(fin[1] + R, P.maxD), fin[2])
        panel.blast.Color, panel.blast.Visible = panel.color or CONFIG.ColorClear, true
    else
        panel.blast.Visible = false
    end
end

-- ---------- humanoids in the blast ----------
local humanoids, humanoidsT = {}, -1
local function refreshHumanoids()
    local list, seen = {}, {}
    local myChar = LocalPlayer.Character
    local myName = myChar and myChar.Name
    local function add(model, name)
        if not model or seen[name] or name == myName then return end
        local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model:FindFirstChild("Head")
        local hum = model:FindFirstChild("Humanoid")
        if root and hum then
            seen[name] = true
            list[#list + 1] = { name = name, root = root, hum = hum }
        end
    end
    -- players
    pcall(function()
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Name ~= LocalPlayer.Name then
                local c = p.Character
                if c then add(c, p.Name) end
            end
        end
    end)
    -- NPCs and characters kept in folders
    pcall(function()
        local spots = { Workspace }
        local cf = Workspace:FindFirstChild("Characters")
        if cf then spots[#spots + 1] = cf end
        for _, f in ipairs(spots) do
            for _, m in ipairs(f:GetChildren()) do
                if m.ClassName == "Model" and m:FindFirstChild("Humanoid") then add(m, m.Name) end
            end
        end
    end)
    humanoids = list
end

local lastInside = {}
local function drawInBlast(landPos)
    local shown = 0
    local names = {}
    if landPos and CONFIG.ShowInBlast then
        if now() - humanoidsT > 1 / CONFIG.InBlastScanHz then
            humanoidsT = now()
            pcall(refreshHumanoids)
        end
        local R = CONFIG.BlastRadius
        local inside = {}
        -- blast center sits a little above the spot so the floor/roof it rests on doesn't count as cover
        local center = landPos + v3(0, 1, 0)
        for _, h in ipairs(humanoids) do
            local ok, pos = pcall(function() return h.root.Position end)
            local okH, hp = pcall(function() return h.hum.Health end)
            local alive = not okH or hp == nil or hp > 0
            if ok and pos and alive then
                local d = (pos - landPos).Magnitude
                if d <= R + 1.5 then -- +1.5: half a body width, they're hit if any part is in
                    local covered = false
                    if CONFIG.BlastNeedsLineOfSight and map.ready then
                        -- check the torso and the head: covered only if both are blocked
                        local toBody = mapHit(center, pos)
                        local toHead = mapHit(center, pos + v3(0, 1.5, 0))
                        covered = (toBody ~= nil) and (toHead ~= nil)
                    end
                    inside[#inside + 1] = { name = h.name, d = d, pos = pos, covered = covered }
                end
            end
        end
        lastInside = inside
        table.sort(inside, function(a, b)
            if a.covered ~= b.covered then return not a.covered end
            return a.d < b.d
        end)
        local hit, cover = {}, {}
        for _, e in ipairs(inside) do
            if shown < #inBlastMarks then
                shown = shown + 1
                local s, on = WorldToScreen(e.pos)
                local c = inBlastMarks[shown]
                if on then
                    c.Position, c.Radius, c.Visible = s, 14, true
                    c.Color = e.covered and CONFIG.CoverColor or CONFIG.InBlastColor
                else
                    c.Visible = false
                end
            end
            local line = string.format("%s (%d)", e.name, math.floor(e.d))
            if e.covered then cover[#cover + 1] = line else hit[#hit + 1] = line end
        end
        for i = 1, math.min(#hit, CONFIG.InBlastMax) do names[#names + 1] = hit[i] end
        names.cover = cover
    end
    for i = shown + 1, #inBlastMarks do inBlastMarks[i].Visible = false end
    names.cover = names.cover or {}
    return names
end

-- map parts around the landing spot, as top-down outlines (refreshed with the arc)
local topBoxes, topCenter = {}, nil
local topErrT = nil
local function collectTopBoxes(center)
    topCenter = center
    local R = CONFIG.TopViewRange
    local list = {}
    if map.ready or map.n > 0 then
        for _, b in ipairs(boxesNear(center.X - R, center.Z - R, center.X + R, center.Z + R)) do
            -- skip the ground / huge flat slabs under the landing spot
            local r, l = b[4], b[6]
            local hx, hz = b[7], b[9]
            local big = hx > R * 2 and hz > R * 2
            if b.top > center.Y - 2 and not big then
                local dx, dz = b[1] - center.X, b[3] - center.Z
                list[#list + 1] = { b = b, d = dx * dx + dz * dz }
            end
        end
        table.sort(list, function(a, c) return a.d < c.d end)
    end
    local out = {}
    for i = 1, math.min(#list, CONFIG.TopMaxBoxes) do
        local b = list[i].b
        local r, l = b[4], b[6]
        local hx, hz = b[7], b[9]
        local corners = {}
        for k, s in ipairs({ { 1, 1 }, { 1, -1 }, { -1, -1 }, { -1, 1 } }) do
            corners[k] = { b[1] + r[1] * hx * s[1] + l[1] * hz * s[2], b[3] + r[3] * hx * s[1] + l[3] * hz * s[2] }
        end
        out[#out + 1] = { corners = corners, top = b.top }
    end
    topBoxes = out
end

-- clip a 2D segment to a square (Liang-Barsky); returns nil if fully outside
local function clipSeg(x0, y0, x1, y1, minX, minY, maxX, maxY)
    local dx, dy = x1 - x0, y1 - y0
    local t0, t1 = 0, 1
    local p = { -dx, dx, -dy, dy }
    local q = { x0 - minX, maxX - x0, y0 - minY, maxY - y0 }
    for i = 1, 4 do
        if p[i] == 0 then
            if q[i] < 0 then return nil end
        else
            local t = q[i] / p[i]
            if p[i] < 0 then if t > t1 then return nil elseif t > t0 then t0 = t end
            else if t < t0 then return nil elseif t < t1 then t1 = t end end
        end
    end
    return x0 + dx * t0, y0 + dy * t0, x0 + dx * t1, y0 + dy * t1
end

local function lerpColor(a, b, t)
    t = clamp(t, 0, 1)
    local ok, c = pcall(function()
        return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
    end)
    if ok and c then return c end
    return t > 0.5 and b or a -- executor without Color3 channels: just two shades
end

local function drawTop(camera, fin, color)
    if not top.bg then return end
    if not fin then hideTop() return end
    local okV, vp = pcall(function() return camera.ViewportSize end)
    local W, H = 1920, 1080
    if okV and vp then W, H = vp.X, vp.Y end
    local S = CONFIG.TopPanelSize
    local x0, y0 = W - CONFIG.TopPanelMargin.X - S, H - CONFIG.TopPanelMargin.Y - S
    local minX, minY, maxX, maxY = x0, y0, x0 + S, y0 + S
    local cx, cy = x0 + S / 2, y0 + S / 2
    local scale = (S / 2) / CONFIG.TopViewRange

    -- heading-up: the throw direction points to the top of the panel
    local o, last = arcPts[1], arcPts[#arcPts]
    local hd = (o and last) and v3(last.X - o.X, 0, last.Z - o.Z) or v3(0, 0, -1)
    if hd.Magnitude < 0.01 then
        local lk = camera.CFrame.LookVector
        hd = v3(lk.X, 0, lk.Z)
    end
    if hd.Magnitude < 0.01 then hd = v3(0, 0, -1) end
    hd = hd.Unit
    local rt = v3(-hd.Z, 0, hd.X)
    local function P(x, z)
        local dx, dz = x - fin.X, z - fin.Z
        local f = dx * hd.X + dz * hd.Z
        local r = dx * rt.X + dz * rt.Z
        return cx + r * scale, cy - f * scale
    end
    local function inside(px, py) return px >= minX and px <= maxX and py >= minY and py <= maxY end
    local function seg(l, ax, az, bx, bz)
        local a1, a2 = P(ax, az)
        local b1, b2 = P(bx, bz)
        local c1, c2, c3, c4 = clipSeg(a1, a2, b1, b2, minX, minY, maxX, maxY)
        if c1 then
            l.From, l.To, l.Visible = Vector2.new(c1, c2), Vector2.new(c3, c4), true
        else
            l.Visible = false
        end
    end
    local function dotAt(c, x, z)
        local px, py = P(x, z)
        if inside(px, py) then c.Position, c.Visible = Vector2.new(px, py), true else c.Visible = false end
        return px, py
    end

    top.bg.Position, top.bg.Size, top.bg.Visible = Vector2.new(x0, y0), Vector2.new(S, S), true
    top.border.Position, top.border.Size, top.border.Visible = Vector2.new(x0, y0), Vector2.new(S, S), true
    top.title.Position = Vector2.new(x0, y0 - 16)
    top.title.Text = string.format("top view  (%d x %d studs, throw direction up)", CONFIG.TopViewRange * 2, CONFIG.TopViewRange * 2)
    top.title.Visible = true

    -- map parts: outlines, lighter = taller than the landing spot
    if not topCenter or (topCenter - fin).Magnitude > 2 then collectTopBoxes(fin) end
    local li = 0
    for _, bx in ipairs(topBoxes) do
        local col = lerpColor(CONFIG.TopColorLow, CONFIG.TopColorHigh, (bx.top - fin.Y) / 15)
        for k = 1, 4 do
            li = li + 1
            local l = top.boxLines[li]
            if not l then break end
            local a, b = bx.corners[k], bx.corners[k % 4 + 1]
            l.Color = col
            seg(l, a[1], a[2], b[1], b[2])
        end
    end
    for i = li + 1, #top.boxLines do top.boxLines[i].Visible = false end

    -- the grenade's path coming in
    local ai = 0
    for i = 1, #arcPts - 1 do
        if ai < #top.arc then
            local a, b = arcPts[i], arcPts[i + 1]
            ai = ai + 1
            seg(top.arc[ai], a.X, a.Z, b.X, b.Z)
        end
    end
    for i = ai + 1, #top.arc do top.arc[i].Visible = false end
    if arcLand and arcRest then seg(top.roll, arcLand.X, arcLand.Z, arcRest.X, arcRest.Z) else top.roll.Visible = false end
    for i, c in ipairs(top.bounces) do
        local p = arcBounces[i]
        if p then dotAt(c, p.X, p.Z) else c.Visible = false end
    end
    if arcLand and (arcRest or arcAir) then dotAt(top.impact, arcLand.X, arcLand.Z) else top.impact.Visible = false end

    -- blast ring + final spot
    top.ring.Position, top.ring.Radius, top.ring.Color = Vector2.new(cx, cy), CONFIG.BlastRadius * scale, color
    top.ring.Visible = CONFIG.ShowBlastRadius
    top.land.Position, top.land.Color, top.land.Visible = Vector2.new(cx, cy), color, true

    -- you
    if arcRoot then dotAt(top.me, arcRoot.X, arcRoot.Z) else top.me.Visible = false end

    -- people: pink = in the blast, grey = in range but behind cover, white = nearby
    local status = {}
    for _, e in ipairs(lastInside) do status[e.name] = e.covered and "cover" or "hit" end
    local pi = 0
    for _, h in ipairs(humanoids) do
        if pi >= #top.people then break end
        local ok, pos = pcall(function() return h.root.Position end)
        if ok and pos then
            local px, py = P(pos.X, pos.Z)
            if inside(px, py) then
                pi = pi + 1
                local st = status[h.name]
                local col = (st == "hit" and CONFIG.InBlastColor) or (st == "cover" and CONFIG.CoverColor)
                    or Color3.fromRGB(255, 255, 255)
                local c, t = top.people[pi], top.names[pi]
                c.Position, c.Color, c.Radius, c.Visible = Vector2.new(px, py), col, st == "hit" and 4 or 3, true
                if st then
                    t.Text, t.Color, t.Position, t.Visible = h.name, col, Vector2.new(px + 6, py - 7), true
                else
                    t.Visible = false
                end
            end
        end
    end
    for i = pi + 1, #top.people do top.people[i].Visible = false top.names[i].Visible = false end
end

local function draw(camera)
    pcall(drawPanel, camera)
    local cf = camera.CFrame
    local camPos, look = cf.Position, cf.LookVector
    local index = 0
    for i = 1, #arcPts - 1 do
        local sa, sb, depth = projectSegment(arcPts[i], arcPts[i + 1], camPos, look)
        if sa and index < MAX_LINES then
            index = index + 1
            local l = lines[index]
            l.From, l.To = sa, sb
            -- thicker up close, thinner far away, so it reads as a 3D arc instead of a flat line
            l.Thickness = clamp(CONFIG.Thickness * 25 / math.max(depth, 1), 1, CONFIG.Thickness * 3)
            l.Visible = true
        end
    end
    for i = index + 1, MAX_LINES do
        if lines[i].Visible then lines[i].Visible = false end
    end

    -- roll segment + small dot where it first hits
    rollLine.Visible, impactDot.Visible = false, false
    if arcLand and arcRest then
        local sa, sb = projectSegment(arcLand, arcRest, camPos, look)
        if sa then rollLine.From, rollLine.To, rollLine.Visible = sa, sb, true end
        if dot(arcLand - camPos, look) > NEAR then
            local s, on = WorldToScreen(arcLand)
            if on then impactDot.Position, impactDot.Visible = s, true end
        end
    end

    -- where it explodes: in the air (fuse ran out), mid-roll, or where it stops
    local landPos = arcAir or arcRest or arcLand

    -- crossbars along the arc for depth
    do
        local o, last = arcPts[1], arcPts[#arcPts]
        local hd = (o and last) and v3(last.X - o.X, 0, last.Z - o.Z) or v3(0, 0, -1)
        if hd.Magnitude < 0.01 then hd = v3(look.X, 0, look.Z) end
        if hd.Magnitude < 0.01 then hd = v3(0, 0, -1) end
        hd = hd.Unit
        local side = v3(-hd.Z, 0, hd.X) * CONFIG.TickWidth
        for i, l in ipairs(ticks) do
            local p = arcTickPts[i]
            local sa, sb, depth = nil, nil, nil
            if p then sa, sb, depth = projectSegment(p - side, p + side, camPos, look) end
            if sa then
                l.From, l.To, l.Visible = sa, sb, true
                l.Thickness = clamp(CONFIG.Thickness * 20 / math.max(depth, 1), 1, 4)
            else
                l.Visible = false
            end
        end
    end

    -- bounce points
    for i, c in ipairs(bounceDots) do
        local p = arcBounces[i]
        if p and dot(p - camPos, look) > NEAR then
            local s, on = WorldToScreen(p)
            if on then c.Position, c.Visible = s, true else c.Visible = false end
        else
            c.Visible = false
        end
    end

    -- outcome -> color
    local color, text
    local fromChar = (landPos and arcRoot) and v3(landPos.X - arcRoot.X, 0, landPos.Z - arcRoot.Z).Magnitude or nil
    local dist3 = (landPos and arcRoot) and (landPos - arcRoot).Magnitude or nil
    local timing = ""
    if arcTimes.land then
        timing = string.format("  |  lands %.1fs, fuse %.1fs", arcTimes.land, arcTimes.fuse or CONFIG.Fuse)
    elseif arcTimes.fuse then
        timing = string.format("  |  fuse %.1fs", arcTimes.fuse)
    end
    if not landPos then
        color, text = CONFIG.ColorNoLanding, "no landing found"
    elseif dist3 and dist3 <= CONFIG.BlastRadius then
        color, text = CONFIG.ColorDanger, string.format("DANGER - you're in the blast (%d studs)", math.floor(dist3))
    elseif arcAir then
        color, text = CONFIG.ColorAirburst, arcAirHeight
            and string.format("AIRBURST - explodes %d studs above the ground", math.floor(arcAirHeight))
            or "AIRBURST - explodes before landing"
    elseif arcRollBurst then
        color, text = CONFIG.ColorRolling, string.format("explodes while rolling - %d studs", math.floor(fromChar or 0))
    elseif not arcFloor then
        color, text = CONFIG.ColorWall, string.format("hits a wall - %d studs", math.floor(fromChar or 0))
    else
        color, text = CONFIG.ColorClear, string.format("%d studs", math.floor(fromChar or 0))
    end
    if #arcBounces > 0 then
        text = text .. (#arcBounces == 1 and "  |  bounces off a wall" or string.format("  |  bounces off %d walls", #arcBounces))
    end
    text = text .. timing
    if map.building then text = text .. string.format("  |  loading map: %d parts", map.n) end

    panel.color = color
    marker.Color = color

    -- blast radius ring, lying flat on the ground around the final spot
    local ringShown = false
    if landPos and CONFIG.ShowBlastRadius then
        local n, R = #blastRing, CONFIG.BlastRadius
        local y = landPos.Y + 0.2
        local prev = v3(landPos.X + R, y, landPos.Z)
        for i = 1, n do
            local a = (i / n) * math.pi * 2
            local cur = v3(landPos.X + math.cos(a) * R, y, landPos.Z + math.sin(a) * R)
            local l = blastRing[i]
            local sa, sb = projectSegment(prev, cur, camPos, look)
            if sa then
                l.From, l.To, l.Color, l.Visible = sa, sb, color, true
                ringShown = true
            else
                l.Visible = false
            end
            prev = cur
        end
    else
        for _, l in ipairs(blastRing) do l.Visible = false end
    end

    -- humanoids inside the ring
    local names = drawInBlast(landPos)
    if CONFIG.TopPanel then
        local okT, errT = pcall(drawTop, camera, landPos, color)
        if not okT and CONFIG.Debug and now() - (topErrT or 0) > 5 then
            topErrT = now()
            print("[Trajectory] top view error: " .. tostring(errT))
        end
    end
    local cover = names.cover
    local hasAny = #names > 0 or #cover > 0
    if hasAny then
        local parts = {}
        if #names > 0 then
            parts[#parts + 1] = "IN BLAST (" .. #names .. ")\n" .. table.concat(names, "\n")
        else
            parts[#parts + 1] = "IN BLAST: nobody exposed"
        end
        if #cover > 0 then
            parts[#parts + 1] = "behind cover: " .. table.concat(cover, ", ")
        end
        inBlastText.Text = table.concat(parts, "\n")
        inBlastText.Color = (#names > 0) and CONFIG.InBlastColor or CONFIG.CoverColor
    end
    local hudDone = false
    if CONFIG.InBlastHud then
        hudDone = true
        if hasAny then
            local okV, vp = pcall(function() return camera.ViewportSize end)
            local W, H = 1920, 1080
            if okV and vp then W, H = vp.X, vp.Y end
            inBlastText.Position = Vector2.new(W * CONFIG.InBlastHudPos.X, H * CONFIG.InBlastHudPos.Y)
            inBlastText.Visible = true
        else
            inBlastText.Visible = false
        end
    end

    -- small center marker + text
    if landPos and dot(landPos - camPos, look) > NEAR then
        local screen, onScreen = WorldToScreen(landPos)
        if onScreen then
            marker.Radius, marker.Position, marker.Color, marker.Visible = 5, screen, color, true
            label.Text, label.Color = text, color
            label.Position, label.Visible = Vector2.new(screen.X, screen.Y - 26), true
            status.Visible = false
            if not hudDone then
                if hasAny then
                    inBlastText.Position, inBlastText.Visible = Vector2.new(screen.X, screen.Y + 14), true
                else
                    inBlastText.Visible = false
                end
            end
            return
        end
    end
    marker.Visible, label.Visible = false, false
    -- landing spot off screen: say so at the top of the screen
    status.Text, status.Color = text .. (landPos and "  (off screen)" or ""), color
    local okV, vp = pcall(function() return camera.ViewportSize end)
    status.Position = Vector2.new(okV and vp and vp.X / 2 or 960, 60)
    status.Visible = true
    if not hudDone then
        if hasAny then
            inBlastText.Position, inBlastText.Visible = Vector2.new(okV and vp and vp.X / 2 or 960, 80), true
        else
            inBlastText.Visible = false
        end
    end
end

-- rate limiter: returns true at most hz times per second (hz <= 0 means always)
local lastTick = {}
local function due(key, hz)
    if not hz or hz <= 0 then return true end
    local t = now()
    if not lastTick[key] or t - lastTick[key] >= 1 / hz then
        lastTick[key] = t
        return true
    end
    return false
end

local function update(camera, char, fresh)
    if fresh or due("physics", CONFIG.PhysicsHz) then simulate(camera, char) end
    if fresh or due("draw", CONFIG.DrawHz) then draw(camera) end
end

-- ---------- flight logger ----------
local flightLog = nil -- { part, t0, until, n, last }
local function fmtV(v) return string.format("%.2f,%.2f,%.2f", v.X, v.Y, v.Z) end

local function startFlightLog(part, launchT, launch)
    flightLog = { part = part, t0 = launchT, untilT = now() + CONFIG.LogSeconds, n = 0, last = nil, buf = {} }
    print("[TrajLog] BEGIN part=" .. part.Name .. " parent=" .. (part.Parent and part.Parent.Name or "nil"))
    if launch then
        print("[TrajLog] launch hand=" .. fmtV(launch.origin) .. " aimDir=" .. fmtV(launch.dir)
            .. " cam=" .. fmtV(launch.cam) .. " look=" .. fmtV(launch.look)
            .. (launch.root and (" root=" .. fmtV(launch.root)) or ""))
    end
    print(string.format("[TrajLog] config ThrowSpeed=%.2f Gravity=%.2f UpBias=%.4f OriginShift=%s",
        CONFIG.ThrowSpeed, CONFIG.Gravity, CONFIG.UpBias, fmtV(CONFIG.OriginShift)))
    pcall(function()
        print("[TrajLog] part size=" .. fmtV(part.Size) .. " anchored=" .. tostring(part.Anchored))
    end)
end

local function stepFlightLog()
    if not flightLog then return end
    local t = now()
    local ok, pos = pcall(function() return flightLog.part.Position end)
    local gone = not ok or not inWorkspace(flightLog.part)
    if gone or t > flightLog.untilT then
        if #flightLog.buf > 0 then print(table.concat(flightLog.buf, "\n")) end
        print("[TrajLog] END samples=" .. flightLog.n .. (gone and " (part removed)" or " (time limit)"))
        flightLog = nil
        return
    end
    if not due("log", CONFIG.LogHz) then return end
    if flightLog.last and (pos - flightLog.last).Magnitude < 0.01 then return end
    flightLog.n = flightLog.n + 1
    flightLog.last = pos
    -- buffered: printing every frame is what lags the console, so flush in chunks
    local buf = flightLog.buf
    buf[#buf + 1] = string.format("[TrajLog] %.3f %s", t - flightLog.t0, fmtV(pos))
    if #buf >= 20 then print(table.concat(buf, "\n")) flightLog.buf = {} end
end

-- ---------- calibration ----------
-- When the grenade leaves your hand, find the flying grenade part, sample its path,
-- and fit speed / gravity / up-bias / start offset from the real flight.
local calibResults = {}   -- every accepted throw
local calib = nil          -- { t0, origin, dir, part, samples, deadline, known }
local lastLaunch = nil     -- origin/dir from the last frame the grenade was in hand


local PART_CLASSES = { Part = true, MeshPart = true, UnionOperation = true, WedgePart = true,
                       CornerWedgePart = true, TrussPart = true }
local function isPart(x)
    local ok, r = pcall(function() return x:IsA("BasePart") end)
    if ok and r then return true end
    return PART_CLASSES[x.ClassName] == true
end

-- depth-first search for the part that carries the grenade (Handle first, then any part)
local function resolvePart(c, depth)
    depth = depth or 0
    if isPart(c) then return c end
    if depth > 4 then return nil end
    local ok, pp = pcall(function() return c.PrimaryPart end)
    if ok and pp then return pp end
    local kids = c:GetChildren()
    for _, k in ipairs(kids) do
        if k.Name == "Handle" and isPart(k) then return k end
    end
    for _, k in ipairs(kids) do
        local p = resolvePart(k, depth + 1)
        if p then return p end
    end
    return nil
end

local function dumpTree(inst, depth, out, prefix)
    depth, out, prefix = depth or 0, out or {}, prefix or "  "
    if #out >= 30 or depth > 3 then return out end
    local pos = ""
    if isPart(inst) then
        local ok, p = pcall(function() return inst.Position end)
        if ok and p then pos = string.format(" @ %.1f,%.1f,%.1f", p.X, p.Y, p.Z) end
    end
    out[#out + 1] = "[Trajectory] " .. prefix .. inst.Name .. " (" .. inst.ClassName .. ")" .. pos
    for _, k in ipairs(inst:GetChildren()) do dumpTree(k, depth + 1, out, prefix .. "  ") end
    return out
end

local function startCalibrationWith(part)
    local launch = lastLaunch
    if not launch then return end
    local t0 = now()
    calib = { t0 = t0, origin = launch.origin, dir = launch.dir, launch = launch,
              part = part, samples = {}, deadline = now() + CONFIG.CalibrateSeconds }
    calib.samples.launchT, calib.samples.origin, calib.samples.dir = t0, launch.origin, launch.dir
    calib.samples.launch = launch
    calib.samples.predLand, calib.samples.predRest, calib.samples.predRoot = arcLand, arcRest, arcRoot
    calib.samples.holdSecs = hold.lastHold or (hold.pressT and (now() - hold.pressT))
    calib.samples.pinSecs = hold.pinT and (now() - hold.pinT)
    calib.samples.timerVal = hold.timer
    if CONFIG.Debug then print("[Trajectory] throw detected: " .. part.Name) end
    if CONFIG.LogThrows then startFlightLog(part, t0, launch) end
end

local function fullName(inst)
    local ok, n = pcall(function() return inst:GetFullName() end)
    if ok then return n end
    local parts, p = {}, inst
    while p and p ~= game do table.insert(parts, 1, p.Name) p = p.Parent end
    return table.concat(parts, ".")
end

local function deepScan()
    print("[Trajectory] deep scan...")
    local count = 0
    for _, d in ipairs(Workspace:GetDescendants()) do
        if isGrenadeName(d.Name) then
            count = count + 1
            print("[Trajectory]   " .. fullName(d) .. " (" .. d.ClassName .. ")")
            if count >= 30 then print("[Trajectory]   ...stopped at 30") break end
        end
    end
    if count == 0 then print("[Trajectory]   nothing named like '" .. CONFIG.GrenadeNameMatch .. "' in Workspace") end
end

-- least squares fit of y = a + b t + c t^2 (c may be 0 for linear axes)
local function fit(ts, ys, quadratic)
    local n = #ts
    if quadratic then
        local s0, s1, s2, s3, s4, y0, y1, y2 = n, 0, 0, 0, 0, 0, 0, 0
        for i = 1, n do
            local t, y = ts[i], ys[i]
            s1, s2, s3, s4 = s1 + t, s2 + t*t, s3 + t^3, s4 + t^4
            y0, y1, y2 = y0 + y, y1 + y*t, y2 + y*t*t
        end
        -- solve 3x3 via Cramer
        local function det(a,b,c,d,e,f,g,h,i) return a*(e*i-f*h) - b*(d*i-f*g) + c*(d*h-e*g) end
        local D = det(s0,s1,s2, s1,s2,s3, s2,s3,s4)
        if math.abs(D) < 1e-9 then return nil end
        local a = det(y0,s1,s2, y1,s2,s3, y2,s3,s4) / D
        local b = det(s0,y0,s2, s1,y1,s3, s2,y2,s4) / D
        local c = det(s0,s1,y0, s1,s2,y1, s2,s3,y2) / D
        return a, b, c
    else
        local st, sy, stt, sty = 0, 0, 0, 0
        for i = 1, n do st, sy, stt, sty = st + ts[i], sy + ys[i], stt + ts[i]^2, sty + ts[i]*ys[i] end
        local D = n * stt - st * st
        if math.abs(D) < 1e-9 then return nil end
        local b = (n * sty - st * sy) / D
        return (sy - b * st) / n, b, 0
    end
end

local function finishCalibration()
    local s = calib.samples
    calib = nil
    local full = {}
    for i, p in ipairs(s) do full[i] = p end
    if #full > 3 and CONFIG.GroundMode == "Learned" then
        local restY = full[#full].pos.Y
        learnedGround[#learnedGround + 1] = restY
        if #learnedGround > 9 then table.remove(learnedGround, 1) end
        print(string.format("[Trajectory] grenade came to rest at height %.1f (ground height for the arc)", restY))
    end
    -- measure wall hits: a sudden change in horizontal motion while still in the air
    -- (reported only - nothing is changed automatically)
    pcall(function()
        local thin = { full[1] }
        for i = 2, #full do
            if full[i].t - thin[#thin].t >= 0.045 then thin[#thin + 1] = full[i] end
        end
        local function hv(a, b)
            local d = b.pos - a.pos
            local dtt = math.max(b.t - a.t, 1e-3)
            return v3(d.X / dtt, 0, d.Z / dtt), d.Y / dtt
        end
        for i = 3, #thin - 1 do
            local vin, vyIn = hv(thin[i - 2], thin[i - 1])
            local vout, vyOut = hv(thin[i], thin[i + 1])
            local sIn = vin.Magnitude
            if sIn > 25 then
                local u = vin * (1 / sIn)
                local along = dot(vout, u)          -- speed still going the same way
                local side = (vout - u * along).Magnitude
                local changed = along < sIn * 0.6
                -- a floor landing flips the vertical speed; a wall hit doesn't stop it falling
                local floorLike = vyIn < -5 and vyOut > vyIn * 0.3 and math.abs(thin[i].pos.Y - thin[i - 1].pos.Y) < 0.5
                if changed and not floorLike then
                    local back = math.max(-along, 0) / sIn
                    print(string.format("[Trajectory] wall hit measured: came in at %.0f studs/s, after: %.0f%% bounced back, %.0f%% kept going forward, %.0f studs/s sideways",
                        sIn, 100 * back, 100 * math.max(along, 0) / sIn, side))
                    print(string.format("[Trajectory]   (current settings: WallRestitution=%.2f WallSlideKeep=%.2f)",
                        CONFIG.WallRestitution, CONFIG.WallSlideKeep))
                    break
                end
            end
        end
    end)

    if not CONFIG.AutoCalibrate then
        -- fixed model: only report how close the prediction was
        if CONFIG.ReportAccuracy and #full > 3 and s.predLand then
            local rest = full[#full].pos
            -- first impact: the first time its horizontal speed drops below 75% of its flight speed
            -- (measured over >= 0.045s steps; the hover before launch is skipped)
            local impact = rest
            local thin = { full[1] }
            for i = 2, #full do
                if full[i].t - thin[#thin].t >= 0.045 then thin[#thin + 1] = full[i] end
            end
            local flightSpeed = nil
            for i = 2, #thin do
                local d = thin[i].pos - thin[i - 1].pos
                local h = v3(d.X, 0, d.Z).Magnitude / math.max(thin[i].t - thin[i - 1].t, 1e-3)
                if not flightSpeed then
                    if h > 30 then flightSpeed = h end
                elseif h < flightSpeed * 0.75 then
                    impact = thin[i - 1].pos
                    break
                else
                    flightSpeed = math.max(flightSpeed, h)
                end
            end
            local function hd(a, b) return v3(a.X - b.X, 0, a.Z - b.Z).Magnitude end
            local rootP = s.predRoot or (s.launch and s.launch.root) or impact
            local msg = string.format("[Trajectory] accuracy: impact off %.1f studs (%.0f%% of %.0f)",
                (s.predLand - impact).Magnitude, 100 * (s.predLand - impact).Magnitude / math.max(hd(impact, rootP), 1), hd(impact, rootP))
            if s.predRest then
                msg = msg .. string.format(", final spot off %.1f studs", (s.predRest - rest).Magnitude)
            end
            print(msg)
        end
        return
    end
    -- only fit the free flight: cut at the first bounce (vertical speed jumps up, or it stops dead)
    do
        -- thin to >= 0.05s spacing first: replication updates arrive in steps, so frame-to-frame
        -- velocities are noise
        local thin = { s[1] }
        for i = 2, #s do
            if s[i].t - thin[#thin].t >= 0.05 then thin[#thin + 1] = s[i] end
        end
        local cutT = math.huge
        local prevVy = nil
        for i = 2, #thin do
            local dt = thin[i].t - thin[i - 1].t
            local vy = (thin[i].pos.Y - thin[i - 1].pos.Y) / dt
            if prevVy and vy > prevVy + 15 then cutT = thin[i - 1].t break end
            prevVy = vy
        end
        for i = #s, 1, -1 do if s[i].t > cutT then s[i] = nil end end
        s.cutT = cutT
    end
    if #s < 4 then print("[Trajectory] calibration: not enough samples (" .. #s .. ")") return end

    local ts, xs, ys, zs = {}, {}, {}, {}
    local t0 = s[1].t
    for i, p in ipairs(s) do ts[i], xs[i], ys[i], zs[i] = p.t - t0, p.pos.X, p.pos.Y, p.pos.Z end
    local ax, bx = fit(ts, xs, false)
    local az, bz = fit(ts, zs, false)
    local ay, by, cy = fit(ts, ys, true)
    if not (ax and az and ay) then print("[Trajectory] calibration: fit failed") return end

    local g = -2 * cy
    if g < 1 then print("[Trajectory] calibration: grenade isn't falling normally, skipped") return end

    -- rewind the fitted path to the moment it passed closest to the hand: that's the launch
    local function posAt(t) return v3(ax + bx * t, ay + by * t + cy * t * t, az + bz * t) end
    -- which body point does the flight path actually pass through? (that's where the game spawns it)
    do
        local L = s.launch
        local pts = { Hand = L and L.hand, Head = L and L.head, Camera = L and L.cam, Root = L and L.root }
        local results, bestName, bestDist = {}, nil, math.huge
        -- camera-space axes (flattened forward) so offsets read as right / up / forward
        local fwd = L and v3(L.look.X, 0, L.look.Z)
        fwd = (fwd and fwd.Magnitude > 0.01) and fwd.Unit or v3(0, 0, -1)
        local right = v3(-fwd.Z, 0, fwd.X)
        local function camSpace(d) return string.format("right %.1f, up %.1f, fwd %.1f", dot(d, right), d.Y, dot(d, fwd)) end
        for name, p in pairs(pts) do
            if p then
                local md, mt = math.huge, 0
                for i = 0, 250 do
                    local t = -i * 0.004
                    local dd = (posAt(t) - p).Magnitude
                    if dd < md then md, mt = dd, t end
                end
                results[#results + 1] = string.format("%s %.1f (%s)", name, md, camSpace(posAt(mt) - p))
                if md < bestDist then bestName, bestDist = name, md end
            end
        end
        print("[Trajectory] path distance from: " .. table.concat(results, " | "))
        if L and L.hand then
            print("[Trajectory] first seen at: " .. camSpace(s[1].pos - L.hand) .. " from hand")
        end
        if s.hover and L then
            print(string.format("[Trajectory] hovered %.2fs before launching, at: %s from %s",
                s.hover.secs, camSpace(s.hover.pos - (L.anchor or L.cam)), CONFIG.LaunchFrom))
        end
        if s.hover and L and (L.anchor or L.hand) then
            -- we saw exactly where it spawned (it hovers before launching): use that point
            local d = s.hover.pos - (L.anchor or L.hand)
            local off = v3(dot(d, right), d.Y, dot(d, fwd))
            if off.Magnitude <= 6 then
                s.spawnOff = off
            else
                print(string.format("[Trajectory] spawn point %.1f studs from hand - too far, ignored", off.Magnitude))
            end
            s.origin = s.hover.pos
            local aimPoint = L.cam + L.look * CONFIG.AimDistance
            local dd = aimPoint - s.origin
            s.dir = (dd.Magnitude < 1) and L.look or dd.Unit
        elseif false then -- (auto-switching the launch point is disabled: it picked the camera from bad readings)
            CONFIG.LaunchFrom = bestName
            CONFIG.OriginShift = v3(0, 0, 0)
            print("[Trajectory] grenade launches from your " .. bestName .. " - switched LaunchFrom to \"" .. bestName .. "\"")
            -- refit this throw from the new launch point
            local o = pts[bestName]
            local aimPoint = L.cam + L.look * CONFIG.AimDistance
            local dd = aimPoint - o
            s.origin = o
            s.dir = (dd.Magnitude < 1) and L.look or dd.Unit
        end
    end
    local lag, best = 0, math.huge
    for i = 0, 250 do
        local t = -i * 0.004                                     -- search back up to 1s (replication lag)
        local dist = (posAt(t) - ((s.hover and s.hover.pos) or s.origin)).Magnitude
        if dist < best then best, lag = dist, -t end
    end
    local v = v3(bx, by + g * lag, bz)                         -- vy at t = -lag
    local start = posAt(-lag)

    local speedH = v3(v.X, 0, v.Z).Magnitude
    local d = s.dir
    local dH = v3(d.X, 0, d.Z).Magnitude
    local speed = (dH > 0.05) and (speedH / dH) or v.Magnitude
    local upBias = (v.Y - d.Y * speed) / speed

    local shift = start - s.origin
    if speed < 20 or speed > 250 or g < 30 or g > 400 or math.abs(upBias) > 0.6 then
        print(string.format("[Trajectory] throw ignored (speed=%.1f g=%.1f up=%.2f outside sane limits, held %s) - probably hit something early or tracked the wrong part",
            speed, g, upBias, s.holdSecs and string.format("%.2fs", s.holdSecs) or "?"))
        return
    end
    -- the start point is only trusted when the path actually passes near the hand
    local shiftNote = string.format(" start=%.1f studs from launch point (lag %.2fs)", shift.Magnitude, lag)
    if shift.Magnitude > 3 then shiftNote = shiftNote .. " - start not applied" end

    -- bounce + roll from the samples after the first impact
    local bounceKeep, rollFric = nil, nil
    local impact = s[#s].pos
    local rest = full[#full].pos
    if s.cutT and s.cutT < math.huge then
        local vhBefore = v3(bx, 0, bz).Magnitude
        -- horizontal speed over the first ~0.15s after impact
        local i0 = #s
        local j = i0
        while full[j + 1] and full[j + 1].t - full[i0].t < 0.15 do j = j + 1 end
        if j > i0 and full[j].t > full[i0].t then
            local d = full[j].pos - full[i0].pos
            local vhAfter = v3(d.X, 0, d.Z).Magnitude / (full[j].t - full[i0].t)
            bounceKeep = vhAfter / math.max(vhBefore, 1)
            local rollDist = v3(rest.X - impact.X, 0, rest.Z - impact.Z).Magnitude
            if rollDist > 0.5 then rollFric = vhAfter * vhAfter / (2 * rollDist) end
        end
    end

    -- how far off was the prediction shown at the moment of the throw?
    local function hdist(a, b) return v3(a.X - b.X, 0, a.Z - b.Z).Magnitude end
    local acc = ""
    local rootP = s.predRoot or (s.launch and s.launch.root)
    if s.predLand and rootP then
        local throwDist = hdist(impact, rootP)
        acc = string.format("\n[Trajectory]   accuracy: impact off %.1f studs (%.0f%% of %.0f)",
            hdist(s.predLand, impact), 100 * hdist(s.predLand, impact) / math.max(throwDist, 1), throwDist)
        if s.predRest then
            local restDist = hdist(rest, rootP)
            acc = acc .. string.format(", final spot off %.1f studs (%.0f%% of %.0f)",
                hdist(s.predRest, rest), 100 * hdist(s.predRest, rest) / math.max(restDist, 1), restDist)
        end
    end

    -- keep every good throw and use the median, so one bad throw can't wreck the numbers
    calibResults[#calibResults + 1] = { speed = speed, g = g, up = upBias, shift = shift,
        keep = bounceKeep, fric = rollFric,
        sx = s.spawnOff and s.spawnOff.X, sy = s.spawnOff and s.spawnOff.Y, sz = s.spawnOff and s.spawnOff.Z }
    local function median(key)
        local arr = {}
        for _, r in ipairs(calibResults) do arr[#arr + 1] = r[key] end
        table.sort(arr)
        local n = #arr
        return (n % 2 == 1) and arr[(n + 1) / 2] or (arr[n / 2] + arr[n / 2 + 1]) / 2
    end
    CONFIG.Gravity, CONFIG.ThrowSpeed, CONFIG.UpBias = median("g"), median("speed"), median("up")
    local function medianOpt(key, cur)
        local arr = {}
        for _, r in ipairs(calibResults) do if r[key] then arr[#arr + 1] = r[key] end end
        if #arr == 0 then return cur end
        table.sort(arr)
        local n = #arr
        return (n % 2 == 1) and arr[(n + 1) / 2] or (arr[n / 2] + arr[n / 2 + 1]) / 2
    end
    if s.spawnOff then
        CONFIG.SpawnOffset = v3(medianOpt("sx", CONFIG.SpawnOffset.X), medianOpt("sy", CONFIG.SpawnOffset.Y),
            medianOpt("sz", CONFIG.SpawnOffset.Z))
    end
    CONFIG.BounceKeep   = clamp(medianOpt("keep", CONFIG.BounceKeep), 0.1, 1)
    CONFIG.RollFriction = clamp(medianOpt("fric", CONFIG.RollFriction), 5, 200)

    print(string.format("[Trajectory] throw %d: held mouse %s, pin pulled %s before throw, Timer=%s",
        #calibResults, s.holdSecs and string.format("%.2fs", s.holdSecs) or "?",
        s.pinSecs and string.format("%.2fs", s.pinSecs) or "?", tostring(s.timerVal)))
    print(string.format("[Trajectory] throw %d: speed=%.1f gravity=%.1f up=%.3f flight=%.2fs samples=%d%s | using median: ThrowSpeed=%.1f Gravity=%.1f UpBias=%.3f",
        #calibResults, speed, g, upBias, ts[#ts], #s, shiftNote, CONFIG.ThrowSpeed, CONFIG.Gravity, CONFIG.UpBias)
        .. string.format("\n[Trajectory]   spawn point: using SpawnOffset=(right %.2f, up %.2f, fwd %.2f) from " .. CONFIG.LaunchFrom,
            CONFIG.SpawnOffset.X, CONFIG.SpawnOffset.Y, CONFIG.SpawnOffset.Z)
        .. string.format("\n[Trajectory]   roll: keep=%s friction=%s | using BounceKeep=%.2f RollFriction=%.0f",
            bounceKeep and string.format("%.2f", bounceKeep) or "?", rollFric and string.format("%.0f", rollFric) or "?",
            CONFIG.BounceKeep, CONFIG.RollFriction)
        .. acc)
end

local companions = {} -- parts that appeared right with the grenade (Handle etc.)

local function reportCompanions()
    if #companions == 0 or not calib then companions = {} return end
    local okB, pb = pcall(function() return calib.part.Position end)
    for _, c in ipairs(companions) do
        local okA, pa = pcall(function() return c.part.Position end)
        if okA and okB and pa and pb then
            local nowOff = pa - pb
            print(string.format("[Trajectory] %s vs %s: %.1f studs apart at start, %.1f now (%s)",
                c.name, calib.part.Name, c.first.Magnitude, nowOff.Magnitude,
                (math.abs(nowOff.Magnitude - c.first.Magnitude) < 1.5) and "moves WITH the grenade" or "separate"))
        end
    end
    companions = {}
end

local function stepCalibration(char)
    if not calib then return end
    local t = now()
    if #companions > 0 and t - calib.t0 > 0.4 then pcall(reportCompanions) end
    local ok, pos = pcall(function() return calib.part.Position end)
    if not ok or not inWorkspace(calib.part) then finishCalibration() return end
    local s = calib.samples
    -- the grenade hangs still for ~0.2s before it launches: only start once it moves
    if not calib.startPos then calib.startPos, calib.startT = pos, t end
    if not calib.moving then
        if (pos - calib.startPos).Magnitude > 0.3 then
            calib.moving = true
            s.launchT = t
            s.hover = { pos = calib.startPos, secs = t - calib.startT }
            table.insert(s, { t = calib.startT + (t - calib.startT), pos = pos })
            calib.deadline = t + CONFIG.CalibrateSeconds
        end
        if t > calib.deadline then finishCalibration() end
        return
    end
    if #s == 0 or (pos - s[#s].pos).Magnitude > 0.01 then
        table.insert(s, { t = t, pos = pos })
    end
    if t > calib.deadline then finishCalibration() end
end

local function smallEnoughPart(inst)
    local ok, sz = pcall(function() return inst.Size end)
    if not ok or not sz then return true end
    return math.max(sz.X, sz.Y, sz.Z) <= CONFIG.ProjectileMaxSize
end

-- ---------- projectile watcher ----------
-- Cheap: only counts children of a few containers. When one gains items while you hold/throw a
-- grenade, the new items (end of the child list) become candidates; a candidate that moves away
-- from your hand fast is the grenade.
local function folderByName(name)
    if name == "" then return Workspace end
    if name == "Camera" then return Workspace.CurrentCamera end
    return Workspace:FindFirstChild(name)
end

local watcher = nil -- { containers = { {inst, path, count} }, untilT, candidates }
local explosions = {} -- explosion parts being measured (they may grow over a few frames)

local function stepExplosions()
    if #explosions == 0 then return end
    local t, keep = now(), {}
    for _, e in ipairs(explosions) do
        local ok, sz = pcall(function() return e.part.Size end)
        if ok and sz then e.maxR = math.max(e.maxR, math.max(sz.X, sz.Y, sz.Z) / 2) end
        if t < e.untilT and ok then
            keep[#keep + 1] = e
        elseif e.maxR > 0.5 then
            print(string.format("[Trajectory] game explosion measured: radius %.1f studs", e.maxR))
            if CONFIG.BlastRadiusFromGame then
                CONFIG.BlastRadius = e.maxR
                print("[Trajectory] blast ring now uses that radius")
            end
        end
    end
    explosions = keep
end

local function isContainer(x)
    local c = x.ClassName
    return c == "Folder" or c == "Model" or c == "Camera"
end

local function buildWatcher(char)
    local list, seenPath = {}, {}
    local function add(inst, path)
        if seenPath[path] then return end
        seenPath[path] = true
        local ok, kids = pcall(function() return inst:GetChildren() end)
        if ok then list[#list + 1] = { inst = inst, path = path, count = #kids } end
        return ok and kids or {}
    end
    for _, fname in ipairs(CONFIG.ProjectileFolders) do
        local f = folderByName(fname)
        if f then
            local path = (fname == "") and "Workspace" or fname
            local kids = add(f, path)
            -- one level of sub-folders (not under Workspace itself: those are the folders above / the map)
            if fname ~= "" then
                for _, k in ipairs(kids) do
                    if isContainer(k) and not CONFIG.ProjectileSkip[k.Name] and #list < 60 then
                        add(k, path .. "/" .. k.Name)
                    end
                end
            end
        end
    end
    -- the character itself (the grenade may be parented there for a moment)
    add(char, "Character")
    watcher = { containers = list, untilT = now() + 1e9, candidates = {} }
    if CONFIG.Debug then print("[Trajectory] watching " .. #list .. " folders for the thrown grenade") end
end

local function stepWatcher(holding)
    if not watcher then return end
    local t = now()
    if holding then watcher.untilT = t + 6 end -- long enough to also see the explosion
    if t > watcher.untilT then watcher = nil return end
    if not due("watch", CONFIG.WatchHz) then return end
    local hand = lastLaunch and lastLaunch.origin
    if not hand then return end

    -- 1) containers that gained children -> new items are candidates
    for _, c in ipairs(watcher.containers) do
        local ok, kids = pcall(function() return c.inst:GetChildren() end)
        if ok then
            local n = #kids
            if n > c.count then
                for i = c.count + 1, n do
                    local item = kids[i]
                    local okP, part = pcall(resolvePart, item)
                    if CONFIG.Debug then
                        print("[Trajectory] new in " .. c.path .. ": " .. item.Name .. " (" .. item.ClassName .. ")"
                            .. ((okP and part) and (" part=" .. part.Name) or " no part"))
                    end
                    if okP and part and calib and part.Name ~= calib.part.Name and t - calib.t0 < 0.5 then
                        local okA, pa = pcall(function() return part.Position end)
                        local okB, pb = pcall(function() return calib.part.Position end)
                        if okA and okB and pa and pb then
                            companions[#companions + 1] = { part = part, name = c.path .. "/" .. item.Name,
                                first = pa - pb, t = t }
                        end
                    end
                    if okP and part and item.Name == "GrenadeExplosion" and isPart(part) then
                        explosions[#explosions + 1] = { part = part, untilT = t + 1, maxR = 0 }
                    end
                    local knownByPath = CONFIG.ProjectilePaths[c.path] and part and CONFIG.ProjectilePaths[c.path] == part.Name
                    if okP and part and (knownByPath or CONFIG.ProjectileNames[part.Name]) and not calib then
                        if CONFIG.Debug then print("[Trajectory] projectile (known name): " .. c.path .. "/" .. item.Name) end
                        startCalibrationWith(part)
                    elseif okP and part and smallEnoughPart(part) then
                        local okPos, pos = pcall(function() return part.Position end)
                        if okPos and pos then
                            table.insert(watcher.candidates, { part = part, pos = pos, t = t, path = c.path .. "/" .. item.Name })
                        end
                    end
                end
            end
            c.count = n
        end
    end

    -- 2) candidates moving away from the hand fast
    local keep = {}
    for _, cand in ipairs(watcher.candidates) do
        local okPos, pos = pcall(function() return cand.part.Position end)
        if okPos and pos and not calib then
            local dt = t - cand.t
            if dt > 0 then
                -- horizontal speed, so a pin or casing dropping at your feet doesn't count
                local d = pos - cand.pos
                local speed = v3(d.X, 0, d.Z).Magnitude / dt
                local away = (pos - hand).Magnitude - (cand.pos - hand).Magnitude
                if speed >= CONFIG.ProjectileMinSpeed and speed <= CONFIG.ProjectileMaxSpeed and away > 0 then
                    if CONFIG.Debug then print(string.format("[Trajectory] projectile: %s (%.0f studs/s)", cand.path, speed)) end
                    startCalibrationWith(cand.part)
                elseif t - cand.t < 0.6 then
                    keep[#keep + 1] = cand
                end
            else
                keep[#keep + 1] = cand
            end
        end
    end
    watcher.candidates = keep
end

-- ---------- loop ----------
local running, visible, hadGrenade = true, false, false
local lastTool = nil
local charDumpedOnce = false
local STANDARD_CHAR = { Head = true, Torso = true, HumanoidRootPart = true, Humanoid = true,
    ["Left Arm"] = true, ["Right Arm"] = true, ["Left Leg"] = true, ["Right Leg"] = true,
    UpperTorso = true, LowerTorso = true, LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
    RightUpperArm = true, RightLowerArm = true, RightHand = true, LeftUpperLeg = true, LeftLowerLeg = true,
    LeftFoot = true, RightUpperLeg = true, RightLowerLeg = true, RightFoot = true, Animate = true,
    ["Body Colors"] = true, Shirt = true, Pants = true, ["Shirt Graphic"] = true, Health = true }
local stop -- defined at the bottom

local function step()
    if CONFIG.UnloadKey and has("iskeypressed") then
        local ok, down = pcall(iskeypressed, CONFIG.UnloadKey)
        if ok and down then
            stop()
            print("[Trajectory] unloaded (X)")
            return
        end
        if CONFIG.MapRefreshKey then
            local okM2, mk = pcall(iskeypressed, CONFIG.MapRefreshKey)
            if okM2 and mk and due("mapRefresh", 0.5) and not map.building then
                map.failed = false
                pcall(startMapBuild, true)
            end
        end
        if CONFIG.ResetKey then
            local okR, r = pcall(iskeypressed, CONFIG.ResetKey)
            if okR and r and due("reset", 1) then
                for k, v in pairs(DEFAULTS) do CONFIG[k] = v end
                calibResults = {}
                print("[Trajectory] calibration reset to defaults")
            end
        end
        if CONFIG.DeepScanKey then
            local okJ, j = pcall(iskeypressed, CONFIG.DeepScanKey)
            if okJ and j and due("deepscan", 1) then pcall(deepScan) end
        end
    end
    if CONFIG.MapCollision and not raycastVerified then
        if not map.ready and not map.building and not map.failed then
            local okB, errB = pcall(startMapBuild)
            if not okB then map.failed = true print("[Trajectory] map read failed: " .. tostring(errB)) end
        end
        local okM, errM = pcall(stepMapBuild)
        if not okM then map.building, map.failed = false, true print("[Trajectory] map read error: " .. tostring(errM)) end
    end
    local camera = Workspace.CurrentCamera
    local char   = LocalPlayer.Character
    if not camera or not char then if visible then hideAll() visible = false end return end

    local tool = getGrenadeTool(char)

    if tool then
        local okL, o, d = pcall(launchFrame, camera, char)
        if okL then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            local head = char:FindFirstChild("Head")
            lastLaunch = { origin = o, dir = d, cam = camera.CFrame.Position, look = camera.CFrame.LookVector,
                           root = hrp and hrp.Position, head = head and head.Position,
                           hand = handPosition(char), anchor = anchorPosition(char, camera), t = now() }
        end
    end
    -- wind-up tracking: how long the throw button / pin has been held
    if tool then
        local okM, m = pcall(ismouse1pressed)
        m = okM and m or false
        if m and not hold.pressT then hold.pressT = now() end
        if not m and hold.pressT then hold.lastHold = now() - hold.pressT hold.pressT = nil end
        pcall(function()
            local pp = tool:FindFirstChild("PinPulled")
            if pp then
                local v = pp.Value
                if v and not hold.pin then hold.pinT = now() end
                hold.pin = v
                local tm = pp:FindFirstChild("Timer")
                if tm then hold.timer = tm.Value end
            end
        end)
    elseif not calib then
        hold.pressT, hold.pin = nil, nil
    end

    if (tool ~= nil) ~= hadGrenade then
        if tool then
            if CONFIG.Debug then
                print("[Trajectory] equipped: " .. tool.Name)
                if not charDumpedOnce then
                    charDumpedOnce = true
                    pcall(function()
                        local out = {}
                        for _, k in ipairs(char:GetChildren()) do
                            if not STANDARD_CHAR[k.Name] and k.ClassName ~= "Accessory" and k.ClassName ~= "Hat" and k.ClassName ~= "Tool" then
                                for _, line in ipairs(dumpTree(k, 1, {}, "  ")) do out[#out + 1] = line end
                                if #out > 30 then break end
                            end
                        end
                        print("[Trajectory] character extras:")
                        print(#out > 0 and table.concat(out, "\n") or "[Trajectory]   (none)")
                    end)
                end
            end
            if (CONFIG.AutoCalibrate or CONFIG.LogThrows or CONFIG.ReportAccuracy) and not watcher then
                pcall(buildWatcher, char)
            end
        elseif lastTool and CONFIG.Debug then
            local p = lastTool.Parent
            print("[Trajectory] left hand: " .. lastTool.Name .. " -> "
                .. (p and (p.Name .. " (" .. p.ClassName .. ")") or "destroyed"))
        end
    end
    hadGrenade = tool ~= nil
    lastTool = tool

    if CONFIG.AutoCalibrate or CONFIG.LogThrows or CONFIG.ReportAccuracy then
        local okW, errW = pcall(stepWatcher, tool ~= nil)
        if not okW then watcher = nil print("[Trajectory] watcher error: " .. tostring(errW)) end
    end
    pcall(stepExplosions)
    if CONFIG.LogThrows then pcall(stepFlightLog) end
    if CONFIG.AutoCalibrate or CONFIG.LogThrows or CONFIG.ReportAccuracy then
        local ok, err = pcall(stepCalibration, char)
        if not ok then calib = nil print("[Trajectory] calibration error: " .. tostring(err)) end
    end

    local show = tool ~= nil and wantsShow()
    if show then
        local ok, err = pcall(update, camera, char, not visible)
        if not ok then
            hideAll()
            print("[Trajectory] " .. tostring(err))
            running = false
            return
        end
        visible = true
    elseif visible then
        hideAll()
        visible = false
    end
end

local connection
local okConnect = RunService and pcall(function()
    connection = RunService.RenderStepped:Connect(function() if running then step() end end)
end)
if not okConnect or not connection then
    local waitFn  = (task and task.wait) or wait
    local spawnFn = (task and task.spawn) or spawn
    spawnFn(function() while running do step() waitFn() end end)
end

-- ---------- unload ----------
local stopped = false
stop = function()
    if not running and stopped then return end
    stopped = true
    running = false
    if connection then pcall(function() connection:Disconnect() end) end
    hideAll()
    for i = 1, MAX_LINES do lines[i]:Remove() end
    rollLine:Remove()
    removePanel()
    topAll(function(o) o:Remove() end)
    impactDot:Remove()
    marker:Remove()
    for _, l in ipairs(blastRing) do l:Remove() end
    for _, l in ipairs(ticks) do l:Remove() end
    for _, c in ipairs(bounceDots) do c:Remove() end
    status:Remove()
    for _, c in ipairs(inBlastMarks) do c:Remove() end
    inBlastText:Remove()
    label:Remove()
    if _G.stopTrajectory == stop then _G.stopTrajectory = nil end
end
_G.stopTrajectory = stop

print("[Trajectory] loaded (" .. CONFIG.ShowMode .. " mode). X = unload, R = reset calibration.")
do
    local okG, wg = pcall(function() return Workspace.Gravity end)
    print("[Trajectory] game gravity (Workspace.Gravity) = " .. (okG and tostring(wg) or "unreadable"))
end
print(string.format("[Trajectory] using ThrowSpeed=%.1f Gravity=%.1f UpBias=%.3f LaunchFrom=%s SpawnOffset=(%.1f, %.1f, %.1f)",
    CONFIG.ThrowSpeed, CONFIG.Gravity, CONFIG.UpBias, CONFIG.LaunchFrom,
    CONFIG.SpawnOffset.X, CONFIG.SpawnOffset.Y, CONFIG.SpawnOffset.Z))
