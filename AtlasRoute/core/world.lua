-- Multimodal travel graph of the game world.
--
-- Nodes:
--   ground nodes  - places you can stand at (towns, quest spots, docks)
--   air nodes     - one per flight master, "in the flight network"
-- Edges (all costs in seconds):
--   walk      ground <-> ground, same continent, k nearest neighbours
--   board     ground -> air   (talking to the flight master; air nodes are faction-gated)
--   fly       air <-> air     (one flight link; chained links are one continuous flight)
--   land      air -> ground
--   boat / zeppelin / tram   ground <-> ground, cost = ride + expected wait (half a cycle)
-- Teleports (edges from *every* ground node, not stored per node):
--   mage teleports (class-gated), hearthstone (one use per plan: see router.lua)
--
-- Splitting each flight master into a ground and an air node is what lets a multi-hop flight
-- cost one boarding instead of one per hop, the same as the in-game taxi.
local _, ns = ...

local World = {}
World.__index = World

World.WALK_DETOUR = 1.3   -- roads and terrain vs. straight line
World.FLY_DETOUR = 1.15
World.FLY_SPEED = 30      -- yards / second, taxi
World.BOARD_TIME = 5      -- seconds to talk to the flight master
World.CAST_TIME = 10      -- hearthstone and mage teleport cast

function World.new()
  return setmetatable({
    nodes = {},       -- index -> node
    byId = {},        -- id -> index
    adj = {},         -- index -> list of edges
    teleports = {},   -- list of {to=index, mode=, cost=, faction=, class=}
    flightLinks = {}, -- list of {a=index, b=index} (air nodes)
  }, World)
end

local function dist(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end
World.dist = dist

function World:_add(node)
  local i = #self.nodes + 1
  node.index = i
  self.nodes[i] = node
  self.byId[node.id] = i
  self.adj[i] = {}
  return i
end

function World:edge(from, to, mode, cost, gate)
  local e = { from = from, to = to, mode = mode, cost = cost }
  if gate then e.faction, e.class = gate.faction, gate.class end
  local list = self.adj[from]
  list[#list + 1] = e
  return e
end

-- place = {id, name, zone, continent, x, y}
function World:addPlace(p)
  p.kind = "ground"
  return self:_add(p)
end

function World:index(id)
  local i = self.byId[id]
  if not i then error("unknown place: " .. tostring(id), 2) end
  return i
end

-- faction = "Alliance", "Horde" or nil (neutral)
function World:addFlightMaster(placeId, faction)
  local g = self:index(placeId)
  local p = self.nodes[g]
  local a = self:_add({ id = "air:" .. placeId, name = p.name .. " (flight master)",
                        zone = p.zone, continent = p.continent, x = p.x, y = p.y,
                        kind = "air", ground = g, faction = faction })
  self:edge(g, a, "board", World.BOARD_TIME, { faction = faction })
  self:edge(a, g, "land", 0)
  return a
end

function World:addFlightLink(idA, idB)
  local a, b = self:index("air:" .. idA), self:index("air:" .. idB)
  local na, nb = self.nodes[a], self.nodes[b]
  local cost = dist(na, nb) * World.FLY_DETOUR / World.FLY_SPEED
  -- a link is usable only if the rider's faction can use both ends
  local faction = na.faction or nb.faction
  self:edge(a, b, "fly", cost, { faction = faction })
  self:edge(b, a, "fly", cost, { faction = faction })
  self.flightLinks[#self.flightLinks + 1] = { a = a, b = b }
end

-- t = {from, to, mode, ride, cycle, faction, oneWay}
function World:addTransport(t)
  local a, b = self:index(t.from), self:index(t.to)
  local cost = t.ride + (t.cycle or 0) / 2
  local gate = { faction = t.faction }
  self:edge(a, b, t.mode, cost, gate)
  if not t.oneWay then self:edge(b, a, t.mode, cost, gate) end
end

-- t = {to, mode, cost, faction, class}
function World:addTeleport(t)
  self.teleports[#self.teleports + 1] = {
    to = self:index(t.to), mode = t.mode, cost = t.cost or World.CAST_TIME,
    faction = t.faction, class = t.class, name = t.name,
  }
end

-- Walking edges: each ground node to its k nearest ground nodes on the same continent,
-- in both directions, plus any explicit pairs given in `extra` (e.g. a mountain pass).
function World:connectWalking(k, extra)
  k = k or 4
  local ground = {}
  for i, n in ipairs(self.nodes) do
    if n.kind == "ground" then ground[#ground + 1] = i end
  end
  local has = {}
  local function link(i, j)
    local key = i < j and (i .. ":" .. j) or (j .. ":" .. i)
    if has[key] then return end
    has[key] = true
    local d = dist(self.nodes[i], self.nodes[j]) * World.WALK_DETOUR
    self:edge(i, j, "walk", d) -- cost in yards; the router divides by ground speed
    self:edge(j, i, "walk", d)
  end
  for _, i in ipairs(ground) do
    local cands = {}
    for _, j in ipairs(ground) do
      if j ~= i and self.nodes[j].continent == self.nodes[i].continent then
        cands[#cands + 1] = { j = j, d = dist(self.nodes[i], self.nodes[j]) }
      end
    end
    table.sort(cands, function(a, b) return a.d < b.d end)
    for r = 1, math.min(k, #cands) do link(i, cands[r].j) end
  end
  for _, pair in ipairs(extra or {}) do link(self:index(pair[1]), self:index(pair[2])) end
end

-- Profile: what this character can use.
--   faction  "Alliance" | "Horde"
--   class    "MAGE", ... (upper-case, as UnitClass returns it)
--   speed    ground speed in yards/s (7 on foot, 11.2 with a 60% mount, 14 with 100%)
--   hearth   place id the hearthstone is bound to, or nil
function World:allowed(gated, profile)
  if gated.faction and gated.faction ~= profile.faction then return false end
  if gated.class and gated.class ~= profile.class then return false end
  return true
end

function World:edgeCost(e, profile)
  if e.mode == "walk" then return e.cost / (profile.speed or 7) end
  return e.cost
end

ns.World = World
