-- Sample quest logs for the demo and tests. Modelled on the kind of quests Classic gives
-- around levels 25-35 in these zones; names are descriptive, not exact in-game titles.
-- In the game the addon builds this list from the player's own input (see ui/addon.lua).
--   giver      place id where the quest is picked up (omit / accepted=true if already taken)
--   objectives place ids to visit
--   turnin     place id to hand it in
--   work       seconds spent at each objective (killing, collecting)
local _, ns = ...

local Q = {}

Q.alliance = {
  { id = "raptors",    name = "Raptor hides",            giver = "menethil",     objectives = { "raptorgrounds" }, turnin = "menethil",     work = 240 },
  { id = "letter",     name = "Letter to Theramore",     giver = "stormwind",    accepted = true,                 turnin = "theramore" },
  { id = "syndicate",  name = "Syndicate in Alterac",    giver = "southshore",   objectives = { "alterac" },       turnin = "southshore",   work = 300 },
  { id = "ogres",      name = "Ogres of Stromgarde",     giver = "refugepointe", objectives = { "stromgarde" },    turnin = "refugepointe", work = 300 },
  { id = "mathystra",  name = "Relics of Mathystra",     giver = "auberdine",    objectives = { "mathystra" },     turnin = "auberdine",    work = 240 },
  { id = "nightwatch", name = "Night Watch at Raven Hill", giver = "darkshire",  objectives = { "ravenhill" },     turnin = "darkshire",    work = 300 },
  { id = "astranaar",  name = "Supplies for Astranaar",  giver = "darnassus",    accepted = true,                 turnin = "astranaar" },
  { id = "uldaman",    name = "Survey of Uldaman",       giver = "ironforge",    objectives = { "uldaman" },       turnin = "ironforge",    work = 180 },
  { id = "tigers",     name = "Stranglethorn tigers",    giver = "nesingwary",   objectives = { "nesingwary" },    turnin = "nesingwary",   work = 360 },
}

Q.horde = {
  { id = "hammerfall", name = "Hammerfall orders",       giver = "undercity",    accepted = true,                 turnin = "hammerfall" },
  { id = "stromgarde", name = "Raid on Stromgarde",      giver = "hammerfall",   objectives = { "stromgarde" },    turnin = "hammerfall",   work = 300 },
  { id = "alterac",    name = "Alterac reconnaissance",  giver = "tarrenmill",   objectives = { "alterac" },       turnin = "tarrenmill",   work = 300 },
  { id = "razorhill",  name = "Durotar supply run",      giver = "orgrimmar",    objectives = { "razorhill" },     turnin = "crossroads",   work = 120 },
  { id = "tigers",     name = "Stranglethorn tigers",    giver = "nesingwary",   objectives = { "nesingwary" },    turnin = "nesingwary",   work = 360 },
  { id = "feralas",    name = "Feralas scouting",        giver = "mojache",      objectives = { "feathermoon" },   turnin = "mojache",      work = 240 },
  { id = "bluff",      name = "Message to Thunder Bluff",giver = "freewind",     accepted = true,                 turnin = "thunderbluff" },
}

ns.QuestData = Q
