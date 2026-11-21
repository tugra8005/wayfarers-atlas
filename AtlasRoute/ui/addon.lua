-- In-game shell: slash commands, character profile from the WoW API, chat output.
-- The planning itself is in core/ and runs unchanged outside the game (tools/, tests/).
--
--   /ar                     help
--   /ar demo                load the sample quest log for your faction
--   /ar quest <a> > <b> > <c>   add a quest: giver > objective(s, comma-separated) > turn-in
--   /ar quest > > <c>       add an already accepted delivery quest (only the turn-in)
--   /ar list | clear | remove <n>
--   /ar plan                plan the tour from where you are
--   /ar route <place>       fastest route from where you are to a place
--   /ar from <place>        override "where you are" (default: matched from your zone)
--   /ar speed <yd/s>        7 on foot, 11.2 with a 60% mount, 14 with 100%
--   /ar places [text]       list known places
--   /ar flier on|off        Forever's Frequent Flier perk (+20% flight speed)
--   /ar beta on|off         also use routes only reported from the Forever beta
local addonName, ns = ...

local World, AtlasPlan = ns.World, ns.AtlasPlan
local world -- built on ADDON_LOADED

local MODE_COLOR = {
  walk = "ffffffff", fly = "ff66ccff", boat = "ff3399ff", zeppelin = "ffff9933",
  tram = "ffcccccc", portal = "ffcc66ff", teleport = "ffcc66ff", hearth = "ff66ff66",
  skyship = "ffffcc33", device = "ffff6666",
}

