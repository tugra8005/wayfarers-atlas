-- Test suite. Usage: luajit tests/run.lua   (also runs under `luajit -joff`, closer to WoW)
local root = arg[0]:match("^(.*)/tests/") or "."
local ns = dofile(root .. "/tools/load.lua")(root)
local gen = dofile(root .. "/tools/gen_fsm.lua")

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

-- Chinese Postman -------------------------------------------------------------------------
-- Brute force: Dijkstra over (node, set of covered edges). Exact for small m.
local function bruteCPP(g, start)
  local full = 2 ^ g.m - 1
  local dist = { [start .. ":0"] = 0 }
  local heap = ns.Heap.new()
  heap:push(0, { start, 0 })
  while not heap:empty() do
    local d, s = heap:pop()
    local key = s[1] .. ":" .. s[2]
    if d <= dist[key] then
      if s[2] == full then return d end
      for _, l in ipairs(g.out[s[1]] or {}) do
        local mask = s[2]
        if math.floor(mask / 2 ^ l) % 2 == 0 then mask = mask + 2 ^ l end
        local e = g.edges[l]
        local nk = e.dest .. ":" .. mask
        if d + e.weight < (dist[nk] or math.huge) then
          dist[nk] = d + e.weight
          heap:push(d + e.weight, { e.dest, mask })
        end
      end
    end
  end
end

test("CPP matches brute force on small weighted graphs", function()
  local checked = 0
  for seed = 1, 40 do
    local states, inputs = 3 + seed % 3, 2 + seed % 2
    local g = ns.FSM.parse(gen(states, inputs, 2, seed, true))
    if g.m <= 14 then
      math.randomseed(seed)
      for l = 0, g.m - 1 do g.edges[l].weight = math.random(1, 9) end
      local c = ns.CPP.solve(g, 0)
      local b = bruteCPP(g, 0)
      if b then
        truthy(c, "cpp returned nil, seed " .. seed)
        near(c.weight, b, "seed " .. seed)
        checked = checked + 1
      end
    end
  end
  truthy(checked >= 20, "too few cases checked: " .. checked)
end)

test("CPP walk is contiguous, starts at 0, covers every edge, weight adds up", function()
  for _, f in ipairs(fixtures) do
    local g = ns.FSM.parse(read(FIX .. f .. ".fsm"))
    local c = ns.CPP.solve(g, 0)
    if c then
      truthy(contiguous(g, c.path), f)
      eq(g.edges[c.path[1]].source, 0, f)
      eq(distinct(c.path), g.m, f)
      local w = 0
      for _, l in ipairs(c.path) do w = w + g.edges[l].weight end
      near(w, c.weight, f)
    end
  end
end)

