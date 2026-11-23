-- In-game shell for the retail client (12.x, the one the free trial runs). Reads the live
-- game into a snapshot for core/retail.lua and prints Atlas's plan in chat.
--
--   /ar                 help
--   /ar plan            tour of your quest log (and of quests added with /ar nearby): opens
--                       the plan window and draws the route on the world map (ui/view.lua)
--   /ar window | map    show/hide the plan window | open the world map
--   /ar nearby [clear]  add the quests offered on this zone's map (the "!" pins)
--   /ar list            what /ar plan will visit, and where each position comes from
--   /ar route <place>   fastest way to a flight point or quest stop on this continent
--   /ar places [text]   flight points and quest stops on this continent
--   /ar speed <yd/s> | auto   ground speed (auto: measured from your mount)
--   /ar status          what the addon has read and measured so far
--
-- What it reads from the client: where you are (UnitPosition), the flight points on your
-- continent and which you have discovered (C_TaxiMap), your quest log and where the map
-- points for each quest (C_QuestLog), the quest givers on the map (C_QuestLine), your
-- hearthstone and its cooldown (C_Item). What it measures: how long your flights take,
-- where your hearthstone lands, how fast your mount runs. Nothing is typed in by hand.
local addonName, ns = ...
local AtlasPlan, Retail = ns.AtlasPlan, ns.Retail

local HEARTHSTONE_ITEM, HEARTHSTONE_SPELL = 6948, 8690
local MAP_CONTINENT, MAP_ZONE = 2, 3 -- Enum.UIMapType
if Enum and Enum.UIMapType then MAP_CONTINENT, MAP_ZONE = Enum.UIMapType.Continent, Enum.UIMapType.Zone end

local DB -- AtlasRouteDB.retail, set on ADDON_LOADED

local MODE_COLOR = { walk = "ffffffff", fly = "ff66ccff", hearth = "ff66ff66" }

local function out(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99AtlasRoute|r " .. msg)
end
ns.out = out

local function fmtTime(s)
  s = math.floor(s + 0.5)
  if s >= 3600 then return ("%dh %02dm"):format(math.floor(s / 3600), math.floor(s % 3600 / 60)) end
  return ("%dm %02ds"):format(math.floor(s / 60), s % 60)
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Positions ---------------------------------------------------------------------------------
-- World positions use UnitPosition's axes (the same as the game tables). Map positions are
-- turned into world positions with C_Map.GetWorldPosFromMapPos; whether that returns the
-- axes in the same order is checked against UnitPosition once (calibrate).
local function playerPos()
  local x, y, _, instance = UnitPosition("player")
  if x then return x, y, instance end
end

ns.playerPos = playerPos

local swapAxes = false
local calibrated = false
local function calibrate()
  if calibrated then return end
  local m = C_Map.GetBestMapForUnit("player")
  local p = m and C_Map.GetPlayerMapPosition(m, "player")
  local _, wp = nil, nil
  if p then _, wp = C_Map.GetWorldPosFromMapPos(m, p) end
  local x, y = playerPos()
  if wp and x then
    local wx, wy = wp:GetXY()
    swapAxes = math.abs(wx - y) + math.abs(wy - x) < math.abs(wx - x) + math.abs(wy - y)
    calibrated = true
  end
end

-- World yards (UnitPosition axes) -> the vector C_Map.GetMapPosFromWorldPos takes.
function ns.apiVec(x, y)
  if swapAxes then return CreateVector2D(y, x) end
  return CreateVector2D(x, y)
end

local function toWorld(mapID, mx, my)
  local cont, wp = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(mx, my))
  if not cont or not wp then return nil end
  local wx, wy = wp:GetXY()
  if swapAxes then wx, wy = wy, wx end
  return cont, wx, wy
end

