-- Weighted Atlas: the professor's edge-coverage idea extended to travel costs and teleports.
--
-- Same round structure as Atlas (DFS post-order over the reachable edges, longest-path DP,
-- append the best chain), with three changes:
--   1. Score.  Atlas scores a chain by the number of new edges (all edges cost 1).
--      Here a chain scores  newRequired * BIG - weight,  i.e. most new required edges first,
--      cheapest among equals. BIG > total weight keeps the order lexicographic.
--   2. Required edges.  Only edges marked required need covering (rural postman); the rest
--      (walking, boats) are there to connect them. With every edge required this is the
--      plain Atlas problem with weights.
--   3. Bridging.  Atlas stops when no chain adds a new edge, which leaves edges uncovered
--      when they cannot be reached in the DFS order. Here the walk instead jumps to the
--      nearest uncovered required edge by the cheapest route, which may use teleports
--      (`jumps`: usable from any node, like a mage teleport). It stops only when every
--      required edge is covered or the rest are unreachable.
-- Also: the walk's last edge is kept (Atlas.java drops it, see atlas.lua).
--
-- Graph: an FSM-shaped graph (fsm.lua) with edge.weight; edge.required defaults to true.
local _, ns = ...
local Heap = ns.Heap

local Coverage = {}
local NEG, INF = -math.huge, math.huge

local function required(e) return e.required ~= false end

