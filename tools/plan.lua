-- Command-line demo of the quest planner (same code the addon runs).
-- Usage: luajit tools/plan.lua [alliance|horde] [start place id] [mage] [nohearth]
local root = arg[0]:match("^(.*)/tools/") or "."
local ns = dofile(root .. "/tools/load.lua")(root)
local world = ns.WorldData.build(ns.World)

local side = (arg[1] or "alliance"):lower()
local flags = {}
for i = 3, #arg do flags[arg[i]] = true end
local horde = side == "horde"
local prof = {
  faction = horde and "Horde" or "Alliance",
  class = flags.mage and "MAGE" or nil,
  speed = 11.2,
  hearth = (not flags.nohearth) and (horde and "orgrimmar" or "stormwind") or nil,
}
local start = arg[2] or (horde and "orgrimmar" or "ironforge")
local quests = horde and ns.QuestData.horde or ns.QuestData.alliance

local function fmt(s) s = math.floor(s + 0.5); return ("%dm %02ds"):format(math.floor(s / 60), s % 60) end

local t0 = os.clock()
local plan = ns.Tour.plan(world, prof, start, quests)
print(("%s%s from %s, hearthstone: %s, %d stops, %s method, %.0f ms"):format(
  prof.faction, prof.class and " mage" or "", world.nodes[world:index(start)].name,
  prof.hearth or "none", #plan.stops, plan.method, 1000 * (os.clock() - t0)))
print(("total %s (travel + time spent at objectives)\n"):format(fmt(plan.seconds)))
for k, leg in ipairs(plan.legs) do
  local s = leg.stop
  print(("%2d. %-9s %-28s @ %-24s +%s"):format(k, s.kind, s.name, world.nodes[s.node].name, fmt(leg.seconds + s.work)))
  for _, t in ipairs(leg.travel) do
    print(("      %-9s -> %-26s %s"):format(t.name or t.mode, world.nodes[t.to].name, fmt(t.seconds)))
  end
end
