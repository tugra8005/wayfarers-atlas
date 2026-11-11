-- Hand-built map of Classic-era Eastern Kingdoms and Kalimdor.
--
-- APPROXIMATE DATA. Coordinates are in yards on a per-continent plane, placed by hand from the
-- zone layout; they are not read from the game files. Flight links, boats, zeppelins and the
-- tram follow the Classic network; ride and wait times are estimates. The algorithm does not
-- depend on these numbers, only the demo results do. Replace this file to plan on other data.
local _, ns = ...

local D = {}

D.places = {
  -- Eastern Kingdoms -----------------------------------------------------------------------
  { id = "undercity",      name = "Undercity",              zone = "Tirisfal Glades",      continent = "EK", x = 1800, y = 8800 },
  { id = "sepulcher",      name = "The Sepulcher",          zone = "Silverpine Forest",    continent = "EK", x = 1300, y = 7900 },
  { id = "tarrenmill",     name = "Tarren Mill",            zone = "Hillsbrad Foothills",  continent = "EK", x = 2600, y = 7400 },
  { id = "southshore",     name = "Southshore",             zone = "Hillsbrad Foothills",  continent = "EK", x = 2100, y = 7000 },
  { id = "alterac",        name = "Alterac Foothills",      zone = "Alterac Mountains",    continent = "EK", x = 2400, y = 7900 },
  { id = "chillwind",      name = "Chillwind Camp",         zone = "Western Plaguelands",  continent = "EK", x = 2500, y = 8300 },
  { id = "lightshope",     name = "Light's Hope Chapel",    zone = "Eastern Plaguelands",  continent = "EK", x = 4500, y = 8500 },
  { id = "aeriepeak",      name = "Aerie Peak",             zone = "The Hinterlands",      continent = "EK", x = 3300, y = 7900 },
  { id = "revantusk",      name = "Revantusk Village",      zone = "The Hinterlands",      continent = "EK", x = 4200, y = 7600 },
  { id = "hammerfall",     name = "Hammerfall",             zone = "Arathi Highlands",     continent = "EK", x = 3600, y = 6800 },
  { id = "refugepointe",   name = "Refuge Pointe",          zone = "Arathi Highlands",     continent = "EK", x = 3200, y = 6500 },
  { id = "stromgarde",     name = "Stromgarde Keep",        zone = "Arathi Highlands",     continent = "EK", x = 2700, y = 6300 },
  { id = "thandol",        name = "Thandol Span",           zone = "Wetlands",             continent = "EK", x = 2600, y = 6000 },
  { id = "menethil",       name = "Menethil Harbor",        zone = "Wetlands",             continent = "EK", x = 1900, y = 5600 },
  { id = "raptorgrounds",  name = "Raptor Grounds",         zone = "Wetlands",             continent = "EK", x = 2400, y = 5700 },
  { id = "dunalgaz",       name = "Dun Algaz",              zone = "Loch Modan",           continent = "EK", x = 2700, y = 5300 },
  { id = "thelsamar",      name = "Thelsamar",              zone = "Loch Modan",           continent = "EK", x = 3300, y = 4900 },
  { id = "ironforge",      name = "Ironforge",              zone = "Dun Morogh",           continent = "EK", x = 2500, y = 4900 },
  { id = "uldaman",        name = "Uldaman Entrance",       zone = "Badlands",             continent = "EK", x = 3500, y = 4500 },
  { id = "kargath",        name = "Kargath",                zone = "Badlands",             continent = "EK", x = 3300, y = 4300 },
  { id = "thoriumpoint",   name = "Thorium Point",          zone = "Searing Gorge",        continent = "EK", x = 2400, y = 4200 },
  { id = "stormwind",      name = "Stormwind City",         zone = "Elwynn Forest",        continent = "EK", x = 1200, y = 3000 },
  { id = "lakeshire",      name = "Lakeshire",              zone = "Redridge Mountains",   continent = "EK", x = 2600, y = 2800 },
  { id = "sentinelhill",   name = "Sentinel Hill",          zone = "Westfall",             continent = "EK", x = 900,  y = 2100 },
  { id = "darkshire",      name = "Darkshire",              zone = "Duskwood",             continent = "EK", x = 1900, y = 2000 },
  { id = "ravenhill",      name = "Raven Hill",             zone = "Duskwood",             continent = "EK", x = 1300, y = 1900 },
  { id = "stonard",        name = "Stonard",                zone = "Swamp of Sorrows",     continent = "EK", x = 3200, y = 2300 },
  { id = "nethergarde",    name = "Nethergarde Keep",       zone = "Blasted Lands",        continent = "EK", x = 3600, y = 1900 },
  { id = "gromgol",        name = "Grom'gol Base Camp",     zone = "Stranglethorn Vale",   continent = "EK", x = 1400, y = 1000 },
  { id = "nesingwary",     name = "Nesingwary's Expedition",zone = "Stranglethorn Vale",   continent = "EK", x = 1600, y = 1300 },
  { id = "bootybay",       name = "Booty Bay",              zone = "Stranglethorn Vale",   continent = "EK", x = 1300, y = 200  },
  -- Teldrassil (an island: own "continent" so nobody walks across the sea) ------------------
  { id = "darnassus",      name = "Darnassus",              zone = "Teldrassil",           continent = "TEL", x = 1600, y = 9700 },
  { id = "ruttheran",      name = "Rut'theran Village",     zone = "Teldrassil",           continent = "TEL", x = 1900, y = 9400 },
  -- Kalimdor -------------------------------------------------------------------------------
  { id = "auberdine",      name = "Auberdine",              zone = "Darkshore",            continent = "KAL", x = 2300, y = 8500 },
  { id = "mathystra",      name = "Ruins of Mathystra",     zone = "Darkshore",            continent = "KAL", x = 2700, y = 9100 },
  { id = "everlook",       name = "Everlook",               zone = "Winterspring",         continent = "KAL", x = 4300, y = 9200 },
  { id = "astranaar",      name = "Astranaar",              zone = "Ashenvale",            continent = "KAL", x = 2900, y = 7300 },
  { id = "splintertree",   name = "Splintertree Post",      zone = "Ashenvale",            continent = "KAL", x = 3700, y = 7100 },
  { id = "orgrimmar",      name = "Orgrimmar",              zone = "Durotar",              continent = "KAL", x = 4400, y = 6200 },
  { id = "razorhill",      name = "Razor Hill",             zone = "Durotar",              continent = "KAL", x = 4600, y = 5600 },
  { id = "crossroads",     name = "The Crossroads",         zone = "The Barrens",          continent = "KAL", x = 3700, y = 5000 },
  { id = "ratchet",        name = "Ratchet",                zone = "The Barrens",          continent = "KAL", x = 4400, y = 5000 },
  { id = "thunderbluff",   name = "Thunder Bluff",          zone = "Mulgore",              continent = "KAL", x = 2500, y = 4800 },
  { id = "taurajo",        name = "Camp Taurajo",           zone = "The Barrens",          continent = "KAL", x = 3200, y = 3900 },
  { id = "theramore",      name = "Theramore Isle",         zone = "Dustwallow Marsh",     continent = "KAL", x = 4500, y = 3500 },
  { id = "brackenwall",    name = "Brackenwall Village",    zone = "Dustwallow Marsh",     continent = "KAL", x = 3900, y = 3500 },
  { id = "freewind",       name = "Freewind Post",          zone = "Thousand Needles",     continent = "KAL", x = 3900, y = 2600 },
  { id = "mojache",        name = "Camp Mojache",           zone = "Feralas",              continent = "KAL", x = 2600, y = 3000 },
  { id = "feathermoon",    name = "Feathermoon Stronghold", zone = "Feralas",              continent = "KAL", x = 1200, y = 3000 },
  { id = "gadgetzan",      name = "Gadgetzan",              zone = "Tanaris",              continent = "KAL", x = 4600, y = 1500 },
  { id = "cenarionhold",   name = "Cenarion Hold",          zone = "Silithus",             continent = "KAL", x = 2700, y = 1400 },
}

