-- What a plan has to achieve, as Atlas sees it: which edges are required.
--
--   Goal (Strategy)    prepare(graph) marks or adds the required edges;
--                      collect(graph, run) turns the solver's walk into the answer
--     QuestTourGoal      every quest stop is a self-loop at its place, weighted by the time
--                        spent there, with prerequisites (accept -> objectives -> turn in,
--                        quest chains)
--     RouteGoal          one zero-weight self-loop at the destination
--     FlightNetworkGoal  every flight link the character may use
--     FsmCoverageGoal    every edge of a test FSM (FsmGraphAdapter marks them)
--   QuestLog           quest definitions -> the stops a tour must visit
--   LegAssembler       a walk -> travel legs (one walk over several waypoints, one flight
--                      over several hops), using each edge's TravelMode
--   AtlasPlanner       runs a Goal with an AtlasSolver; a new kind of plan is a new Goal
local _, ns = ...
local Class, Interface, implements = ns.Class, ns.Interface, ns.implements

-- QuestLog ---------------------------------------------------------------------------------
-- quest = {id, name, giver, objectives = {place ids}, turnin, accepted, work, requires = {ids}}
-- stop  = {node, quest, name, kind = "accept"|"objective"|"turnin", work, after = {stop indices}}
-- `requires`: quests in the same log that must be handed in before this one is picked up.
local QuestLog = Class("QuestLog")
function QuestLog:init(world, quests) self.world, self.quests = world, quests end