-- The maps of the continent you are on: your current map, every zone below the continent,
-- and the continent itself. Exile's Reach and other islands without a continent map are
-- their own top map.
local function regionMaps()
  local here = C_Map.GetBestMapForUnit("player")
  if not here then return nil end
  local top, info = here, C_Map.GetMapInfo(here)
  local zone = (info and info.mapType == MAP_ZONE) and here or nil
  while info and info.parentMapID and info.parentMapID ~= 0 do
    local parent = C_Map.GetMapInfo(info.parentMapID)
    if not parent or parent.mapType < MAP_CONTINENT then break end
    top, info = parent.mapID, parent
    if not zone and parent.mapType == MAP_ZONE then zone = parent.mapID end
  end
  local maps, seen = {}, {}
  local function add(m) if m and not seen[m] then seen[m] = true; maps[#maps + 1] = m end end
  add(here)
  add(zone)
  for _, c in ipairs(C_Map.GetMapChildrenInfo(top, nil, true) or {}) do
    if c.mapType == MAP_ZONE then add(c.mapID) end
  end
  add(top)
  return maps, zone or here
end

-- Reading the game --------------------------------------------------------------------------
local FACTION = {}
if Enum and Enum.FlightPathFaction then
  FACTION[Enum.FlightPathFaction.Horde] = "Horde"
  FACTION[Enum.FlightPathFaction.Alliance] = "Alliance"
end

local function readTaxi(maps, continent)
  local nodes = {}
  for _, m in ipairs(maps) do
    for _, n in ipairs(C_TaxiMap.GetTaxiNodesForMap(m) or {}) do
      if not nodes[n.nodeID] then
        local cont, x, y = toWorld(m, n.position:GetXY())
        if cont == continent then
          nodes[n.nodeID] = { known = not n.isUndiscovered, faction = FACTION[n.faction], name = n.name, x = x, y = y }
        end
      end
    end
  end
  return nodes
end

local function readQuests(maps, continent)
  local live = {}
  for _, m in ipairs(maps) do
    for _, info in ipairs(C_QuestLog.GetQuestsOnMap(m) or {}) do
      if not live[info.questID] and not info.isMapIndicatorQuest then
        local cont, x, y = toWorld(m, info.x, info.y)
        if cont then live[info.questID] = { continent = cont, x = x, y = y } end
      end
    end
  end
  local list = {}
  local n = C_QuestLog.GetNumQuestLogEntries()
  for i = 1, n do
    local q = C_QuestLog.GetInfo(i)
    if q and not q.isHeader and not q.isHidden and not q.isTask and not q.isBounty then
      local id = q.questID
      local e = { id = id, name = q.title, done = {},
                  complete = (C_QuestLog.ReadyForTurnIn(id) or C_QuestLog.IsComplete(id)) and true or false }
      local p = live[id]
      if not p then
        local wm, wx, wy = C_QuestLog.GetNextWaypoint(id)
        if wm then
          local cont, x, y = toWorld(wm, wx, wy)
          if cont then p = { continent = cont, x = x, y = y, waypoint = true } end
        end
      end
      if p then
        if p.continent == continent then e.live = p else e.liveElsewhere = true end
      end
      for k, o in ipairs(C_QuestLog.GetQuestObjectives(id) or {}) do
        if o.finished then e.done[k - 1] = true end
      end
      list[#list + 1] = e
    end
  end
  return list
end

local function givers(continent)
  local list = {}
  for id, g in pairs(DB.nearby) do
    if C_QuestLog.GetLogIndexForQuestID(id) or C_QuestLog.IsQuestFlaggedCompleted(id) then
      DB.nearby[id] = nil -- picked up or done since: the quest log has it now
    elseif g.continent == continent then
      list[#list + 1] = { id = id, name = g.name, x = g.x, y = g.y }
    end
  end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

-- Ground speed: what you set, else your mount's speed as measured, else your run speed.
local function readSpeed()
  local ok, run = pcall(function() local _, r = GetUnitSpeed("player"); return r + 0 end)
  if not ok then run = nil end
  if run and IsMounted() and not (IsFlying and IsFlying()) and run > (DB.mountSpeed or 0) then
    DB.mountSpeed = run
  end
  if DB.speed then return DB.speed, "set with /ar speed" end
  if DB.mountSpeed then return DB.mountSpeed, "your mount, measured" end
  return run or 7, "on foot"
end

local function hearthReady()
  if C_Item.GetItemCount(HEARTHSTONE_ITEM) == 0 then return false end
  local _, duration = C_Item.GetItemCooldown(HEARTHSTONE_ITEM)
  return not duration or duration <= 1.5 -- 1.5 s = global cooldown
end

local function snapshot()
  calibrate()
  local x, y, continent = playerPos()
  if not x then return nil, "The game doesn't give a position here (instances hide it)." end
  local maps = regionMaps()
  if not maps then return nil, "No map for where you are." end
  local _, class = UnitClass("player")
  local speed, speedFrom = readSpeed()
  local bind = GetBindLocation()
  local snap = {
    continent = continent, x = x, y = y,
    faction = UnitFactionGroup("player"), class = class, speed = speed,
    taxi = readTaxi(maps, continent),
    quests = readQuests(maps, continent),
    givers = givers(continent),
    hearth = bind and DB.binds[bind], hearthReady = hearthReady(),
    flightSpeed = DB.flight.seconds > 0 and DB.flight.yards / DB.flight.seconds or nil,
    flightTimes = DB.flightTimes,
  }
  return snap, speedFrom
end

-- Measuring: flights, hearthstone, quest givers --------------------------------------------
local pathYards = {} -- "a>b" -> yards, direct flights from the game tables
local function indexPaths()
  for _, p in ipairs(ns.RetailTaxi.paths) do pathYards[p[1] .. ">" .. p[2]] = p[3] end
end

local function nearestTaxiNode(x, y, continent)
  local best, bestD
  for id, n in pairs(ns.RetailTaxi.nodes) do
    if n[2] == continent then
      local d = (n[3] - x) ^ 2 + (n[4] - y) ^ 2
      if not bestD or d < bestD then best, bestD = id, d end
    end
  end
  return best, bestD and math.sqrt(bestD)
end

local flight -- {start = GetTime(), node} while on a taxi
local function onTaxiChange(onTaxi)
  local x, y, continent = playerPos()
  if not x then flight = nil; return end
  local node, d = nearestTaxiNode(x, y, continent)
  if onTaxi then
    flight = (d and d < 80) and { start = GetTime(), node = node } or nil
    return
  end
  if not flight or not d or d > 80 or node == flight.node then flight = nil; return end
  local seconds, key = GetTime() - flight.start, flight.node .. ">" .. node
  flight = nil
  local yards = pathYards[key]
  if not yards then return end -- several hops: no single path to measure against
  DB.flightTimes[key] = seconds
  DB.flight.yards, DB.flight.seconds = DB.flight.yards + yards, DB.flight.seconds + seconds
  out(("Timed the flight %s -> %s: %s (saved; flights now average %.1f yd/s)."):format(
      ns.RetailTaxi.nodes[tonumber(key:match("^(%d+)"))][1], ns.RetailTaxi.nodes[node][1], fmtTime(seconds),
      DB.flight.yards / DB.flight.seconds))
end

local function recordBind(why)
  local x, y, continent = playerPos()
  local name = GetBindLocation()
  if not x or not name then return end
  DB.binds[name] = { x = x, y = y, continent = continent, name = name }
  out(("Hearthstone point %s recorded (%s)."):format(name, why))
end

local hearthFrom -- position when a hearthstone cast finished
local function afterHearth()
  local x, y, continent = playerPos()
  if not hearthFrom or not x then return end
  local moved = continent ~= hearthFrom.continent or (x - hearthFrom.x) ^ 2 + (y - hearthFrom.y) ^ 2 > 100 ^ 2
  hearthFrom = nil
  if moved then recordBind("where your hearthstone landed") end
end

-- Planning ------------------------------------------------------------------------------------
local last -- the last build, for /ar places and /ar route names

local function build()
  local snap, info = snapshot()
  if not snap then out(info); return nil end
  local b = Retail.build(snap)
  b.snap, b.speedFrom = snap, info
  last = b
  return b
end

local function describeTravel(world, travel)
  local parts = {}
  for _, t in ipairs(travel) do
    local name = (t.mode == "hearth") and "hearthstone" or t.mode
    parts[#parts + 1] = ("|c%s%s|r to %s"):format(MODE_COLOR[t.mode] or "ffffffff", name, world.nodes[t.to].name)
  end
  if #parts == 0 then return "already here" end
  return table.concat(parts, ", ")
end

local CHAT_LIST = 25 -- the window shows this many stops; longer plans are also listed in chat

local function printPlan(b, plan)
  local w = b.world
  out(("%d stops, %s of travel (Atlas, %d rounds). The stops are in the AtlasRoute window, the route on your world map (M)."):format(
      #plan.order, fmtTime(plan.seconds), plan.rounds))
  if #plan.legs > CHAT_LIST then
    for k, leg in ipairs(plan.legs) do
      local s = leg.stop
      out(("%2d. [%s] %s  (%s)"):format(k, s.kind, w.nodes[s.node].name, fmtTime(leg.seconds)))
      out("     " .. describeTravel(w, leg.travel))
    end
  end
  if ns.View then
    ns.View.show(ns.View.model(w, plan, b.snap.continent, function(travel) return describeTravel(w, travel) end))
  end
  if #plan.unreachable > 0 then
    out(("%d stops can't be reached from here and were left out."):format(#plan.unreachable))
  end
  for _, n in ipairs(b.notes) do out("  note: " .. n) end
end

local runner = CreateFrame("Frame")
local job, jobBuild
local taxiState = false
runner:SetScript("OnUpdate", function()
  local onTaxi = UnitOnTaxi("player") and true or false
  if onTaxi ~= taxiState then taxiState = onTaxi; onTaxiChange(onTaxi) end
  if not job then return end
  local ok, res = coroutine.resume(job)
  if not ok then out("error: " .. tostring(res)); job = nil
  elseif coroutine.status(job) == "dead" then job = nil; if res then printPlan(jobBuild, res) end end
end)

local commands = {}

function commands.help()
  out("/ar plan | window | map | nearby [clear] | list | route <place> | places [text] | speed <yd/s>|auto | status")
end

function commands.window() ns.View.toggleWindow() end
function commands.map() ToggleWorldMap() end

function commands.plan()
  local b = build()
  if not b then return end
  if #b.quests == 0 then
    out("Nothing to plan on this continent: your quest log is empty here. Add quest givers with /ar nearby.")
    for _, n in ipairs(b.notes) do out("  note: " .. n) end
    return
  end
  out(("Planning %d quests from where you are (%s, %.1f yd/s %s, hearthstone: %s)..."):format(
      #b.quests, b.profile.faction or "?", b.profile.speed, b.speedFrom,
      b.profile.hearth and b.snap.hearth.name or (b.snap.hearth and "on cooldown" or "not recorded yet")))
  jobBuild = b
  job = coroutine.create(function()
    return AtlasPlan.plan(b.world, b.profile, b.start, b.quests, { yield = coroutine.yield })
  end)
end

function commands.nearby(rest)
  if trim(rest) == "clear" then DB.nearby = {}; out("Cleared the added quest givers."); return end
  calibrate()
  local maps, zone = regionMaps()
  if not maps then out("No map for where you are."); return end
  C_QuestLine.RequestQuestLinesForMap(zone)
  out("Reading the quest givers on this zone's map...")
  C_Timer.After(1.5, function()
    local offers = {}
    for _, ql in ipairs(C_QuestLine.GetAvailableQuestLines(zone) or {}) do offers[#offers + 1] = ql end
    for _, id in ipairs(C_QuestLine.GetForceVisibleQuests(zone) or {}) do
      local ql = C_QuestLine.GetQuestLineInfo(id, zone)
      if ql then offers[#offers + 1] = ql end
    end
    local added = 0
    for _, ql in ipairs(offers) do
      local id = ql.questID
      if not ql.isHidden and not DB.nearby[id] and not C_QuestLog.GetLogIndexForQuestID(id)
         and not C_QuestLog.IsQuestFlaggedCompleted(id) then
        local cont, x, y = toWorld(zone, ql.x, ql.y)
        if cont then
          DB.nearby[id] = { name = ql.questName, continent = cont, x = x, y = y }
          added = added + 1
        end
      end
    end
    out(("Added %d quest givers from the map. /ar plan includes them until you pick them up."):format(added))
  end)
end

function commands.list()
  local b = build()
  if not b then return end
  if #b.quests == 0 then out("No quests on this continent.") end
  for i, q in ipairs(b.quests) do
    local parts = {}
    if q.giver then parts[#parts + 1] = "pick up (map pin)" end
    for _, o in ipairs(q.objectives) do
      parts[#parts + 1] = o:match(":obj$") and "objective (quest log, live)" or "objective (game tables)"
    end
    if q.turnin then parts[#parts + 1] = "turn in" end
    out(("%d. %s: %s"):format(i, q.name, table.concat(parts, " > ")))
  end
  for _, n in ipairs(b.notes) do out("  note: " .. n) end
end

local function findPlace(world, text)
  text = trim(text or ""):lower()
  if text == "" then return nil end
  local prefix = {}
  for _, n in ipairs(world.nodes) do
    if n.kind == "ground" then
      local name = n.name:lower()
      if name == text then return n end
      if name:sub(1, #text) == text then prefix[#prefix + 1] = n end
    end
  end
  if #prefix == 1 then return prefix[1] end
  return nil, prefix
end

function commands.route(rest)
  local b = build()
  if not b then return end
  local to, cands = findPlace(b.world, rest)
  if not to then out(("Unknown or ambiguous place (%d matches). See /ar places."):format(cands and #cands or 0)); return end
  local t, legs = AtlasPlan.route(b.world, b.profile, b.start, to.id)
  if not t then out("No route."); return end
  out(("To %s: %s"):format(to.name, fmtTime(t)))
  out("  " .. describeTravel(b.world, legs))
end

function commands.places(rest)
  local b = last or build()
  if not b then return end
  local f = trim(rest or ""):lower()
  local names = {}
  for _, n in ipairs(b.world.nodes) do
    if n.kind == "ground" and n.id ~= "here" and (f == "" or n.name:lower():find(f, 1, true)) then
      names[#names + 1] = n.name .. ((n.taxi and b.world.byId["air:" .. n.id]) and " *" or "")
    end
  end
  out(table.concat(names, ", "))
  out("(* = flight point you have discovered)")
end

function commands.speed(rest)
  local v = trim(rest or ""):lower()
  if v == "auto" then DB.speed = nil; out("Ground speed: measured."); return end
  local n = tonumber(v)
  if not n or n <= 0 then out("Speed in yards/second (7 on foot), or /ar speed auto."); return end
  DB.speed = n
  out(("Ground speed %.1f yd/s."):format(n))
end

function commands.status()
  local b = build()
  if not b then return end
  local s = b.snap
  local _, build_, _, toc = GetBuildInfo()
  local nKnown, nTaxi = 0, 0
  for _, n in pairs(s.taxi) do nTaxi = nTaxi + 1; if n.known then nKnown = nKnown + 1 end end
  local nTimed = 0
  for _ in pairs(DB.flightTimes) do nTimed = nTimed + 1 end
  out(("Client %s (interface %s); game tables from build %s."):format(build_ or "?", toc or "?", ns.RetailTaxi.build))
  out(("Continent %d: %d flight points shown, %d discovered by you."):format(s.continent, nTaxi, nKnown))
  out(("Flights: %s; %d flights timed."):format(
      s.flightSpeed and ("%.1f yd/s, measured"):format(s.flightSpeed) or ("%.1f yd/s (434%% of run speed)"):format(Retail.TAXI_SPEED), nTimed))
  out(("Ground speed: %.1f yd/s (%s)."):format(s.speed, b.speedFrom))
  local bind = GetBindLocation()
  out(("Hearthstone: %s, %s, %s."):format(bind or "?", s.hearth and "point recorded" or "point not recorded yet (use it once, or bind at an inn)",
      s.hearthReady and "ready" or "not ready"))
  out(("Quest stops: %d from the live quest log or map, %d from the game tables."):format(b.sources.live, b.sources.tables))
end

SLASH_ATLASROUTE1 = "/ar"
SLASH_ATLASROUTE2 = "/atlasroute"
SlashCmdList.ATLASROUTE = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  local f = commands[(cmd or ""):lower()] or commands.help
  f(rest or "")
end
ns.commands = commands

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("HEARTHSTONE_BOUND")
events:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
events:SetScript("OnEvent", function(_, event, a1, _, a3)
  if event == "ADDON_LOADED" then
    if a1 ~= addonName then return end
    AtlasRouteDB = AtlasRouteDB or {}
    AtlasRouteDB.retail = AtlasRouteDB.retail or {}
    DB = AtlasRouteDB.retail
    DB.nearby = DB.nearby or {}
    DB.binds = DB.binds or {}
    DB.flightTimes = DB.flightTimes or {}
    DB.flight = DB.flight or { yards = 0, seconds = 0 }
    indexPaths()
  elseif event == "HEARTHSTONE_BOUND" then
    recordBind("you bound your hearthstone here")
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" and a1 == "player" and a3 == HEARTHSTONE_SPELL then
    local x, y, continent = playerPos()
    if x then
      hearthFrom = { x = x, y = y, continent = continent }
      C_Timer.After(5, afterHearth)
    end
  end
end)
