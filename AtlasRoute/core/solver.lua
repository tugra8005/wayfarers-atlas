-- Atlas (Savaş Takan, github.com/savastakan/atlas) as a solver: cover every required edge of
-- a TravelGraph with one walk.
--
-- AtlasSolver.solve is a Template Method. Each round:
--   explore(order)  DFS post-order of the edges reachable from the walk's last edge
--   score(order)    longest-path dynamic programming over that order; the ScoringRule
--                   decides what a chain is worth
--   choose          the best chain over every ExplorationOrder
--   append          add it to the walk, mark new required edges covered, spend one-use
--                   teleports (their edges leave the graph)
-- until every required edge is covered or none can be reached. A subclass may override any
-- step; the loop stays the same.
--
-- The solver is Observable: it emits
--   "covered"  (label, walk)                 a required edge was covered
--   "round"    (rounds, covered, required)   a round is done (the game yields a frame here)
--
-- ScoringRule (Strategy):
--   SingleTarget  each round goes to one new required edge, the one whose own chain is best
--                 (the default; much shorter quest tours on the game map)
--   WholeChain    Atlas.java's rule: the chain with the most new required edges wins
-- A chain's score is  newRequired * VALUE - seconds,  VALUE > the sum of all weights, so a
-- new required edge always outweighs any amount of travel.
local _, ns = ...
local Class, Interface, implements = ns.Class, ns.Interface, ns.implements
local NEG = -math.huge

-- Scoring rules (Strategy) ------------------------------------------------------------------
-- propagate(avail, value)       what a newly available edge adds while a chain grows
-- candidate(nc, avail, value)   the score of ending a chain on this edge, or nil if it may not
local ScoringRule = Interface("ScoringRule", { "propagate", "candidate" })

local SingleTarget = Class("SingleTarget")
function SingleTarget:propagate() return 0 end
function SingleTarget:candidate(nc, avail, value) if avail then return nc + value end end
implements(SingleTarget, ScoringRule)

local WholeChain = Class("WholeChain")
function WholeChain:propagate(avail, value) return avail and value or 0 end
function WholeChain:candidate(nc) return nc end
implements(WholeChain, ScoringRule)

-- AtlasSolver (Template Method, Observable) ------------------------------------------------
local AtlasSolver = Class("AtlasSolver", ns.Observable)

-- opts.orders: ExplorationOrders (or their short forms); default: ExplorationOrders.default()
-- opts.scoring: a ScoringRule; default SingleTarget
function AtlasSolver:init(opts)
  opts = opts or {}
  self.orders = {}
  for i, o in ipairs(opts.orders or ns.ExplorationOrders.default()) do
    self.orders[i] = ns.ExplorationOrders.of(o)
  end
  self.scoring = opts.scoring or SingleTarget.new()
end

-- Step 1: DFS post-order of the edges reachable from `last`.
function AtlasSolver:explore(g, last, order)
  local stack, mark = {}, { [last] = true }
  local frames = { { e = last, i = 0, nbrs = g:outEdges(g.edges[last].dest, order) } }
  while #frames > 0 do
    local f = frames[#frames]
    local advanced = false
    while f.i < #f.nbrs do
      f.i = f.i + 1
      local n = f.nbrs[f.i]
      if not mark[n] then
        mark[n] = true
        frames[#frames + 1] = { e = n, i = 0, nbrs = g:outEdges(g.edges[n].dest, order) }
        advanced = true
        break
      end
    end
    if not advanced then
      stack[#stack + 1] = f.e
      frames[#frames] = nil
    end
  end
  return stack
end

-- Step 2: longest-path DP over the order. Returns the best score, the edge it ends on and
-- the links back to `last`.
function AtlasSolver:score(g, last, order, state)
  local stack = self:explore(g, last, order)
  local rule, value = self.scoring, state.value
  local cost, comeFrom, visited = { [last] = 0 }, {}, {}
  local bestCost, best = 0, nil
  for s = #stack, 1, -1 do
    local e = stack[s]
    visited[e] = true
    local ce = cost[e]
    if ce then
      for _, n in ipairs(g:outEdges(g.edges[e].dest, order)) do
        if not visited[n] then
          local avail = state:available(n)
          local nc = ce + rule:propagate(avail, value) - g.edges[n].weight
          if nc > (cost[n] or NEG) then
            cost[n] = nc
            comeFrom[n] = e
          end
          local score = rule:candidate(nc, avail, value)
          if score and score > bestCost then bestCost, best = score, n end
        end
      end
    end
  end
  return bestCost, best, comeFrom
end

-- Step 3: the best chain over every exploration order.
function AtlasSolver:choose(g, last, state)
  local bestCost, best, links = 0, nil, nil
  for _, o in ipairs(self.orders) do
    local c, b, cf = self:score(g, last, o, state)
    if b and c > bestCost then bestCost, best, links = c, b, cf end
  end
  if not best then return nil end
  local chain, cur = {}, best
  while cur ~= last do chain[#chain + 1] = cur; cur = links[cur] end
  return chain -- from the chain's end back to its first edge
end

-- Step 4: walk the chain. Returns the new last edge.
function AtlasSolver:append(g, chain, last, state)
  for i = #chain, 1, -1 do
    local l = chain[i]
    local e = g.edges[l]
    if g.removed[l] then break end -- a one-use teleport spent earlier in this chain
    state.walk[#state.walk + 1] = l
    state.seconds = state.seconds + e.weight
    if state:available(l) then
      state.covered[l] = true
      state.nCovered = state.nCovered + 1
      state.order[#state.order + 1] = l
      self:emit("covered", l, state.walk)
    end
    if e.group then g:removeGroup(e.group) end
    last = l
  end
  return last
end

-- What a run knows: what is covered, the walk so far, and the value of a new edge.
local RunState = Class("RunState")
function RunState:init(g)
  self.g, self.covered, self.nCovered, self.order = g, {}, 0, {}
  self.walk, self.seconds, self.rounds = {}, 0, 0
  local total, nReq = 0, 0
  for l = 1, g.m do
    total = total + g.edges[l].weight
    if g.edges[l].required then nReq = nReq + 1 end
  end
  self.value, self.required = total + 1, nReq
end
-- A required edge counts as new once its prerequisites are covered.
function RunState:available(l)
  local e = self.g.edges[l]
  if not e.required or self.covered[l] then return false end
  for _, p in ipairs(e.prereq or {}) do if not self.covered[p] then return false end end
  return true
end

-- The template: cover every required edge of g with one walk from node `start`.
-- Returns {walk = edge labels, seconds, covered, required, rounds, order = labels covered}.
function AtlasSolver:solve(g, start)
  local last = g:add({ source = start, dest = start, weight = 0, mode = "start" })
  local state = RunState.new(g)
  while state.nCovered < state.required do
    state.rounds = state.rounds + 1
    local chain = self:choose(g, last, state)
    if not chain then break end -- the remaining required edges cannot be reached
    last = self:append(g, chain, last, state)
    self:emit("round", state.rounds, state.nCovered, state.required)
  end
  return { walk = state.walk, seconds = state.seconds, covered = state.nCovered,
           required = state.required, rounds = state.rounds, order = state.order }
end

ns.ScoringRule, ns.SingleTarget, ns.WholeChain = ScoringRule, SingleTarget, WholeChain
ns.AtlasSolver, ns.RunState = AtlasSolver, RunState