-- Weighted Atlas --------------------------------------------------------------------------
test("Weighted Atlas covers everything and is never cheaper than the optimum", function()
  for seed = 1, 25 do
    local g = ns.FSM.parse(gen(5 + seed, 2 + seed % 4, 3, 1000 + seed, true))
    math.randomseed(seed)
    for l = 0, g.m - 1 do g.edges[l].weight = math.random(1, 20) end
    local c = ns.CPP.solve(g, 0)
    local w = ns.Coverage.run(g, 0)
    if c then
      eq(w.covered, g.m, "seed " .. seed)
      truthy(w.weight >= c.weight - 1e-9, "beat the optimum, seed " .. seed)
      local labels = {}
      for _, s in ipairs(w.steps) do labels[#labels + 1] = s.edge end
      truthy(contiguous(g, labels), "seed " .. seed)
    end
  end
end)

test("Weighted Atlas uses a teleport to reach an otherwise unreachable part", function()
  -- 0 -> 1 -> 0 and an island 2 <-> 3 reachable only by a jump
  local g = ns.FSM.new()
  g:addEdge(0, 1, 0, 0, 1); g:addEdge(1, 0, 0, 0, 1)
  g:addEdge(2, 3, 0, 0, 1); g:addEdge(3, 2, 0, 0, 1)
  local without = ns.Coverage.run(g, 0)
  eq(without.covered, 2)
  local with = ns.Coverage.run(g, 0, { jumps = { { to = 2, cost = 5 } } })
  eq(with.covered, 4)
end)

test("Rural postman equals the exact CPP when every edge is required", function()
  for seed = 1, 15 do
    local g = ns.FSM.parse(gen(4 + seed, 2 + seed % 3, 3, 500 + seed, true))
    math.randomseed(seed)
    for l = 0, g.m - 1 do g.edges[l].weight = math.random(1, 20) end
    local c = ns.CPP.solve(g, 0)
    local r = ns.Coverage.rpp(g, 0)
    if c then near(r.weight, c.weight, "seed " .. seed); eq(r.covered, g.m) end
  end
end)

-- Router ----------------------------------------------------------------------------------
local world = ns.WorldData.build(ns.World)
local A = { faction = "Alliance", speed = 11.2, hearth = "stormwind" }
local H = { faction = "Horde", speed = 11.2, hearth = "orgrimmar" }

local function legSum(legs) local s = 0; for _, l in ipairs(legs) do s = s + l.seconds end; return s end

test("Route legs add up to the route time", function()
  for _, pair in ipairs({ { "raptorgrounds", "theramore" }, { "nesingwary", "astranaar" }, { "darnassus", "lakeshire" } }) do
    local t, legs = ns.Router.route(world, A, pair[1], pair[2], true)
    near(legSum(legs), t, pair[1] .. "->" .. pair[2])
  end
end)

test("Factions only use their own flight masters and transports", function()
  for _, prof in ipairs({ A, H }) do
    for _, pair in ipairs({ { "stromgarde", "thunderbluff" }, { "feathermoon", "undercity" }, { "southshore", "gadgetzan" } }) do
      local dist, prev, ctx = ns.Router.search(world, prof, world:index(pair[1]), true)
      local _, state = ns.Router.best(dist, ctx, world:index(pair[2]))
      local v = state
      while prev[v] do
        local e = prev[v].edge
        truthy(not e.faction or e.faction == prof.faction, prof.faction .. " used " .. tostring(e.mode) .. " gated " .. tostring(e.faction))
        v = prev[v].state
      end
    end
  end
end)

test("Mage teleports only for mages; hearthstone at most once", function()
  local t1 = ns.Router.route(world, { faction = "Alliance", speed = 11.2 }, "nesingwary", "astranaar")
  local t2, legs = ns.Router.route(world, { faction = "Alliance", class = "MAGE", speed = 11.2 }, "nesingwary", "astranaar")
  truthy(t2 < t1, "mage should be faster")
  local tele = 0
  for _, l in ipairs(legs) do if l.mode == "teleport" then tele = tele + 1 end end
  truthy(tele >= 1, "mage route should teleport")
  local _, hlegs = ns.Router.route(world, A, "nesingwary", "feathermoon", true)
  local h = 0
  for _, l in ipairs(hlegs) do if l.mode == "hearth" then h = h + 1 end end
  truthy(h <= 1, "hearth used " .. h .. " times")
end)

test("Hearthstone never makes a route slower", function()
  local ids = { "raptorgrounds", "theramore", "nesingwary", "astranaar", "uldaman", "mathystra", "gadgetzan" }
  for _, a in ipairs(ids) do
    for _, b in ipairs(ids) do
      if a ~= b then
        local without = ns.Router.route(world, A, a, b, false)
        local with = ns.Router.route(world, A, a, b, true)
        truthy(with <= without + 1e-9, a .. "->" .. b)
      end
    end
  end
end)

test("Walking never crosses between continents", function()
  for i = 1, #world.nodes do
    for _, e in ipairs(world.adj[i]) do
      if e.mode == "walk" then eq(world.nodes[e.from].continent, world.nodes[e.to].continent) end
    end
  end
end)

test("Map coverage walks are valid and cover every flight link", function()
  for _, prof in ipairs({ A, H, { faction = "Alliance", class = "MAGE", speed = 11.2 } }) do
    local g, jumps, req = ns.Coverage.fromWorld(world, prof)
    local start = world:index(prof.faction == "Horde" and "orgrimmar" or "stormwind")
    for _, res in ipairs({ ns.Coverage.run(g, start, { jumps = jumps }), ns.Coverage.rpp(g, start, { jumps = jumps }) }) do
      eq(res.covered, req)
      local at, w = start, 0
      for _, s in ipairs(res.steps) do
        if s.edge then
          eq(g.edges[s.edge].source, at, "walk breaks")
          at = g.edges[s.edge].dest
          w = w + g.edges[s.edge].weight
        else
          truthy(world.nodes[at].kind == "ground", "teleport cast while flying")
          at = jumps[s.jump].to
          w = w + jumps[s.jump].cost
        end
      end
      near(w, res.weight)
      truthy(res.weight >= ns.Coverage.lowerBound(g) - 1e-9)
    end
  end
end)

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

-- Forever additions ----------------------------------------------------------------------
local function modes(legs) local m = {}; for _, l in ipairs(legs) do m[#m + 1] = l.mode end; return table.concat(m, "+") end
local function uses(legs, mode, toName)
  for _, l in ipairs(legs) do
    if l.mode == mode and (not toName or world.nodes[l.to].name == toName) then return true end
  end
  return false
end

test("Skyborne start: both factions reach Dalaran, only Horde takes the Skywatcher skyship", function()
  local tA, lA = ns.Router.route(world, { faction = "Alliance", speed = 7 }, "valanaar", "stormwind")
  truthy(tA and uses(lA, "skyship", "Dalaran"), "Alliance from Valanaar: " .. modes(lA or {}))
  local _, lH = ns.Router.route(world, { faction = "Horde", speed = 7 }, "valanaar", "thunderbluff")
  truthy(uses(lH, "skyship", "Skywatcher Plateau"), "Horde from Valanaar: " .. modes(lH))
  local _, lA2 = ns.Router.route(world, { faction = "Alliance", speed = 7 }, "valanaar", "thunderbluff")
  truthy(not uses(lA2, "skyship", "Skywatcher Plateau"), "Alliance used the Horde skyship")
end)

test("Beta-only routes are used only when asked for", function()
  local base = { faction = "Alliance", speed = 11.2 }
  local beta = { faction = "Alliance", speed = 11.2, unconfirmed = true }
  local t1, l1 = ns.Router.route(world, base, "dalaran", "stormwind")
  local t2, l2 = ns.Router.route(world, beta, "dalaran", "stormwind")
  truthy(not uses(l1, "portal", "Stormwind City"), "portal used without the beta flag")
  truthy(uses(l2, "portal", "Stormwind City"), "portal not used with the beta flag: " .. modes(l2))
  truthy(t2 < t1)
  local mage = { faction = "Horde", class = "MAGE", speed = 11.2 }
  local _, lm = ns.Router.route(world, mage, "orgrimmar", "dalaran")
  truthy(not uses(lm, "teleport", "Dalaran"), "beta Teleport: Dalaran used")
end)

test("Riverglades flight masters, Powderfuse boat and Menethil loop", function()
  local _, l = ns.Router.route(world, A, "farholde", "thelsamar")
  eq(modes(l), "fly")
  local _, lh = ns.Router.route(world, H, "rogmar", "kargath")
  eq(modes(lh), "fly")
  local _, lb = ns.Router.route(world, { faction = "Horde", speed = 11.2 }, "steamwheedle", "powderfuse")
  eq(modes(lb), "boat")
  -- the Menethil loop is one-way: Auberdine -> Menethil is direct, Menethil -> Auberdine goes round
  local back = ns.Router.route(world, A, "auberdine", "menethil", false)
  local there = ns.Router.route(world, A, "menethil", "auberdine", false)
  truthy(there > back, "loop should make Menethil -> Auberdine slower")
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
  local tD, lD = ns.Router.route(world, { faction = "Horde", class = "DRUID", speed = 11.2 }, "gadgetzan", "nighthaven")
  local tW = ns.Router.route(world, { faction = "Horde", class = "WARRIOR", speed = 11.2 }, "gadgetzan", "nighthaven")
  truthy(uses(lD, "teleport", "Nighthaven"))
  truthy(tD < tW)
  local _, lW = ns.Router.route(world, { faction = "Alliance", class = "WARRIOR", speed = 11.2 }, "ruttheran", "nighthaven")
  truthy(not uses(lW, "fly", "Nighthaven"), "non-druid landed at the druid flight master: " .. modes(lW))
end)

test("Several one-use teleports: each spent at most once, devices need the item", function()
  local shaman = { faction = "Horde", class = "SHAMAN", speed = 11.2, hearth = "orgrimmar",
                   items = { [18984] = true, [18986] = true } }
  local ctx = ns.Router.context(world, shaman)
  eq(#ctx.L, 4, "hearth, Astral Recall, two devices")
  eq(#ns.Router.context(world, { faction = "Horde", class = "SHAMAN", hearth = "orgrimmar" }).L, 2)
  local _, legs = ns.Router.route(world, shaman, "stromgarde", "gadgetzan")
  truthy(uses(legs, "device", "Gadgetzan"), "transporter not used: " .. modes(legs))
  local plan = ns.Tour.plan(world, shaman, "undercity", pick(ns.QuestData.horde, { "hunting", "returntb", "agony", "gromgol" }))
  local count = {}
  for _, leg in ipairs(plan.legs) do
    for _, t in ipairs(leg.travel) do
      if t.mode == "hearth" or t.mode == "device" or (t.name == "Astral Recall") then
        count[t.name] = (count[t.name] or 0) + 1
      end
    end
  end
  for name, c in pairs(count) do truthy(c == 1, name .. " used " .. c .. " times") end
end)

-- Tour ------------------------------------------------------------------------------------
local function permutations(n, fn)
  local a, used = {}, {}
  local function rec(k)
    if k > n then fn(a); return end
    for i = 1, n do
      if not used[i] then used[i] = true; a[k] = i; rec(k + 1); used[i] = false end
    end
  end
  rec(1)
end


test("Exact tour equals brute force over all orders (with precedence and hearthstone)", function()
  local cases = {
    { A, "ironforge", pick(ns.QuestData.alliance, { "plea", "jameshyal", "barrensport" }) },
    { A, "stormwind", pick(ns.QuestData.alliance, { "nightwatch", "jameshyal", "ironband" }) },
    { H, "orgrimmar", pick(ns.QuestData.horde, { "hammerfall", "raisingspirits", "returntb" }) },
    { { faction = "Horde", class = "MAGE", speed = 7 }, "crossroads", pick(ns.QuestData.horde, { "hunting", "returntb", "hammerfall" }) },
    { { faction = "Horde", class = "SHAMAN", speed = 11.2, hearth = "orgrimmar", items = { [18984] = true, [18986] = true } },
      "undercity", pick(ns.QuestData.horde, { "hunting", "agony", "hillsbrad" }) },
  }
  for ci, c in ipairs(cases) do
    local plan = ns.Tour.plan(world, c[1], c[2], c[3], { method = "exact" })
    local stops = plan.stops
    local best = math.huge
    permutations(#stops, function(order)
      if ns.Tour.feasible(order, stops) then
        local cost = ns.Tour.orderCost(plan.matrices, order, stops)
        if cost < best then best = cost end
      end
    end)
    near(plan.seconds, best, "case " .. ci)
  end
end)

test("Quest chains: Raising Spirits is picked up only after Hammerfall is handed in", function()
  for _, m in ipairs({ "exact", "heuristic" }) do
    local plan = ns.Tour.plan(world, H, "undercity", pick(ns.QuestData.horde, { "raisingspirits", "hammerfall", "agony" }), { method = m })
    local pos = {}
    for k, leg in ipairs(plan.legs) do pos[leg.stop.quest .. ":" .. leg.stop.kind] = k end
    truthy(pos["hammerfall:turnin"] < pos["raisingspirits:accept"], m)
  end
end)

test("Every sample quest names places on the map", function()
  for _, side in ipairs({ "alliance", "horde" }) do
    local stops = ns.Tour.stops(world, ns.QuestData[side])
    truthy(#stops > 0, side)
    for _, q in ipairs(ns.QuestData[side]) do truthy(q.wiki, q.id .. " has no wiki page") end
  end
end)

test("Tour orders respect accept -> objective -> turn-in", function()
  for _, m in ipairs({ "exact", "heuristic" }) do
    local plan = ns.Tour.plan(world, A, "ironforge", pick(ns.QuestData.alliance, { "nightwatch", "northfold", "nobledeaths", "plea" }), { method = m })
    truthy(ns.Tour.feasible(plan.order, plan.stops), m)
    eq(#plan.order, #plan.stops, m)
  end
end)

test("Heuristic is never better than exact", function()
  local plan1 = ns.Tour.plan(world, A, "menethil", pick(ns.QuestData.alliance, { "jameshyal", "northfold", "badlandsrun", "plea", "nightwatch" }), { method = "exact" })
  local plan2 = ns.Tour.plan(world, A, "menethil", pick(ns.QuestData.alliance, { "jameshyal", "northfold", "badlandsrun", "plea", "nightwatch" }), { method = "heuristic" })
  truthy(plan2.seconds >= plan1.seconds - 1e-9)
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
  truthy(text:find("stops, .- total"), "plan output:\n" .. text:sub(-800))
  truthy(text:find("Menethil Harbor %-> Astranaar"), "route")
  truthy(not text:find("error"), "error in output")
end)

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
