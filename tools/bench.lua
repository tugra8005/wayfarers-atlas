-- Benchmarks for the report. Usage: luajit tools/bench.lua [fsm|weighted|map|tour|all]
local root = arg[0]:match("^(.*)/tools/") or "."
local ns = dofile(root .. "/tools/load.lua")(root)
local gen = dofile(root .. "/tools/gen_fsm.lua")
local which = arg[1] or "all"

local function clock() return os.clock() end
local function coveredBy(g, labels)
  local seen, n = {}, 0
  for _, l in ipairs(labels) do if not seen[l] then seen[l] = true; n = n + 1 end end
  return n
end
local function stepsLabels(steps)
  local r = {}
  for _, s in ipairs(steps) do if s.edge then r[#r + 1] = s.edge end end
  return r
end

if which == "fsm" or which == "all" then
  print("## Unit weights: original Atlas vs weighted Atlas vs optimal (open CPP)")
  print("states inputs edges | atlas len cov  ms | atlas+last cov | w-atlas len cov ms | cpp len ms | atlas/cpp w-atlas/cpp")
  for _, cfg in ipairs({ {10,3}, {10,8}, {50,4}, {50,10}, {100,10}, {200,10} }) do
    local agg = { a = 0, ac = 0, al = 0, alc = 0, w = 0, wc = 0, c = 0, ta = 0, tw = 0, tc = 0, m = 0, n = 0, aok = 0, wok = 0 }
    for seed = 1, 5 do
      local g = ns.FSM.parse(gen(cfg[1], cfg[2], 4, seed * 7919 + cfg[1], true))
      local t = clock(); local _, p = ns.Atlas.run(g); agg.ta = agg.ta + clock() - t
      local _, pk = ns.Atlas.run(g, true)
      t = clock(); local w = ns.Coverage.run(g, 0); agg.tw = agg.tw + clock() - t
      t = clock(); local c = ns.CPP.solve(g, 0); agg.tc = agg.tc + clock() - t
      if c then
        agg.n = agg.n + 1
        agg.m = agg.m + g.m
        agg.a = agg.a + #p; agg.ac = agg.ac + coveredBy(g, p)
        agg.al = agg.al + #pk; agg.alc = agg.alc + coveredBy(g, pk)
        agg.w = agg.w + w.length; agg.wc = agg.wc + w.covered
        agg.c = agg.c + c.length
        if coveredBy(g, p) == g.m then agg.aok = agg.aok + 1 end
        if w.covered == g.m then agg.wok = agg.wok + 1 end
      end
    end
    local n = agg.n
    print(("%6d %6d %5d | %5.0f %5.1f%% %4.0f | %5.1f%% | %5.0f %5.1f%% %4.0f | %5.0f %5.0f | %.3f %.3f   (full cover: atlas %d/%d, w-atlas %d/%d)"):format(
      cfg[1], cfg[2], agg.m / n, agg.a / n, 100 * agg.ac / agg.m, 1000 * agg.ta / n,
      100 * agg.alc / agg.m, agg.w / n, 100 * agg.wc / agg.m, 1000 * agg.tw / n,
      agg.c / n, 1000 * agg.tc / n, agg.a / agg.c, agg.w / agg.c, agg.aok, n, agg.wok, n))
  end
end

if which == "weighted" or which == "all" then
  print("\n## Random weights 1-20: total weight of the walk (only covering walks compared)")
  print("states inputs | atlas weight (cov) | w-atlas weight | cpp weight | atlas/cpp w-atlas/cpp")
  for _, cfg in ipairs({ {10,4}, {50,4}, {50,10}, {100,10} }) do
    local A, W, C, cov, cnt = 0, 0, 0, 0, 0
    for seed = 1, 5 do
      local g = ns.FSM.parse(gen(cfg[1], cfg[2], 4, seed * 104729 + cfg[1], true))
      math.randomseed(seed)
      for l = 0, g.m - 1 do g.edges[l].weight = math.random(1, 20) end
      local _, p = ns.Atlas.run(g, true)
      local s = ns.Atlas.stats(g, p)
      local w = ns.Coverage.run(g, 0)
      local c = ns.CPP.solve(g, 0)
      if c then
        cnt = cnt + 1
        A = A + s.weight; W = W + w.weight; C = C + c.weight; cov = cov + s.covered / s.total
      end
    end
    print(("%6d %6d | %8.0f (%5.1f%%) | %8.0f | %8.0f | %.3f %.3f"):format(cfg[1], cfg[2], A / cnt, 100 * cov / cnt, W / cnt, C / cnt, A / C, W / C))
  end
end

if which == "map" or which == "all" then
  print("\n## Game map: ride every flight connection (both directions), time in seconds")
  local world = ns.WorldData.build(ns.World)
  for _, prof in ipairs({
    { label = "Alliance",      faction = "Alliance", speed = 11.2, start = "stormwind" },
    { label = "Alliance mage", faction = "Alliance", class = "MAGE", speed = 11.2, start = "stormwind" },
    { label = "Horde",         faction = "Horde", speed = 11.2, start = "orgrimmar" },
    { label = "Horde mage",    faction = "Horde", class = "MAGE", speed = 11.2, start = "orgrimmar" },
  }) do
    local g, jumps, req = ns.Coverage.fromWorld(world, prof)
    local s = world:index(prof.start)
    -- original Atlas from the first edge leaving the start
    local first = g.out[s][1]
    local p = ns.Atlas.longestPath(g, first, true)
    local seen, aw, ac = {}, 0, 0
    for _, l in ipairs(p) do
      aw = aw + g.edges[l].weight
      if g.edges[l].required and not seen[l] then seen[l] = true; ac = ac + 1 end
    end
    local noJ = ns.Coverage.run(g, s)
    local withJ = ns.Coverage.run(g, s, { jumps = jumps })
    local lb = ns.Coverage.lowerBound(g)
    local t0 = clock()
    local r = ns.Coverage.rpp(g, s, { jumps = jumps })
    local tr = clock() - t0
    print(("%-14s links %3d | atlas %3d/%d, %6.0f s | w-atlas %3d/%d, %6.0f s | +tele %6.0f s | rpp %3d/%d, %6.0f s (%3.0f ms) | lower bound %6.0f s"):format(
      prof.label, req, ac, req, aw, noJ.covered, req, noJ.weight, withJ.weight, r.covered, req, r.weight, 1000 * tr, lb))
  end
end

if which == "tour" or which == "all" then
  print("\n## Quest tours: exact Held-Karp vs heuristic (random subsets of the sample logs)")
  local world = ns.WorldData.build(ns.World)
  local logs = {
    { faction = "Alliance", quests = ns.QuestData.alliance, starts = { "ironforge", "stormwind", "menethil", "auberdine" }, hearth = "stormwind" },
    { faction = "Horde", quests = ns.QuestData.horde, starts = { "orgrimmar", "undercity", "crossroads" }, hearth = "orgrimmar" },
  }
  print("stops | runs | exact ms | heur ms | heuristic = exact | mean gap | worst gap")
  local buckets = {}
  math.randomseed(42)
  for run = 1, 120 do
    local L = logs[(run % 2) + 1]
    local pool = {}
    for _, q in ipairs(L.quests) do if math.random() < 0.6 then pool[#pool + 1] = q end end
    local prof = { faction = L.faction, speed = 11.2, hearth = (math.random() < 0.7) and L.hearth or nil,
                   class = (math.random() < 0.3) and "MAGE" or nil }
    local start = L.starts[math.random(#L.starts)]
    local n = #ns.Tour.stops(world, pool)
    if n >= 3 and n <= ns.Tour.EXACT_LIMIT then
      local t = clock(); local e = ns.Tour.plan(world, prof, start, pool, { method = "exact" }); local te = clock() - t
      t = clock(); local h = ns.Tour.plan(world, prof, start, pool, { method = "heuristic" }); local th = clock() - t
      local b = buckets[n] or { runs = 0, te = 0, th = 0, eq = 0, gap = 0, worst = 0 }
      buckets[n] = b
      b.runs = b.runs + 1; b.te = b.te + te; b.th = b.th + th
      local gap = (h.seconds - e.seconds) / e.seconds
      if gap < 1e-9 then b.eq = b.eq + 1 end
      if gap < -1e-9 then print("!! heuristic beat exact", n, h.seconds, e.seconds) end
      b.gap = b.gap + gap; if gap > b.worst then b.worst = gap end
    end
  end
  for n = 3, ns.Tour.EXACT_LIMIT do
    local b = buckets[n]
    if b then
      print(("%5d | %4d | %8.1f | %7.1f | %d/%d | %6.2f%% | %6.2f%%"):format(n, b.runs, 1000 * b.te / b.runs, 1000 * b.th / b.runs, b.eq, b.runs, 100 * b.gap / b.runs, 100 * b.worst))
    end
  end
end