local function dfsOrder(g, startLabel, mark)
  local stack, frames = {}, { { e = startLabel, i = 0 } }
  mark[startLabel] = true
  while #frames > 0 do
    local f = frames[#frames]
    local nbrs = g:outEdges(g.edges[f.e].dest)
    local advanced = false
    while f.i < #nbrs do
      f.i = f.i + 1
      local n = nbrs[f.i]
      if not mark[n] then
        mark[n] = true
        frames[#frames + 1] = { e = n, i = 0 }
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

-- Strongly connected components of the node graph (edges + jumps), and which components
-- can reach which. Used to stop the walk from entering a part of the graph it cannot leave
-- while required edges elsewhere are still uncovered.
local function components(g, jumps)
  local nodes = {}
  for v in pairs(g.out) do nodes[#nodes + 1] = v end
  table.sort(nodes)
  local function succ(u)
    local r = {}
    for _, l in ipairs(g.out[u] or {}) do r[#r + 1] = g.edges[l].dest end
    for _, t in ipairs(jumps or {}) do
      if not (t.allowedFrom and not t.allowedFrom(u)) then r[#r + 1] = t.to end
    end
    return r
  end
  -- iterative Tarjan
  local index, low, onStack, comp = {}, {}, {}, {}
  local stack, counter, ncomp = {}, 0, 0
  for _, root in ipairs(nodes) do
    if not index[root] then
      local frames = { { v = root, s = succ(root), i = 0 } }
      counter = counter + 1
      index[root], low[root] = counter, counter
      stack[#stack + 1] = root; onStack[root] = true
      while #frames > 0 do
        local f = frames[#frames]
        if f.i < #f.s then
          f.i = f.i + 1
          local w = f.s[f.i]
          if not index[w] then
            counter = counter + 1
            index[w], low[w] = counter, counter
            stack[#stack + 1] = w; onStack[w] = true
            frames[#frames + 1] = { v = w, s = succ(w), i = 0 }
          elseif onStack[w] and index[w] < low[f.v] then
            low[f.v] = index[w]
          end
        else
          frames[#frames] = nil
          local p = frames[#frames]
          if p and low[f.v] < low[p.v] then low[p.v] = low[f.v] end
          if low[f.v] == index[f.v] then
            ncomp = ncomp + 1
            repeat
              local w = table.remove(stack)
              onStack[w] = nil
              comp[w] = ncomp
            until w == f.v
          end
        end
      end
    end
  end
  -- reach[c][d]: component d reachable from c (Tarjan numbers sinks first)
  local cedges = {}
  for c = 1, ncomp do cedges[c] = {} end
  for _, u in ipairs(nodes) do
    for _, v in ipairs(succ(u)) do
      if comp[u] ~= comp[v] then cedges[comp[u]][comp[v]] = true end
    end
  end
  local reach = {}
  for c = 1, ncomp do
    local r = { [c] = true }
    for d in pairs(cedges[c]) do for x in pairs(reach[d]) do r[x] = true end end
    reach[c] = r
  end
  return comp, reach
end

-- May the walk move from node u to node v (by edge `l`, or by a jump when l is nil)?
-- Within a component always. Into another component only if every uncovered required
-- edge, other than `l` itself, is still reachable from there.
local function crossingOK(g, u, v, l, comp, reach, pending)
  local from, to = comp[u], comp[v]
  if from == to then return true end
  local selfCovers = l and required(g.edges[l]) and not pending.covered[l]
  for c, count in pairs(pending) do
    if not reach[to][c] then
      local own = (selfCovers and c == from) and 1 or 0
      if count - own > 0 then return false end
    end
  end
  return true
end

-- Uncovered required edges per component of their source.
local function pendingBySource(g, covered, comp)
  local p = {}
  for l = 0, g.m - 1 do
    local e = g.edges[l]
    if required(e) and not covered[l] then
      local c = comp[e.source]
      p[c] = (p[c] or 0) + 1
    end
  end
  return setmetatable(p, { __index = { covered = covered } })
end

-- Cheapest way from `node` to the source of any uncovered required edge.
-- Returns list of steps ({edge = label} or {jump = j}) and the target edge label.
local function bridge(g, node, covered, jumps, comp, reach)
  local pending = pendingBySource(g, covered, comp)
  local targets = {}
  for l = 0, g.m - 1 do
    local e = g.edges[l]
    if required(e) and not covered[l] and not targets[e.source]
       and crossingOK(g, e.source, e.dest, l, comp, reach, pending) then
      targets[e.source] = l
    end
  end
  local dist, prev = { [node] = 0 }, {}
  local heap = Heap.new()
  heap:push(0, node)
  while not heap:empty() do
    local d, u = heap:pop()
    if d <= dist[u] then
      if targets[u] then
        local steps, v = {}, u
        while prev[v] do table.insert(steps, 1, prev[v].step); v = prev[v].from end
        return steps, targets[u], d
      end
      local function relax(v, c, step)
        if d + c < (dist[v] or INF) then
          dist[v] = d + c
          prev[v] = { from = u, step = step }
          heap:push(d + c, v)
        end
      end
      for _, l in ipairs(g.out[u] or {}) do
        local v = g.edges[l].dest
        if crossingOK(g, u, v, l, comp, reach, pending) then relax(v, g.edges[l].weight, { edge = l }) end
      end
      for j, t in ipairs(jumps or {}) do
        if not (t.allowedFrom and not t.allowedFrom(u))
           and crossingOK(g, u, t.to, nil, comp, reach, pending) then
          relax(t.to, t.cost, { jump = j })
        end
      end
    end
  end
  return nil
end

-- Returns {steps = list of {edge=label}|{jump=index}, weight, covered, required, length}
function Coverage.run(g, startNode, opts)
  opts = opts or {}
  local jumps = opts.jumps or {}
  local totalW, nReq = 0, 0
  for l = 0, g.m - 1 do
    totalW = totalW + g.edges[l].weight
    if required(g.edges[l]) then nReq = nReq + 1 end
  end
  local BIG = totalW + 1
  local covered, nCovered = {}, 0
  local steps, weight = {}, 0
  local function take(l)
    steps[#steps + 1] = { edge = l }
    weight = weight + g.edges[l].weight
    if required(g.edges[l]) and not covered[l] then
      covered[l] = true
      nCovered = nCovered + 1
    end
  end

  local comp, reach = components(g, jumps)
  local node = startNode
  while nCovered < nReq do
    -- bridge to the nearest uncovered required edge (zero steps if one leaves `node`)
    local path, target = bridge(g, node, covered, jumps, comp, reach)
    if not path then break end
    for _, s in ipairs(path) do
      if s.edge then take(s.edge)
      else
        steps[#steps + 1] = { jump = s.jump }
        weight = weight + jumps[s.jump].cost
      end
    end
    take(target)
    local last = target
    -- Atlas rounds from the last edge
    while true do
      local pending = pendingBySource(g, covered, comp)
      local mark = {}
      local stack = dfsOrder(g, last, mark)
      local cost, comeFrom, visited = { [last] = 0 }, {}, {}
      local bestCost, best = 0, nil
      for s = #stack, 1, -1 do
        local e = stack[s]
        visited[e] = true
        local ce = cost[e]
        if ce then
          for _, n in ipairs(g:outEdges(g.edges[e].dest)) do
            local en = g.edges[n]
            if not visited[n] and crossingOK(g, en.source, en.dest, n, comp, reach, pending) then
              local gain = (required(en) and not covered[n]) and BIG or 0
              local nc = ce + gain - en.weight
              if nc > (cost[n] or NEG) then
                cost[n] = nc
                comeFrom[n] = e
                if nc > bestCost then bestCost, best = nc, n end
              end
            end
          end
        end
      end
      if not best then break end -- no chain adds a required edge
      local chain = {}
      local cur = best
      while cur ~= last do chain[#chain + 1] = cur; cur = comeFrom[cur] end
      for i = #chain, 1, -1 do take(chain[i]) end
      last = best
    end
    node = g.edges[last].dest
  end
  return { steps = steps, weight = weight, covered = nCovered, required = nReq,
           length = #steps }
end

-- Rural Postman construction (the classic heuristic, Frederickson 1979 style):
--   1. the required edges fall into connected pieces (plus the start node);
--   2. join the pieces with a minimum spanning tree whose edge cost is the round trip
--      between two pieces, adding both shortest paths;
--   3. balance in/out degrees with min-cost flow over all edges and jumps (cpp.lua);
--   4. Euler walk from the start.
-- Exact when the required edges are already connected (then it is the CPP with optional
-- edges); otherwise step 2 can over-pay.
-- Returns the same shape as Coverage.run, or nil if some required edge is unreachable.
function Coverage.rpp(g, startNode, opts)
  opts = opts or {}
  local jumps = opts.jumps or {}
  local nodes = {}
  for v in pairs(g.out) do nodes[#nodes + 1] = v end
  table.sort(nodes)
  local arcs, base = {}, {}
  local outArcs = {}
  for _, v in ipairs(nodes) do outArcs[v] = {} end
  local function addArc(from, to, cost, ref)
    arcs[#arcs + 1] = { from = from, to = to, cost = cost, ref = ref }
    table.insert(outArcs[from], #arcs)
    return #arcs
  end
  for l = 0, g.m - 1 do
    local e = g.edges[l]
    local i = addArc(e.source, e.dest, e.weight, { edge = l })
    base[i] = required(e) and 1 or 0
  end
  for j, t in ipairs(jumps) do
    for _, v in ipairs(nodes) do
      if v ~= t.to and not (t.allowedFrom and not t.allowedFrom(v)) then
        addArc(v, t.to, t.cost, { jump = j })
      end
    end
  end

  -- 1. pieces: union-find over endpoints of required edges, plus the start
  local parent = {}
  local function find(x)
    while parent[x] ~= x do parent[x] = parent[parent[x]]; x = parent[x] end
    return x
  end
  local function touch(x) if not parent[x] then parent[x] = x end end
  touch(startNode)
  for l = 0, g.m - 1 do
    local e = g.edges[l]
    if required(e) then
      touch(e.source); touch(e.dest)
      local a, b = find(e.source), find(e.dest)
      if a ~= b then parent[a] = b end
    end
  end
  local roots, members = {}, {}
  for x in pairs(parent) do
    local r = find(x)
    if not members[r] then members[r] = {}; roots[#roots + 1] = r end
    table.insert(members[r], x)
  end
  table.sort(roots)
  local pieces = {}
  for k, r in ipairs(roots) do pieces[k] = members[r] end

  -- shortest paths from a whole piece (multi-source Dijkstra over arcs)
  local function fromPiece(k)
    local dist, prev = {}, {}
    local heap = Heap.new()
    for _, v in ipairs(pieces[k]) do dist[v] = 0; heap:push(0, v) end
    while not heap:empty() do
      local d, u = heap:pop()
      if d <= dist[u] then
        for _, i in ipairs(outArcs[u]) do
          local a = arcs[i]
          if d + a.cost < (dist[a.to] or INF) then
            dist[a.to] = d + a.cost
            prev[a.to] = i
            heap:push(d + a.cost, a.to)
          end
        end
      end
    end
    return { dist = dist, prev = prev }
  end
  local np = #pieces
  local sp = {}
  for k = 1, np do sp[k] = fromPiece(k) end
  -- cheapest arrival node of piece b from piece a
  local function link(a, b)
    local best, at = INF, nil
    for _, v in ipairs(pieces[b]) do
      local d = sp[a].dist[v] or INF
      if d < best then best, at = d, v end
    end
    return best, at
  end
  local function addPath(a, at)
    local prev = sp[a].prev
    local v = at
    while prev[v] do
      local i = prev[v]
      base[i] = (base[i] or 0) + 1
      v = arcs[i].from
    end
  end

  -- 2. Prim's MST on round-trip cost
  local inTree = { [1] = true }
  for _ = 2, np do
    local best, ba, bb = INF, nil, nil
    for a = 1, np do
      if inTree[a] then
        for b = 1, np do
          if not inTree[b] then
            local c = link(a, b) + link(b, a)
            if c < best then best, ba, bb = c, a, b end
          end
        end
      end
    end
    if not ba then return nil end -- a piece cannot be reached
    local _, at1 = link(ba, bb)
    local _, at2 = link(bb, ba)
    addPath(ba, at1)
    addPath(bb, at2)
    inTree[bb] = true
  end

  -- 3 + 4
  local r = ns.CPP.balanceAndWalk(nodes, arcs, base, startNode)
  if not r then return nil end
  local steps, covered, seen, nReq = {}, 0, {}, 0
  for l = 0, g.m - 1 do if required(g.edges[l]) then nReq = nReq + 1 end end
  for _, i in ipairs(r.arcs) do
    local ref = arcs[i].ref
    steps[#steps + 1] = ref
    if ref.edge and required(g.edges[ref.edge]) and not seen[ref.edge] then
      seen[ref.edge] = true
      covered = covered + 1
    end
  end
  return { steps = steps, weight = r.weight, covered = covered, required = nReq, length = #steps }
end

-- Lower bound for the rural postman: every required edge once.
function Coverage.lowerBound(g)
  local w = 0
  for l = 0, g.m - 1 do if required(g.edges[l]) then w = w + g.edges[l].weight end end
  return w
end

-- Build an FSM-shaped graph from the world for one character. Required: every flight link
-- the character can fly, both directions ("ride the whole flight network").
-- Jumps: the character's mage teleports (hearthstone is left out: one use per hour).
function Coverage.fromWorld(world, profile)
  local g = ns.FSM.new()
  local reqCount = 0
  for i = 1, #world.nodes do
    for _, e in ipairs(world.adj[i]) do
      if world:allowed(e, profile) then
        local l = g:addEdge(e.from, e.to, 0, 0, world:edgeCost(e, profile))
        g.edges[l].mode = e.mode
        g.edges[l].required = (e.mode == "fly")
        if e.mode == "fly" then reqCount = reqCount + 1 end
      end
    end
  end
  local jumps = {}
  for _, t in ipairs(world.teleports) do
    if world:allowed(t, profile) then
      jumps[#jumps + 1] = { to = t.to, cost = t.cost, name = t.name,
                            allowedFrom = function(u) return world.nodes[u].kind == "ground" end }
    end
  end
  return g, jumps, reqCount
end

ns.Coverage = Coverage
