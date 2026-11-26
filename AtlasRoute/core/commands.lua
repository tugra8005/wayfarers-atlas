-- Slash commands as objects (Command pattern).
--
--   Command          one command: a name and what it does (execute)
--   CommandRegistry  parses "/ar <name> <rest>" and runs the matching Command; an unknown
--                    or empty name runs "help". Adding a command is one register() call;
--                    the dispatcher never changes.
--
-- Both in-game shells (ui/addon.lua for Forever, ui/retail.lua for retail) keep their own
-- commands and hand them to a registry. Plain Lua, so the tests run it outside the game.
local _, ns = ...
local Class = ns.Class

local Command = Class("Command")
function Command:init(name, handler) self.name, self.handler = name, handler end
function Command:execute(rest) return self.handler(rest or "") end

local CommandRegistry = Class("CommandRegistry")
function CommandRegistry:init() self.commands = {} end

function CommandRegistry:register(name, handler)
  local cmd = Command.new(name:lower(), handler)
  self.commands[cmd.name] = cmd
  return cmd
end

function CommandRegistry:get(name) return self.commands[(name or ""):lower()] end

-- Every function in a table of name -> handler becomes a Command.
function CommandRegistry.fromTable(t)
  local registry = CommandRegistry.new()
  local names = {}
  for name in pairs(t) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do registry:register(name, t[name]) end
  return registry
end

-- "plan", "route Astranaar", "  speed 11.2 " ...
function CommandRegistry:dispatch(msg)
  local name, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  local cmd = self:get(name) or self:get("help")
  if cmd then return cmd:execute(rest) end
end

ns.Command, ns.CommandRegistry = Command, CommandRegistry
