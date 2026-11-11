-- Quest tour: the order to visit every quest stop (accept -> objectives -> turn in) that
-- minimises total travel time, using the multimodal router for every leg.
--
--   1. Router.search from the start and from every stop gives two travel-time matrices:
--        noH[i][j]  fastest i -> j without the hearthstone
--        useH[i][j] fastest i -> j that uses the hearthstone on the way
--   2. Ordering:
--        exact     Held-Karp DP over (visited set, last stop, hearthstone still unused),
--                  only adding stop j once its prerequisites are in the set. O(2^n * n^2).
--        heuristic for larger logs: precedence-safe nearest-neighbour start, then Or-opt
--                  (move a block of 1-3 stops elsewhere) until no move helps.
--   The hearthstone is spent at most once per plan; the DP decides on which leg.
--
-- Stops: { node = world index, quest = quest id, kind = "accept"|"objective"|"turnin",
--          work = seconds spent at the stop, after = {stop indices that must come first} }
local _, ns = ...
local Router = ns.Router

local bit = bit or bit32 -- WoW and LuaJIT provide `bit`
local band, bor, lshift = bit.band, bit.bor, bit.lshift

local Tour = {}
local INF = math.huge

Tour.EXACT_LIMIT = 13 -- stops; 2^13 * 13 * 2 states

-- Turn quest definitions into stops. quest = {id, name, giver, objectives = {place ids},
-- turnin, accepted = bool, work = seconds per objective}
function Tour.stops(world, quests)
  local stops = {}
  for _, q in ipairs(quests) do
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
    end
  end
  return stops
end

-- Travel-time matrices. Index 0 is the start node, 1..n the stops.
function Tour.matrices(world, profile, startNode, stops)
  local pts = { [0] = startNode }
  for i, s in ipairs(stops) do pts[i] = s.node end
  local noH, useH = {}, {}
  local cache = {}
  for i = 0, #stops do
    local src = pts[i]
    local res = cache[src]
    if not res then
      local dist, prev = Router.search(world, profile, src, true)
      res = { dist = dist, prev = prev }
      cache[src] = res
    end
    noH[i], useH[i] = {}, {}
    for j = 1, #stops do
      local dst = pts[j]
      if profile.hearth then
        noH[i][j] = res.dist[Router.sid(dst, 1)] or INF
        useH[i][j] = res.dist[Router.sid(dst, 0)] or INF
      else
        noH[i][j] = res.dist[Router.sid(dst, 0)] or INF
        useH[i][j] = INF
      end
    end
  end
  return { noH = noH, useH = useH, pts = pts, cache = cache }
end

-- Cost of a fixed order, choosing the best leg for the hearthstone. Returns cost, hearthLeg.
function Tour.orderCost(M, order, stops)
  local total, bestGain, bestLeg = 0, 0, nil
  local prev = 0
  for k, j in ipairs(order) do
    local a, b = M.noH[prev][j], M.useH[prev][j]
    total = total + a + stops[j].work
    if b < a and (a - b) > bestGain then bestGain, bestLeg = a - b, k end
    prev = j
  end
  return total - bestGain, bestLeg
end

local function feasible(order, stops)
  local pos = {}
  for k, j in ipairs(order) do pos[j] = k end
  for k, j in ipairs(order) do
    for _, p in ipairs(stops[j].after) do
      if (pos[p] or INF) > k then return false end
    end
  end
  return true
end
Tour.feasible = feasible

-- Exact Held-Karp. `yield` (optional) is called every few thousand states so the game can
-- run it in a coroutine without freezing a frame.
function Tour.exact(M, stops, yield)
  local n = #stops
  local need = {}
  for j = 1, n do
    local m = 0
    for _, p in ipairs(stops[j].after) do m = bor(m, lshift(1, p - 1)) end
    need[j] = m
  end
  -- dp[h][mask * (n+1) + last]; h = 1 hearth unused, h = 2 used
  local W = n + 1
  local dp = { {}, {} }
  local par = { {}, {} }
  for j = 1, n do
    if need[j] == 0 then
      local key = lshift(1, j - 1) * W + j
      local w = stops[j].work
      local a, b = M.noH[0][j] + w, M.useH[0][j] + w
      dp[1][key] = a
      if b < INF then dp[2][key] = b; par[2][key] = { 0, 0, 1 } end
    end
  end
  local full = lshift(1, n) - 1
  local steps = 0
  for mask = 1, full do
    for last = 1, n do
      if band(mask, lshift(1, last - 1)) ~= 0 then
        local key = mask * W + last
        for h = 1, 2 do
          local cur = dp[h][key]
          if cur then
            for j = 1, n do
              local bj = lshift(1, j - 1)
              if band(mask, bj) == 0 and band(mask, need[j]) == need[j] then
                local nk = bor(mask, bj) * W + j
                local w = stops[j].work
                local c = cur + M.noH[last][j] + w
                if c < (dp[h][nk] or INF) then dp[h][nk] = c; par[h][nk] = { mask, last, h } end
                if h == 1 then
                  local c2 = cur + M.useH[last][j] + w
                  if c2 < (dp[2][nk] or INF) then dp[2][nk] = c2; par[2][nk] = { mask, last, 1 } end
                end
              end
            end
          end
        end
        steps = steps + 1
        if yield and steps % 4000 == 0 then yield() end
      end
    end
  end
  local best, bh, bl = INF, nil, nil
  for h = 1, 2 do
    for last = 1, n do
      local c = dp[h][full * W + last]
      if c and c < best then best, bh, bl = c, h, last end
    end
  end
  if not bl then return nil end
  local order = {}
  local mask, last, h = full, bl, bh
  while last and last > 0 do
    table.insert(order, 1, last)
    local p = par[h][mask * W + last]
    if not p then break end
    mask, last, h = p[1], p[2], p[3]
  end
  return order, best
