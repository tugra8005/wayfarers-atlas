-- Retail tests. Usage: luajit tests/retail.lua
-- The game data is the generated data/retail_*.lua (tools/extract_retail.py, build in the
-- files' headers); the in-game shell runs against a stubbed 12.x API at the end.
local root = arg[0]:match("^(.*)/tests/") or "."
local ns = dofile(root .. "/tools/load.lua")(root, "AtlasRoute_Mainline.toc")
local Retail, AP, Taxi, Q = ns.Retail, ns.AtlasPlan, ns.RetailTaxi, ns.RetailQuests

local passed, failed = 0, 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then passed = passed + 1; print("ok   " .. name)
  else failed = failed + 1; print("FAIL " .. name .. "\n     " .. tostring(err)) end
end
local function eq(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
local function truthy(v, msg) if not v then error(msg or "expected true", 2) end end
local function read(p) local f = assert(io.open(p)); local s = f:read("*a"); f:close(); return s end

-- Game data ---------------------------------------------------------------------------------
test("Flight data: nodes and paths from the game tables are consistent", function()
  eq(Taxi.nodes[2][1], "Stormwind, Elwynn")
  eq(Taxi.nodes[2][2], 0, "Stormwind continent")
  eq(Taxi.nodes[23][2], 1, "Orgrimmar continent")
  eq(Taxi.nodes[2401][2], 2175, "Exile's Reach continent")
  local n = 0
  for _, p in ipairs(Taxi.paths) do
    n = n + 1
    local a, b = Taxi.nodes[p[1]], Taxi.nodes[p[2]]
    truthy(a and b, "path to an unknown node")
    eq(a[2], b[2], "a flight path never leaves its continent")
    -- a flight is never shorter than the straight line between its ends
    truthy(p[3] + 1 >= math.sqrt((a[3] - b[3]) ^ 2 + (a[4] - b[4]) ^ 2), "path shorter than straight line")
  end
  truthy(n > 3000, "paths: " .. n)
end)

test("Quest data: turn-ins and objectives, Exile's Reach included", function()
  local t = Q.turnin[40] -- A Fishy Peril, handed in to Marshal Dughan in Goldshire
  eq(t[1], 0)
  local fp = Taxi.nodes[582] -- Goldshire flight point
  truthy(math.sqrt((t[2] - fp[3]) ^ 2 + (t[3] - fp[4]) ^ 2) < 60, "Marshal Dughan is next to the Goldshire flight master")
  local er = 0
  for _, s in pairs(Q.turnin) do if s[1] == 2175 then er = er + 1 end end
  truthy(er > 50, "Exile's Reach turn-ins: " .. er)
  for _, list in pairs(Q.objectives) do
    eq(#list % 4, 0)
    for i = 1, #list, 4 do truthy(list[i] >= 0 and list[i] < 26, "objective index " .. list[i]) end
  end
end)

-- Builder + planner ---------------------------------------------------------------------------
local function elwynn(over)
  local snap = {
    continent = 0, x = -8913, y = 554, -- Stormwind, Trade District
    faction = "Alliance", class = "WARRIOR", speed = 7,
    taxi = {
      [2] = { known = true, faction = "Alliance" }, [582] = { known = true, faction = "Alliance" },
      [4] = { known = true, faction = "Alliance" }, [5] = { known = false, faction = "Alliance" },
      [12] = { known = true, faction = "Alliance" }, [18] = { known = true, faction = "Horde" },
    },
    quests = {
      { id = 11, name = "Riverpaw Gnoll Bounty", complete = false, done = {} },        -- tables only
      { id = 35, name = "Further Concerns", complete = true, done = {} },              -- tables only
      { id = 46, name = "Bounty on Murlocs", complete = false, done = {},
        live = { x = -9000, y = -1200 } },                                             -- live POI
      { id = 475, name = "A Troubling Breeze", complete = false, done = {} },          -- Kalimdor
    },
    givers = {},
  }
  for k, v in pairs(over or {}) do snap[k] = v end
  return snap
end

local function contiguous(world, plan)
  local at = world:index("here")
  for _, leg in ipairs(plan.legs) do
    for _, t in ipairs(leg.travel) do
      if t.from ~= at then return false end
      at = t.to
    end
    if leg.stop.node ~= at then return false end
  end
  return true
end

test("Builds the graph from the snapshot and the tables, plans every reachable stop", function()
  local b = Retail.build(elwynn())
  local w = b.world
  truthy(w.byId["air:fp2"] and w.byId["air:fp4"], "discovered flight masters")
  truthy(w.byId["fp5"] and not w.byId["air:fp5"], "undiscovered Lakeshire: a place, but no flight master")
  truthy(not w.byId["fp18"], "the Horde Booty Bay flight point is not on an Alliance map")
  -- stops: 11 objective + turn-in, 35 turn-in, 46 live objective + turn-in; 475 left out
  local plan = AP.plan(w, b.profile, b.start, b.quests)
  eq(#plan.order, 5)
  eq(#plan.unreachable, 0)
  truthy(contiguous(w, plan), "one connected walk")
  local note = table.concat(b.notes, "\n")
  truthy(note:find("A Troubling Breeze: handed in on another continent"), note)
  eq(b.sources.live, 1)
end)

test("Flies when it is faster, and only between discovered flight points", function()
  -- Stormwind to Darkshire (~2400 yd): flying beats walking. The Riverpaw objective in
  -- western Elwynn (~1070 yd) is faster on foot than via the Sentinel Hill flight.
  local b = Retail.build(elwynn())
  local t, legs = AP.route(b.world, b.profile, b.start, "fp12")
  eq(legs[#legs].mode, "fly", "to Darkshire")
  truthy(t < 2400 * 1.3 / 7, "faster than walking")
  local _, walk = AP.route(b.world, b.profile, b.start, "q11:o0")
  eq(#walk, 1, "Riverpaw objective")
  eq(walk[1].mode, "walk", "Riverpaw objective")
  for l = 1, #b.world.nodes do
    for _, e in ipairs(b.world.adj[l]) do
      if e.mode == "fly" then
        local a, z = b.world.nodes[e.from].id, b.world.nodes[e.to].id
        truthy(a ~= "air:fp5" and z ~= "air:fp5", "flew through undiscovered Lakeshire")
      end
    end
  end
end)

test("Flight times: the measured time replaces the 434% estimate", function()
  local est = Retail.build(elwynn()).world
  local function cost(w)
    for _, e in ipairs(w.adj[w:index("air:fp2")]) do
      if e.mode == "fly" and w.nodes[e.to].id == "air:fp4" then return e.cost end
    end
  end
  local yards
  for _, p in ipairs(Taxi.paths) do if p[1] == 2 and p[2] == 4 then yards = p[3] end end
  truthy(math.abs(cost(est) - yards / Retail.TAXI_SPEED) < 1e-6, "estimate")
  local timed = Retail.build(elwynn({ flightTimes = { ["2>4"] = 95 } })).world
  eq(cost(timed), 95)
end)

test("Finished objectives are skipped; quest givers from the map become pick-up stops", function()
  local b = Retail.build(elwynn({
    quests = { { id = 54933, name = "ER quest", complete = false, done = { [0] = true, [2] = true } } },
    continent = 2175, x = 300, y = -2480, taxi = {},
  }))
  -- objectives 1 and 3 remain (0 and 2 done) plus the turn-in
  eq(#b.quests[1].objectives, 2)
  local g = Retail.build(elwynn({ quests = {}, givers = { { id = 40, name = "A Fishy Peril", x = -9466, y = 74 } } }))
  eq(g.quests[1].giver, "q40:giver")
  local plan = AP.plan(g.world, g.profile, g.start, g.quests)
  eq(plan.legs[1].stop.kind, "accept")
end)

test("Hearthstone is used only where it has been recorded, and only when ready", function()
  local h = { x = -9466, y = 60, continent = 0, name = "Goldshire" }
  local ready = Retail.build(elwynn({ hearth = h, hearthReady = true }))
  eq(ready.profile.hearth, "hearth")
  local cd = Retail.build(elwynn({ hearth = h, hearthReady = false }))
  eq(cd.profile.hearth, nil)
  local away = Retail.build(elwynn({ hearth = { x = 0, y = 0, continent = 1, name = "Orgrimmar" }, hearthReady = true }))
  eq(away.profile.hearth, nil)
end)

test("Every place is reachable on foot (walking graph is connected)", function()
  local b = Retail.build(elwynn())
  local w = b.world
  local seen, stack = { [w:index("here")] = true }, { w:index("here") }
  while #stack > 0 do
    local i = table.remove(stack)
    for _, e in ipairs(w.adj[i]) do
      if e.mode == "walk" and not seen[e.to] then seen[e.to] = true; stack[#stack + 1] = e.to end
    end
  end
  for i, n in ipairs(w.nodes) do
    if n.kind == "ground" then truthy(seen[i], n.name .. " cut off") end
  end
end)

-- In-game shell, stubbed 12.x API ------------------------------------------------------------
-- A toy world: two zone maps on continent 0 laid over real world coordinates, so map
-- positions convert to the same world yards the tables use. GetWorldPosFromMapPos returns
-- the axes swapped (`swap`) to check that the shell calibrates against UnitPosition.
-- Stub frames and regions: every method exists (unknown ones do nothing); the ones the UI
-- reads back return what was set, and lines/points/colours/text are recorded for the tests.
local Stub = {}
local function stub(kind, parent)
  local o = { kind = kind, parent = parent, scripts = {}, events = {}, points = {}, shown = true,
              w = 0, h = 0, level = 1, children = {} }
  if parent then parent.children[#parent.children + 1] = o end
  -- unknown methods (WoW's are capitalised) do nothing; unknown fields are nil, as in WoW
  return setmetatable(o, { __index = function(_, k)
    if Stub[k] then return Stub[k] end
    if type(k) == "string" and k:match("^%u") then return function() end end
  end })
end
function Stub:SetThickness(t) self.thickness = t end
function Stub:SetAlpha(a) self.alpha = a end
function Stub:SetScript(k, fn) self.scripts[k] = fn end
function Stub:GetScript(k) return self.scripts[k] end
function Stub:RegisterEvent(e) self.events[e] = true end
function Stub:CreateTexture() return stub("Texture", self) end
function Stub:CreateFontString() return stub("FontString", self) end
function Stub:CreateLine() return stub("Line", self) end
function Stub:Show() self.shown = true end
function Stub:Hide() self.shown = false end
function Stub:IsShown() return self.shown end
function Stub:SetText(t) self.text = t end
function Stub:GetText() return self.text end
function Stub:SetSize(w, h) self.w, self.h = w, h end
function Stub:SetHeight(h) self.h = h end
function Stub:GetSize() return self.w, self.h end
function Stub:GetFrameLevel() return self.level end
function Stub:SetFrameLevel(l) self.level = l end
function Stub:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function Stub:SetStartPoint(_, _, x, y) self.start = { x, y } end
function Stub:SetEndPoint(_, _, x, y) self.stop = { x, y } end
function Stub:ClearAllPoints() self.points = {} end
function Stub:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Stub:Click(button) self.scripts.OnClick(self, button or "LeftButton") end
function Stub:SetShown(v) self.shown = v and true or false end
function Stub:SetWidth(w) self.w = w end
function Stub:GetWidth() return self.w end
function Stub:SetScale(s) self.scale = s end
function Stub:SetAtlas(a) self.atlas = a end
function Stub:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a } end
function Stub:CreateMaskTexture() return stub("MaskTexture", self) end
function Stub:CreateAnimationGroup() local g = stub("AnimationGroup", self); g.anims = {}; return g end
function Stub:CreateAnimation(kind) local a = stub(kind); self.anims[#self.anims + 1] = a; return a end
function Stub:GetAnimations() return unpack(self.anims) end
function Stub:Play() self.playing = true end
function Stub:Stop() self.playing = false end
function Stub:SetStartDelay(d) self.delay = d end

local function runShell(swap)
  local chat, frames, timers = {}, {}, {}
  local waypoints = {}
  local now = 1000
  local player = { x = -8913, y = 554, cont = 0, onTaxi = false, mounted = false }
  local MAPS = {
    [13] = { name = "Eastern Kingdoms", mapType = 2, parent = 947, top = -7000, left = 3000, h = 6000, w = 6000 },
    [37] = { name = "Elwynn Forest", mapType = 3, parent = 13, top = -8500, left = 1000, h = 1500, w = 2600 },
    [52] = { name = "Westfall", mapType = 3, parent = 13, top = -10000, left = 2000, h = 1500, w = 1500 },
  }
  local function mapOf(x, y)
    for _, id in ipairs({ 37, 52 }) do
      local m = MAPS[id]
      local mx, my = (m.left - y) / m.w, (m.top - x) / m.h
      if mx >= 0 and mx <= 1 and my >= 0 and my <= 1 then return id, mx, my end
    end
    local m = MAPS[13]
    return 13, (m.left - y) / m.w, (m.top - x) / m.h
  end
  local function vec(x, y) return { x = x, y = y, GetXY = function(s) return s.x, s.y end } end
  local function worldOf(id, mx, my)
    local m = MAPS[id]
    return m.top - my * m.h, m.left - mx * m.w
  end
  local function onMap(id, x, y)
    local m = MAPS[id]
    local mx, my = (m.left - y) / m.w, (m.top - x) / m.h
    if mx >= 0 and mx <= 1 and my >= 0 and my <= 1 then return mx, my end
  end
  local discovered = { [2] = true, [582] = true, [4] = true }
  local log = { -- quest log: 11 in progress (no live point), 46 with a live point, 35 complete
    { questID = 11, title = "Riverpaw Gnoll Bounty" },
    { questID = 46, title = "Bounty on Murlocs", live = { -9000, -1200 } },
    { questID = 35, title = "Further Concerns", complete = true },
  }
  local cooldown = 0
  local canvas = stub("Frame")
  canvas.w, canvas.h = 1000, 667
  local worldMap = stub("Frame")
  worldMap.mapID, worldMap.scale = 37, 1
  function worldMap:AddDataProvider(p) self.provider = p; p:OnAdded(self) end
  function worldMap:GetMapID() return self.mapID end
  function worldMap:GetCanvas() return canvas end
  function worldMap:GetCanvasScale() return self.scale end
  local env
  env = setmetatable({
    DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m end },
    CreateFrame = function(kind, _, parent)
      local f = stub(kind, parent)
      frames[#frames + 1] = f
      return f
    end,
    SlashCmdList = {},
    WorldMapFrame = worldMap,
    UIParent = stub("Frame"),
    GameTooltip = stub("GameTooltip"),
    BACKDROP_DARK_DIALOG_32_32 = {},
    CreateFromMixins = function(m) local o = {}; for k, v in pairs(m) do o[k] = v end; return o end,
    MapCanvasDataProviderMixin = {
      OnAdded = function(self, map) self.owningMap = map end,
      GetMap = function(self) return self.owningMap end,
      RemoveAllData = function() end, RefreshAllData = function() end,
    },
    ToggleWorldMap = function() end,
    UiMapPoint = { CreateFromCoordinates = function(id, x, y) return { uiMapID = id, x = x, y = y } end },
    C_SuperTrack = { SetSuperTrackedUserWaypoint = function(on) waypoints.tracked = on end },
    Enum = { UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3 },
             FlightPathFaction = { Neutral = 0, Horde = 1, Alliance = 2 } },
    CreateVector2D = vec,
    UnitPosition = function() return player.x, player.y, 0, player.cont end,
    UnitClass = function() return "Warrior", "WARRIOR", 1 end,
    UnitFactionGroup = function() return "Alliance", "Alliance" end,
    GetBindLocation = function() return "Goldshire" end,
    GetBuildInfo = function() return "12.1.5", "70961", "Nov 18 2026", 120105 end,
    GetUnitSpeed = function() return 0, player.mounted and 14 or 7, 0, 0 end,
    IsMounted = function() return player.mounted end,
    IsFlying = function() return false end,
    UnitOnTaxi = function() return player.onTaxi end,
    GetTime = function() return now end,
    C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end },
    C_Item = {
      GetItemCount = function(id) return id == 6948 and 1 or 0 end,
      GetItemCooldown = function() return now, cooldown, true end,
    },
    C_Map = {
      GetBestMapForUnit = function() return (mapOf(player.x, player.y)) end,
      GetMapInfo = function(id)
        local m = MAPS[id]
        if not m then return id == 947 and { mapID = 947, name = "Azeroth", mapType = 1, parentMapID = 946 } or nil end
        return { mapID = id, name = m.name, mapType = m.mapType, parentMapID = m.parent }
      end,
      GetMapChildrenInfo = function(id)
        if id ~= 13 then return {} end
        return { { mapID = 37, mapType = 3 }, { mapID = 52, mapType = 3 } }
      end,
      GetPlayerMapPosition = function(id) local mx, my = onMap(id, player.x, player.y); return mx and vec(mx, my) end,
      GetWorldPosFromMapPos = function(id, p)
        if not MAPS[id] then return nil end
        local x, y = worldOf(id, p.x, p.y)
        if swap then x, y = y, x end
        return 0, vec(x, y)
      end,
      GetMapPosFromWorldPos = function(cont, p, override)
        if cont ~= 0 then return nil end
        local x, y = p.x, p.y
        if swap then x, y = y, x end
        local id = override or (mapOf(x, y))
        local m = MAPS[id]
        if not m then return nil end
        return id, vec((m.left - y) / m.w, (m.top - x) / m.h)
      end,
      CanSetUserWaypointOnMap = function(id) return MAPS[id] ~= nil and MAPS[id].mapType == 3 end,
      SetUserWaypoint = function(point) waypoints[#waypoints + 1] = point; return true end,
    },
    C_TaxiMap = {
      GetTaxiNodesForMap = function(id)
        local list = {}
        for nodeID, n in pairs(ns.RetailTaxi.nodes) do
          if n[2] == 0 and (nodeID == 2 or nodeID == 582 or nodeID == 4 or nodeID == 5 or nodeID == 18) then
            local mx, my = onMap(id, n[3], n[4])
            if mx then
              list[#list + 1] = { nodeID = nodeID, position = vec(mx, my), name = n[1],
                                  faction = n[5] == 2 and 1 or 2, isUndiscovered = not discovered[nodeID] }
            end
          end
        end
        return list
      end,
    },
    C_QuestLog = {
      GetNumQuestLogEntries = function() return #log + 1, #log end,
      GetInfo = function(i)
        if i == 1 then return { isHeader = true, title = "Elwynn Forest" } end
        local q = log[i - 1]
        return q and { questID = q.questID, title = q.title, isHeader = false, isHidden = false, isTask = false, isBounty = false }
      end,
      GetQuestsOnMap = function(id)
        local list = {}
        for _, q in ipairs(log) do
          if q.live then
            local mx, my = onMap(id, q.live[1], q.live[2])
            if mx then list[#list + 1] = { questID = q.questID, x = mx, y = my, isMapIndicatorQuest = false } end
          end
        end
        return list
      end,
      GetNextWaypoint = function() return nil end,
      ReadyForTurnIn = function(id) for _, q in ipairs(log) do if q.questID == id then return q.complete or false end end end,
      IsComplete = function(id) for _, q in ipairs(log) do if q.questID == id then return q.complete or false end end end,
      GetQuestObjectives = function() return { { finished = false } } end,
      GetLogIndexForQuestID = function(id) for i, q in ipairs(log) do if q.questID == id then return i + 1 end end end,
      IsQuestFlaggedCompleted = function() return false end,
    },
    C_QuestLine = {
      RequestQuestLinesForMap = function() end,
      GetAvailableQuestLines = function(id)
        if id ~= 37 then return {} end
        local mx, my = onMap(37, -9466, 74) -- Marshal Dughan, Goldshire
        return { { questID = 40, questName = "A Fishy Peril", x = mx, y = my, isHidden = false },
                 { questID = 99999, questName = "Trivial", x = mx, y = my, isHidden = true } }
      end,
      GetForceVisibleQuests = function() return {} end,
      GetQuestLineInfo = function() return nil end,
    },
  }, { __index = _G })

  local addonNs = {}
  local toc = read(root .. "/AtlasRoute/AtlasRoute_Mainline.toc")
  for line in toc:gmatch("[^\r\n]+") do
    if not line:match("^#") and line:match("%.lua") then
      local chunk = assert(loadfile(root .. "/AtlasRoute/" .. line:gsub("\\", "/")))
      setfenv(chunk, env)
      chunk("AtlasRoute", addonNs)
    end
  end
  local function fire(event, ...)
    for _, f in ipairs(frames) do if f.events[event] then f.scripts.OnEvent(f, event, ...) end end
  end
  local function tick(n)
    for _ = 1, n or 1 do
      for _, f in ipairs(frames) do if f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.016) end end
    end
  end
  local function runTimers() local t = timers; timers = {}; for _, fn in ipairs(t) do fn() end end
  fire("ADDON_LOADED", "AtlasRoute")
  local slash = env.SlashCmdList.ATLASROUTE
  return { chat = chat, slash = slash, fire = fire, tick = tick, runTimers = runTimers, player = player,
           ns = addonNs, worldMap = worldMap, canvas = canvas, waypoints = waypoints, log = log,
           env = env, setTime = function(t) now = t end, setCooldown = function(c) cooldown = c end,
           text = function() return table.concat(chat, "\n") end }
end

for _, swap in ipairs({ false, true }) do
  test("In-game shell plans from the live (stubbed) client" .. (swap and ", map axes swapped" or ""), function()
    local s = runShell(swap)
    s.slash("status")
    s.slash("nearby")
    s.runTimers()
    s.slash("list")
    s.slash("plan")
    s.tick(5000)
    s.slash("route Sentinel")
    s.slash("places")
    local text = s.text()
    truthy(text:find("Client 70961 %(interface 120105%); game tables from build 12%.1%.5%.70961"), "status:\n" .. text)
    truthy(text:find("Continent 0: 4 flight points shown, 3 discovered by you"), "taxi count:\n" .. text)
    truthy(text:find("Added 1 quest givers"), "nearby:\n" .. text)
    truthy(text:find("Bounty on Murlocs: objective %(quest log, live%) > turn in"), "list:\n" .. text)
    truthy(text:find("A Fishy Peril: pick up %(map pin%)"), "list giver:\n" .. text)
    truthy(text:find("Planning 4 quests"), "plan header:\n" .. text)
    truthy(text:find("%d+ stops, .- of travel %(Atlas"), "plan output:\n" .. text:sub(-1500))
    truthy(text:find("To Sentinel Hill, Westfall: "), "route:\n" .. text)
    truthy(not text:find("error"), "error in output:\n" .. text)
    -- the Riverpaw objective is ~1000 yd west of Goldshire: the plan's positions must be the
    -- tables' world yards, so a wrong axis calibration would show up as an unreachable stop
    truthy(not text:find("can't be reached"), "unreachable stops:\n" .. text)
  end)
end

test("In-game shell times a flight and records where the hearthstone lands", function()
  local s = runShell(true)
  -- take off at the Stormwind flight master, land at Sentinel Hill 80 s later
  local sw, sh = ns.RetailTaxi.nodes[2], ns.RetailTaxi.nodes[4]
  s.player.x, s.player.y = sw[3] + 5, sw[4]
  s.player.onTaxi = true; s.tick()
  s.setTime(1080)
  s.player.x, s.player.y = sh[3], sh[4] + 5
  s.player.onTaxi = false; s.tick()
  truthy(s.text():find("Timed the flight Stormwind, Elwynn %-> Sentinel Hill, Westfall: 1m 20s"), s.text())
  -- hearthstone: cast in Westfall, land in Goldshire
  s.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 8690)
  s.player.x, s.player.y = -9460, 70
  s.runTimers()
  truthy(s.text():find("Hearthstone point Goldshire recorded"), s.text())
  s.slash("status")
  truthy(s.text():find("Hearthstone: Goldshire, point recorded, ready"), s.text())
  truthy(s.text():find("1 flights timed"), s.text())
  -- on cooldown: planned without it
  s.setCooldown(1800)
  s.slash("plan")
  truthy(s.text():find("hearthstone: on cooldown"), s.text())
end)

test("Mounted: the measured mount speed is kept for later plans", function()
  local s = runShell(false)
  s.player.mounted = true
  s.slash("status")
  s.player.mounted = false
  s.slash("status")
  truthy(select(2, s.text():gsub("Ground speed: 14%.0 yd/s %(your mount, measured%)", "")) == 2, s.text())
end)

-- Plan window and world map -----------------------------------------------------------------
local function planned(swap)
  local s = runShell(swap)
  s.slash("nearby")
  s.runTimers()
  s.slash("plan")
  s.tick(5000)
  return s
end

-- Shown lines (inside their holder frames), shown markers, flight holders, the layer.
local function mapRegions(s)
  local layer
  for _, c in ipairs(s.canvas.children) do if c.kind == "Frame" then layer = c end end
  local lines, markers, flights = {}, {}, {}
  for _, c in ipairs(layer and layer.children or {}) do
    if c.shown and c.kind == "Frame" then
      for _, l in ipairs(c.children) do if l.kind == "Line" then lines[#lines + 1] = l end end
      if c.Fill.atlas then flights[#flights + 1] = c end
    end
    if c.shown and c.kind == "Button" then markers[#markers + 1] = c end
  end
  return lines, markers, flights, layer
end

test("Plan window lists every stop in order with its time", function()
  local s = planned(false)
  local cur = s.ns.View.current()
  local win = s.ns.View.window()
  truthy(win and win.shown, "window shown")
  eq(#cur.stops, 7)
  for i, st in ipairs(cur.stops) do
    local row = win.rows[i]
    truthy(row.shown, "row " .. i)
    truthy(row.text.text:find(("^%d%%. "):format(i), 1), row.text.text)
    truthy(row.text.text:find(st.name, 1, true), row.text.text)
  end
  truthy(not win.rows[8].shown, "no extra rows")
  truthy(win.subtitle.text:find("^7 stops, 13m 41s of travel$"), win.subtitle.text)
  truthy(win.barText.text:find("^0 / 7 done  %-  13m 41s left$"), win.barText.text)
  truthy(win.nextName.text:find("1%. A Fishy Peril %(pick up%)"), win.nextName.text)
  truthy(win.nextInfo.text:find("^%d+ yd away  %-  1m 00s planned  %-  pick up$"), win.nextInfo.text)
  truthy(win.rows[1].cur.shown and not win.rows[2].cur.shown, "next row highlighted")
  truthy(win.rows[1].mode.text:find("fly"), "row 1 travel includes a flight")
  truthy(s.text():find("The stops are in the AtlasRoute window"), s.text())
  truthy(not s.text():find("%[accept%]"), "short plans are not listed in chat too")
end)

for _, swap in ipairs({ false, true }) do
  test("World map: route lines and stop markers inside the map" .. (swap and ", axes swapped" or ""), function()
    local s = planned(swap)
    s.worldMap.provider:RefreshAllData()
    local lines, markers = mapRegions(s)
    truthy(#lines > 0, "no lines")
    for _, l in ipairs(lines) do
      for _, p in ipairs({ l.start, l.stop }) do
        truthy(p[1] >= -1e-6 and p[1] <= 1000 + 1e-6 and p[2] <= 1e-6 and p[2] >= -667 - 1e-6,
               ("line point outside the canvas: %.1f, %.1f"):format(p[1], p[2]))
      end
    end
    local _, _, flights = mapRegions(s)
    eq(#flights, 1, "the flight Stormwind -> Goldshire")
    eq(flights[1].Fill.atlas, "_UI-Taxi-Line-horizontal", "drawn with the flight map's line")
    -- stops 1,2 (Goldshire) and 5,7 (Guard Thomas) are at the same spot: one marker each
    eq(#markers, 6, "5 spots + you")
    local labels = {}
    for _, m in ipairs(markers) do labels[m.label.text] = m end
    truthy(labels["1,2"] and labels["5,7"] and labels["3"] and labels["4"] and labels["6"], "labels")
    -- marker "1,2": stop 1 is next, so it glows and pulses; it sits where the stop is
    local mk = labels["1,2"]
    truthy(mk.glow.shown and mk.pulse.playing, "next stop glows")
    truthy(not labels["3"].glow.shown, "other stops don't")
    eq(mk.stop, 1, "a click goes to the first stop not done")
    local st = s.ns.View.current().stops[1]
    local p = mk.points[#mk.points]
    local nx, ny = (1000 - st.y) / 2600, (-8500 - st.x) / 1500
    truthy(math.abs(p[4] - nx * 1000) < 1e-6 and math.abs(p[5] + ny * 667) < 1e-6, "marker position")
    -- a new plan draws its route in, segment after segment
    local delays = {}
    for _, l in ipairs(lines) do
      local h = l.parent
      if h.reveal.playing then delays[#delays + 1] = h.reveal.anims[1].delay end
    end
    truthy(#delays > 3, "reveal animations")
  end)
end

test("World map: a shared marker moves on once its first stop is done", function()
  local s = planned(false)
  s.ns.View.toggle(1)
  s.worldMap.provider:RefreshAllData()
  local _, markers = mapRegions(s)
  local mk
  for _, m in ipairs(markers) do if m.label.text == "1,2" then mk = m end end
  eq(mk.stop, 2, "click goes to stop 2 now")
  truthy(mk.glow.shown, "stop 2 is next")
  eq(mk.alpha, 1, "not dimmed while stop 2 is open")
  s.ns.View.toggle(2)
  s.worldMap.provider:RefreshAllData()
  _, markers = mapRegions(s)
  for _, m in ipairs(markers) do if m.label.text == "1,2" then mk = m end end
  truthy(mk.alpha < 1 and not mk.glow.shown, "both done: dimmed, no glow")
end)

test("World map: switching to another map redraws and clips the route to it", function()
  local s = planned(false)
  s.worldMap.mapID = 52 -- Westfall: the route is in Elwynn, mostly off this map
  s.worldMap.provider:RefreshAllData()
  local lines, markers = mapRegions(s)
  for _, l in ipairs(lines) do
    for _, p in ipairs({ l.start, l.stop }) do
      truthy(p[1] >= -1e-6 and p[1] <= 1000 + 1e-6 and p[2] <= 1e-6 and p[2] >= -667 - 1e-6, "clipped")
    end
  end
  eq(#markers, 0, "no stop is in Westfall")
  s.worldMap.mapID = 37
  s.worldMap.scale = 2 -- zoomed in: markers keep their screen size (frame scale 1/2)
  s.worldMap.provider:RefreshAllData()
  local l2, m2 = mapRegions(s)
  truthy(#l2 > 0 and #m2 == 6, "redrawn")
  local mk
  for _, m in ipairs(m2) do if m.label.text == "3" then mk = m end end
  eq(mk.scale, 0.5)
  eq(mk.w, 20)
  local st = s.ns.View.current().stops[3]
  local p = mk.points[#mk.points]
  truthy(math.abs(p[4] - (1000 - st.y) / 2600 * 1000 * 2) < 1e-6, "offset divided by the marker's scale")
  for _, l in ipairs(l2) do -- walk 3, its dark edge 5, flight 18: halved at zoom 2
    local t = l.thickness * 2
    truthy(math.abs(t - 3) < 1e-9 or math.abs(t - 5) < 1e-9 or math.abs(t - 18) < 1e-9, "thickness " .. l.thickness)
  end
end)

test("Left-click a stop: the game's waypoint arrow points to it", function()
  local s = planned(false)
  local win = s.ns.View.window()
  win.rows[3]:Click("LeftButton")
  local wp = s.waypoints[#s.waypoints]
  local st = s.ns.View.current().stops[3]
  eq(wp.uiMapID, 37, "zone map")
  truthy(math.abs(wp.x - (1000 - st.y) / 2600) < 1e-6 and math.abs(wp.y - (-8500 - st.x) / 1500) < 1e-6, "waypoint position")
  eq(s.waypoints.tracked, true, "arrow shown")
  truthy(s.text():find("Arrow points to stop 3"), s.text())
end)

test("Right-click ticks a stop off; quest events tick stops off by themselves", function()
  local s = planned(false)
  local View = s.ns.View
  local win = View.window()
  win.rows[2]:Click("RightButton")
  truthy(View.current().stops[2].done, "right-click")
  truthy(win.barText.text:find("^1 / 7 done"), win.barText.text)
  truthy(win.rows[2].check.shown and not win.rows[2].dot.shown, "done row shows the checkmark")
  truthy(win.barFill.w > 0.001, "progress bar grows")
  win.rows[2]:Click("RightButton")
  truthy(not View.current().stops[2].done, "right-click again: not done")
  -- picking up A Fishy Peril (the first stop) ticks it off and moves the arrow on
  local first = View.current().stops[1]
  eq(first.kind, "accept")
  s.fire("QUEST_ACCEPTED", first.quest)
  truthy(View.current().stops[1].done, "QUEST_ACCEPTED")
  truthy(s.text():find("Arrow points to stop 2"), s.text())
  -- Bounty on Murlocs completes: its objective stop ticks off on the next log update
  for _, q in ipairs(s.log) do if q.questID == 46 then q.complete = true end end
  s.fire("QUEST_LOG_UPDATE")
  for _, st in ipairs(View.current().stops) do
    if st.quest == 46 and st.kind == "objective" then truthy(st.done, "objective ticked") end
    if st.quest == 46 and st.kind == "turnin" then truthy(not st.done, "turn-in still to do") end
  end
  s.fire("QUEST_TURNED_IN", 46, 0, 0)
  for _, st in ipairs(View.current().stops) do
    if st.quest == 46 then truthy(st.done, "turned in") end
  end
  -- /ar window hides and shows it again
  s.slash("window"); truthy(not win.shown, "hidden")
  s.slash("window"); truthy(win.shown, "shown")
end)

test("Clipping a segment to the map square", function()
  local clip = ns.View and ns.View.clip
  if not clip then -- the view loads with the UI; load it on its own
    local v = {}
    local chunk = assert(loadfile(root .. "/AtlasRoute/ui/view.lua"))
    setfenv(chunk, setmetatable({ CreateFromMixins = function(m) return m end, MapCanvasDataProviderMixin = {},
                                  CreateFrame = function() return stub("Frame") end }, { __index = _G }))
    chunk("AtlasRoute", v)
    clip = v.View.clip
  end
  local a, b, c, d = clip(-1, 0.5, 2, 0.5)
  truthy(a == 0 and b == 0.5 and c == 1 and d == 0.5, "horizontal through")
  eq(clip(2, 2, 3, 3), nil, "outside")
  a, b, c, d = clip(0.2, 0.2, 0.4, 0.4)
  truthy(a == 0.2 and d == 0.4, "inside untouched")
end)

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
