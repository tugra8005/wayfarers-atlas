-- Quest tour: the order to visit every quest stop (accept -> objectives -> turn in) that
-- minimises total travel time, using the multimodal router for every leg.
--
--   1. One Router.search from the start and from every stop, with every one-use teleport
--      available, gives D[i][j][C] = fastest i -> j spending exactly the teleport set C
--      (the search state is (node, spent set), so this is read off directly).
--   2. Ordering:
--        exact     Held-Karp DP over (visited stops, last stop, teleports spent), adding stop
--                  j only once its prerequisites are visited; each leg may spend any set C
--                  of teleports not spent yet. O(2^n * n^2 * 3^K) for K one-use teleports.
--        heuristic for larger logs: precedence-safe nearest-neighbour start, then Or-opt
--                  (move a block of 1-3 stops elsewhere) until no move helps. A fixed order's
--                  best use of the teleports is found exactly by a DP over legs.
--
-- Stops: { node = world index, quest = quest id, kind = "accept"|"objective"|"turnin",
--          work = seconds spent at the stop, after = {stop indices that must come first} }
local _, ns = ...
local Router = ns.Router

local bit = bit or bit32 -- WoW and LuaJIT provide `bit`
local band, bor, lshift = bit.band, bit.bor, bit.lshift

local Tour = {}
local INF = math.huge

-- Exact search is used while 2^n * n^2 * 3^K stays under this (13 stops with one teleport).
Tour.EXACT_BUDGET = 2 ^ 13 * 13 * 13 * 3

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

-- Travel-time tables. Index 0 is the start node, 1..n the stops. D[i][j][C + 1].
function Tour.matrices(world, profile, startNode, stops)
  local ctx = Router.context(world, profile)
  local pts = { [0] = startNode }
  for i, s in ipairs(stops) do pts[i] = s.node end
  local D, cache = {}, {}
  for i = 0, #stops do
    local src = pts[i]
    local res = cache[src]
    if not res then
      local dist, prev = Router.search(world, profile, src, true, ctx)
      res = { dist = dist, prev = prev }
      cache[src] = res
    end
    D[i] = {}
    for j = 1, #stops do
      local row = {}
      for C = 0, ctx.S - 1 do
        row[C + 1] = res.dist[Router.sid(ctx, pts[j], C)] or INF
      end
      D[i][j] = row
    end
  end
  return { D = D, S = ctx.S, ctx = ctx, pts = pts, cache = cache }
end

-- Cost of a fixed order with the best use of the one-use teleports.
-- Returns cost and, per leg, the teleport set it spends.
function Tour.orderCost(M, order, stops)
  local S = M.S
  local best = { [0] = 0 }
  local parents = {}
  local prev = 0
  for k, j in ipairs(order) do
    local nb, par = {}, {}
    local row = M.D[prev][j]
    local w = stops[j].work
    for U, c in pairs(best) do
      for C = 0, S - 1 do
        if band(C, U) == 0 then
          local d = row[C + 1]
          if d < INF then
            local nu = bor(U, C)
            local v = c + d + w
            if v < (nb[nu] or INF) then nb[nu] = v; par[nu] = { U, C } end
          end
        end
      end
    end
    best = nb
    parents[k] = par
    prev = j
  end
  local cost, U = INF, nil
  for u, c in pairs(best) do if c < cost then cost, U = c, u end end
  if not U then return INF, {} end
  local spend = {}
  for k = #order, 1, -1 do
    local p = parents[k][U]
    spend[k] = p[2]
    U = p[1]
  end
  return cost, spend
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
  local n, S = #stops, M.S
  local need = {}
  for j = 1, n do
    local m = 0
    for _, p in ipairs(stops[j].after) do m = bor(m, lshift(1, p - 1)) end
    need[j] = m
  end
  local W = n + 1
  local function key(mask, last, U) return (mask * W + last) * S + U end
  local dp, par = {}, {}
  for j = 1, n do
    if need[j] == 0 then
      for C = 0, S - 1 do
        local d = M.D[0][j][C + 1]
        if d < INF then
          local k = key(lshift(1, j - 1), j, C)
          local v = d + stops[j].work
          if v < (dp[k] or INF) then dp[k] = v; par[k] = -1 end
        end
      end
    end
  end
  local full = lshift(1, n) - 1
  local steps = 0
  for mask = 1, full do
    for last = 1, n do
      if band(mask, lshift(1, last - 1)) ~= 0 then
        for U = 0, S - 1 do
          local k0 = key(mask, last, U)
          local cur = dp[k0]
          if cur then
            for j = 1, n do
              local bj = lshift(1, j - 1)
              if band(mask, bj) == 0 and band(mask, need[j]) == need[j] then
                local row, w = M.D[last][j], stops[j].work
                local nm = bor(mask, bj)
                for C = 0, S - 1 do
                  if band(C, U) == 0 then
                    local d = row[C + 1]
                    if d < INF then
                      local nk = key(nm, j, bor(U, C))
                      local v = cur + d + w
                      if v < (dp[nk] or INF) then dp[nk] = v; par[nk] = k0 end
                    end
                  end
                end
              end
            end
          end
        end
        steps = steps + 1
        if yield and steps % 2000 == 0 then yield() end
      end
    end
  end
  local best, bk = INF, nil
  for last = 1, n do
    for U = 0, S - 1 do
      local c = dp[key(full, last, U)]
      if c and c < best then best, bk = c, key(full, last, U) end
    end
  end
  if not bk then return nil end
  local order = {}
  local k = bk
  while k and k >= 0 do
    local last = math.floor(k / S) % W
    table.insert(order, 1, last)
    k = par[k]
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
        if ok and M.D[prev][j][1] < best then best, bj = M.D[prev][j][1], j end
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

function Tour.exactAffordable(n, S)
  local K = 0
  while 2 ^ K < S do K = K + 1 end
  return 2 ^ n * n * n * 3 ^ K <= Tour.EXACT_BUDGET
end

-- Full plan. opts = {method = "auto"|"exact"|"heuristic", yield = fn}
-- Returns {order, seconds, method, stops, legs = {{stop, seconds, travel}}, matrices}
function Tour.plan(world, profile, startId, quests, opts)
  opts = opts or {}
  local stops = Tour.stops(world, quests)
  local startNode = world:index(startId)
  local M = Tour.matrices(world, profile, startNode, stops)
  local method = opts.method or "auto"
  if method == "auto" then method = Tour.exactAffordable(#stops, M.S) and "exact" or "heuristic" end
  local order
  if #stops == 0 then
    order = {}
  elseif method == "exact" then
    order = Tour.exact(M, stops, opts.yield)
  else
    order = Tour.heuristic(M, stops, opts.yield)
  end
  local seconds, spend = Tour.orderCost(M, order, stops)
  local legs = {}
  local prev = 0
  for k, j in ipairs(order) do
    local res = M.cache[M.pts[prev]]
    local state = Router.sid(M.ctx, stops[j].node, spend[k])
    local travel = Router.legs(world, res.dist, res.prev, state, M.ctx)
    legs[#legs + 1] = { stop = stops[j], index = j, seconds = res.dist[state], travel = travel }
    prev = j
  end
  return { order = order, seconds = seconds, method = method, stops = stops,
           legs = legs, matrices = M }
end

ns.Tour = Tour
