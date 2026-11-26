-- AtlasPlan: the one entry point the addons, the web page, the command-line demo and the
-- tests use (Facade). Every function here is a few lines wiring the classes together:
--
--   world + profile --TravelGraphFactory--> TravelGraph
--   Goal (QuestTourGoal | RouteGoal | FlightNetworkGoal | FsmCoverageGoal) + AtlasSolver
--     --AtlasPlanner--> the answer
--
-- All planning is Atlas (core/solver.lua). Its design: every way of travelling is an edge of
-- one graph weighted by its time; what must happen is a required edge; Atlas covers every
-- required edge with one walk, round by round (DFS post-order, longest-path DP, best chain).
local _, ns = ...

local AtlasPlan = {}

-- The 16 exploration orders every round tries.
AtlasPlan.ORDERS = ns.ExplorationOrders.default()

local function solverFor(opts)
  opts = opts or {}
  local solver = ns.AtlasSolver.new({
    orders = opts.orders,
    scoring = opts.chain and ns.WholeChain.new() or ns.SingleTarget.new(),
  })
  -- In game the plan runs in a coroutine and gives the frame back after every round.
  if opts.yield then solver:on("round", function() opts.yield() end) end
  return solver
end

local function planner(opts) return ns.AtlasPlanner.new(solverFor(opts)) end

-- The one-use teleports this character has.
function AtlasPlan.limited(world, profile)
  return ns.TravelGraphFactory.new(world, profile):limited()
end

-- The travel graph for one character: every edge it may use, weighted in seconds.
function AtlasPlan.travelGraph(world, profile)
  return ns.TravelGraphFactory.new(world, profile):build()
end

-- Cover every required edge of g with one walk from node `start`.
-- opts.orders: exploration orders; opts.chain = true: Atlas.java's whole-chain scoring.
function AtlasPlan.walk(g, start, opts)
  return solverFor(opts):solve(g, start)
end

function AtlasPlan.legsOf(g, labels) return ns.LegAssembler.new():legs(g, labels) end

function AtlasPlan.stops(world, quests) return ns.QuestLog.new(world, quests):stops() end

-- Plan a quest tour. Returns {seconds, method = "atlas", stops, order = stop indices,
-- legs = {{stop, index, seconds (travel), travel = legs}}, rounds, unreachable = stop list}
function AtlasPlan.plan(world, profile, startId, quests, opts)
  local goal = ns.QuestTourGoal.new(world, quests)
  return planner(opts):run(AtlasPlan.travelGraph(world, profile), world:index(startId), goal)
end

-- Fastest way (as Atlas finds it) from one place to another.
-- Returns seconds and travel legs, or nil if the destination cannot be reached.
function AtlasPlan.route(world, profile, fromId, toId, opts)
  local goal = ns.RouteGoal.new(world:index(toId))
  return planner(opts):run(AtlasPlan.travelGraph(world, profile), world:index(fromId), goal)
end

-- Fly every flight link this character can use (both directions).
-- Returns {steps = {{mode, from, to, seconds, name, required}}, seconds, covered, required, rounds}.
function AtlasPlan.cover(world, profile, startId, opts)
  return planner(opts):run(AtlasPlan.travelGraph(world, profile), world:index(startId), ns.FlightNetworkGoal.new())
end

-- Atlas with weights on a test FSM (fsm.lua): every edge required.
-- Returns {path = FSM edge labels, weight, covered, required, length}.
function AtlasPlan.coverFSM(fsm, startNode, opts)
  return planner(opts):run(ns.FsmGraphAdapter.new(fsm):build(), startNode or 0, ns.FsmCoverageGoal.new())
end

ns.AtlasPlan = AtlasPlan