end

-- Heuristic: nearest feasible stop first, then Or-opt with blocks of 1..3.
function Tour.heuristic(M, stops, yield)
  local n = #stops
  local done, order = {}, {}
  local prev = 0
  for _ = 1, n do
    local best, bj = INF, nil
    for j = 1, n do
      if not done[j] then
        local ok = true
        for _, p in ipairs(stops[j].after) do if not done[p] then ok = false; break end end
        if ok and M.noH[prev][j] < best then best, bj = M.noH[prev][j], j end
      end
    end
    if not bj then -- unreachable stop: append the rest in any feasible order
      for j = 1, n do if not done[j] then bj = j; break end end
    end
    done[bj] = true
    order[#order + 1] = bj
    prev = bj
  end
  local cost = Tour.orderCost(M, order, stops)
  local improved = true
  while improved do
    improved = false
    for len = 1, 3 do
      for i = 1, n - len + 1 do
        local block = {}
        for k = i, i + len - 1 do block[#block + 1] = order[k] end
        local rest = {}
        for k = 1, n do if k < i or k >= i + len then rest[#rest + 1] = order[k] end end
        for pos = 0, #rest do
          if pos ~= i - 1 then
            local cand = {}
            for k = 1, pos do cand[#cand + 1] = rest[k] end
            for _, b in ipairs(block) do cand[#cand + 1] = b end
            for k = pos + 1, #rest do cand[#cand + 1] = rest[k] end
            if feasible(cand, stops) then
              local c = Tour.orderCost(M, cand, stops)
              if c < cost - 1e-9 then
                order, cost, improved = cand, c, true
                break
              end
            end
          end
        end
        if improved then break end
      end
      if improved then break end
    end
    if yield then yield() end
  end
  return order, cost
end

-- Full plan. opts = {method = "auto"|"exact"|"heuristic", yield = fn}
-- Returns {order, seconds, method, legs = {{stop, seconds, travel legs}}, hearthLeg}
function Tour.plan(world, profile, startId, quests, opts)
  opts = opts or {}
  local stops = Tour.stops(world, quests)
  local startNode = world:index(startId)
  local M = Tour.matrices(world, profile, startNode, stops)
  local method = opts.method or "auto"
  if method == "auto" then method = (#stops <= Tour.EXACT_LIMIT) and "exact" or "heuristic" end
  local order
  if #stops == 0 then
    order = {}
  elseif method == "exact" then
    order = Tour.exact(M, stops, opts.yield)
  else
    order = Tour.heuristic(M, stops, opts.yield)
  end
  local seconds, hearthLeg = Tour.orderCost(M, order, stops)
  -- Expand each leg into its travel steps.
  local legs = {}
  local prev = 0
  for k, j in ipairs(order) do
    local res = M.cache[M.pts[prev]]
    local useHearth = (k == hearthLeg)
    -- With the hearthstone: shortest path to (dst, used). Without: (dst, unused) when a
    -- hearthstone exists, else (dst, 0).
    local state
    if useHearth then
      state = Router.sid(stops[j].node, 0)
    else
      state = Router.sid(stops[j].node, profile.hearth and 1 or 0)
    end
    local travel = Router.legs(world, res.dist, res.prev, state)
    legs[#legs + 1] = { stop = stops[j], index = j, seconds = res.dist[state], travel = travel }
    prev = j
  end
  return { order = order, seconds = seconds, method = method, stops = stops,
           legs = legs, hearthLeg = hearthLeg, matrices = M }
end

ns.Tour = Tour
