-- Exact open directed Chinese Postman: the cheapest walk that starts at a given node, may end
-- anywhere, and uses every edge at least once. Used as the optimum Atlas is measured against.
--
-- A walk from s to t uses every edge iff the multigraph (edges + repeated copies) has
--   out(v) - in(v) = [v = s] - [v = t]  for every v.
-- Repeating a shortest u -> w path adds one out at u and one in at w, so choosing the copies
-- is a min-cost flow: supply(v) = in(v) - out(v) + [v = s], demand where negative, plus one
-- unit that may end anywhere (a zero-cost arc from every node to a sink T, capacity 1).
-- Solved with successive shortest paths (Dijkstra with potentials), then Hierholzer.
--
-- Works on the FSM graph (fsm.lua): g.edges[label] = {source, dest, weight}.
local _, ns = ...
local Heap = ns.Heap

local CPP = {}
local INF = math.huge

-- Minimal min-cost-flow network.
local function newNet() return { head = {}, arcs = {} } end
local function addArc(net, u, v, cap, cost, tag)
  local a = { to = v, cap = cap, cost = cost, tag = tag }
  local r = { to = u, cap = 0, cost = -cost }
  a.rev, r.rev = r, a
  net.head[u] = net.head[u] or {}
  net.head[v] = net.head[v] or {}
  table.insert(net.head[u], a)
  table.insert(net.head[v], r)
  net.arcs[#net.arcs + 1] = a
  return a
end

local function minCostFlow(net, S, T, need)
  local pot = {}
  for v in pairs(net.head) do pot[v] = 0 end
  local flow, cost = 0, 0
  while flow < need do
    local dist, prevArc = {}, {}
    local heap = Heap.new()
    dist[S] = 0
    heap:push(0, S)
    while not heap:empty() do
      local d, u = heap:pop()
      if d <= (dist[u] or INF) then
        for _, a in ipairs(net.head[u]) do
          if a.cap > 0 then
            local nd = d + a.cost + pot[u] - pot[a.to]
            if nd < (dist[a.to] or INF) - 1e-9 then
              dist[a.to] = nd
              prevArc[a.to] = a
              heap:push(nd, a.to)
            end
          end
        end
      end
    end
    if not dist[T] then return nil end -- infeasible
    for v in pairs(net.head) do
      if dist[v] then pot[v] = pot[v] + dist[v] end
    end
    local push = need - flow
    local v = T
    while v ~= S do
      local a = prevArc[v]
      if a.cap < push then push = a.cap end
      v = a.rev.to
    end
    v = T
    while v ~= S do
      local a = prevArc[v]
      a.cap = a.cap - push
      a.rev.cap = a.rev.cap + push
      cost = cost + push * a.cost
      v = a.rev.to
    end
    flow = flow + push
  end
  return cost
end

-- Generic core: given arcs {from, to, cost} and how many times each must be used
-- (base[i] >= 0), add the cheapest extra copies so that an open walk from `start` uses
-- every arc its count of times, then return that walk.
-- Returns {arcs = list of arc indices in walk order, weight} or nil if infeasible.
-- The caller must make sure the arcs with base > 0 and `start` are connected.
function CPP.balanceAndWalk(nodes, arcs, base, start)
  local outDeg, inDeg = {}, {}
  for _, v in ipairs(nodes) do outDeg[v], inDeg[v] = 0, 0 end
  local need0, weight = 0, 0
  for i, a in ipairs(arcs) do
    local k = base[i] or 0
    if k > 0 then
      outDeg[a.from] = outDeg[a.from] + k
      inDeg[a.to] = inDeg[a.to] + k
      weight = weight + k * a.cost
      need0 = need0 + k
    end
  end
  local net = newNet()
  local S, T, SINK = {}, {}, {} -- unique keys that cannot clash with node ids
  local need = 0
  for _, v in ipairs(nodes) do
    local supply = inDeg[v] - outDeg[v] + ((v == start) and 1 or 0)
    if supply > 0 then addArc(net, S, v, supply, 0); need = need + supply end
    if supply < 0 then addArc(net, v, SINK, -supply, 0) end
    addArc(net, v, T, 1, 0) -- the walk may end here
  end
  addArc(net, T, SINK, 1, 0)
  local copies = {}
  for i, a in ipairs(arcs) do copies[i] = addArc(net, a.from, a.to, INF, a.cost) end
  local extra = minCostFlow(net, S, SINK, need)
  if not extra then return nil end

  local mult, total = {}, 0
  for _, v in ipairs(nodes) do mult[v] = {} end
  for i, a in ipairs(arcs) do
    local times = (base[i] or 0) + copies[i].rev.cap -- flow on the arc = extra traversals
    for _ = 1, times do table.insert(mult[a.from], i) end
    total = total + times
  end
  -- Hierholzer (iterative)
  local rwalk, st = {}, { { node = start } }
  while #st > 0 do
    local top = st[#st]
    local list = mult[top.node]
    if #list > 0 then
      local i = table.remove(list)
      st[#st + 1] = { node = arcs[i].to, arc = i }
    else
      table.remove(st)
      if top.arc then rwalk[#rwalk + 1] = top.arc end
    end
  end
  if #rwalk ~= total then return nil end -- not connected
  local walk = {}
  for i = #rwalk, 1, -1 do walk[#walk + 1] = rwalk[i] end
  return { arcs = walk, weight = weight + extra }
end

-- Open directed Chinese Postman on an FSM-shaped graph: every edge at least once.
-- Returns {path = list of edge labels, weight, length} or nil if some edge is unreachable.
function CPP.solve(g, startNode)
  startNode = startNode or 0
  local nodes = {}
  for v in pairs(g.out) do nodes[#nodes + 1] = v end
  table.sort(nodes)
  local arcs, base = {}, {}
  for l = 0, g.m - 1 do
    local e = g.edges[l]
    arcs[l + 1] = { from = e.source, to = e.dest, cost = e.weight }
    base[l + 1] = 1
  end
  local r = CPP.balanceAndWalk(nodes, arcs, base, startNode)
  if not r then return nil end
  local path = {}
  for i, a in ipairs(r.arcs) do path[i] = a - 1 end
  return { path = path, weight = r.weight, length = #path }
end

ns.CPP = CPP
