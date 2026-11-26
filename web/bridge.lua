-- Bridge between the showcase page and the addon's Lua code. The page runs the same
-- core/ and data/ files in a browser Lua VM (wasmoon) and calls these functions; requests
-- are query strings ("faction=Horde&start=orgrimmar"), answers are JSON strings.
local _, ns = ...
local B = {}

-- JSON ------------------------------------------------------------------------------------
local function encode(v, out)
  local t = type(v)
  if t == "nil" then out[#out + 1] = "null"
  elseif t == "boolean" then out[#out + 1] = v and "true" or "false"
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then out[#out + 1] = "null"
    elseif v == math.floor(v) and math.abs(v) < 2 ^ 53 then out[#out + 1] = string.format("%d", v)
    else out[#out + 1] = string.format("%.3f", v) end
  elseif t == "string" then
    out[#out + 1] = '"' .. v:gsub('[%c"\\]', function(c)
      local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\t"] = "\\t" }
      return map[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
  elseif t == "table" then
    if v[1] ~= nil or next(v) == nil and getmetatable(v) == B.ARRAY then
      out[#out + 1] = "["
      for i = 1, #v do
        if i > 1 then out[#out + 1] = "," end
        encode(v[i], out)
      end
      out[#out + 1] = "]"
    else
      out[#out + 1] = "{"
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = tostring(k) end
      table.sort(keys)
      for i, k in ipairs(keys) do
        if i > 1 then out[#out + 1] = "," end
        encode(k, out)
        out[#out + 1] = ":"
        local val = v[k]
        if val == nil then val = v[tonumber(k)] end
        encode(val, out)
      end
      out[#out + 1] = "}"
    end
  end
end
B.ARRAY = {}
local function array(t) return setmetatable(t or {}, B.ARRAY) end
local function json(v) local out = {}; encode(v, out); return table.concat(out) end
B.json = json

local function parse(q)
  local r = {}
  for k, v in (q or ""):gmatch("([^&=]+)=([^&]*)") do r[k] = v end
  return r
end

local world
local function getWorld()
  world = world or ns.ForeverMap.new():build()
  return world
end

-- World -----------------------------------------------------------------------------------
function B.world()
  local w = getWorld()
  local D = ns.WorldData
  local places = array()
  for _, n in ipairs(w.nodes) do
    if n.kind == "ground" then
      places[#places + 1] = { id = n.id, name = n.name, zone = n.zone, continent = n.continent,
                              region = n.region or n.continent, x = n.x, y = n.y }
    end
  end
  local masters = array()
  for _, n in ipairs(w.nodes) do
    if n.kind == "air" then
      masters[#masters + 1] = { id = w.nodes[n.ground].id, faction = n.faction, class = n.class }
    end
  end
  local links = array()
  local seen = {}
  for i = 1, #w.nodes do
    for _, e in ipairs(w.adj[i]) do
      if e.mode == "fly" then
        local a, b = w.nodes[e.from], w.nodes[e.to]
        local key = math.min(e.from, e.to) .. ":" .. math.max(e.from, e.to)
        if not seen[key] then
          seen[key] = true
          links[#links + 1] = { a = w.nodes[a.ground].id, b = w.nodes[b.ground].id,
                                faction = e.faction, class = e.class, unconfirmed = e.unconfirmed }
        end
      end
    end
  end
  local transports = array()
  for _, t in ipairs(D.transports) do
    transports[#transports + 1] = { from = t.from, to = t.to, mode = t.mode, faction = t.faction,
                                    oneWay = t.oneWay, unconfirmed = t.unconfirmed }
  end
  local quests = {}
  for side, list in pairs(ns.QuestData) do
    local qs = array()
    for _, q in ipairs(list) do
      local objs = array()
      for i, o in ipairs(q.objectives or {}) do objs[i] = o end
      qs[#qs + 1] = { id = q.id, name = q.name, giver = q.giver, accepted = q.accepted,
                      objectives = objs, turnin = q.turnin }
    end
    quests[side] = qs
  end
  return json({ places = places, masters = masters, links = links, transports = transports,
                quests = quests })
end

local function profileFrom(o)
  return {
    faction = o.faction or "Alliance",
    class = (o.class ~= nil and o.class ~= "") and o.class or nil,
    speed = tonumber(o.speed) or 11.2,
    hearth = (o.hearth ~= nil and o.hearth ~= "") and o.hearth or nil,
    items = (o.engineer == "1") and { [18984] = true, [18986] = true } or nil,
    flySpeed = (o.flier == "1") and 1.2 or 1,
    unconfirmed = o.beta == "1",
  }
end

local function legsOut(w, travel)
  local out = array()
  for _, t in ipairs(travel) do
    local path = array()
    for _, node in ipairs(t.path or { t.from, t.to }) do
      local n = w.nodes[node]
      local id = n.kind == "air" and w.nodes[n.ground].id or n.id
      if path[#path] ~= id then path[#path + 1] = id end -- ground and air node share a spot
    end
    if #path == 1 then path[2] = path[1] end
    out[#out + 1] = { mode = t.mode, name = t.name, from = path[1], to = path[#path],
                      seconds = t.seconds, path = path }
  end
  return out
end

-- Quest plan ------------------------------------------------------------------------------
function B.plan(q)
  local o = parse(q)
  local w = getWorld()
  local prof = profileFrom(o)
  local pool = (o.faction == "Horde") and ns.QuestData.horde or ns.QuestData.alliance
  local want = {}
  for id in (o.quests or ""):gmatch("[^,]+") do want[id] = true end
  local quests = {}
  for _, qd in ipairs(pool) do if want[qd.id] then quests[#quests + 1] = qd end end
  local t0 = os.clock()
  local plan = ns.AtlasPlan.plan(w, prof, o.start, quests)
  local ms = (os.clock() - t0) * 1000
  local steps = array()
  for k, leg in ipairs(plan.legs) do
    local s = leg.stop
    steps[k] = { kind = s.kind, quest = s.quest, name = s.name, place = w.nodes[s.node].id,
                 work = s.work, seconds = leg.seconds, travel = legsOut(w, leg.travel) }
  end
  local missing = array()
  for _, st in ipairs(plan.unreachable) do missing[#missing + 1] = st.name end
  return json({ seconds = plan.seconds, method = "atlas", rounds = plan.rounds, stops = #plan.stops,
                ms = ms, steps = steps, unreachable = missing })
end

-- Single route ----------------------------------------------------------------------------
function B.route(q)
  local o = parse(q)
  local w = getWorld()
  local t, legs = ns.AtlasPlan.route(w, profileFrom(o), o.from, o.to)
  if not t then return json({ error = "No route between those places for this character." }) end
  return json({ seconds = t, travel = legsOut(w, legs) })
end

-- Flight-network coverage: Atlas as written (2020, every edge one step) and Atlas with
-- travel times (core/atlasplan.lua), on the same travel graph.
function B.cover(q)
  local o = parse(q)
  local w = getWorld()
  local prof = profileFrom(o)
  local function id(node)
    local n = w.nodes[node]
    return n.kind == "air" and w.nodes[n.ground].id or n.id
  end
  local function stepsOut(list)
    local out = array()
    for _, st in ipairs(list) do
      if st.mode ~= "board" and st.mode ~= "land" and st.mode ~= "start" then
        out[#out + 1] = { mode = st.mode, name = st.name, from = id(st.from), to = id(st.to),
                          seconds = st.seconds }
      end
    end
    return out
  end
  local result = { methods = {} }

  -- Atlas with travel times
  do
    local t0 = os.clock()
    local r = ns.AtlasPlan.cover(w, prof, o.start)
    result.required = r.required
    result.methods.atlas = { seconds = r.seconds, covered = r.covered, rounds = r.rounds,
                             ms = (os.clock() - t0) * 1000, steps = stepsOut(r.steps) }
  end
  -- Atlas as written: the same graph as an FSM, every edge costs one step
  do
    local t0 = os.clock()
    local tg = ns.AtlasPlan.travelGraph(w, prof)
    local fsm = ns.FSM.new()
    local first
    local startNode = w:index(o.start)
    for l = 1, tg.m do
      local e = tg.edges[l]
      local fl = fsm:addEdge(e.source, e.dest, 0, 0, e.weight)
      fsm.edges[fl].mode, fsm.edges[fl].name = e.mode, e.name
      if e.source == startNode and not first then first = fl end
    end
    local path = ns.Atlas.longestPath(fsm, first)
    local list, seen, covered, weight, lb = {}, {}, 0, 0, 0
    for _, l in ipairs(path) do
      local e = fsm.edges[l]
      list[#list + 1] = { mode = e.mode, name = e.name, from = e.source, to = e.dest, seconds = e.weight }
      weight = weight + e.weight
      if e.mode == "fly" and not seen[l] then seen[l] = true; covered = covered + 1 end
    end
    for l = 0, fsm.m - 1 do if fsm.edges[l].mode == "fly" then lb = lb + fsm.edges[l].weight end end
    result.lowerBound = lb
    result.methods.atlas2020 = { seconds = weight, covered = covered, ms = (os.clock() - t0) * 1000,
                                 steps = stepsOut(list) }
  end
  return json(result)
end

ns.Bridge = B
