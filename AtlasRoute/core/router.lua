-- Fastest route between two places: Dijkstra over (node, hearthstone available?) states.
--
-- The hearthstone is a teleport you can use once per plan (its cooldown, 60 min in Classic,
-- is longer than most legs). Carrying "is it still available" in the state makes the search
-- exact: a route may use it on the leg where it saves the most, and the tour planner can ask
-- for both "arrive with it unused" and "arrive having used it".
local _, ns = ...
local Heap = ns.Heap

local Router = {}

local INF = math.huge

-- State id: node index * 2 + h, h = 1 while the hearthstone is still available.
local function sid(node, h) return node * 2 + h end

-- Single-source search. Returns dist[state], prev[state] = {state, edge}.
function Router.search(world, profile, src, hearthAvail)
  local dist, prev = {}, {}
  local heap = Heap.new()
  local h0 = (hearthAvail and profile.hearth) and 1 or 0
  local s = sid(src, h0)
  dist[s] = 0
  heap:push(0, s)

  local tps = {}
  for _, t in ipairs(world.teleports) do
    if world:allowed(t, profile) then tps[#tps + 1] = t end
  end
  local hearthIdx = profile.hearth and world:index(profile.hearth)
  local hearthEdge = hearthIdx and { mode = "hearth", to = hearthIdx, cost = world.CAST_TIME,
                                     name = "Hearthstone" }

  while not heap:empty() do
    local d, u = heap:pop()
    if d <= (dist[u] or INF) then
      local node, h = math.floor(u / 2), u % 2
      local function relax(to, th, cost, e)
        local v = sid(to, th)
        local nd = d + cost
        if nd < (dist[v] or INF) then
          dist[v] = nd
          prev[v] = { state = u, edge = e }
          heap:push(nd, v)
        end
      end
      for _, e in ipairs(world.adj[node]) do
        if world:allowed(e, profile) then
          relax(e.to, h, world:edgeCost(e, profile), e)
        end
      end
      if world.nodes[node].kind == "ground" then -- no casting while on a flight
        for _, t in ipairs(tps) do relax(t.to, h, t.cost, t) end
        if h == 1 and hearthEdge then relax(hearthIdx, 0, hearthEdge.cost, hearthEdge) end
      end
    end
  end
  return dist, prev
end

-- Rebuild the legs from the search result, with each leg's time taken from the distance
-- labels. Consecutive walks merge into one walk; board + fly hops + land become one flight
-- (from the flight master's ground node to the landing ground node).
function Router.legs(world, dist, prev, dstState)
  local steps = {}
  local v = dstState
  while prev[v] do
    local p = prev[v]
    steps[#steps + 1] = { from = math.floor(p.state / 2), to = math.floor(v / 2),
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
      if mode == "fly" then last.hops = last.hops + 1 end
    elseif mode == "walk" and last and last.mode == "walk" then
      last.to = st.to
      last.seconds = last.seconds + st.seconds
    else
      legs[#legs + 1] = { mode = (mode == "board") and "fly" or mode, from = st.from, to = st.to,
                          seconds = st.seconds, name = st.edge.name, hops = 0 }
    end
  end
  return legs
end

-- Best arrival state at node dst: returns (seconds, state).
function Router.best(dist, dst)
  local a, b = dist[sid(dst, 1)] or INF, dist[sid(dst, 0)] or INF
  if a <= b then return a, (a < INF) and sid(dst, 1) or nil end
  return b, sid(dst, 0)
end

-- Convenience: fastest route from place id a to place id b.
-- Returns total seconds and a list of legs {mode, from, to, seconds}.
function Router.route(world, profile, a, b, hearthAvail)
  local src, dst = world:index(a), world:index(b)
  local dist, prev = Router.search(world, profile, src, hearthAvail)
  local best, state = Router.best(dist, dst)
  if not state then return nil end
  return best, Router.legs(world, dist, prev, state)
end

Router.sid = sid
ns.Router = Router
