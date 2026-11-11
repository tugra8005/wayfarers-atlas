-- Runs the Lua Atlas port and the original Java Atlas on the same FSM files and checks
-- that they print the same test suite.
-- Usage: luajit tools/compare_java.lua <java-classes-dir> file1.fsm [file2.fsm ...]
local root = arg[0]:match("^(.*)/tools/") or "."
local ns = dofile(root .. "/tools/load.lua")(root)
local classes = arg[1]
local same, diff = 0, 0
for i = 2, #arg do
  local f = arg[i]
  local text = assert(io.open(f)):read("*a")
  local suite = ns.Atlas.run(ns.FSM.parse(text))
  local p = io.popen("java -Xss64m -cp '" .. classes .. "' RefMain '" .. f .. "' 2>&1")
  local java = p:read("*a"):gsub("%s+$", "")
  p:close()
  if java == suite then
    same = same + 1
  else
    diff = diff + 1
    print("DIFF " .. f)
    print("  java: " .. java:sub(1, 200))
    print("  lua : " .. suite:sub(1, 200))
  end
end
print(("identical: %d  different: %d"):format(same, diff))
os.exit(diff == 0 and 0 or 1)
