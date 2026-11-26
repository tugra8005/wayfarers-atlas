-- The graph Atlas walks on, and how it is built.
--
--   TravelGraph          labelled directed edges, out-edge lists per exploration order,
--                        groups of edges that leave together (one-use teleports)
--   ExplorationOrder     Strategy: the order a DFS explores a node's out-edges in
--     CheapestFirst, DearestFirst, InsertionOrder, Shuffled(seed)
--   TravelGraphFactory   Factory: the travel graph of one character in one world (only the
--                        edges it may use, weighted in seconds, plus its teleports)
--   FsmGraphAdapter      Adapter: a test FSM (fsm.lua, Atlas.java's graph) as a TravelGraph
local _, ns = ...
local Class, Interface, implements = ns.Class, ns.Interface, ns.implements

-- Exploration orders (Strategy) -------------------------------------------------------------
-- key():                       caches are kept per key
-- arrange(list, edges, node):  reorder the out-edge labels of `node` in place
local ExplorationOrder = Interface("ExplorationOrder", { "key", "arrange" })

local function byWeight(edges, sign)
  return function(a, b)
    if edges[a].weight ~= edges[b].weight then return sign * edges[a].weight < sign * edges[b].weight end
    return a < b
  end
end

local CheapestFirst = Class("CheapestFirst")
function CheapestFirst:key() return "cheap" end
function CheapestFirst:arrange(list, edges) table.sort(list, byWeight(edges, 1)) end
implements(CheapestFirst, ExplorationOrder)

local DearestFirst = Class("DearestFirst")
function DearestFirst:key() return "dear" end
function DearestFirst:arrange(list, edges) table.sort(list, byWeight(edges, -1)) end
implements(DearestFirst, ExplorationOrder)

-- As added. (Atlas.java explores in Java's HashSet order, which is arbitrary.)
local InsertionOrder = Class("InsertionOrder")
function InsertionOrder:key() return "insert" end
function InsertionOrder:arrange() end
implements(InsertionOrder, ExplorationOrder)

-- A fixed pseudo-random shuffle: same seed, same order, on every machine.
local Shuffled = Class("Shuffled")
function Shuffled:init(seed) self.seed = seed end
function Shuffled:key() return self.seed end
function Shuffled:arrange(list, _, node)
  local x = (self.seed + node) * 7919 + 17
  for i = #list, 2, -1 do
    x = (x * 1103515245 + 12345) % 2147483648
    local j = (x % i) + 1
    list[i], list[j] = list[j], list[i]
  end
end
implements(Shuffled, ExplorationOrder)

local ExplorationOrders = {}
-- The 16 orders every Atlas round tries; it keeps the best-scoring chain.
function ExplorationOrders.default()
  local list = { DearestFirst.new(), CheapestFirst.new(), InsertionOrder.new() }
  for seed = 1, 13 do list[#list + 1] = Shuffled.new(seed) end
  return list
end
-- Accept the short forms too: "cheap", "dear", "insert" or a seed number.
function ExplorationOrders.of(spec)
  if type(spec) == "table" then return spec end
  if spec == "cheap" or spec == nil then return CheapestFirst.new() end
  if spec == "dear" then return DearestFirst.new() end
  if spec == "insert" then return InsertionOrder.new() end
  return Shuffled.new(spec)
end

-- TravelGraph --------------------------------------------------------------------------------
-- An edge: {source, dest, weight (seconds), mode, name, required, prereq = {labels}, group}
local TravelGraph = Class("TravelGraph")
function TravelGraph:init()
  self.edges, self.out, self.m, self.removed, self.groups = {}, {}, 0, {}, {}
end

function TravelGraph:add(e)
  local l = self.m + 1
  self.m = l
  e.label = l
  self.edges[l] = e
  self.out[e.source] = self.out[e.source] or {}
  self.out[e.dest] = self.out[e.dest] or {}
  table.insert(self.out[e.source], l)
  if e.group then
    self.groups[e.group] = self.groups[e.group] or {}
    table.insert(self.groups[e.group], l)
  end
  self._sorted = nil -- new edge: rebuild the orders
  return l
end

-- Out-edges of a node in an exploration order, without removed ones.
function TravelGraph:outEdges(node, order)
  order = ExplorationOrders.of(order)
  local key = order:key()
  self._sorted = self._sorted or {}
  self._sorted[key] = self._sorted[key] or {}
  local list = self._sorted[key][node]
  if not list then
    list = {}
    for i, l in ipairs(self.out[node] or {}) do list[i] = l end
    order:arrange(list, self.edges, node)
    self._sorted[key][node] = list
  end
  if not next(self.removed) then return list end
  local live = {}
  for _, l in ipairs(list) do if not self.removed[l] then live[#live + 1] = l end end
  return live
end

function TravelGraph:removeGroup(group)
  for _, l in ipairs(self.groups[group] or {}) do self.removed[l] = true end
end

-- TravelGraphFactory (Factory) -------------------------------------------------------------
local TravelGraphFactory = Class("TravelGraphFactory")
function TravelGraphFactory:init(world, profile)
  self.world, self.profile = world, ns.Profile.of(profile)
end

-- The one-use teleports this character has (hearthstone, Astral Recall, devices).
function TravelGraphFactory:limited()
  local world, profile, list = self.world, self.profile, {}
  if profile.hearth then
    list[#list + 1] = { mode = "hearth", name = "Hearthstone", to = world:index(profile.hearth), cost = world.CAST_TIME }
  end
  for _, t in ipairs(world.teleports) do
    if t.limited and t:allows(profile) then
      local to = t.to
      if t.toBind then to = profile.hearth and world:index(profile.hearth) end
      if to then list[#list + 1] = { mode = t.mode, name = t.name, to = to, cost = t.cost } end
    end
  end
  return list
end

-- Every edge the character may use, weighted in seconds; teleports from every ground node
-- (no casting on a flight); the edges of each one-use teleport share a group.
function TravelGraphFactory:build()
  local world, profile = self.world, self.profile
  local g = TravelGraph.new()
  for i = 1, #world.nodes do
    for _, e in ipairs(world.adj[i]) do
      if e:allows(profile) then
        g:add({ source = e.from, dest = e.to, weight = e:seconds(profile), mode = e.mode, name = e.name })
      end
    end
  end
  local free = {}
  for _, t in ipairs(world.teleports) do
    if not t.limited and t:allows(profile) then free[#free + 1] = t end
  end
  local once = self:limited()
  for i, n in ipairs(world.nodes) do
    if n.kind == "ground" then
      for _, t in ipairs(free) do
        if t.to ~= i then g:add({ source = i, dest = t.to, weight = t.cost, mode = t.mode, name = t.name }) end
      end
      for k, t in ipairs(once) do
        if t.to ~= i then
          g:add({ source = i, dest = t.to, weight = t.cost, mode = t.mode, name = t.name, group = "once" .. k })
        end
      end
    end
  end
  return g
end

-- FsmGraphAdapter (Adapter) ----------------------------------------------------------------
-- Atlas.java's FSM graph (0-based labels, weights) as a TravelGraph; every edge required.
local FsmGraphAdapter = Class("FsmGraphAdapter")
function FsmGraphAdapter:init(fsm) self.fsm = fsm end
function FsmGraphAdapter:build()
  local g = TravelGraph.new()
  for l = 0, self.fsm.m - 1 do
    local e = self.fsm.edges[l]
    g:add({ source = e.source, dest = e.dest, weight = e.weight, mode = "edge", required = true, fsmLabel = l })
  end
  return g
end

ns.ExplorationOrder, ns.ExplorationOrders = ExplorationOrder, ExplorationOrders
ns.CheapestFirst, ns.DearestFirst, ns.InsertionOrder, ns.Shuffled = CheapestFirst, DearestFirst, InsertionOrder, Shuffled
ns.TravelGraph, ns.TravelGraphFactory, ns.FsmGraphAdapter = TravelGraph, TravelGraphFactory, FsmGraphAdapter