function QuestLog:stops()
  local world, stops = self.world, {}
  local turninOf, firstOf = {}, {}
  for _, q in ipairs(self.quests) do
    firstOf[q.id] = #stops + 1
    local acceptIdx
    if not q.accepted then
      stops[#stops + 1] = { node = world:index(q.giver), quest = q.id, name = q.name,
                            kind = "accept", work = 0, after = {} }
      acceptIdx = #stops
    end
    local objIdx = {}
    for _, o in ipairs(q.objectives or {}) do
      if not (q.done and q.done[o]) then
        stops[#stops + 1] = { node = world:index(o), quest = q.id, name = q.name,
                              kind = "objective", work = q.work or 0,
                              after = acceptIdx and { acceptIdx } or {} }
        objIdx[#objIdx + 1] = #stops
      end
    end
    if q.turnin then
      local after = {}
      if acceptIdx then after[#after + 1] = acceptIdx end
      for _, i in ipairs(objIdx) do after[#after + 1] = i end
      stops[#stops + 1] = { node = world:index(q.turnin), quest = q.id, name = q.name,
                            kind = "turnin", work = 0, after = after }
      turninOf[q.id] = #stops
    end
  end
  for _, q in ipairs(self.quests) do
    for _, r in ipairs(q.requires or {}) do
      local t = turninOf[r]
      if t then
        for i = firstOf[q.id], #stops do
          if stops[i].quest ~= q.id then break end
          table.insert(stops[i].after, t)
        end
      end
    end
  end
  return stops
end

-- LegAssembler -----------------------------------------------------------------------------
local LegAssembler = Class("LegAssembler")
-- labels: travel edges in walk order. Returns legs {mode, from, to, seconds, name, hops, path}.
function LegAssembler:legs(g, labels)
  local legs = {}
  for _, l in ipairs(labels) do
    local e = g.edges[l]
    local mode = ns.TravelModes.get(e.mode)
    local last = legs[#legs]
    if last and mode:joins(last.mode) then
      last.to = e.dest
      last.seconds = last.seconds + e.weight
      last.path[#last.path + 1] = e.dest
      if e.mode == "fly" then last.hops = last.hops + 1 end
    else
      legs[#legs + 1] = { mode = mode:legMode(), from = e.source, to = e.dest,
                          seconds = e.weight, name = e.name, hops = 0, path = { e.source, e.dest } }
    end
  end
  return legs
end

-- Goals (Strategy) -------------------------------------------------------------------------
local Goal = Interface("Goal", { "prepare", "collect" })

local QuestTourGoal = Class("QuestTourGoal")
function QuestTourGoal:init(world, quests)
  self.world, self.stops = world, QuestLog.new(world, quests):stops()
end
function QuestTourGoal:prepare(g)
  local labelOf = {}
  for i, s in ipairs(self.stops) do
    labelOf[i] = g:add({ source = s.node, dest = s.node, weight = s.work, mode = "stop",
                         required = true, stop = i })
  end
  for i, s in ipairs(self.stops) do
    local pre = {}
    for _, a in ipairs(s.after) do pre[#pre + 1] = labelOf[a] end
    g.edges[labelOf[i]].prereq = pre
  end
end
-- Returns {seconds, method = "atlas", stops, order = stop indices,
--          legs = {{stop, index, seconds (travel), travel = legs}}, rounds, unreachable}
function QuestTourGoal:collect(g, run)
  local stops, assembler = self.stops, LegAssembler.new()
  local legs, order, pending = {}, {}, {}
  for _, l in ipairs(run.walk) do
    local e = g.edges[l]
    if e.mode == "stop" then
      local travel = assembler:legs(g, pending)
      local t = 0
      for _, x in ipairs(travel) do t = t + x.seconds end
      legs[#legs + 1] = { stop = stops[e.stop], index = e.stop, seconds = t, travel = travel }
      order[#order + 1] = e.stop
      pending = {}
    elseif e.mode ~= "start" then
      pending[#pending + 1] = l
    end
  end
  local done, unreachable = {}, {}
  for _, i in ipairs(order) do done[i] = true end
  for i, s in ipairs(stops) do if not done[i] then unreachable[#unreachable + 1] = s end end
  return { seconds = run.seconds, method = "atlas", stops = stops, order = order, legs = legs,
           rounds = run.rounds, unreachable = unreachable }
end
implements(QuestTourGoal, Goal)

local RouteGoal = Class("RouteGoal")
function RouteGoal:init(dest) self.dest = dest end
function RouteGoal:prepare(g)
  g:add({ source = self.dest, dest = self.dest, weight = 0, mode = "stop", required = true })
end
-- Returns seconds and travel legs, or nil if the destination cannot be reached.
function RouteGoal:collect(g, run)
  if run.covered < run.required then return nil end
  local travel = {}
  for _, l in ipairs(run.walk) do
    if g.edges[l].mode ~= "stop" and g.edges[l].mode ~= "start" then travel[#travel + 1] = l end
  end
  return run.seconds, LegAssembler.new():legs(g, travel)
end
implements(RouteGoal, Goal)

local FlightNetworkGoal = Class("FlightNetworkGoal")
function FlightNetworkGoal:prepare(g)
  self.required = 0
  for l = 1, g.m do
    if g.edges[l].mode == "fly" then g.edges[l].required = true; self.required = self.required + 1 end
  end
end
-- Returns {steps = {{mode, from, to, seconds, name, required}}, seconds, covered, required, rounds}
function FlightNetworkGoal:collect(g, run)
  local steps = {}
  for _, l in ipairs(run.walk) do
    local e = g.edges[l]
    if e.mode ~= "start" then
      steps[#steps + 1] = { mode = e.mode, from = e.source, to = e.dest, seconds = e.weight,
                            name = e.name, required = e.required }
    end
  end
  return { steps = steps, seconds = run.seconds, covered = run.covered, required = self.required, rounds = run.rounds }
end
implements(FlightNetworkGoal, Goal)

local FsmCoverageGoal = Class("FsmCoverageGoal")
function FsmCoverageGoal:prepare() end -- FsmGraphAdapter already marks every edge required
-- Returns {path = FSM edge labels, weight, covered, required, length}
function FsmCoverageGoal:collect(g, run)
  local labels = {}
  for _, l in ipairs(run.walk) do
    if g.edges[l].fsmLabel then labels[#labels + 1] = g.edges[l].fsmLabel end
  end
  return { path = labels, weight = run.seconds, covered = run.covered, required = run.required, length = #labels }
end
implements(FsmCoverageGoal, Goal)

-- AtlasPlanner ------------------------------------------------------------------------------
local AtlasPlanner = Class("AtlasPlanner")
-- solver: an AtlasSolver (default: a new one with the default orders and SingleTarget)
function AtlasPlanner:init(solver) self.solver = solver or ns.AtlasSolver.new() end
function AtlasPlanner:run(g, start, goal)
  goal:prepare(g)
  return goal:collect(g, self.solver:solve(g, start))
end

ns.Goal, ns.QuestLog, ns.LegAssembler, ns.AtlasPlanner = Goal, QuestLog, LegAssembler, AtlasPlanner
ns.QuestTourGoal, ns.RouteGoal, ns.FlightNetworkGoal, ns.FsmCoverageGoal = QuestTourGoal, RouteGoal, FlightNetworkGoal, FsmCoverageGoal
