-- Builds the showcase page with the addon's Lua files and web/bridge.lua inlined.
--   luajit tools/build_web.lua
--       web/AtlasRoute.html: one file that opens anywhere (fetches the wasmoon Lua VM,
--       its glue.wasm and two fonts from CDNs).
--   luajit tools/build_web.lua artifact <dir>
--       <dir>/wayfarers-atlas.html for publishing as a claude.ai artifact: no html/head/body
--       wrapper (the host adds it), and glue.wasm is loaded from a copy published next to
--       the page, because the host only lets scripts, not other files, come from a CDN.
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

local mode, outdir = arg[1], arg[2]
local html = read(root .. "/web/template.html")
local a, b = html:find("__LUA_SOURCES__", 1, true)
assert(a, "placeholder __LUA_SOURCES__ not found in web/template.html")
html = html:sub(1, a - 1) .. payload .. html:sub(b + 1)

local function replace(s, what, with)
  local i, j = s:find(what, 1, true)
  assert(i, "not found in template: " .. what)
  return s:sub(1, i - 1) .. with .. s:sub(j + 1)
end
local target
if mode == "artifact" then
  assert(outdir, "usage: luajit tools/build_web.lua artifact <dir>")
  html = replace(html, "__GLUE_URL__", 'new URL("glue.wasm", location.href).href')
  for _, tag in ipairs({ "<!doctype html>\n", '<html lang="en">\n', "<head>\n", '<meta charset="utf-8">\n',
                         '<meta name="viewport" content="width=device-width, initial-scale=1">\n',
                         "</head>\n", "<body>\n", "</body>\n", "</html>\n" }) do
    html = replace(html, tag, "")
  end
  target = outdir .. "/wayfarers-atlas.html"
else
  html = replace(html, "__GLUE_URL__", '"https://cdn.jsdelivr.net/npm/wasmoon@1.16.0/dist/glue.wasm"')
  target = root .. "/web/AtlasRoute.html"
end
local out = assert(io.open(target, "wb"))
out:write(html)
out:close()
print(("%s: %d Lua files, %d bytes"):format(target, #files, #html))
