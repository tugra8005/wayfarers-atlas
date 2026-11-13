-- Sample quest logs for the demo and tests: real World of Warcraft Classic quests (all
-- removed in patch 4.0.3a, so their wiki pages still describe the Classic versions).
-- Source: Wowpedia, https://wowpedia.fandom.com/wiki/<page> (the `wiki` field), read
-- 2026-11-13. warcraft.wiki.gg carries the same pages but was unreachable from here.
--
-- Givers, turn-ins and where the objectives are come from the quest, NPC and mob pages.
-- Where a page names only the zone (raptors "in Arathi Highlands"), the objective place
-- is put in that zone's middle on the hand-drawn map. `work` is our estimate of the
-- minutes of killing or collecting, in seconds; the wiki does not give it.
--
-- Some quests continue a chain; the previous step is assumed done (`previous`), except
-- where both steps are in the log: `requires` makes the planner hand in the first before
-- picking up the second.
--   giver      place id where the quest is picked up
--   objectives place ids to visit
--   turnin     place id to hand it in
--   work       seconds spent at each objective
-- In the game the addon builds the list from the player's own input (see ui/addon.lua).
local _, ns = ...

local Q = {}

Q.alliance = {
  { id = "nightwatch", name = "The Night Watch", wiki = "The_Night_Watch_(Classic)", questId = 56, level = 24,
    -- Commander Althea Ebonlocke, Darkshire; 8 Skeletal Warriors, 6 Skeletal Mages in Tranquil Gardens, south of Darkshire
    giver = "darkshire", objectives = { "tranquilgardens" }, turnin = "darkshire", work = 300 },
  { id = "plea", name = "Plea To The Alliance", wiki = "Plea_To_The_Alliance", questId = 634, level = 31,
    previous = "The Thandol Span",
    -- Rhag Garmason, Dun Modr (Wetlands) -> Captain Nials, Refuge Pointe
    giver = "dunmodr", turnin = "refugepointe" },
  { id = "northfold", name = "Northfold Manor", wiki = "Northfold_Manor_(Classic)", questId = 681, level = 31,
    -- Captain Nials, Refuge Pointe; 10 Syndicate Highwaymen, 6 Syndicate Mercenaries at Northfold Manor
    giver = "refugepointe", objectives = { "northfold" }, turnin = "refugepointe", work = 360 },
  { id = "nobledeaths", name = "Noble Deaths", wiki = "Noble_Deaths", level = 36,
    previous = "Foreboding Plans",
    -- Magistrate Henry Maleb, Southshore; 7 Alterac Signet Rings from the Syndicate in the ruins of Strahnbrad
    giver = "southshore", objectives = { "strahnbrad" }, turnin = "southshore", work = 420 },
  { id = "badlandsrun", name = "Badlands Reagent Run", wiki = "Badlands_Reagent_Run_(Alliance)", questId = 2500, level = 39,
    -- Ghak Healtouch, Thelsamar; buzzard gizzards, crag coyote fangs, rock elemental shards in the Badlands
    giver = "thelsamar", objectives = { "badlands" }, turnin = "thelsamar", work = 420 },
  { id = "ironband", name = "Ironband Wants You!", wiki = "Ironband_Wants_You!", questId = 707, level = 37,
    -- Prospector Stormpike, The Library, Ironforge -> Prospector Ironband, Ironband's Excavation Site (Loch Modan)
    giver = "ironforge", turnin = "ironbandsdig" },
  { id = "jameshyal", name = "James Hyal", wiki = "James_Hyal_(2)", questId = 1302, level = 35,
    previous = "James Hyal",
    -- Vincent Hyal, Menethil Harbor -> Clerk Lendry, Theramore Isle
    giver = "menethil", turnin = "theramore" },
  { id = "barrensport", name = "The Barrens Port", wiki = "The_Barrens_Port", questId = 1039, level = 30,
    previous = "Velinde's Effects",
    -- Thyn'tel Bladeweaver, Warrior's Terrace, Darnassus -> Wharfmaster Dizzywig, Ratchet
    giver = "darnassus", turnin = "ratchet" },
}

Q.horde = {
  { id = "hammerfall", name = "Hammerfall", wiki = "Hammerfall_(Classic)", questId = 655, level = 34,
    -- Gor'mul -> Tor'gan, both in Hammerfall
    giver = "hammerfall", turnin = "hammerfall" },
  { id = "raisingspirits", name = "Raising Spirits", wiki = "Raising_Spirits_(1)", questId = 672, level = 34,
    requires = { "hammerfall" },
    -- Tor'gan, Hammerfall; 10 Highland Raptor Eyes from Highland Striders and Thrashers (Arathi Highlands)
    giver = "hammerfall", objectives = { "arathiraptors" }, turnin = "hammerfall", work = 360 },
  { id = "agony", name = "Elixir of Agony", wiki = "Elixir_of_Agony_(2)", questId = 513, level = 28,
    previous = "Elixir of Agony",
    -- Apothecary Lydon, Tarren Mill -> Master Apothecary Faranell, the Apothecarium, Undercity
    giver = "tarrenmill", turnin = "undercity" },
  { id = "returntb", name = "Return to Thunder Bluff", wiki = "Return_to_Thunder_Bluff_(1)", questId = 1067, level = 23,
    previous = "Blood of Innocents",
    -- Apothecary Lydon, Tarren Mill -> Apothecary Zamah, Pools of Vision, Thunder Bluff
    giver = "tarrenmill", turnin = "thunderbluff" },
  { id = "hillsbrad", name = "Battle of Hillsbrad", wiki = "Battle_of_Hillsbrad_(2)", questId = 528, level = 25,
    previous = "Battle of Hillsbrad",
    -- High Executor Darthalia, Tarren Mill; 15 Hillsbrad Peasants in the southern fields
    giver = "tarrenmill", objectives = { "hillsbradfields" }, turnin = "tarrenmill", work = 300 },
  { id = "badlandsrun", name = "Badlands Reagent Run", wiki = "Badlands_Reagent_Run_(Horde)", questId = 2258, level = 39,
    -- Jarkal Mossmeld, Kargath; the same reagents from the Badlands
    giver = "kargath", objectives = { "badlands" }, turnin = "kargath", work = 420 },
  { id = "hunting", name = "Hunting in Stranglethorn", wiki = "Hunting_in_Stranglethorn_(Classic)", level = 31,
    -- Roon Wildmane, Shadowprey Village (Desolace) -> Hemet Nesingwary, Nesingwary's Expedition
    giver = "shadowprey", turnin = "nesingwary" },
  { id = "gromgol", name = "The Defense of Grom'gol", wiki = "The_Defense_of_Grom'gol", questId = 568, level = 36,
    -- Commander Aggro'gosh, Grom'gol Base Camp; 15 Lashtail Raptors in northern Stranglethorn
    giver = "gromgol", objectives = { "lashtail" }, turnin = "gromgol", work = 360 },
}

ns.QuestData = Q
