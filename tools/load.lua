-- Loads the addon's files outside the game the same way WoW does: each file listed in
-- AtlasRoute.toc is run with (addonName, namespaceTable) as its varargs.
-- Usage from another script:  local ns = dofile(<repo>/tools/load.lua)(<repo>)
return function(root)
  local ns = {}
  local toc = assert(io.open(root .. "/AtlasRoute/AtlasRoute.toc")):read("*a")
  for line in toc:gmatch("[^\r\n]+") do
    if not line:match("^%s*#") and line:match("%.lua%s*$") then
      local rel = line:gsub("\\", "/"):gsub("%s+$", "")
      if not rel:match("^ui/") then -- in-game UI needs the WoW API
        local chunk = assert(loadfile(root .. "/AtlasRoute/" .. rel))
        chunk("AtlasRoute", ns)
      end
    end
  end
  return ns
end