-- Flight masters: place id -> faction (nil = both factions)
D.flightMasters = {
  stormwind = "Alliance", ironforge = "Alliance", sentinelhill = "Alliance", lakeshire = "Alliance",
  darkshire = "Alliance", nethergarde = "Alliance", thelsamar = "Alliance", menethil = "Alliance",
  southshore = "Alliance", refugepointe = "Alliance", aeriepeak = "Alliance", chillwind = "Alliance",
  ruttheran = "Alliance", auberdine = "Alliance", astranaar = "Alliance", theramore = "Alliance",
  feathermoon = "Alliance",
  undercity = "Horde", sepulcher = "Horde", tarrenmill = "Horde", hammerfall = "Horde",
  revantusk = "Horde", kargath = "Horde", stonard = "Horde", gromgol = "Horde",
  orgrimmar = "Horde", splintertree = "Horde", crossroads = "Horde", thunderbluff = "Horde",
  taurajo = "Horde", brackenwall = "Horde", freewind = "Horde", mojache = "Horde",
  bootybay = false, thoriumpoint = false, lightshope = false, ratchet = false,
  gadgetzan = false, cenarionhold = false, everlook = false,
}

-- Flight links (undirected). Each link is usable by a faction if both ends are its own or neutral.
D.flightLinks = {
  -- Alliance, Eastern Kingdoms
  { "stormwind", "ironforge" }, { "stormwind", "sentinelhill" }, { "stormwind", "lakeshire" },
  { "stormwind", "darkshire" }, { "lakeshire", "darkshire" }, { "darkshire", "nethergarde" },
  { "lakeshire", "nethergarde" }, { "ironforge", "thelsamar" }, { "ironforge", "menethil" },
  { "menethil", "refugepointe" }, { "menethil", "southshore" }, { "refugepointe", "southshore" },
  { "southshore", "aeriepeak" }, { "aeriepeak", "chillwind" }, { "southshore", "chillwind" },
  -- Horde, Eastern Kingdoms
  { "undercity", "sepulcher" }, { "undercity", "tarrenmill" }, { "sepulcher", "tarrenmill" },
  { "tarrenmill", "hammerfall" }, { "hammerfall", "revantusk" }, { "tarrenmill", "revantusk" },
  { "hammerfall", "kargath" }, { "kargath", "stonard" }, { "stonard", "gromgol" },
  -- Alliance, Kalimdor
  { "ruttheran", "auberdine" }, { "auberdine", "astranaar" }, { "astranaar", "theramore" },
  { "auberdine", "feathermoon" }, { "astranaar", "feathermoon" }, { "feathermoon", "theramore" },
  -- Horde, Kalimdor
  { "orgrimmar", "crossroads" }, { "orgrimmar", "splintertree" }, { "crossroads", "thunderbluff" },
  { "crossroads", "taurajo" }, { "crossroads", "brackenwall" }, { "thunderbluff", "taurajo" },
  { "taurajo", "freewind" }, { "freewind", "mojache" }, { "thunderbluff", "mojache" },
  { "splintertree", "crossroads" },
  -- Neutral flight masters, linked into both networks
  { "thoriumpoint", "ironforge" }, { "thoriumpoint", "kargath" },
  { "lightshope", "chillwind" }, { "lightshope", "undercity" }, { "lightshope", "revantusk" },
  { "lightshope", "aeriepeak" },
  { "bootybay", "stormwind" }, { "bootybay", "darkshire" }, { "bootybay", "gromgol" }, { "bootybay", "stonard" },
  { "ratchet", "orgrimmar" }, { "ratchet", "crossroads" }, { "ratchet", "theramore" }, { "ratchet", "astranaar" },
  { "gadgetzan", "freewind" }, { "gadgetzan", "theramore" }, { "gadgetzan", "brackenwall" }, { "gadgetzan", "feathermoon" },
  { "gadgetzan", "cenarionhold" }, { "cenarionhold", "mojache" }, { "cenarionhold", "feathermoon" },
  { "everlook", "auberdine" }, { "everlook", "astranaar" }, { "everlook", "orgrimmar" }, { "everlook", "splintertree" },
}

