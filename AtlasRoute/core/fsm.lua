-- Edge-labelled directed graph in the shape the original Atlas uses (Graph.java / Edge.java),
-- plus a parser for the KISS2-like ".fsm" lines it reads: "state -- input / output -> next".
--
-- Java's HashSet<Integer> iterates by bucket index, not insertion order, and Atlas's result
-- depends on that order. outEdges() reproduces it (bucket = label mod capacity, capacity
-- starting at 16 and doubling past 0.75 load) so the Lua port can be checked edge for edge.
local _, ns = ...

local FSM = {}
FSM.__index = FSM

function FSM.new()
  return setmetatable({ edges = {}, out = {}, m = 0, starts = {} }, FSM)
end

-- label is 0-based like the Java code; weight defaults to 1.
function FSM:addEdge(source, dest, input, output, weight)
  local label = self.m
  self.m = label + 1
  self.edges[label] = { label = label, source = source, dest = dest,
                        input = input, output = output, weight = weight or 1 }
  self.out[source] = self.out[source] or {}
  self.out[dest] = self.out[dest] or {}
  local list = self.out[source]
  list[#list + 1] = label
  self._order = nil
  if source == 0 then self.starts[#self.starts + 1] = label end
  return label
end

local function javaCapacity(size)
  local cap = 16
  while size > cap * 0.75 do cap = cap * 2 end
  return cap
end

-- Out-edge labels of a node in java.util.HashSet<Integer> iteration order.
function FSM:outEdges(node)
  self._order = self._order or {}
  local cached = self._order[node]
  if cached then return cached end
  local list = self.out[node] or {}
  local cap = javaCapacity(#list)
  local idx = {}
  for i, label in ipairs(list) do idx[label] = i end
  local sorted = {}
  for i = 1, #list do sorted[i] = list[i] end
  table.sort(sorted, function(a, b)
    local ba, bb = a % cap, b % cap
    if ba ~= bb then return ba < bb end
    return idx[a] < idx[b]
  end)
  self._order[node] = sorted
  return sorted
end

-- First element of the Java HashSet of start edges (edges leaving state 0).
function FSM:firstStart()
  local cap = javaCapacity(#self.starts)
  local best
  for _, l in ipairs(self.starts) do
    if best == nil or (l % cap) < (best % cap) then best = l end
  end
  return best
end

function FSM.parse(text)
  local g = FSM.new()
  for line in text:gmatch("[^\r\n]+") do
    local s, i, o, d = line:match("^(%d+)%s%-%-%s(%d+)%s/%s(%d+)%s%->%s(%d+)")
    if s then g:addEdge(tonumber(s), tonumber(d), tonumber(i), tonumber(o), 1) end
  end
  return g
end

function FSM:numNodes()
  local n = 0
  for _ in pairs(self.out) do n = n + 1 end
  return n
end

ns.FSM = FSM