local function out(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99AtlasRoute|r " .. msg)
end

local function fmtTime(s)
  s = math.floor(s + 0.5)
  if s >= 3600 then return ("%dh %02dm"):format(math.floor(s / 3600), math.floor(s % 3600 / 60)) end
  return ("%dm %02ds"):format(math.floor(s / 60), s % 60)
end
ns.fmtTime = fmtTime

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Find a ground place by id, exact name, or unique name prefix (case-insensitive).
local function findPlace(text)
  text = trim(text or ""):lower()
  if text == "" then return nil end
  local prefix = {}
  for _, n in ipairs(world.nodes) do
    if n.kind == "ground" then
      if n.id == text or n.name:lower() == text then return n end
      if n.name:lower():sub(1, #text) == text then prefix[#prefix + 1] = n end
    end
  end
  if #prefix == 1 then return prefix[1] end
  return nil, prefix
end

local function profile()
  local db = AtlasRouteDB
  local _, class = UnitClass("player")
  local p = { faction = UnitFactionGroup("player"), class = class, speed = db.speed or 11.2,
              flySpeed = db.flier and 1.2 or 1, unconfirmed = db.beta or false }
  local function ready(start, duration) return not duration or duration <= 1.5 end -- 1.5 s = GCD
  -- Spells: known and not on cooldown.
  if IsSpellKnown then
    p.knows = function(id)
      if not IsSpellKnown(id) then return false end
      if GetSpellCooldown then return ready(GetSpellCooldown(id)) end
      return true
    end
  end
  -- Engineering devices in the bags and off cooldown.
  p.items = {}
  for _, t in ipairs(world.teleports) do
    if t.item and GetItemCount and GetItemCount(t.item) > 0
       and (not GetItemCooldown or ready(GetItemCooldown(t.item))) then
      p.items[t.item] = true
    end
  end
  local bind = GetBindLocation and GetBindLocation()
  if bind then
    local place = findPlace(bind)
    if not place then -- bind location is often a sub-zone inside a town: match by zone
      for _, n in ipairs(world.nodes) do
        if n.kind == "ground" and n.zone == bind then place = n; break end
      end
    end
    if place then p.hearth = place.id end
  end
  -- Hearthstone (item 6948) on cooldown: plan without it.
  if p.hearth and GetItemCooldown then
    local _, duration = GetItemCooldown(6948)
    if duration and duration > 1.5 then p.hearth = nil end -- 1.5 s = global cooldown
  end
  return p
end

local function startPlace()
  local db = AtlasRouteDB
  if db.from then return db.from end
  local zone = GetZoneText and GetZoneText()
  local sub = GetSubZoneText and GetSubZoneText()
  local place = sub and findPlace(sub)
  if place then return place.id end
  for _, n in ipairs(world.nodes) do
    if n.kind == "ground" and n.zone == zone then return n.id end
  end
  return nil
end

local function describeTravel(travel)
  local parts = {}
  for _, t in ipairs(travel) do
    local name = (t.mode == "teleport" or t.mode == "hearth") and (t.name or t.mode) or t.mode
    parts[#parts + 1] = ("|c%s%s|r to %s"):format(MODE_COLOR[t.mode] or "ffffffff", name, world.nodes[t.to].name)
  end
  if #parts == 0 then return "already here" end
  return table.concat(parts, ", ")
end

local function printPlan(plan)
  out(("%d stops, %s total (Atlas, %d rounds)"):format(#plan.order, fmtTime(plan.seconds), plan.rounds))
  if #plan.unreachable > 0 then
    out(("%d stops cannot be reached by this character and were left out."):format(#plan.unreachable))
  end
  for k, leg in ipairs(plan.legs) do
    local s = leg.stop
    out(("%2d. [%s] %s - %s  (%s)"):format(k, s.kind, s.name, world.nodes[s.node].name, fmtTime(leg.seconds)))
    out("     " .. describeTravel(leg.travel))
  end
end

-- Run the planner in a coroutine, a slice per frame, so a large exact search never
-- stalls the game.
local runner = CreateFrame("Frame")
local job
runner:SetScript("OnUpdate", function()
  if not job then return end
  local ok, res = coroutine.resume(job)
  if not ok then out("error: " .. tostring(res)); job = nil
  elseif coroutine.status(job) == "dead" then job = nil; if res then printPlan(res) end end
end)

local function plan()
  local from = startPlace()
  if not from then out("Can't tell where you are. Use /ar from <place>."); return end
  if #AtlasRouteDB.quests == 0 then out("No quests. Add some with /ar quest or /ar demo."); return end
  local prof = profile()
  out(("Planning from %s (%s%s, hearth: %s)..."):format(world.nodes[world:index(from)].name,
      prof.faction or "?", prof.class and ("/" .. prof.class) or "", prof.hearth or "none"))
  job = coroutine.create(function()
    return AtlasPlan.plan(world, prof, from, AtlasRouteDB.quests, { yield = coroutine.yield })
  end)
end
ns.plan = plan

local function parseQuest(rest)
  local parts = {}
  for piece in (rest .. ">"):gmatch("([^>]*)>") do parts[#parts + 1] = trim(piece) end
  local giverText, objText, turnText = parts[1] or "", parts[2] or "", parts[3] or ""
  local q = { objectives = {} }
  if giverText == "" then q.accepted = true
  else
    local p = findPlace(giverText); if not p then return nil, "unknown giver place: " .. giverText end
    q.giver = p.id
  end
  for o in objText:gmatch("[^,]+") do
    local p = findPlace(o); if not p then return nil, "unknown objective place: " .. o end
    q.objectives[#q.objectives + 1] = p.id
  end
  local p = findPlace(turnText); if not p then return nil, "unknown turn-in place: " .. turnText end
  q.turnin = p.id
  q.id = "q" .. (#AtlasRouteDB.quests + 1) .. "-" .. q.turnin
  q.name = "Quest " .. (#AtlasRouteDB.quests + 1)
  q.work = 180
  return q
end

local commands = {}
function commands.help()
  out("/ar demo | quest <giver> > <objectives> > <turn-in> | list | clear | remove <n> | plan | route <place> | from <place> | speed <yd/s> | places [text] | flier on|off | beta on|off")
end
function commands.demo()
  local prof = profile()
  local src = (prof.faction == "Horde") and ns.QuestData.horde or ns.QuestData.alliance
  AtlasRouteDB.quests = {}
  for i, q in ipairs(src) do AtlasRouteDB.quests[i] = q end
  out(("Loaded %d sample quests for %s."):format(#src, prof.faction or "Alliance"))
end
function commands.quest(rest)
  local q, err = parseQuest(rest)
  if not q then out(err); return end
  table.insert(AtlasRouteDB.quests, q)
  out("Added " .. q.name .. ".")
end
function commands.list()
  if #AtlasRouteDB.quests == 0 then out("No quests."); return end
  for i, q in ipairs(AtlasRouteDB.quests) do
    local objs = {}
    for _, o in ipairs(q.objectives or {}) do objs[#objs + 1] = world.nodes[world:index(o)].name end
    out(("%d. %s: %s > %s > %s"):format(i, q.name, q.giver and world.nodes[world:index(q.giver)].name or "(accepted)",
        table.concat(objs, ", "), world.nodes[world:index(q.turnin)].name))
  end
end
function commands.clear() AtlasRouteDB.quests = {}; out("Cleared.") end
function commands.remove(rest)
  local n = tonumber(rest)
  if n and AtlasRouteDB.quests[n] then table.remove(AtlasRouteDB.quests, n); out("Removed.") else out("No quest " .. tostring(rest)) end
end
commands.plan = plan
function commands.route(rest)
  local to, cands = findPlace(rest)
  if not to then out(("Unknown or ambiguous place (%d matches)."):format(cands and #cands or 0)); return end
  local from = startPlace()
  if not from then out("Can't tell where you are. Use /ar from <place>."); return end
  local t, legs = AtlasPlan.route(world, profile(), from, to.id)
  if not t then out("No route."); return end
  out(("%s -> %s: %s"):format(world.nodes[world:index(from)].name, to.name, fmtTime(t)))
  out("  " .. describeTravel(legs))
end
function commands.from(rest)
  if trim(rest) == "" then AtlasRouteDB.from = nil; out("Using your current zone."); return end
  local p = findPlace(rest)
  if not p then out("Unknown place."); return end
  AtlasRouteDB.from = p.id
  out("Starting from " .. p.name .. ".")
end
function commands.speed(rest)
  local v = tonumber(rest)
  if not v or v <= 0 then out("Speed in yards/second, e.g. 7, 11.2, 14."); return end
  AtlasRouteDB.speed = v
  out(("Ground speed %.1f yd/s."):format(v))
end
local function toggle(key, label)
  return function(rest)
    local v = trim(rest or ""):lower()
    if v == "on" then AtlasRouteDB[key] = true elseif v == "off" then AtlasRouteDB[key] = false
    else AtlasRouteDB[key] = not AtlasRouteDB[key] end
    out(label .. ": " .. (AtlasRouteDB[key] and "on" or "off"))
  end
end
commands.flier = toggle("flier", "Frequent Flier (+20% flight speed)")
commands.beta = toggle("beta", "Beta-only routes")

function commands.places(rest)
  local f = trim(rest or ""):lower()
  local names = {}
  for _, n in ipairs(world.nodes) do
    if n.kind == "ground" and (f == "" or n.name:lower():find(f, 1, true) or n.zone:lower():find(f, 1, true)) then
      names[#names + 1] = n.name
    end
  end
  out(table.concat(names, ", "))
end

SLASH_ATLASROUTE1 = "/ar"
SLASH_ATLASROUTE2 = "/atlasroute"
SlashCmdList.ATLASROUTE = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  local f = commands[(cmd or ""):lower()] or commands.help
  f(rest or "")
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, name)
  if name ~= addonName then return end
  AtlasRouteDB = AtlasRouteDB or {}
  AtlasRouteDB.quests = AtlasRouteDB.quests or {}
  world = ns.WorldData.build(World)
  ns.world = world
end)
