-- Route planning with Atlas (Savaş Takan, github.com/savastakan/atlas).
--
-- Every way of travelling is an edge of one graph, weighted by its time in seconds:
-- walking, boarding a flight master, each flight link, landing, boats, zeppelins, skyships,
-- the tram, portals, and teleports (mage, druid; hearthstone, Astral Recall and engineering
-- devices, which can be used once per plan). Things that must happen are REQUIRED edges:
--   quest tour     each stop (accept, objective, turn in) is a self-loop at its place,
--                  weighted by the time spent there
--   single route   one zero-weight self-loop at the destination
--   flight network every flight link the character can use
-- The plan is then Atlas's own problem: one walk that covers every required edge.
--
-- Atlas, round by round, as in Atlas.java:
--   1. order the edges reachable from the walk's last edge by DFS post-order;
--   2. over that order, a longest-path dynamic program scores each chain;
--   3. append the best chain to the walk; repeat until every required edge is covered.
-- Atlas.java gives every edge the same cost and scores a chain by its new edges. With
-- travel times, a chain scores  newRequired * BIG - seconds  (BIG > the sum of all
-- weights). Additions for the game:
--   * each round runs steps 1-2 for several DFS exploration orders (cheapest edge first,
--     most expensive first, as added, fixed shuffles) and keeps the best chain: the DP only
--     follows edges that point forward in its DFS order, so more orders, better chains;
--   * by default each round goes to one new required edge, the one whose own chain scores
--     best (opts.chain = true appends whole chains instead, as Atlas.java does);
--   * a required edge counts as new only once its prerequisites are covered
--     (accept -> objectives -> turn in, and quest chains);
--   * when a one-use teleport is taken, all its edges leave the graph;
--   * the walk's last edge is kept (Atlas.java drops it, see atlas.lua).
local _, ns = ...

local AtlasPlan = {}
local NEG = -math.huge

-- Graph -----------------------------------------------------------------------------------
local G = {}
G.__index = G

local function newGraph()
  return setmetatable({ edges = {}, out = {}, m = 0, removed = {}, groups = {} }, G)
end

-- e = {source, dest, weight, mode, name, required, prereq = {labels}, group, stop}
function G:add(e)
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

-- Out-edges of a node in a given exploration order, without removed ones.
--   "cheap"  cheapest first          "dear"  most expensive first
--   "insert" as added (Atlas.java's order is Java's HashSet order, which is arbitrary)
--   number   a fixed pseudo-random shuffle with that seed (same seed, same order)
local function shuffle(list, seed)
  local x = seed * 7919 + 17
  for i = #list, 2, -1 do
    x = (x * 1103515245 + 12345) % 2147483648
    local j = (x % i) + 1
    list[i], list[j] = list[j], list[i]
  end
end

