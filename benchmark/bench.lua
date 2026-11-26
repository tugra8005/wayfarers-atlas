-- How close Atlas gets. The addon plans with Atlas only (core/atlasplan.lua); the other
-- methods here (benchmark/) are used only as yardsticks.
-- Usage: luajit benchmark/bench.lua [fsm|weighted|map|tour|routes|all]
local root = arg[0]:match("^(.*)/benchmark/") or "."
local ns = dofile(root .. "/benchmark/load.lua")(root)
local gen = dofile(root .. "/tools/gen_fsm.lua")
local which = arg[1] or "all"
local clock = os.clock

local function coveredBy(labels)
  local seen, n = {}, 0
  for _, l in ipairs(labels) do if not seen[l] then seen[l] = true; n = n + 1 end end
  return n
end

if which == "fsm" or which == "all" then
  print("## Test FSMs, unit weights: walk length / optimum (open Chinese Postman)")
  print("states inputs edges | Atlas.java  covered | Atlas (ours)  covered |  ms Atlas.java  ms ours")
  for _, cfg in ipairs({ {10,3}, {10,8}, {50,4}, {50,10}, {100,10}, {200,10} }) do
    local a, ac, o, oc, c, m, n, ta, to = 0, 0, 0, 0, 0, 0, 0, 0, 0
    for seed = 1, 5 do
      local g = ns.FSM.parse(gen(cfg[1], cfg[2], 4, seed * 7919 + cfg[1], true))
      local cpp = ns.CPP.solve(g, 0)
      if cpp then
        local t = clock(); local _, p = ns.Atlas.run(g); ta = ta + clock() - t
        t = clock(); local r = ns.AtlasPlan.coverFSM(g, 0); to = to + clock() - t
        n = n + 1; m = m + g.m; c = c + cpp.length
        a = a + #p; ac = ac + coveredBy(p)
        o = o + r.length; oc = oc + r.covered
      end
    end
    print(("%6d %6d %5d | %10.3f %7.1f%% | %12.3f %7.1f%% | %12.0f %8.0f"):format(
      cfg[1], cfg[2], m / n, a / c, 100 * ac / m, o / c, 100 * oc / m, 1000 * ta / n, 1000 * to / n))
  end
end

if which == "weighted" or which == "all" then
  print("\n## Test FSMs, weights 1-20: walk weight / optimum")
  print("states inputs | Atlas.java (keeps last edge) | Atlas (ours)")
  for _, cfg in ipairs({ {10,4}, {50,4}, {50,10}, {100,10} }) do
    local a, o, c = 0, 0, 0
    for seed = 1, 5 do
      local g = ns.FSM.parse(gen(cfg[1], cfg[2], 4, seed * 104729 + cfg[1], true))
      math.randomseed(seed)
      for l = 0, g.m - 1 do g.edges[l].weight = math.random(1, 20) end
      local cpp = ns.CPP.solve(g, 0)
      if cpp then
        local _, p = ns.Atlas.run(g, true)
        a = a + ns.Atlas.stats(g, p).weight
        o = o + ns.AtlasPlan.coverFSM(g, 0).weight
        c = c + cpp.weight
      end
    end
    print(("%6d %6d | %28.3f | %12.3f"):format(cfg[1], cfg[2], a / c, o / c))
  end
end

if which == "map" or which == "all" then
  print("\n## Game map: fly every flight link (both directions), seconds")
  print("character      links | Atlas.java (unit steps) | Atlas (ours)            | Rural Postman | lower bound")
  local world = ns.ForeverMap.new():build()
  for _, prof in ipairs({
    { label = "Alliance",      faction = "Alliance", speed = 11.2, start = "stormwind" },
    { label = "Alliance mage", faction = "Alliance", class = "MAGE", speed = 11.2, start = "stormwind" },
    { label = "Horde",         faction = "Horde", speed = 11.2, start = "orgrimmar" },
    { label = "Horde mage",    faction = "Horde", class = "MAGE", speed = 11.2, start = "orgrimmar" },
  }) do
    -- Atlas.java on the travel graph, every edge one step
    local tg = ns.AtlasPlan.travelGraph(world, prof)
    local fsm, first = ns.FSM.new(), nil
    local s = world:index(prof.start)
    for l = 1, tg.m do
      local e = tg.edges[l]
      local fl = fsm:addEdge(e.source, e.dest, 0, 0, e.weight)
      fsm.edges[fl].mode = e.mode
      if e.source == s and not first then first = fl end
    end
    local p = ns.Atlas.longestPath(fsm, first)
    local aw, seen, ac, lb = 0, {}, 0, 0
    for _, l in ipairs(p) do
      aw = aw + fsm.edges[l].weight
      if fsm.edges[l].mode == "fly" and not seen[l] then seen[l] = true; ac = ac + 1 end
    end
    for l = 0, fsm.m - 1 do if fsm.edges[l].mode == "fly" then lb = lb + fsm.edges[l].weight end end
    local t0 = clock()
    local ours = ns.AtlasPlan.cover(world, prof, prof.start)
    local tOurs = clock() - t0
    local g, jumps = ns.Coverage.fromWorld(world, prof)
    local rpp = ns.Coverage.rpp(g, s, { jumps = jumps })
    print(("%-14s %5d | %7.0f (%d/%d) | %6.0f (%3.0f ms) %.2fx | %6.0f %.2fx | %6.0f"):format(
      prof.label, ours.required, aw, ac, ours.required, ours.seconds, tOurs * 1000, ours.seconds / lb,
      rpp.weight, rpp.weight / lb, lb))
  end
