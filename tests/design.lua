-- Design tests: the class diagrams match the code, and the patterns do what the diagrams say.
-- Usage: luajit tests/design.lua
local root = arg[0]:match("^(.*)/tests/") or "."
local loader = dofile(root .. "/tools/load.lua")
local ns = loader(root)                                -- Forever (AtlasRoute.toc)
local rns = loader(root, "AtlasRoute_Mainline.toc")    -- retail (AtlasRoute_Mainline.toc)

local passed, failed = 0, 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then passed = passed + 1; print("ok   " .. name)
  else failed = failed + 1; print("FAIL " .. name .. "\n     " .. tostring(err)) end
end
local function eq(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
local function truthy(v, msg) if not v then error(msg or "expected true", 2) end end
local function read(p) local f = assert(io.open(p)); local s = f:read("*a"); f:close(); return s end

-- Everything either addon defines, by name.
local all = {}
for k, v in pairs(ns) do all[k] = v end
for k, v in pairs(rns) do if all[k] == nil then all[k] = v end end

-- Parse the Mermaid class diagrams ---------------------------------------------------------
local DIAGRAMS = { "2-dunya.mmd", "3-atlas.mmd", "4-planlama.mmd" }
local classes, relations = {}, {}
for _, file in ipairs(DIAGRAMS) do
  local text = read(root .. "/docs/diagrams/" .. file)
  for name, body in text:gmatch("class%s+([%w_]+)%s*(%b{})") do
    local c = { file = file, methods = {}, static = {} }
    c.stereo = body:match("<<([^>]+)>>")
    for line in body:gmatch("[^\n]+") do
      local static, m = line:match("^%s*%+[%w_]+%(.-%)(%$?)"), line:match("^%s*%+([%w_]+)%(")
      if m then
        c.methods[#c.methods + 1] = m
        if static == "$" then c.static[m] = true end
      end
    end
    classes[name] = c
  end
  for a, arrow, b in text:gmatch("\n%s*([%w_]+)%s+([<|.%-]+)%s+([%w_]+)") do
    if arrow == "<|--" or arrow == "<|.." then relations[#relations + 1] = { parent = a, kind = arrow, child = b, file = file } end
  end
end

test("Every class in the diagrams exists in the code, with every method listed", function()
  local n = 0
  for name, c in pairs(classes) do
    if not (c.stereo and c.stereo:match("^module")) then
      local obj = all[name]
      truthy(obj, c.file .. ": no class " .. name .. " in the code")
      if c.stereo == "interface" then
        truthy(obj.__interface, name .. " should be an Interface")
        local declared = {}
        for _, m in ipairs(obj.methods) do declared[m] = true end
        for _, m in ipairs(c.methods) do truthy(declared[m], name .. " declares no " .. m) end
        eq(#c.methods, #obj.methods, name .. " method count")
      else
        for _, m in ipairs(c.methods) do
          eq(type(obj[m]), "function", c.file .. ": " .. name .. "." .. m)
          n = n + 1
        end
      end
    end
  end
  truthy(n > 80, "only " .. n .. " methods checked")
  local arrows = 0
  for _ in pairs(relations) do arrows = arrows + 1 end
  truthy(arrows >= 18, "only " .. arrows .. " inheritance arrows parsed")
end)

test("Every inheritance and interface arrow in the diagrams holds in the code", function()
  for _, r in ipairs(relations) do
    local parent, child = all[r.parent], all[r.child]
    truthy(parent and child, r.file .. ": " .. r.parent .. " / " .. r.child)
    if r.kind == "<|.." then
      truthy(child.__implements and child.__implements[r.parent],
             r.file .. ": " .. r.child .. " does not implement " .. r.parent)
    else
      local s, found = child.super, false
      while s do if s == parent then found = true end; s = s.super end
      truthy(found, r.file .. ": " .. r.child .. " does not extend " .. r.parent)
    end
  end
end)

test("Every class and interface in the code is in a diagram", function()
  for k, v in pairs(all) do
    if type(v) == "table" and (v.__name == k or v.__interface == k) then
      truthy(classes[k], k .. " is missing from docs/diagrams")
    end
  end
end)

test("The Markdown page GitHub shows has the same diagrams as the sources", function()
  local page = read(root .. "/docs/diagrams/README.md")
  for _, f in ipairs({ "1-genel.mmd", "2-dunya.mmd", "3-atlas.mmd", "4-planlama.mmd" }) do
    local src = read(root .. "/docs/diagrams/" .. f):gsub("%s+$", "")
    truthy(page:find(src, 1, true), f .. " differs from docs/diagrams/README.md; run docs/diagrams/pdf.mjs")
  end
end)

-- The patterns at work ---------------------------------------------------------------------
local world = ns.ForeverMap.new():build()
local A = { faction = "Alliance", speed = 11.2, hearth = "stormwind" }
local function pick(ids)
  local r = {}
  for _, id in ipairs(ids) do for _, q in ipairs(ns.QuestData.alliance) do if q.id == id then r[#r + 1] = q end end end
  return r
end

test("Observer: the solver announces every round and every covered edge", function()
  local solver = ns.AtlasSolver.new()
  local rounds, covered = 0, 0
  solver:on("round", function() rounds = rounds + 1 end)
  local l = solver:on("covered", function() covered = covered + 1 end)
  local goal = ns.QuestTourGoal.new(world, pick({ "nightwatch", "plea", "jameshyal" }))
  local plan = ns.AtlasPlanner.new(solver):run(ns.AtlasPlan.travelGraph(world, A), world:index("ironforge"), goal)
  eq(rounds, plan.rounds)
  eq(covered, #plan.order)
  solver:off("covered", l)
  ns.AtlasPlanner.new(solver):run(ns.AtlasPlan.travelGraph(world, A), world:index("ironforge"), ns.RouteGoal.new(world:index("ratchet")))
  eq(covered, #plan.order, "unsubscribed listener was called")
end)

test("Strategy: every exploration order and both scoring rules give a complete, valid tour", function()
  local quests = pick({ "nightwatch", "northfold", "plea", "ironband" })
  local strategies = {}
  for _, o in ipairs(ns.ExplorationOrders.default()) do strategies[#strategies + 1] = { orders = { o } } end
  strategies[#strategies + 1] = { chain = true }
  for i, opts in ipairs(strategies) do
    local plan = ns.AtlasPlan.plan(world, A, "ironforge", quests, opts)
    eq(#plan.order, #plan.stops, "strategy " .. i)
    local pos = {}
    for k, s in ipairs(plan.order) do pos[s] = k end
    for k, s in ipairs(plan.order) do
      for _, p in ipairs(plan.stops[s].after) do truthy(pos[p] < k, "strategy " .. i .. " order") end
    end
  end
end)

test("Open/closed: a new travel mode is one register() call", function()
  local Gondola = ns.Class("Gondola", ns.FixedMode)
  function Gondola:seconds(edge) return edge.cost * 2 end
  ns.implements(Gondola, ns.TravelMode)
  ns.TravelModes.register("gondola", Gondola.new("gondola"))
  local w = ns.ForeverMap.new():build()
  w:addTransport({ from = "ironforge", to = "thelsamar", mode = "gondola", ride = 50, cycle = 0 })
  local g = ns.AtlasPlan.travelGraph(w, A)
  local found
  for l = 1, g.m do if g.edges[l].mode == "gondola" then found = g.edges[l].weight end end
  ns.TravelModes.modes.gondola = nil
  eq(found, 100)
end)

test("Interfaces are checked when a class is declared", function()
  local Broken = ns.Class("Broken")
  function Broken:key() return "x" end
  local ok, err = pcall(ns.implements, Broken, ns.ExplorationOrder)
  truthy(not ok and tostring(err):find("arrange"), "missing method not reported")
end)

test("Command: the registry dispatches by name, any case, and falls back to help", function()
  local ran = {}
  local registry = ns.CommandRegistry.fromTable({
    help = function() ran[#ran + 1] = "help" end,
    route = function(rest) ran[#ran + 1] = "route:" .. rest end,
  })
  registry:dispatch("route  Astranaar ")
  registry:dispatch("ROUTE Ratchet")
  registry:dispatch("")
  registry:dispatch("nonsense")
  eq(table.concat(ran, ","), "route:Astranaar,route:Ratchet,help,help")
  truthy(ns.isA(registry:get("route"), ns.Command))
end)

test("Adapter: both world sources build a World the same planner plans on", function()
  local fw = ns.ForeverMap.new():build()
  truthy(ns.isA(fw, ns.World), "ForeverMap")
  truthy(ns.ForeverMap.__implements.WorldSource)
  local snap = { continent = 0, x = 0, y = 0, faction = "Alliance", speed = 7, taxi = {}, quests = {},
                 givers = {} }
  local src = rns.RetailSnapshot.new(snap)
  local rw = src:build()
  truthy(rns.isA(rw, rns.World), "RetailSnapshot")
  truthy(rns.RetailSnapshot.__implements.WorldSource)
  eq(src.start, "here")
  local t = rns.AtlasPlan.route(rw, src.profile, "here", "here")
  eq(t, 0)
end)

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
