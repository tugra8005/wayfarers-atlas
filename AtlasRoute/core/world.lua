-- The game world as a multimodal travel graph.
--
-- Nodes (Place):
--   ground  places you can stand at (towns, quest spots, docks)
--   air     one per flight master, "in the flight network"
-- Edges (TravelEdge), each with a TravelMode that turns its stored cost into seconds:
--   walk      ground <-> ground, same region, k nearest neighbours (cost in yards)
--   board     ground -> air   (talking to the flight master; faction-gated)
--   fly       air <-> air     (one flight link; chained links are one continuous flight)
--   land      air -> ground
--   boat / zeppelin / skyship / tram / portal   ride + expected wait (half a cycle)
-- Teleports (Teleport) are usable from every ground node; some once per plan.
--
-- Splitting each flight master into a ground and an air node is what lets a multi-hop flight
-- cost one boarding instead of one per hop, the same as the in-game taxi.
--
-- Classes here: Gated (who may use something), TravelEdge, Teleport, Place, Profile,
-- TravelMode and its strategies (WalkMode, FlightMode, FixedMode) in the TravelModes
-- registry, World, and the WorldSource interface the map data and the retail client implement.
local _, ns = ...
local Class, Interface, implements = ns.Class, ns.Interface, ns.implements

-- Profile ------------------------------------------------------------------------------------
-- What this character can use.
--   faction      "Alliance" | "Horde"
--   class        "MAGE", ... (upper-case, as UnitClass returns it)
--   speed        ground speed in yards/s (7 on foot, 11.2 with a 60% mount, 14 with 100%)
--   hearth       place id the hearthstone is bound to, or nil
--   items        set of item ids the character carries (engineering devices), or nil
--   knows        function(spellId) -> bool (in game: IsSpellKnown), or nil = trust the class
--   flySpeed     flight speed multiplier (Forever's Frequent Flier perk: 1.2)
--   unconfirmed  true = also use routes only reported from the beta
local Profile = Class("Profile")
function Profile:init(t) for k, v in pairs(t or {}) do self[k] = v end end
-- Accept a plain table as a profile (callers and tests pass tables).
function Profile.of(t)
  if getmetatable(t) == Profile then return t end
  return Profile.new(t)
end
function Profile:groundSpeed() return self.speed or 7 end
function Profile:flightFactor() return self.flySpeed or 1 end

-- Gated: anything only some characters may use -----------------------------------------------
local Gated = Class("Gated")
function Gated.check(g, profile)
  if g.faction and g.faction ~= profile.faction then return false end
  if g.class and g.class ~= profile.class then return false end
  if g.item and not (profile.items and profile.items[g.item]) then return false end
  if g.spell and profile.knows and not profile.knows(g.spell) then return false end
  if g.unconfirmed and not profile.unconfirmed then return false end
  return true
end
function Gated:allows(profile) return Gated.check(self, profile) end

local GATES = { "faction", "class", "item", "spell", "unconfirmed", "name" }

local TravelEdge = Class("TravelEdge", Gated)
function TravelEdge:init(from, to, mode, cost, gate)
  self.from, self.to, self.mode, self.cost = from, to, mode, cost
  if gate then for _, k in ipairs(GATES) do self[k] = gate[k] end end
end
function TravelEdge:seconds(profile) return ns.TravelModes.get(self.mode):seconds(self, Profile.of(profile)) end

local Teleport = Class("Teleport", Gated)
function Teleport:init(t)
  for k, v in pairs(t) do self[k] = v end
end

-- Place --------------------------------------------------------------------------------------
local Place = Class("Place")
function Place:init(t) for k, v in pairs(t) do self[k] = v end end
function Place:distanceTo(other)
  local dx, dy = self.x - other.x, self.y - other.y
  return math.sqrt(dx * dx + dy * dy)
end

-- Travel modes (Strategy) -------------------------------------------------------------------
-- seconds(edge, profile): the edge's time for this character.
-- legMode():              the mode a leg starting with this edge is shown as.
-- joins(legMode):         whether this edge continues a leg of that mode (one walk over
--                         several waypoints, one flight over several hops).
local TravelMode = Interface("TravelMode", { "seconds", "legMode", "joins" })

local FixedMode = Class("FixedMode")
function FixedMode:init(name, legMode) self.name, self.leg = name, legMode or name end
function FixedMode:seconds(edge) return edge.cost end
function FixedMode:legMode() return self.leg end
function FixedMode:joins() return false end
implements(FixedMode, TravelMode)

local WalkMode = Class("WalkMode", FixedMode)
function WalkMode:init() FixedMode.init(self, "walk") end
function WalkMode:seconds(edge, profile) return edge.cost / profile:groundSpeed() end
function WalkMode:joins(legMode) return legMode == "walk" end
implements(WalkMode, TravelMode)

local FlightMode = Class("FlightMode", FixedMode)
function FlightMode:init(name) FixedMode.init(self, name, name == "land" and "land" or "fly") end
function FlightMode:seconds(edge, profile)
  if self.name == "fly" then return edge.cost / profile:flightFactor() end
  return edge.cost -- boarding and landing take the same time for everyone
end
function FlightMode:joins(legMode) return self.name ~= "board" and legMode == "fly" end
implements(FlightMode, TravelMode)

-- Registry: a new way of travelling is one register() call; nothing else changes.
local TravelModes = { modes = {} }
function TravelModes.register(name, mode) TravelModes.modes[name] = mode; return mode end
function TravelModes.get(name)
  return TravelModes.modes[name] or TravelModes.register(name, FixedMode.new(name))
end
TravelModes.register("walk", WalkMode.new())
for _, m in ipairs({ "board", "fly", "land" }) do TravelModes.register(m, FlightMode.new(m)) end
for _, m in ipairs({ "boat", "zeppelin", "skyship", "tram", "portal", "teleport", "hearth", "device" }) do
  TravelModes.register(m, FixedMode.new(m))
end

-- World --------------------------------------------------------------------------------------
local World = Class("World")

World.WALK_DETOUR = 1.3   -- roads and terrain vs. straight line
World.FLY_DETOUR = 1.15
World.FLY_SPEED = 30      -- yards / second, taxi
World.BOARD_TIME = 5      -- seconds to talk to the flight master
World.CAST_TIME = 10      -- hearthstone and mage teleport cast

function World:init()
  self.nodes = {}       -- index -> Place
  self.byId = {}        -- id -> index
  self.adj = {}         -- index -> list of TravelEdge
  self.teleports = {}   -- list of Teleport
  self.flightLinks = {} -- list of {a=index, b=index} (air nodes)
end

function World.dist(a, b) return Place.distanceTo(a, b) end

function World:_add(node)
  if getmetatable(node) ~= Place then node = Place.new(node) end
  local i = #self.nodes + 1
  node.index = i
  self.nodes[i] = node
  self.byId[node.id] = i
  self.adj[i] = {}
  return i
end

function World:edge(from, to, mode, cost, gate)
  local e = TravelEdge.new(from, to, mode, cost, gate)
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

-- faction = "Alliance", "Horde" or nil (neutral); class = only that class may use it;
-- unconfirmed = only reported from the beta
function World:addFlightMaster(placeId, faction, class, unconfirmed)
  local g = self:index(placeId)
  local p = self.nodes[g]
  local a = self:_add({ id = "air:" .. placeId, name = p.name .. " (flight master)",
                        zone = p.zone, continent = p.continent, x = p.x, y = p.y,
                        kind = "air", ground = g, faction = faction, class = class })
  self:edge(g, a, "board", World.BOARD_TIME, { faction = faction, class = class, unconfirmed = unconfirmed })
  self:edge(a, g, "land", 0)
  return a
end

-- opts = {class = "DRUID", unconfirmed = true}
function World:addFlightLink(idA, idB, opts)
  opts = opts or {}
  local a, b = self:index("air:" .. idA), self:index("air:" .. idB)
  local na, nb = self.nodes[a], self.nodes[b]
  local cost = na:distanceTo(nb) * World.FLY_DETOUR / World.FLY_SPEED
  -- a link is usable only if the rider's faction can use both ends
  local gate = { faction = na.faction or nb.faction, class = opts.class or na.class or nb.class,
                 unconfirmed = opts.unconfirmed }
  self:edge(a, b, "fly", cost, gate)
  self:edge(b, a, "fly", cost, gate)
  self.flightLinks[#self.flightLinks + 1] = { a = a, b = b }
end

-- t = {from, to, mode, ride, cycle, faction, oneWay, unconfirmed, name}
function World:addTransport(t)
  local a, b = self:index(t.from), self:index(t.to)
  local cost = t.ride + (t.cycle or 0) / 2
  local gate = { faction = t.faction, unconfirmed = t.unconfirmed, name = t.name }
  self:edge(a, b, t.mode, cost, gate)
  if not t.oneWay then self:edge(b, a, t.mode, cost, gate) end
end

-- t = {to | toBind, mode, cost, faction, class, item, spell, limited, unconfirmed, name}
--   limited  = usable once per plan (cooldown longer than a plan)
--   toBind   = goes to the hearthstone's bind location (Astral Recall)
--   item     = needs this item in the bags (engineering devices)
--   spell    = spell id, checked in game with IsSpellKnown
function World:addTeleport(t)
  self.teleports[#self.teleports + 1] = Teleport.new({
    to = t.to and self:index(t.to), toBind = t.toBind, mode = t.mode,
    cost = t.cost or World.CAST_TIME, faction = t.faction, class = t.class, item = t.item,
    spell = t.spell, limited = t.limited, unconfirmed = t.unconfirmed, name = t.name,
  })
end

-- Walking edges: each ground node to its k nearest ground nodes in the same region,
-- in both directions, plus any explicit pairs given in `extra` (e.g. a mountain pass).
function World:connectWalking(k, extra)
  k = k or 4
  local ground = {}
  for i, n in ipairs(self.nodes) do
    if n.kind == "ground" then ground[#ground + 1] = i end
  end
  -- k-nearest only within a region (default: the continent); walled-off areas such as
  -- Mount Hyjal get their own region and are joined only by the explicit `extra` passes
  local function region(n) return n.region or n.continent end
  local has = {}
  local function link(i, j)
    local key = i < j and (i .. ":" .. j) or (j .. ":" .. i)
    if has[key] then return end
    has[key] = true
    local d = self.nodes[i]:distanceTo(self.nodes[j]) * World.WALK_DETOUR
    self:edge(i, j, "walk", d) -- cost in yards; WalkMode divides by ground speed
    self:edge(j, i, "walk", d)
  end
  for _, i in ipairs(ground) do
    local cands = {}
    for _, j in ipairs(ground) do
      if j ~= i and region(self.nodes[j]) == region(self.nodes[i]) then
        cands[#cands + 1] = { j = j, d = self.nodes[i]:distanceTo(self.nodes[j]) }
      end
    end
    table.sort(cands, function(a, b) return a.d < b.d end)
    for r = 1, math.min(k, #cands) do link(i, cands[r].j) end
  end
  for _, pair in ipairs(extra or {}) do link(self:index(pair[1]), self:index(pair[2])) end
end

-- May this character use `gated` (an edge, a teleport, or a plain table of gate fields)?
function World:allowed(gated, profile) return Gated.check(gated, profile) end

function World:edgeCost(e, profile)
  return TravelModes.get(e.mode):seconds(e, Profile.of(profile))
end

-- WorldSource (Adapter target): anything that can turn its own data into a World to plan on.
-- Implemented by ForeverMap (data/world_data.lua) and RetailSnapshot (core/retail.lua).
local WorldSource = Interface("WorldSource", { "build" })

ns.Profile, ns.Gated, ns.TravelEdge, ns.Teleport, ns.Place = Profile, Gated, TravelEdge, Teleport, Place
ns.TravelMode, ns.FixedMode, ns.WalkMode, ns.FlightMode, ns.TravelModes = TravelMode, FixedMode, WalkMode, FlightMode, TravelModes
ns.World, ns.WorldSource = World, WorldSource