-- Ships, zeppelins, tram. cycle = time between departures; expected wait = cycle / 2.
D.transports = {
  { from = "menethil",  to = "theramore", mode = "boat",     ride = 150, cycle = 360, faction = "Alliance" },
  { from = "menethil",  to = "auberdine", mode = "boat",     ride = 150, cycle = 360, faction = "Alliance" },
  { from = "auberdine", to = "ruttheran", mode = "boat",     ride = 90,  cycle = 240, faction = "Alliance" },
  { from = "bootybay",  to = "ratchet",   mode = "boat",     ride = 150, cycle = 360 },
  { from = "orgrimmar", to = "undercity", mode = "zeppelin", ride = 120, cycle = 300, faction = "Horde" },
  { from = "orgrimmar", to = "gromgol",   mode = "zeppelin", ride = 120, cycle = 300, faction = "Horde" },
  { from = "undercity", to = "gromgol",   mode = "zeppelin", ride = 120, cycle = 300, faction = "Horde" },
  { from = "stormwind", to = "ironforge", mode = "tram",     ride = 90,  cycle = 120, faction = "Alliance" },
  { from = "ruttheran", to = "darnassus", mode = "portal",   ride = 5,   cycle = 0,   faction = "Alliance" },
}

-- Mage self-teleports (cast from anywhere on the ground).
D.teleports = {
  { name = "Teleport: Stormwind",     to = "stormwind",    mode = "teleport", class = "MAGE", faction = "Alliance" },
  { name = "Teleport: Ironforge",     to = "ironforge",    mode = "teleport", class = "MAGE", faction = "Alliance" },
  { name = "Teleport: Darnassus",     to = "darnassus",    mode = "teleport", class = "MAGE", faction = "Alliance" },
  { name = "Teleport: Orgrimmar",     to = "orgrimmar",    mode = "teleport", class = "MAGE", faction = "Horde" },
  { name = "Teleport: Undercity",     to = "undercity",    mode = "teleport", class = "MAGE", faction = "Horde" },
  { name = "Teleport: Thunder Bluff", to = "thunderbluff", mode = "teleport", class = "MAGE", faction = "Horde" },
}

-- Walking links the k-nearest rule misses (mountain passes, bridges).
D.extraWalks = {
  { "menethil", "dunalgaz" }, { "thandol", "refugepointe" }, { "dunalgaz", "ironforge" },
}

function D.build(World)
  local w = World.new()
  for _, p in ipairs(D.places) do
    local copy = {}
    for k, v in pairs(p) do copy[k] = v end
    w:addPlace(copy)
  end
  local fm = {}
  for id in pairs(D.flightMasters) do fm[#fm + 1] = id end
  table.sort(fm) -- deterministic node order
  for _, id in ipairs(fm) do w:addFlightMaster(id, D.flightMasters[id] or nil) end
  for _, l in ipairs(D.flightLinks) do w:addFlightLink(l[1], l[2]) end
  for _, t in ipairs(D.transports) do w:addTransport(t) end
  for _, t in ipairs(D.teleports) do w:addTeleport(t) end
  w:connectWalking(4, D.extraWalks)
  return w
end

ns.WorldData = D
