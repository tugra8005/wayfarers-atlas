-- Builds web/AtlasRoute.html: the showcase page with the addon's Lua files and
-- web/bridge.lua inlined, so it is one file that opens anywhere (it fetches only the
-- wasmoon Lua VM and two fonts from CDNs).
-- Usage: luajit tools/build_web.lua
local root = arg[0]:match("^(.*)/tools/") or "."
local function read(p) local f = assert(io.open(p, "rb")); local s = f:read("*a"); f:close(); return s end

local files = {}
local toc = read(root .. "/AtlasRoute/AtlasRoute.toc")
for line in toc:gmatch("[^\r\n]+") do
  if not line:match("^%s*#") and line:match("%.lua%s*$") and not line:match("^ui") then
    local rel = line:gsub("\\", "/"):gsub("%s+$", "")
    files[#files + 1] = { name = rel, src = read(root .. "/AtlasRoute/" .. rel) }
  end
end
files[#files + 1] = { name = "web/bridge.lua", src = read(root .. "/web/bridge.lua") }

local function jstr(s)
  s = s:gsub('[%c"\\]', function(c)
    local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
    return map[c] or string.format("\\u%04x", c:byte())
  end)
  return '"' .. s:gsub("</", "<\\/") .. '"' -- never close the <script> early
end
local parts = {}
for i, f in ipairs(files) do
  parts[i] = '{"name":' .. jstr(f.name) .. ',"src":' .. jstr(f.src) .. '}'
end
local payload = "[" .. table.concat(parts, ",") .. "]"

local html = read(root .. "/web/template.html")
local a, b = html:find("__LUA_SOURCES__", 1, true)
assert(a, "placeholder __LUA_SOURCES__ not found in web/template.html")
html = html:sub(1, a - 1) .. payload .. html:sub(b + 1)
local out = assert(io.open(root .. "/web/AtlasRoute.html", "wb"))
out:write(html)
out:close()
print(("web/AtlasRoute.html: %d Lua files, %d bytes"):format(#files, #html))
