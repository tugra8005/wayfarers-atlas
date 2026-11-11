-- Binary min-heap keyed by a number. Used by Dijkstra and min-cost flow.
local _, ns = ...

local Heap = {}
Heap.__index = Heap

function Heap.new()
  return setmetatable({ keys = {}, vals = {}, n = 0 }, Heap)
end

function Heap:push(key, val)
  local n = self.n + 1
  self.n = n
  local keys, vals = self.keys, self.vals
  keys[n], vals[n] = key, val
  while n > 1 do
    local p = math.floor(n / 2)
    if keys[p] <= keys[n] then break end
    keys[p], keys[n] = keys[n], keys[p]
    vals[p], vals[n] = vals[n], vals[p]
    n = p
  end
end

function Heap:pop()
  local n = self.n
  if n == 0 then return nil end
  local keys, vals = self.keys, self.vals
  local topKey, topVal = keys[1], vals[1]
  keys[1], vals[1] = keys[n], vals[n]
  keys[n], vals[n] = nil, nil
  n = n - 1
  self.n = n
  local i = 1
  while true do
    local l, r, m = 2 * i, 2 * i + 1, i
    if l <= n and keys[l] < keys[m] then m = l end
    if r <= n and keys[r] < keys[m] then m = r end
    if m == i then break end
    keys[m], keys[i] = keys[i], keys[m]
    vals[m], vals[i] = vals[i], vals[m]
    i = m
  end
  return topKey, topVal
end

function Heap:empty() return self.n == 0 end

ns.Heap = Heap
