-- Observer: an object that others can subscribe to.
--
--   local Solver = ns.Class("Solver", ns.Observable)
--   solver:on("round", function(info) ... end)   -- subscribe; returns the listener
--   solver:emit("round", info)                   -- notify every listener of "round"
--   solver:off("round", listener)                -- unsubscribe
local _, ns = ...

local Observable = ns.Class("Observable")

function Observable:on(event, listener)
  self._listeners = self._listeners or {}
  self._listeners[event] = self._listeners[event] or {}
  table.insert(self._listeners[event], listener)
  return listener
end

function Observable:off(event, listener)
  local list = self._listeners and self._listeners[event]
  if not list then return end
  for i = #list, 1, -1 do
    if list[i] == listener then table.remove(list, i) end
  end
end

function Observable:emit(event, ...)
  local list = self._listeners and self._listeners[event]
  if not list then return end
  for i = 1, #list do list[i](...) end
end

ns.Observable = Observable
