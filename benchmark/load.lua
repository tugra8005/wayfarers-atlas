-- Loads the addon (as tools/load.lua does) plus the comparison algorithms in benchmark/.
-- These are NOT part of the addon: the addon plans only with Atlas (core/atlasplan.lua).
-- They are here to measure how close Atlas gets to exact or classic methods:
--   heap.lua      binary heap
--   router.lua    Dijkstra over (place, one-use teleports spent): exact single routes
--   tour.lua      Held-Karp (exact) and Or-opt quest tours on Dijkstra's travel times
--   cpp.lua       exact open Chinese Postman (min-cost flow + Hierholzer)
--   coverage.lua  weighted Atlas with Dijkstra jumps, and the Rural Postman construction
-- Usage: local ns = dofile(<repo>/benchmark/load.lua)(<repo>)
return function(root)
  local ns = dofile(root .. "/tools/load.lua")(root)
  for _, f in ipairs({ "heap", "router", "tour", "cpp", "coverage" }) do
    assert(loadfile(root .. "/benchmark/" .. f .. ".lua"))("AtlasRoute", ns)
  end
  return ns
end