end

if which == "tour" or which == "all" then
  print("\n## Quest tours: Atlas vs the exact Held-Karp tour (random subsets of the real quest logs)")
  print("stops | runs | Atlas = exact | mean Atlas/exact | worst | Atlas ms | exact ms")
  local world = ns.ForeverMap.new():build()
  local logs = {
    { faction = "Alliance", quests = ns.QuestData.alliance, starts = { "ironforge", "stormwind", "menethil", "auberdine" }, hearth = "stormwind" },
    { faction = "Horde", quests = ns.QuestData.horde, starts = { "orgrimmar", "undercity", "crossroads" }, hearth = "orgrimmar" },
  }
  local buckets = {}
  math.randomseed(42)
  for run = 1, 160 do
    local L = logs[(run % 2) + 1]
    local pool = {}
    for _, q in ipairs(L.quests) do if math.random() < 0.55 then pool[#pool + 1] = q end end
    local prof = { faction = L.faction, speed = 11.2, hearth = (math.random() < 0.7) and L.hearth or nil,
                   class = (math.random() < 0.3) and "MAGE" or nil }
    local start = L.starts[math.random(#L.starts)]
    local n = #ns.Tour.stops(world, pool)
    if n >= 3 and ns.Tour.exactAffordable(n, ns.Router.context(world, prof).S) then
      local t = clock(); local e = ns.Tour.plan(world, prof, start, pool, { method = "exact" }); local te = clock() - t
      t = clock(); local a = ns.AtlasPlan.plan(world, prof, start, pool); local ta = clock() - t
      local b = buckets[n] or { runs = 0, te = 0, ta = 0, eq = 0, ratio = 0, worst = 0 }
      buckets[n] = b
      local r = a.seconds / e.seconds
      if r < 1 - 1e-9 then print("!! Atlas beat the exact tour", n, a.seconds, e.seconds) end
      b.runs = b.runs + 1; b.te = b.te + te; b.ta = b.ta + ta; b.ratio = b.ratio + r
      if r < 1 + 1e-9 then b.eq = b.eq + 1 end
      if r > b.worst then b.worst = r end
    end
  end
  for n = 3, 16 do
    local b = buckets[n]
    if b then
      print(("%5d | %4d | %6d/%-4d | %16.3f | %5.3f | %8.1f | %8.1f"):format(n, b.runs, b.eq, b.runs, b.ratio / b.runs, b.worst, 1000 * b.ta / b.runs, 1000 * b.te / b.runs))
    end
  end
  print("\nFull logs (20 stops), Atlas vs the Or-opt heuristic (Held-Karp is too slow at 20):")
  for _, c in ipairs({
    { "Alliance from Ironforge", { faction = "Alliance", speed = 11.2, hearth = "stormwind" }, "ironforge", ns.QuestData.alliance },
    { "Horde from Undercity", { faction = "Horde", speed = 11.2, hearth = "orgrimmar" }, "undercity", ns.QuestData.horde },
    { "Alliance mage from Darkshire", { faction = "Alliance", class = "MAGE", speed = 11.2, hearth = "stormwind" }, "darkshire", ns.QuestData.alliance },
    { "Horde shaman from Valanaar", { faction = "Horde", class = "SHAMAN", speed = 11.2, hearth = "orgrimmar", items = { [18984] = true, [18986] = true } }, "valanaar", ns.QuestData.horde },
  }) do
    local a = ns.AtlasPlan.plan(world, c[2], c[3], c[4])
    local h = ns.Tour.plan(world, c[2], c[3], c[4], { method = "heuristic" })
    print(("  %-30s Atlas %5.0f s | Or-opt %5.0f s | %.2fx"):format(c[1], a.seconds, h.seconds, a.seconds / h.seconds))
  end
end

if which == "routes" or which == "all" then
  print("\n## Single routes: Atlas vs Dijkstra (exact), every pair of 12 places")
  local world = ns.ForeverMap.new():build()
  local ids = { "raptorgrounds", "theramore", "nesingwary", "astranaar", "darnassus", "lakeshire",
                "uldaman", "gadgetzan", "strahnbrad", "ratchet", "valanaar", "everlook" }
  for _, prof in ipairs({ { label = "Alliance", faction = "Alliance", speed = 11.2, hearth = "stormwind" },
                          { label = "Horde mage", faction = "Horde", class = "MAGE", speed = 11.2, hearth = "orgrimmar" } }) do
    local n, sum, eqn, worst = 0, 0, 0, 1
    for _, a in ipairs(ids) do
      for _, b in ipairs(ids) do
        if a ~= b then
          local ta = ns.AtlasPlan.route(world, prof, a, b)
          local td = ns.Router.route(world, prof, a, b, true)
          if ta and td then
            local r = ta / td
            n = n + 1; sum = sum + r
            if r < 1 + 1e-9 then eqn = eqn + 1 end
            if r > worst then worst = r end
          end
        end
      end
    end
    print(("  %-11s %d pairs | same as exact %d | mean %.3f | worst %.2f"):format(prof.label, n, eqn, sum / n, worst))
  end
end