function G:outEdges(node, order)
  order = order or "cheap"
  self._sorted = self._sorted or {}
  self._sorted[order] = self._sorted[order] or {}
  local list = self._sorted[order][node]
  if not list then
    list = {}
    for i, l in ipairs(self.out[node] or {}) do list[i] = l end
    local edges = self.edges
    if order == "cheap" or order == "dear" then
      local sign = (order == "dear") and -1 or 1
      table.sort(list, function(a, b)
        if edges[a].weight ~= edges[b].weight then return sign * edges[a].weight < sign * edges[b].weight end
        return a < b
      end)
    elseif type(order) == "number" then
      shuffle(list, order + node)
    end
    self._sorted[order][node] = list
  end
  if not next(self.removed) then return list end
  local live = {}
  for _, l in ipairs(list) do if not self.removed[l] then live[#live + 1] = l end end
  return live
end

function G:removeGroup(group)
  for _, l in ipairs(self.groups[group] or {}) do self.removed[l] = true end
end

-- The one-use teleports this character has.
function AtlasPlan.limited(world, profile)
  local list = {}
  if profile.hearth then
    list[#list + 1] = { mode = "hearth", name = "Hearthstone", to = world:index(profile.hearth), cost = world.CAST_TIME }
  end
  for _, t in ipairs(world.teleports) do
    if t.limited and world:allowed(t, profile) then
      local to = t.to
      if t.toBind then to = profile.hearth and world:index(profile.hearth) end
      if to then list[#list + 1] = { mode = t.mode, name = t.name, to = to, cost = t.cost } end
    end
  end
  return list
end

-- The travel graph for one character: every edge it may use, weighted in seconds.
function AtlasPlan.travelGraph(world, profile)
  local g = newGraph()
  for i = 1, #world.nodes do
    for _, e in ipairs(world.adj[i]) do
      if world:allowed(e, profile) then
        g:add({ source = e.from, dest = e.to, weight = world:edgeCost(e, profile), mode = e.mode, name = e.name })
      end
    end
  end
  local free = {}
  for _, t in ipairs(world.teleports) do
    if not t.limited and world:allowed(t, profile) then free[#free + 1] = t end
  end
  local once = AtlasPlan.limited(world, profile)
  for i, n in ipairs(world.nodes) do
    if n.kind == "ground" then -- no casting on a flight
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

-- Atlas ------------------------------------------------------------------------------------
local function dfsOrder(g, startLabel, order)
  local stack, mark = {}, { [startLabel] = true }
  local frames = { { e = startLabel, i = 0, nbrs = g:outEdges(g.edges[startLabel].dest, order) } }
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

-- One Atlas round from edge `last` with one exploration order: DFS post-order, then the
-- longest-path DP over it. Returns the best score, the edge it ends on, and the chain links.
-- single = true: a chain's score counts only the required edge it ends on (the DP then
-- finds the fastest Atlas chain to each one), so a round reaches exactly one new edge.
local function round(g, last, order, value, available, single)
  local stack = dfsOrder(g, last, order)
  local cost, comeFrom, visited = { [last] = 0 }, {}, {}
  local bestCost, best = 0, nil
  for s = #stack, 1, -1 do
    local e = stack[s]
    visited[e] = true
    local ce = cost[e]
    if ce then
      for _, n in ipairs(g:outEdges(g.edges[e].dest, order)) do
        if not visited[n] then
          local avail = available(n)
          local gain = (avail and not single) and value or 0
          local nc = ce + gain - g.edges[n].weight
          if nc > (cost[n] or NEG) then
            cost[n] = nc
            comeFrom[n] = e
          end
          local score = (single and avail) and (nc + value) or nc
          if score > bestCost and (avail or not single) then bestCost, best = score, n end
        end
      end
    end
  end
  return bestCost, best, comeFrom
end

-- Exploration orders tried in every round; Atlas keeps the best-scoring chain.
AtlasPlan.ORDERS = { "dear", "cheap", "insert", 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13 }

-- Cover every required edge of g with one walk that starts at node `start`.
-- opts.orders: exploration orders per round (default AtlasPlan.ORDERS).
-- opts.chain = true: score chains as Atlas.java does (most new required edges, then the
--   least time) and append the whole chain. Default: each round scores the chain to every
--   reachable new required edge by its own time and appends the best one; on the game map
--   this gives much faster tours (see README, results).
-- Returns {walk = edge labels in order (without the start loop), seconds, covered,
--          required, rounds, order = required labels in the order they were covered}.
function AtlasPlan.walk(g, start, opts)
  opts = opts or {}
  local orders = opts.orders or AtlasPlan.ORDERS
  local startLabel = g:add({ source = start, dest = start, weight = 0, mode = "start" })
  local total, nReq = 0, 0
  for l = 1, g.m do
    total = total + g.edges[l].weight
    if g.edges[l].required then nReq = nReq + 1 end
  end
  local VALUE = total + 1 -- one new required edge outweighs any amount of travel
  local single = not opts.chain
  local covered, nCovered, order = {}, 0, {}
  local function available(l)
    local e = g.edges[l]
    if not e.required or covered[l] then return false end
    for _, p in ipairs(e.prereq or {}) do if not covered[p] then return false end end
    return true
  end

  local walk, seconds, rounds = {}, 0, 0
  local last = startLabel
  while nCovered < nReq do
    rounds = rounds + 1
    local bestCost, best, links = 0, nil, nil
    for _, o in ipairs(orders) do
      local c, b, cf = round(g, last, o, VALUE, available, single)
      if b and c > bestCost then bestCost, best, links = c, b, cf end
    end
    if not best then break end -- the remaining required edges cannot be reached

    local chain, cur = {}, best
    while cur ~= last do chain[#chain + 1] = cur; cur = links[cur] end
    for i = #chain, 1, -1 do
      local l = chain[i]
      local e = g.edges[l]
      if g.removed[l] then break end -- a one-use teleport spent earlier in this chain
      walk[#walk + 1] = l
      seconds = seconds + e.weight
      local newly = available(l)
      if newly then
        covered[l] = true
        nCovered = nCovered + 1
        order[#order + 1] = l
      end
      if e.group then g:removeGroup(e.group) end
      last = l
    end
    if opts.yield then opts.yield() end
  end
  return { walk = walk, seconds = seconds, covered = nCovered, required = nReq,
           rounds = rounds, order = order }
end

-- Travel legs between two required edges: consecutive walks merge, and boarding + flight
-- hops + landing become one flight (as the in-game taxi).
local function legsOf(g, labels)
  local legs = {}
  for _, l in ipairs(labels) do
    local e = g.edges[l]
    local mode = e.mode
    local last = legs[#legs]
    if (mode == "fly" or mode == "land") and last and last.mode == "fly" then
      last.to = e.dest
      last.seconds = last.seconds + e.weight
      last.path[#last.path + 1] = e.dest
      if mode == "fly" then last.hops = last.hops + 1 end
    elseif mode == "walk" and last and last.mode == "walk" then
      last.to = e.dest
      last.seconds = last.seconds + e.weight
      last.path[#last.path + 1] = e.dest
    else
      legs[#legs + 1] = { mode = (mode == "board") and "fly" or mode, from = e.source, to = e.dest,
                          seconds = e.weight, name = e.name, hops = 0, path = { e.source, e.dest } }
    end
  end
  return legs
end
AtlasPlan.legsOf = legsOf

-- Quests -----------------------------------------------------------------------------------
-- quest = {id, name, giver, objectives = {place ids}, turnin, accepted, work, requires = {ids}}
-- Stops: {node, quest, name, kind = "accept"|"objective"|"turnin", work, after = {stop indices}}
-- `requires`: quests in the same log that must be handed in before this one is picked up.
function AtlasPlan.stops(world, quests)
  local stops = {}
  local turninOf, firstOf = {}, {}
  for _, q in ipairs(quests) do
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
  for _, q in ipairs(quests) do
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

-- Plan a quest tour. Returns {seconds, method = "atlas", stops, order = stop indices,
-- legs = {{stop, index, seconds (travel), travel = legs}}, rounds, unreachable = stop list}
function AtlasPlan.plan(world, profile, startId, quests, opts)
  local stops = AtlasPlan.stops(world, quests)
  local g = AtlasPlan.travelGraph(world, profile)
  local labelOf = {}
  for i, s in ipairs(stops) do
    labelOf[i] = g:add({ source = s.node, dest = s.node, weight = s.work, mode = "stop",
                         required = true, stop = i })
  end
  for i, s in ipairs(stops) do
    local pre = {}
    for _, a in ipairs(s.after) do pre[#pre + 1] = labelOf[a] end
    g.edges[labelOf[i]].prereq = pre
  end
  local r = AtlasPlan.walk(g, world:index(startId), opts)
  local legs, order, pending = {}, {}, {}
  for _, l in ipairs(r.walk) do
    local e = g.edges[l]
    if e.mode == "stop" then
      local travel = legsOf(g, pending)
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
  return { seconds = r.seconds, method = "atlas", stops = stops, order = order, legs = legs,
           rounds = r.rounds, unreachable = unreachable }
end

-- Fastest way (as Atlas finds it) from one place to another.
-- Returns seconds and travel legs, or nil if the destination cannot be reached.
function AtlasPlan.route(world, profile, fromId, toId)
  local g = AtlasPlan.travelGraph(world, profile)
  local dest = world:index(toId)
  g:add({ source = dest, dest = dest, weight = 0, mode = "stop", required = true })
  local r = AtlasPlan.walk(g, world:index(fromId))
  if r.covered < r.required then return nil end
  local travel = {}
  for _, l in ipairs(r.walk) do
    if g.edges[l].mode ~= "stop" and g.edges[l].mode ~= "start" then travel[#travel + 1] = l end
  end
  return r.seconds, legsOf(g, travel)
end

-- Fly every flight link this character can use (both directions): the flight links are
-- the required edges. Returns the walk as steps {mode, from, to, seconds, name}.
function AtlasPlan.cover(world, profile, startId)
  local g = AtlasPlan.travelGraph(world, profile)
  local req = 0
  for l = 1, g.m do
    if g.edges[l].mode == "fly" then g.edges[l].required = true; req = req + 1 end
  end
  local r = AtlasPlan.walk(g, world:index(startId))
  local steps = {}
  for _, l in ipairs(r.walk) do
    local e = g.edges[l]
    if e.mode ~= "start" then
      steps[#steps + 1] = { mode = e.mode, from = e.source, to = e.dest, seconds = e.weight,
                            name = e.name, required = e.required }
    end
  end
  return { steps = steps, seconds = r.seconds, covered = r.covered, required = req, rounds = r.rounds }
end

-- Atlas on any edge-labelled graph (e.g. an FSM from fsm.lua) with weights: every edge
-- required. Used to compare with the unit-cost Atlas.java on test FSMs.
function AtlasPlan.coverFSM(fsm, startNode)
  local g = newGraph()
  for l = 0, fsm.m - 1 do
    local e = fsm.edges[l]
    g:add({ source = e.source, dest = e.dest, weight = e.weight, mode = "edge", required = true, fsmLabel = l })
  end
  local r = AtlasPlan.walk(g, startNode or 0)
  local labels = {}
  for _, l in ipairs(r.walk) do
    if g.edges[l].fsmLabel then labels[#labels + 1] = g.edges[l].fsmLabel end
  end
  return { path = labels, weight = r.seconds, covered = r.covered, required = r.required, length = #labels }
end

ns.AtlasPlan = AtlasPlan
