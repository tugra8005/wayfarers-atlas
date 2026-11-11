-- Random complete FSM generator (stand-in for the fsm-gen-fsm tool Util.java calls, which is
-- not in the Atlas repo). Every state has one transition per input; all states are reachable
-- from state 0. With strong=true, state 0 is also reachable from every state.
-- Usage: luajit tools/gen_fsm.lua <states> <inputs> <outputs> <seed> [strong]
local function gen(states, inputs, outputs, seed, strong)
  math.randomseed(seed)
  local next = {}
  for s = 0, states - 1 do next[s] = {} end
  -- random spanning tree from 0 so every state is reachable
  local order = { 0 }
  for s = 1, states - 1 do order[#order + 1] = s end
  for i = #order, 3, -1 do
    local j = math.random(2, i)
    order[i], order[j] = order[j], order[i]
  end
  for i = 2, #order do
    local parent = order[math.random(1, i - 1)]
    local free = {}
    for k = 0, inputs - 1 do if next[parent][k] == nil then free[#free + 1] = k end end
    if #free > 0 then next[parent][free[math.random(#free)]] = order[i] end
  end
  for s = 0, states - 1 do
    for k = 0, inputs - 1 do
      if next[s][k] == nil then
        next[s][k] = (strong and k == inputs - 1 and math.random() < 0.5) and 0
                     or math.random(0, states - 1)
      end
    end
  end
  local lines = {}
  for s = 0, states - 1 do
    for k = 0, inputs - 1 do
      lines[#lines + 1] = ("%d -- %d / %d -> %d"):format(s, k, math.random(0, outputs - 1), next[s][k])
    end
  end
  return table.concat(lines, "\n") .. "\n"
end

if arg and arg[0] and arg[0]:match("gen_fsm%.lua$") then
  io.write(gen(tonumber(arg[1]), tonumber(arg[2]), tonumber(arg[3]), tonumber(arg[4]), arg[5] == "strong"))
end
return gen
