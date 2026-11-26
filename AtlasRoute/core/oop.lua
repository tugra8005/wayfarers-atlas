-- Classes and interfaces for the addon (Lua has neither, so this adds the minimum).
--
--   local Shape = ns.Class("Shape")             -- a class
--   function Shape:init(x) self.x = x end       -- constructor body
--   local Circle = ns.Class("Circle", Shape)    -- subclass: methods are inherited
--   local c = Circle.new(1)                     -- instance
--   ns.isA(c, Shape) --> true
--
--   local Drawable = ns.Interface("Drawable", { "draw" })
--   ns.implements(Circle, Drawable)             -- errors at load time if Circle lacks draw
--
-- Interfaces are checked when a class declares them, so a class that forgets a method fails
-- as soon as the addon loads, not when the method is first called in game.
local _, ns = ...

local function Class(name, parent)
  local cls = {}
  cls.__index = cls
  cls.__name = name
  cls.super = parent
  if parent then setmetatable(cls, { __index = parent }) end
  function cls.new(...)
    local obj = setmetatable({}, cls)
    if obj.init then obj:init(...) end
    return obj
  end
  return cls
end

local function Interface(name, methods)
  return { __interface = name, methods = methods }
end

local function implements(cls, iface)
  for _, m in ipairs(iface.methods) do
    if type(cls[m]) ~= "function" then
      error(("%s does not implement %s:%s"):format(cls.__name or "?", iface.__interface, m), 2)
    end
  end
  cls.__implements = cls.__implements or {}
  cls.__implements[iface.__interface] = true
  return cls
end

local function isA(obj, cls)
  local mt = getmetatable(obj)
  while mt do
    if mt == cls then return true end
    mt = mt.super
  end
  return false
end

ns.Class, ns.Interface, ns.implements, ns.isA = Class, Interface, implements, isA
