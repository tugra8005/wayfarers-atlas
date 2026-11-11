-- Fastest route between two places: Dijkstra over (node, set of one-use teleports spent).
--
-- Some teleports have cooldowns longer than most plans, so each is treated as usable once:
-- the hearthstone, a shaman's Astral Recall, engineering devices. With K of them the state
-- is (node, spent-mask), 2^K states per node. Carrying the mask makes the search exact: a
-- route spends a teleport only where it pays, and the tour planner can read "fastest i -> j
-- that spends exactly the set C" straight from one search per origin.
local _, ns = ...
local Heap = ns.Heap

local Router = {}

local INF = math.huge

-- The one-use teleports this character has, in a fixed order (bit k-1 = item k).
function Router.limited(world, profile)
  local list = {}
  if profile.hearth then
    list[#list + 1] = { mode = "hearth", name = "Hearthstone", to = world:index(profile.hearth),
                        cost = world.CAST_TIME }
  end
  for _, t in ipairs(world.teleports) do
    if t.limited and world:allowed(t, profile) then
      local to = t.to
      if t.toBind then to = profile.hearth and world:index(profile.hearth) end
      if to then
        list[#list + 1] = { mode = t.mode, name = t.name, to = to, cost = t.cost }
      end
    end
  end
  return list
end

-- ctx: what the state numbers mean for this character.
function Router.context(world, profile)
  local L = Router.limited(world, profile)
  local S = 1
  for _ = 1, #L do S = S * 2 end
  return { L = L, S = S }
end

local function sid(ctx, node, used) return node * ctx.S + used end
local function decode(ctx, s) return math.floor(s / ctx.S), s % ctx.S end
Router.sid, Router.decode = sid, decode

local function hasBit(mask, k) return math.floor(mask / 2 ^ (k - 1)) % 2 == 1 end
Router.hasBit = hasBit

-- Single-source search. allowLimited=false forbids every one-use teleport.
-- Returns dist[state], prev[state] = {state, edge}, ctx.
function Router.search(world, profile, src, allowLimited, ctx)
  ctx = ctx or Router.context(world, profile)
  local dist, prev = {}, {}
  local heap = Heap.new()
  local s = sid(ctx, src, 0)
  dist[s] = 0
  heap:push(0, s)

  local tps = {}
  for _, t in ipairs(world.teleports) do
    if not t.limited and world:allowed(t, profile) then tps[#tps + 1] = t end
  end
  local L = (allowLimited ~= false) and ctx.L or {}

  while not heap:empty() do
    local d, u = heap:pop()
    if d <= (dist[u] or INF) then
      local node, used = decode(ctx, u)
      local function relax(to, nused, cost, e)
        local v = sid(ctx, to, nused)
        local nd = d + cost
        if nd < (dist[v] or INF) then
          dist[v] = nd
          prev[v] = { state = u, edge = e }
          heap:push(nd, v)
        end
      end
      for _, e in ipairs(world.adj[node]) do
        if world:allowed(e, profile) then
          relax(e.to, used, world:edgeCost(e, profile), e)
        end
      end
      if world.nodes[node].kind == "ground" then -- no casting while on a flight
        for _, t in ipairs(tps) do relax(t.to, used, t.cost, t) end
        for k, t in ipairs(L) do
          if not hasBit(used, k) then relax(t.to, used + 2 ^ (k - 1), t.cost, t) end
        end
      end
    end
  end
  return dist, prev, ctx
end

-- Rebuild the legs from the search result, with each leg's time taken from the distance
-- labels. Consecutive walks merge into one walk; board + fly hops + land become one flight
-- (from the flight master's ground node to the landing ground node).
function Router.legs(world, dist, prev, dstState, ctx)
  local steps = {}
  local v = dstState
  while prev[v] do
    local p = prev[v]
    steps[#steps + 1] = { from = decode(ctx, p.state), to = decode(ctx, v),
                          edge = p.edge, seconds = dist[v] - dist[p.state] }
    v = p.state
  end
  local legs = {}
  for i = #steps, 1, -1 do
    local st = steps[i]
    local mode = st.edge.mode
    local last = legs[#legs]
    if (mode == "fly" or mode == "land") and last and last.mode == "fly" then
      last.to = st.to
      last.seconds = last.seconds + st.seconds
      last.path[#last.path + 1] = st.to
      if mode == "fly" then last.hops = last.hops + 1 end
    elseif mode == "walk" and last and last.mode == "walk" then
      last.to = st.to
      last.seconds = last.seconds + st.seconds
      last.path[#last.path + 1] = st.to
    else
      -- path: every node the leg passes through, for drawing it on a map
      legs[#legs + 1] = { mode = (mode == "board") and "fly" or mode, from = st.from, to = st.to,
                          seconds = st.seconds, name = st.edge.name, hops = 0,
                          path = { st.from, st.to } }
    end
  end
  return legs
end

-- Best arrival state at node dst over every spent-mask: returns (seconds, state).
function Router.best(dist, ctx, dst)
  local best, state = INF, nil
  for used = 0, ctx.S - 1 do
    local s = sid(ctx, dst, used)
    local d = dist[s]
    if d and d < best then best, state = d, s end
  end
  return best, state
end

-- Convenience: fastest route from place id a to place id b.
-- Returns total seconds and a list of legs {mode, from, to, seconds}.
function Router.route(world, profile, a, b, allowLimited)
  local src, dst = world:index(a), world:index(b)
  local dist, prev, ctx = Router.search(world, profile, src, allowLimited)
  local best, state = Router.best(dist, ctx, dst)
  if not state then return nil end
  return best, Router.legs(world, dist, prev, state, ctx)
end

ns.Router = Router
