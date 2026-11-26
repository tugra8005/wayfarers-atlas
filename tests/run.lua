-- Addon tests. Usage: luajit tests/run.lua   (also under `luajit -joff`, closer to WoW)
-- The comparison algorithms have their own tests: luajit benchmark/tests.lua
local root = arg[0]:match("^(.*)/tests/") or "."
local ns = dofile(root .. "/tools/load.lua")(root)

local passed, failed = 0, 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then passed = passed + 1; print("ok   " .. name)
  else failed = failed + 1; print("FAIL " .. name .. "\n     " .. tostring(err)) end
end
local function eq(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
local function near(a, b, msg) if math.abs(a - b) > 1e-6 * math.max(1, math.abs(b)) then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
local function truthy(v, msg) if not v then error(msg or "expected true", 2) end end
local function read(p) local f = assert(io.open(p)); local s = f:read("*a"); f:close(); return s end

local FIX = root .. "/tests/fixtures/"
local fixtures = { "bbtas", "r_4_3_1", "r_10_8_2", "r_40_4_3", "b_100_10_1", "b_200_4_2" }

local function distinct(list) local s, n = {}, 0; for _, l in ipairs(list) do if not s[l] then s[l] = true; n = n + 1 end end; return n end
local function contiguous(g, labels)
  for i = 2, #labels do
    if g.edges[labels[i - 1]].dest ~= g.edges[labels[i]].source then return false, i end
  end
  return true
end

-- Atlas port ------------------------------------------------------------------------------
test("Lua Atlas prints the same test suite as Atlas.java", function()
  for _, f in ipairs(fixtures) do
    local g = ns.FSM.parse(read(FIX .. f .. ".fsm"))
    local suite = ns.Atlas.run(g)
    eq(suite, (read(FIX .. f .. ".java.txt"):gsub("%s+$", "")), f)
  end
end)

test("Atlas walks are contiguous", function()
  for _, f in ipairs(fixtures) do
    local g = ns.FSM.parse(read(FIX .. f .. ".fsm"))
    local _, p = ns.Atlas.run(g, true)
    truthy(contiguous(g, p), f)
  end
end)

test("Atlas.java drops the last edge, and that edge is then uncovered", function()
  for _, f in ipairs(fixtures) do
    local g = ns.FSM.parse(read(FIX .. f .. ".fsm"))
    local _, orig = ns.Atlas.run(g)
    local _, kept = ns.Atlas.run(g, true)
    eq(#kept, #orig + 1, f .. " length")
    eq(distinct(orig), distinct(kept) - 1, f .. " covered")
  end
end)

test("Atlas with weights covers every FSM edge with a contiguous walk from state 0", function()
  for _, f in ipairs(fixtures) do
    local g = ns.FSM.parse(read(FIX .. f .. ".fsm"))
    local r = ns.AtlasPlan.coverFSM(g, 0)
    -- the fixtures are not all strongly connected; Atlas covers what is reachable
    truthy(r.covered >= distinct(select(2, ns.Atlas.run(g, true))), f .. " covers less than Atlas.java")
    truthy(contiguous(g, r.path), f)
    eq(g.edges[r.path[1]].source, 0, f)
    local w = 0
    for _, l in ipairs(r.path) do w = w + g.edges[l].weight end
    near(w, r.weight, f)
  end
end)

-- The world and the Atlas planner ----------------------------------------------------------
local world = ns.ForeverMap.new():build()
local AP = ns.AtlasPlan
local A = { faction = "Alliance", speed = 11.2, hearth = "stormwind" }
local H = { faction = "Horde", speed = 11.2, hearth = "orgrimmar" }

local function legSum(legs) local s = 0; for _, l in ipairs(legs) do s = s + l.seconds end; return s end
local function modes(legs) local m = {}; for _, l in ipairs(legs) do m[#m + 1] = l.mode end; return table.concat(m, "+") end
local function uses(legs, mode, toName)
  for _, l in ipairs(legs) do
    if l.mode == mode and (not toName or world.nodes[l.to].name == toName) then return true end
  end
  return false
end
local function pick(list, ids)
  local r = {}
  for _, id in ipairs(ids) do
    local found
    for _, q in ipairs(list) do if q.id == id then found = q end end
    assert(found, "no sample quest with id " .. id)
    r[#r + 1] = found
  end
  return r
end
-- legs of a plan in order, as one list
local function allTravel(plan)
  local t = {}
  for _, leg in ipairs(plan.legs) do for _, x in ipairs(leg.travel) do t[#t + 1] = x end end
  return t
end
-- every leg starts where the previous one ended
local function chained(start, legs)
  local at = start
  for _, l in ipairs(legs) do
    if l.from ~= at then return false end
    at = l.to
  end
  return true, at
end

test("Routes arrive at the destination, legs chain and add up", function()
  local ids = { "raptorgrounds", "theramore", "nesingwary", "astranaar", "darnassus", "lakeshire", "valanaar", "gadgetzan" }
  for _, a in ipairs(ids) do
    for _, b in ipairs(ids) do
      if a ~= b then
        local t, legs = AP.route(world, A, a, b)
        truthy(t, a .. "->" .. b .. " unreachable")
        local ok, at = chained(world:index(a), legs)
        truthy(ok, a .. "->" .. b .. " legs do not chain")
        eq(world.nodes[at].id, b, a .. "->" .. b .. " ends elsewhere")
        near(legSum(legs), t, a .. "->" .. b)
      end
    end
  end
end)

test("The travel graph holds only what the character may use", function()
  for _, prof in ipairs({ A, H, { faction = "Horde", class = "MAGE", speed = 7 } }) do
    local g = AP.travelGraph(world, prof)
    for l = 1, g.m do
      local e = g.edges[l]
      if e.mode == "fly" or e.mode == "board" or e.mode == "boat" or e.mode == "zeppelin" then
        -- find the world edge it came from and check its gate
        for _, we in ipairs(world.adj[e.source]) do
          if we.to == e.dest and we.mode == e.mode then
            truthy(world:allowed(we, prof), prof.faction .. " got " .. e.mode .. " " .. world.nodes[e.source].id)
          end
        end
      end
      if e.mode == "teleport" then truthy(prof.class == "MAGE" or prof.class == "DRUID", "teleport for " .. tostring(prof.class)) end
    end
  end
end)

test("Mage teleports help mages; teleports are never cast in the air", function()
  local t1 = AP.route(world, { faction = "Alliance", speed = 11.2 }, "nesingwary", "astranaar")
  local t2, legs = AP.route(world, { faction = "Alliance", class = "MAGE", speed = 11.2 }, "nesingwary", "astranaar")
  truthy(t2 < t1, "mage should be faster")
  truthy(uses(legs, "teleport"), "mage route should teleport: " .. modes(legs))
  local g = AP.travelGraph(world, { faction = "Alliance", class = "MAGE", speed = 11.2, hearth = "stormwind" })
  for l = 1, g.m do
    local e = g.edges[l]
    if e.mode == "teleport" or e.mode == "hearth" then eq(world.nodes[e.source].kind, "ground") end
  end
end)

test("Walking never crosses between continents", function()
  for i = 1, #world.nodes do
    for _, e in ipairs(world.adj[i]) do
      if e.mode == "walk" then eq(world.nodes[e.from].continent, world.nodes[e.to].continent) end
    end
  end
end)

test("Flight network: Atlas flies every link with one connected walk", function()
  for _, prof in ipairs({ A, H, { faction = "Alliance", class = "MAGE", speed = 11.2 } }) do
    local start = prof.faction == "Horde" and "orgrimmar" or "stormwind"
    local r = AP.cover(world, prof, start)
    eq(r.covered, r.required, prof.faction)
    local at, w, flown = world:index(start), 0, {}
    for _, s in ipairs(r.steps) do
      eq(s.from, at, "walk breaks")
      at = s.to
      w = w + s.seconds
    end
    near(w, r.seconds)
  end
end)

test("Skyborne start: both factions reach Dalaran, only Horde takes the Skywatcher skyship", function()
  local tA, lA = AP.route(world, { faction = "Alliance", speed = 7 }, "valanaar", "stormwind")
  truthy(tA and uses(lA, "skyship", "Dalaran"), "Alliance from Valanaar: " .. modes(lA or {}))
  local _, lH = AP.route(world, { faction = "Horde", speed = 7 }, "valanaar", "thunderbluff")
  truthy(uses(lH, "skyship", "Skywatcher Plateau"), "Horde from Valanaar: " .. modes(lH))
  local _, lA2 = AP.route(world, { faction = "Alliance", speed = 7 }, "valanaar", "thunderbluff")
  truthy(not uses(lA2, "skyship", "Skywatcher Plateau"), "Alliance used the Horde skyship")
end)

test("Beta-only routes are used only when asked for", function()
  local base = { faction = "Alliance", speed = 11.2 }
  local beta = { faction = "Alliance", speed = 11.2, unconfirmed = true }
  local t1, l1 = AP.route(world, base, "dalaran", "stormwind")
  local t2, l2 = AP.route(world, beta, "dalaran", "stormwind")
  truthy(not uses(l1, "portal", "Stormwind City"), "portal used without the beta flag")
  truthy(uses(l2, "portal", "Stormwind City"), "portal not used with the beta flag: " .. modes(l2))
  truthy(t2 < t1)
  local _, lm = AP.route(world, { faction = "Horde", class = "MAGE", speed = 11.2 }, "orgrimmar", "dalaran")
  truthy(not uses(lm, "teleport", "Dalaran"), "beta Teleport: Dalaran used")
end)

test("Riverglades flight masters, Powderfuse boat and the one-way Menethil loop", function()
  local _, l = AP.route(world, A, "farholde", "thelsamar")
  eq(modes(l), "fly")
  local _, lh = AP.route(world, H, "rogmar", "kargath")
  eq(modes(lh), "fly")
  local _, lb = AP.route(world, { faction = "Horde", speed = 11.2 }, "steamwheedle", "powderfuse")
  eq(modes(lb), "boat")
  local noHearth = { faction = "Alliance", speed = 11.2 }
  local back = AP.route(world, noHearth, "auberdine", "menethil")
  local there = AP.route(world, noHearth, "menethil", "auberdine")
  truthy(there > back, "the loop should make Menethil -> Auberdine slower")
end)

test("Walled-off zones are entered only through their pass", function()
  local function regionOf(n) return n.region or n.continent end
  local passes = { ["taintedfoothills:everlook"] = true, ["everlook:taintedfoothills"] = true,
                   ["nighthaven:everlook"] = true, ["everlook:nighthaven"] = true,
                   ["shendralas:shadowprey"] = true, ["shadowprey:shendralas"] = true }
  for i = 1, #world.nodes do
    for _, e in ipairs(world.adj[i]) do
      local a, b = world.nodes[e.from], world.nodes[e.to]
      if e.mode == "walk" and regionOf(a) ~= regionOf(b) and a.continent == b.continent then
        local inner = { HYJAL = 1, MOONGLADE = 1, SHENDRALAS = 1 }
        if inner[regionOf(a)] or inner[regionOf(b)] then
          truthy(passes[a.id .. ":" .. b.id], "unexpected walk " .. a.id .. " -> " .. b.id)
        end
      end
    end
  end
end)

test("Druids: Teleport: Moonglade and the druid-only flight master", function()
  local tD, lD = AP.route(world, { faction = "Horde", class = "DRUID", speed = 11.2 }, "gadgetzan", "nighthaven")
  local tW = AP.route(world, { faction = "Horde", class = "WARRIOR", speed = 11.2 }, "gadgetzan", "nighthaven")
  truthy(uses(lD, "teleport", "Nighthaven"))
  truthy(tD < tW)
  local _, lW = AP.route(world, { faction = "Alliance", class = "WARRIOR", speed = 11.2 }, "ruttheran", "nighthaven")
  truthy(not uses(lW, "fly", "Nighthaven"), "non-druid landed at the druid flight master: " .. modes(lW))
end)

test("One-use teleports: each spent at most once, devices need the item", function()
  local shaman = { faction = "Horde", class = "SHAMAN", speed = 11.2, hearth = "orgrimmar",
                   items = { [18984] = true, [18986] = true } }
  eq(#AP.limited(world, shaman), 4, "hearth, Astral Recall, two devices")
  eq(#AP.limited(world, { faction = "Horde", class = "SHAMAN", hearth = "orgrimmar" }), 2)
  local _, legs = AP.route(world, shaman, "stromgarde", "gadgetzan")
  truthy(uses(legs, "device", "Gadgetzan"), "transporter not used: " .. modes(legs))
  for _, start in ipairs({ "undercity", "valanaar", "gadgetzan" }) do
    local plan = AP.plan(world, shaman, start, ns.QuestData.horde)
    local count = {}
    for _, t in ipairs(allTravel(plan)) do
      if t.mode == "hearth" or t.mode == "device" or t.name == "Astral Recall" then
        count[t.name] = (count[t.name] or 0) + 1
      end
    end
    for name, c in pairs(count) do eq(c, 1, start .. ": " .. name .. " uses") end
  end
end)

-- Quest tours -------------------------------------------------------------------------------
local function valid(plan)
  local pos = {}
  for k, i in ipairs(plan.order) do pos[i] = k end
  for k, i in ipairs(plan.order) do
    for _, p in ipairs(plan.stops[i].after) do
      if (pos[p] or math.huge) > k then return false, plan.stops[i].name .. " " .. plan.stops[i].kind end
    end
  end
  return true
end

test("Atlas tours visit every stop, in a valid order, along one connected walk", function()
  local cases = {
    { A, "ironforge", ns.QuestData.alliance },
    { H, "undercity", ns.QuestData.horde },
    { { faction = "Alliance", class = "MAGE", speed = 11.2, hearth = "stormwind" }, "darkshire", ns.QuestData.alliance },
    { { faction = "Horde", class = "DRUID", speed = 7 }, "thunderbluff", ns.QuestData.horde },
    { { faction = "Horde", class = "SHAMAN", speed = 11.2, hearth = "orgrimmar", items = { [18984] = true, [18986] = true } },
      "valanaar", ns.QuestData.horde },
  }
  for ci, c in ipairs(cases) do
    local plan = AP.plan(world, c[1], c[2], c[3])
    eq(#plan.order, #plan.stops, "case " .. ci .. " stops")
    eq(#plan.unreachable, 0, "case " .. ci .. " unreachable")
    truthy(valid(plan), "case " .. ci .. " order")
    -- legs chain from the start through every stop
    local at, total = world:index(c[2]), 0
    for _, leg in ipairs(plan.legs) do
      local ok, last = chained(at, leg.travel)
      truthy(ok, "case " .. ci .. ": travel to " .. leg.stop.name .. " does not chain")
      eq(last, leg.stop.node, "case " .. ci .. ": arrives elsewhere")
      at = leg.stop.node
      total = total + leg.seconds + leg.stop.work
    end
    near(total, plan.seconds, "case " .. ci .. " time")
  end
end)

test("Quest chains: Raising Spirits is picked up only after Hammerfall is handed in", function()
  for _, start in ipairs({ "undercity", "hammerfall", "orgrimmar" }) do
    local plan = AP.plan(world, H, start, pick(ns.QuestData.horde, { "raisingspirits", "hammerfall", "agony" }))
    local pos = {}
    for k, leg in ipairs(plan.legs) do pos[leg.stop.quest .. ":" .. leg.stop.kind] = k end
    truthy(pos["hammerfall:turnin"] < pos["raisingspirits:accept"], start)
  end
end)

test("Every sample quest is on the map and has its wiki page", function()
  for _, side in ipairs({ "alliance", "horde" }) do
    local stops = AP.stops(world, ns.QuestData[side])
    truthy(#stops > 0, side)
    for _, q in ipairs(ns.QuestData[side]) do truthy(q.wiki, q.id .. " has no wiki page") end
  end
end)

test("A stop the character cannot reach is reported, not silently dropped", function()
  -- Teldrassil is an island reached only by Alliance boats and the Alliance portal.
  local plan = AP.plan(world, { faction = "Horde", speed = 11.2 }, "orgrimmar",
                       { { id = "x", name = "Visit Darnassus", giver = "orgrimmar", turnin = "darnassus" } })
  eq(#plan.unreachable, 1)
  eq(plan.unreachable[1].kind, "turnin")
end)

-- In-game shell with a stubbed WoW API -----------------------------------------------------
test("Addon loads and plans with a stubbed WoW API", function()
  local chat = {}
  local frames = {}
  local env = setmetatable({
    DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m end },
    CreateFrame = function()
      local f = { scripts = {}, events = {} }
      function f:SetScript(k, fn) self.scripts[k] = fn end
      function f:RegisterEvent(e) self.events[e] = true end
      frames[#frames + 1] = f
      return f
    end,
    SlashCmdList = {},
    UnitClass = function() return "Mage", "MAGE" end,
    UnitFactionGroup = function() return "Alliance" end,
    GetBindLocation = function() return "Stormwind City" end,
    GetZoneText = function() return "Wetlands" end,
    GetSubZoneText = function() return "Menethil Harbor" end,
  }, { __index = _G })
  local addonNs = {}
  local toc = read(root .. "/AtlasRoute/AtlasRoute.toc")
  for line in toc:gmatch("[^\r\n]+") do
    if not line:match("^#") and line:match("%.lua") then
      local chunk = assert(loadfile(root .. "/AtlasRoute/" .. line:gsub("\\", "/")))
      setfenv(chunk, env)
      chunk("AtlasRoute", addonNs)
    end
  end
  truthy(not addonNs.Router and not addonNs.Tour and not addonNs.CPP and not addonNs.Coverage,
         "the addon must plan with Atlas only")
  for _, f in ipairs(frames) do
    if f.events.ADDON_LOADED then f.scripts.OnEvent(f, "ADDON_LOADED", "AtlasRoute") end
  end
  local slash = env.SlashCmdList.ATLASROUTE
  slash("demo")
  slash("quest Stormwind > > Theramore")
  slash("list")
  slash("plan")
  for _ = 1, 10000 do
    for _, f in ipairs(frames) do if f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.016) end end
  end
  slash("route Astranaar")
  local text = table.concat(chat, "\n")
  truthy(text:find("Loaded 8 sample quests"), "demo")
  truthy(text:find("Planning from Menethil Harbor %(Alliance/MAGE, hearth: stormwind%)"), "profile")
  truthy(text:find("stops, .- total %(Atlas"), "plan output:\n" .. text:sub(-800))
  truthy(text:find("Menethil Harbor %-> Astranaar"), "route")
  truthy(not text:find("error"), "error in output")
end)

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
