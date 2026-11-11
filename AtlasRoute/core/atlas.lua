-- Faithful Lua port of Atlas.java (github.com/savastakan/atlas @ 1748ccf).
--
-- Atlas covers every edge of a graph with one walk. Each round it:
--   1. orders the edges reachable from the walk's last edge by DFS post-order,
--   2. runs a longest-path DP over that order, where an edge is worth 1 if it is not
--      yet on the walk and 0 if it is,
--   3. appends the best-scoring chain to the walk,
-- and stops when no chain adds a new edge. Edge weights are ignored (every edge costs 1).
--
-- Differences from the Java code, none of which change the output:
--   * the DFS is iterative (Java recursion depth = edge count);
--   * "path.contains(e)" is a counter lookup instead of a linear list scan;
--   * if no edge can be relaxed the Java code indexes cost[Integer.MIN_VALUE] and throws;
--     here that case ends the walk.
local _, ns = ...

local Atlas = {}
local NEG = -math.huge

-- Post-order DFS over edges, matching Atlas.dfs(). Marks reached edges in cost[] with NEG.
local function dfsOrder(g, startLabel, cost)
  local stack = {}
  local frames = { { e = startLabel, i = 0 } }
  cost[startLabel] = NEG
  while #frames > 0 do
    local f = frames[#frames]
    local nbrs = g:outEdges(g.edges[f.e].dest)
    local advanced = false
    while f.i < #nbrs do
      f.i = f.i + 1
      local n = nbrs[f.i]
      if cost[n] ~= NEG then
        cost[n] = NEG
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

-- Returns the walk as a list of edge labels.
function Atlas.longestPath(g, start, keepLast)
  local path = { start }
  local onPath = { [start] = 1 }
  while true do
    local currentStart = path[#path]
    path[#path] = nil
    onPath[currentStart] = onPath[currentStart] - 1

    local cost = {}
    for l = 0, g.m - 1 do cost[l] = 0 end
    local stack = dfsOrder(g, currentStart, cost)
    local comeFrom = {}
    for l = 0, g.m - 1 do comeFrom[l] = cost[l] end
    cost[currentStart] = 0

    local visited = {}
    local currentCost, current = NEG, nil
    for s = #stack, 1, -1 do
      local e = stack[s]
      visited[e] = true
      for _, n in ipairs(g:outEdges(g.edges[e].dest)) do
        if not visited[n] then
          local newCost = cost[e] + (((onPath[n] or 0) > 0) and 0 or 1)
          if cost[n] < newCost then
            cost[n] = newCost
            comeFrom[n] = e
            if currentCost < cost[n] then
              currentCost = cost[n]
              current = n
            end
          end
        end
      end
    end

    if current == nil or cost[current] <= 0 then
      -- Java returns here after path.removeLast(), so the walk's final edge is dropped.
      -- keepLast = true puts it back (see Atlas.stats: the drop can leave an edge uncovered).
      if keepLast then
        path[#path + 1] = currentStart
        onPath[currentStart] = onPath[currentStart] + 1
      end
      return path
    end
    -- Java: path.add(current); then walk comeFrom back, inserting each before it.
    local chain = { current }
    while comeFrom[current] >= 0 do
      current = comeFrom[current]
      chain[#chain + 1] = current
    end
    for i = #chain, 1, -1 do
      local e = chain[i]
      path[#path + 1] = e
      onPath[e] = (onPath[e] or 0) + 1
    end
  end
end

-- Same string Atlas.run() returns: comma-separated inputs along the walk.
function Atlas.testSuite(g, path)
  local parts = {}
  for i, e in ipairs(path) do parts[i] = tostring(g.edges[e].input) end
  return table.concat(parts, ",")
end

function Atlas.run(g, keepLast)
  local path = Atlas.longestPath(g, g:firstStart(), keepLast)
  return Atlas.testSuite(g, path), path
end

-- How many distinct edges the walk covers, and its total weight.
function Atlas.stats(g, path)
  local seen, distinct, weight = {}, 0, 0
  for _, e in ipairs(path) do
    if not seen[e] then seen[e] = true; distinct = distinct + 1 end
    weight = weight + g.edges[e].weight
  end
  return { length = #path, covered = distinct, total = g.m, weight = weight }
end

ns.Atlas = Atlas
