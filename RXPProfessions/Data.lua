-- RestedXP Professions - static profession data (1-300)
-- Routes are the standard community leveling paths, checked row by row
-- against each game's recipe data (Classic Era and TBC: the client's
-- skill-up ranges and the trainer tables; WoW Forever: its client data
-- and trainer windows players recorded, October 2026). Skill-up RNG means
-- brackets can shift by a few points in practice.

local addonName, ns = ...

-- Rank progression: at `trainAt` skill you can (and should) learn the rank
-- that raises your cap to the next tier.
ns.RANKS = {
    {cap = 75, trainAt = 50, nextRank = "Journeyman"},
    {cap = 150, trainAt = 125, nextRank = "Expert"},
    {cap = 225, trainAt = 200, nextRank = "Artisan"},
    {cap = 300, trainAt = 275, nextRank = "Master", fromTBC = true}, -- not on Classic Era or Forever
    {cap = 375, trainAt = 350, nextRank = "Grand Master", later = true}, -- Mists Classic
    {cap = 450, trainAt = 425, nextRank = "Illustrious", later = true},
    {cap = 525, trainAt = 500, nextRank = "Zen Master", later = true},
    {cap = 600}
}

-- What a rank asks besides skill. Crafting trainers want a character
-- level; First Aid, Cooking and Fishing give Expert through a book and
-- Artisan through a quest at 225 (the notes say where).
ns.RANK_RULES = {
    craft = {Journeyman = {level = 10}, Expert = {level = 20}, Artisan = {level = 35}, Master = {level = 50}},
    ["First Aid"] = {Expert = {how = "book"}, Artisan = {how = "quest", skill = 225, level = 35}},
    ["Cooking"] = {Expert = {how = "book"}, Artisan = {how = "quest", skill = 225, level = 35}},
    ["Fishing"] = {Expert = {how = "book"}, Artisan = {how = "quest", skill = 225, level = 35}}
}
-- ...and where a game differs (looked up first; Core.lua ns.CLIENT): the
-- trainers' and books' level gates as each game's data has them, and
-- TBC's Master First Aid, Cooking and Fishing, which are books in Outland
ns.RANK_RULES_FOR = {
    era = {
        ["Cooking"] = {Journeyman = {level = 10}},
        ["Fishing"] = {Expert = {how = "book", level = 20}}
    },
    tbc = {
        ["Cooking"] = {Journeyman = {level = 10}, Master = {how = "book", skill = 300}},
        ["First Aid"] = {Master = {how = "book", skill = 300}},
        ["Fishing"] = {Journeyman = {level = 10}, Master = {how = "book", skill = 275, level = 45}}
    },
    forever = {
        ["Fishing"] = {Journeyman = {level = 10}, Expert = {how = "book", level = 20}}
    }
}

-- Gathering professions: what unlocks at which skill. Sorted ascending.
-- (Forever's tiers are the same; `forever` names its new starter nodes.)
-- Herbs carry their item IDs: the game names the herb in its language.
ns.GATHER = {
    ["Mining"] = {
        verb = "Mine",
        tiers = {
            {1, "Copper Vein", forever = "Copper Vein / Poor Copper Vein (Chunk of Amber in Shadowglen)"},
            {65, "Tin Vein"},
            {75, "Silver Vein"},
            {125, "Iron Deposit"},
            {155, "Gold Vein"},
            {175, "Mithril Deposit"},
            {230, "Truesilver Deposit"},
            {245, "Small Thorium Vein"},
            {275, "Rich Thorium Vein"}
        }
    },
    ["Herbalism"] = {
        verb = "Pick",
        tiers = {
            {1, "Peacebloom / Silverleaf", items = {2447, 765}, forever = "Peacebloom / Silverleaf (Wilted / Stunted in starting areas)"},
            {15, "Earthroot", items = {2449}},
            {50, "Mageroyal", items = {785}},
            {70, "Briarthorn", items = {2450}},
            {85, "Stranglekelp", items = {3820}},
            {100, "Bruiseweed", items = {2453}},
            {115, "Wild Steelbloom", items = {3355}},
            {125, "Kingsblood", items = {3356}},
            {150, "Liferoot", items = {3357}},
            {170, "Goldthorn", items = {3821}},
            {185, "Khadgar's Whisker", items = {3358}},
            {205, "Firebloom", items = {4625}},
            {210, "Purple Lotus", items = {8831}},
            {230, "Sungrass", items = {8838}},
            {245, "Ghost Mushroom", items = {8845}},
            {250, "Gromsblood", items = {8846}},
            {260, "Golden Sansam", items = {13464}},
            {270, "Dreamfoil", items = {13463}},
            {280, "Mountain Silversage", items = {13465}},
            {285, "Plaguebloom", items = {13466}},
            {290, "Icecap", items = {13467}}
        }
    }
}

-- Crafting professions: route = {from, recipe, mats}, notes = {at, text}.
-- A row reads "from this skill, craft this until the next row". A recipe
-- may list alternatives split by " / " (whichever you know); `source` says
-- where to get one a trainer does not teach ({A = ..., H = ...} per
-- faction); `tbc` / `tbcMats` are TBC's name and mats where they differ.
-- primary = counts against the ~5-skill-per-level pace check.
-- foreverRoute / foreverNotes: WoW Forever's own, where the game differs
-- (its client data, build 70291, and its trainers as players recorded
-- them; Core.lua swaps them in on Forever).
-- notes shown on some games only (Core.lua NoteVisible, ns.CLIENT)
local ERA = {era = true}
local TBC = {tbc = true}
local BOOKS = {era = true, tbc = true, forever = true} -- book and quest ranks, before patch 3.1

ns.CRAFT = {
    ["First Aid"] = {
        route = {
            {1, "Linen Bandage", "1 Linen Cloth",
             spell = 3275, reagents = {{2589, 1}}},
            {40, "Heavy Linen Bandage", "2 Linen Cloth",
             spell = 3276, reagents = {{2589, 2}}},
            {80, "Wool Bandage", "1 Wool Cloth",
             spell = 3277, reagents = {{2592, 1}}},
            {115, "Heavy Wool Bandage", "2 Wool Cloth",
             spell = 3278, reagents = {{2592, 2}}},
            {150, "Silk Bandage", "1 Silk Cloth",
             spell = 7928, reagents = {{4306, 1}}},
            {180, "Heavy Silk Bandage", "2 Silk Cloth",
             spell = 7929, reagents = {{4306, 2}}, source = {A = "Manual (22s): Deneb Walker - Stromgarde Keep, Arathi Highlands",
                       H = "Manual (22s): Balai Lok'Wein - Brackenwall Village, Dustwallow Marsh"}},
            {210, "Mageweave Bandage", "1 Mageweave Cloth",
             spell = 10840, reagents = {{4338, 1}}, source = {A = "Manual (50s): Deneb Walker - Stromgarde Keep, Arathi Highlands",
                       H = "Manual (50s): Balai Lok'Wein - Brackenwall Village, Dustwallow Marsh"}},
            {240, "Heavy Mageweave Bandage", "2 Mageweave Cloth",
             spell = 10841, reagents = {{4338, 2}}, source = {A = "Doctor Gustaf VanHowzen - Theramore Isle, Dustwallow Marsh (the Triage doctor)",
                       H = "Doctor Gregory Victor - Hammerfall, Arathi Highlands (the Triage doctor)"}},
            {260, "Runecloth Bandage", "1 Runecloth",
             spell = 18629, reagents = {{14047, 1}}, source = {A = "Doctor Gustaf VanHowzen - Theramore Isle, Dustwallow Marsh (the Triage doctor)",
                       H = "Doctor Gregory Victor - Hammerfall, Arathi Highlands (the Triage doctor)"}},
            {290, "Heavy Runecloth Bandage", "2 Runecloth",
             spell = 18630, reagents = {{14047, 2}}, source = {A = "Doctor Gustaf VanHowzen - Theramore Isle, Dustwallow Marsh (the Triage doctor)",
                       H = "Doctor Gregory Victor - Hammerfall, Arathi Highlands (the Triage doctor)"}}
        },
        notes = {
            {150, {A = "Expert rank: book |cFFFFCC00Expert First Aid - Under Wraps|r (1g) - Deneb Walker, Stromgarde (Arathi); also sells the 180 and 210 bandage manuals",
                   H = "Expert rank: book |cFFFFCC00Expert First Aid - Under Wraps|r (1g) - Balai Lok'Wein, Brackenwall (Dustwallow); also sells the 180 and 210 bandage manuals"},
             req = 125, gate = 150, clients = BOOKS},
            {225, {A = "Artisan rank: |cFFFFCC00Triage|r quest (level 35) - Doctor Gustaf VanHowzen, Theramore",
                   H = "Artisan rank: |cFFFFCC00Triage|r quest (level 35) - Doctor Gregory Victor, Hammerfall (Arathi)"},
             req = 225, gate = 225, clients = BOOKS},
            {300, {A = "Master rank (Outland): book |cFFFFCC00Master First Aid - Doctor in the House|r - Burko, Temple of Telhamat (Hellfire Peninsula)",
                   H = "Master rank (Outland): book |cFFFFCC00Master First Aid - Doctor in the House|r - Aresella, Falcon Watch (Hellfire Peninsula)"},
             req = 290, gate = 300, clients = TBC}
        },
        foreverNotes = {
            {50, "Forever: First Aid makes the healing potions too - Minor (1), Lesser (55) and Healing (110) from your trainer, with herbs and vials"},
            {150, {A = "Expert rank: book |cFFFFCC00Expert First Aid - Under Wraps|r (1g) - Deneb Walker, Stromgarde (Arathi); also sells the 180 and 210 bandage manuals",
                   H = "Expert rank: book |cFFFFCC00Expert First Aid - Under Wraps|r (1g) - Balai Lok'Wein, Brackenwall (Dustwallow); also sells the 180 and 210 bandage manuals"},
             req = 125, gate = 150, clients = BOOKS},
            {225, {A = "Artisan rank: |cFFFFCC00Triage|r quest (level 35) - Doctor Gustaf VanHowzen, Theramore",
                   H = "Artisan rank: |cFFFFCC00Triage|r quest (level 35) - Doctor Gregory Victor, Hammerfall (Arathi)"},
             req = 225, gate = 225, clients = BOOKS},
            {300, {A = "Master rank (Outland): book |cFFFFCC00Master First Aid - Doctor in the House|r - Burko, Temple of Telhamat (Hellfire Peninsula)",
                   H = "Master rank (Outland): book |cFFFFCC00Master First Aid - Doctor in the House|r - Aresella, Falcon Watch (Hellfire Peninsula)"},
             req = 290, gate = 300, clients = TBC}
        }
    },
    ["Alchemy"] = {
        primary = true,
        route = {
            {1, "Minor Healing Potion", "1 Peacebloom + 1 Silverleaf + 1 Empty Vial",
             spell = 2330, reagents = {{2447, 1}, {765, 1}, {3371, 1}}},
            {60, "Lesser Healing Potion", "1 Minor Healing Potion + 1 Briarthorn",
             spell = 2337, reagents = {{118, 1}, {2450, 1}}},
            {110, "Healing Potion", "1 Bruiseweed + 1 Briarthorn + 1 Leaded Vial",
             spell = 3447, reagents = {{2453, 1}, {2450, 1}, {3372, 1}}},
            {140, "Lesser Mana Potion", "1 Mageroyal + 1 Stranglekelp + 1 Empty Vial",
             spell = 3173, reagents = {{785, 1}, {3820, 1}, {3371, 1}}},
            {155, "Greater Healing Potion", "1 Liferoot + 1 Kingsblood + 1 Leaded Vial",
             spell = 7181, reagents = {{3357, 1}, {3356, 1}, {3372, 1}}},
            {185, "Elixir of Agility", "1 Stranglekelp + 1 Goldthorn + 1 Leaded Vial",
             spell = 11449, reagents = {{3820, 1}, {3821, 1}, {3372, 1}}},
            {210, "Elixir of Greater Defense", "1 Wild Steelbloom + 1 Goldthorn + 1 Leaded Vial",
             spell = 11450, reagents = {{3355, 1}, {3821, 1}, {3372, 1}}},
            {215, "Superior Healing Potion", "1 Sungrass + 1 Khadgar's Whisker + 1 Crystal Vial",
             spell = 11457, reagents = {{8838, 1}, {3358, 1}, {8925, 1}}},
            {230, "Elixir of Detect Undead", "1 Arthas' Tears + 1 Crystal Vial",
             spell = 11460, reagents = {{8836, 1}, {8925, 1}}},
            {250, "Elixir of Greater Agility", "1 Sungrass + 1 Goldthorn + 1 Crystal Vial",
             spell = 11467, reagents = {{8838, 1}, {3821, 1}, {8925, 1}}},
            {265, "Superior Mana Potion", "2 Sungrass + 2 Blindweed + 1 Crystal Vial",
             spell = 17553, reagents = {{8838, 2}, {8839, 2}, {8925, 1}}, tbcSource = "", source = {A = "Recipe (limited stock): Ulthir - Alchemy supplies, Darnassus",
                       H = "Recipe (limited stock): Algernon - Alchemy supplies, Undercity"}},
            {285, "Major Healing Potion", "2 Golden Sansam + 1 Mountain Silversage + 1 Crystal Vial",
             spell = 17556, reagents = {{13464, 2}, {13465, 1}, {8925, 1}}, tbcSource = "", source = "Recipe (limited stock): Evie Whirlbrew - Everlook, Winterspring"}
        },
        foreverRoute = {
            -- Forever moved the healing potions to First Aid
            {1, "Elixir of Minor Defense", "1 Silverleaf + 1 Peacebloom + 1 Empty Vial",
             spell = 7183, reagents = {{765, 1}, {2447, 1}, {3371, 1}}},
            {60, "Elixir of Minor Fortitude", "2 Earthroot + 1 Peacebloom + 1 Empty Vial",
             spell = 2334, reagents = {{2449, 2}, {2447, 1}, {3371, 1}}},
            {90, "Elixir of Wisdom", "1 Mageroyal + 2 Briarthorn + 1 Empty Vial",
             spell = 3171, reagents = {{785, 1}, {2450, 2}, {3371, 1}}},
            {120, "Lesser Mana Potion", "1 Mageroyal + 1 Stranglekelp + 1 Empty Vial",
             spell = 3173, reagents = {{785, 1}, {3820, 1}, {3371, 1}}},
            {160, "Mana Potion", "1 Stranglekelp + 1 Kingsblood + 1 Leaded Vial",
             spell = 3452, reagents = {{3820, 1}, {3356, 1}, {3372, 1}}},
            {185, "Elixir of Agility", "1 Stranglekelp + 1 Goldthorn + 1 Leaded Vial",
             spell = 11449, reagents = {{3820, 1}, {3821, 1}, {3372, 1}}},
            {210, "Elixir of Defense", "1 Wild Steelbloom + 1 Goldthorn + 1 Leaded Vial",
             spell = 11450, reagents = {{3355, 1}, {3821, 1}, {3372, 1}}},
            {230, "Draught of Detect Undead", "1 Arthas' Tears + 1 Crystal Vial",
             spell = 11460, reagents = {{8836, 1}, {8925, 1}}},
            {250, "Elixir of Greater Agility", "1 Sungrass + 1 Goldthorn + 1 Crystal Vial",
             spell = 11467, reagents = {{8838, 1}, {3821, 1}, {8925, 1}}},
            {265, "Superior Mana Potion", "2 Sungrass + 2 Blindweed + 1 Crystal Vial",
             spell = 17553, reagents = {{8838, 2}, {8839, 2}, {8925, 1}}, source = {A = "Recipe (about 1g 20s, limited stock): Ulthir - Alchemy supplies, Darnassus",
                       H = "Recipe (about 1g 25s, limited stock): Algernon - Alchemy supplies, Undercity"}}
        },
        notes = {
            {1, "Vials: Alchemy supplies vendor (near trainers)"},
            {150, {A = "Expert rank: Ainethil - Darnassus", H = "Expert rank: Doctor Herbert Halsey - Undercity"},
             req = 125, gate = 150, clients = ERA},
            {225, {A = "Artisan trainer: Kylanna Windwhisper - Feathermoon Stronghold, Feralas",
                   H = "Artisan trainer: Rogvar - Stonard, Swamp of Sorrows"},
             req = 200, gate = 225, clients = ERA}
        },
        foreverNotes = {
            {1, "Vials: Alchemy supplies vendor (near trainers)"},
            {20, "Forever: the healing potions are First Aid recipes now"},
            {225, {A = "Artisan trainer: Kylanna Windwhisper - Feathermoon Stronghold, Feralas; or Master Mycologist Shurome - Emerald Sanctuary, Felwood",
                   H = "Artisan trainer: Master Mycologist Shurome - Emerald Sanctuary, Felwood"},
             req = 200, gate = 225}
        }
    },
    ["Blacksmithing"] = {
        primary = true,
        route = {
            {1, "Rough Sharpening Stone", "1 Rough Stone",
             spell = 2660, reagents = {{2835, 1}}},
            {25, "Rough Grinding Stone", "2 Rough Stone",
             spell = 3320, reagents = {{2835, 2}}},
            {75, "Coarse Grinding Stone", "2 Coarse Stone",
             spell = 3326, reagents = {{2836, 2}}},
            {90, "Runed Copper Belt", "10 Copper Bar",
             spell = 2666, reagents = {{2840, 10}}},
            {105, "Rough Bronze Leggings", "6 Bronze Bar",
             spell = 2668, reagents = {{2841, 6}}},
            {125, "Heavy Grinding Stone", "3 Heavy Stone",
             spell = 3337, reagents = {{2838, 3}}},
            {137, "Patterned Bronze Bracers", "5 Bronze Bar + 2 Coarse Grinding Stone",
             spell = 2672, reagents = {{2841, 5}, {3478, 2}}},
            {155, "Green Iron Leggings", "8 Iron Bar + 1 Heavy Grinding Stone + 1 Green Dye",
             spell = 3506, reagents = {{3575, 8}, {3486, 1}, {2605, 1}}},
            {165, "Green Iron Bracers", "6 Iron Bar + 1 Green Dye",
             spell = 3501, reagents = {{3575, 6}, {2605, 1}}},
            {190, "Golden Scale Bracers", "5 Steel Bar + 2 Heavy Grinding Stone",
             spell = 7223, reagents = {{3859, 5}, {3486, 2}}},
            {215, "Steel Plate Helm", "14 Steel Bar + 1 Solid Grinding Stone",
             spell = 9935, reagents = {{3859, 14}, {7966, 1}}},
            {235, "Mithril Coif", "10 Mithril Bar + 6 Mageweave Cloth",
             spell = 9961, reagents = {{3860, 10}, {4338, 6}}},
            {250, "Dense Grinding Stone", "4 Dense Stone",
             spell = 16639, reagents = {{12365, 4}}},
            {257, "Heavy Mithril Boots", "14 Mithril Bar + 4 Thick Leather",
             spell = 9968, reagents = {{3860, 14}, {4304, 4}}},
            {270, "Imperial Plate Bracers", "20 Thorium Bar + 1 Star Ruby",
             tbcMats = "12 Thorium Bar", spell = 16649, reagents = {{12359, 20}, {7910, 1}}, tbcReagents = {{12359, 12}}, source = "Plans: quest from Derotain Mudsipper, Gadgetzan (Tanaris) - needs level 50 and 20 Thorium Bar (TBC: 10)"}
        },
        foreverRoute = {
            {1, "Rough Sharpening Stone", "1 Rough Stone",
             spell = 2660, reagents = {{2835, 1}}},
            {25, "Rough Grinding Stone", "2 Rough Stone",
             spell = 3320, reagents = {{2835, 2}}},
            {65, "Copper Chain Belt", "6 Copper Bar",
             spell = 2661, reagents = {{2840, 6}}},
            {90, "Rough Bronze Leggings", "6 Bronze Bar",
             spell = 2668, reagents = {{2841, 6}}},
            {130, "Green Iron Leggings", "8 Iron Bar + 1 Heavy Grinding Stone + 1 Green Dye",
             spell = 3506, reagents = {{3575, 8}, {3486, 1}, {2605, 1}}, source = {A = "Expert trainer: Bengus Deepforge - Ironforge, or Brikk Keencraft - Booty Bay",
                       H = "Expert trainer: Saru Steelfury - Orgrimmar, or Brikk Keencraft - Booty Bay"}},
            {140, "Green Iron Bracers", "6 Iron Bar + 1 Green Dye",
             spell = 3501, reagents = {{3575, 6}, {2605, 1}}, source = {A = "Expert trainer: Bengus Deepforge - Ironforge, or Brikk Keencraft - Booty Bay",
                       H = "Expert trainer: Saru Steelfury - Orgrimmar, or Brikk Keencraft - Booty Bay"}},
            {177, "Golden Scale Bracers", "5 Steel Bar + 2 Heavy Grinding Stone",
             spell = 7223, reagents = {{3859, 5}, {3486, 2}}},
            {197, "Heavy Mithril Gauntlet", "6 Mithril Bar + 4 Mageweave Cloth",
             spell = 9928, reagents = {{3860, 6}, {4338, 4}}},
            {210, "Steel Plate Helm", "14 Steel Bar + 1 Solid Grinding Stone",
             spell = 9935, reagents = {{3859, 14}, {7966, 1}}},
            {220, "Heavy Mithril Axe", "12 Mithril Bar + 2 Citrine + 1 Solid Grinding Stone + 4 Heavy Leather",
             spell = 9993, reagents = {{3860, 12}, {3864, 2}, {7966, 1}, {4234, 4}}},
            {230, "Mithril Coif", "10 Mithril Bar + 6 Mageweave Cloth",
             spell = 9961, reagents = {{3860, 10}, {4338, 6}}, source = "Artisan trainer: Brikk Keencraft - Booty Bay"},
            {235, "Heavy Mithril Boots", "14 Mithril Bar + 4 Thick Leather",
             spell = 9968, reagents = {{3860, 14}, {4304, 4}}, source = "Artisan trainer: Brikk Keencraft - Booty Bay"},
            {240, "Imperial Plate Belt", "22 Thorium Bar + 6 Rugged Leather + 1 Aquamarine",
             spell = 16647, reagents = {{12359, 22}, {8170, 6}, {7909, 1}}, source = "Plans: quest from Derotain Mudsipper, Gadgetzan (Tanaris) - needs level 50 and 20 Thorium Bar"},
            {260, "Imperial Plate Bracers", "20 Thorium Bar + 1 Star Ruby",
             spell = 16649, reagents = {{12359, 20}, {7910, 1}}, source = "Plans: quest from Derotain Mudsipper, Gadgetzan (Tanaris) - needs level 50 and 20 Thorium Bar"},
            {275, "Imperial Plate Boots", "34 Thorium Bar + 1 Star Ruby + 1 Aquamarine",
             spell = 16657, reagents = {{12359, 34}, {7910, 1}, {7909, 1}}, source = "Plans: quest from Derotain Mudsipper, Gadgetzan (Tanaris) - needs level 50 and 40 Thorium Bar"}
        },
        notes = {
            {1, "Pairs best with Mining"},
            {100, "Keep your Coarse Grinding Stones: Patterned Bronze Bracers (137) takes 2 each, about 37"},
            {130, "Make extra Heavy Grinding Stones and keep them: Green Iron Leggings (155) takes 1, Golden Scale Bracers (190) 2 - about 65 in all"},
            {150, {A = "Expert rank: Bengus Deepforge - Ironforge", H = "Expert rank: Saru Steelfury - Orgrimmar"},
             req = 125, gate = 150, clients = ERA},
            {215, "Steel Plate Helm takes a Solid Grinding Stone each: learn it at the trainer (200) and make about 20 (4 Solid Stone each)"},
            {225, "Artisan trainer: Brikk Keencraft, Booty Bay", req = 200, gate = 225, clients = ERA},
            {255, "Imperial Plate Bracers (270): the plans are a quest in Gadgetzan that needs character level 50"}
        },
        foreverNotes = {
            {1, "Pairs best with Mining"},
            {130, "Learn Heavy Grinding Stone (100) and make about 60 (3 Heavy Stone each): Green Iron Leggings takes 1, Golden Scale Bracers (177) 2"},
            {210, "Learn Solid Grinding Stone (175) and make about 40 (4 Solid Stone each) for Steel Plate Helm and Heavy Mithril Axe"},
            {220, "Heavy Mithril Axe turns green at 222: if Brikk Keencraft (Booty Bay) already teaches you Mithril Coif, make that instead"},
            {225, "Artisan trainer: Brikk Keencraft, Booty Bay", req = 200, gate = 225},
            {240, "Imperial Plate plans (240+) are quests in Gadgetzan that need character level 50. Not 50 yet? From 250, Plans: Ornate Thorium Handaxe (Magnus Frostwake, Caer Darrow) is orange to 274"}
        }
    },
    ["Engineering"] = {
        primary = true,
        route = {
            {1, "Rough Blasting Powder", "1 Rough Stone",
             spell = 3918, reagents = {{2835, 1}}},
            {30, "Handful of Copper Bolts", "1 Copper Bar",
             spell = 3922, reagents = {{2840, 1}}},
            {50, "Arclight Spanner", "6 Copper Bar",
             spell = 7430, reagents = {{2840, 6}}},
            {51, "Copper Tube", "2 Copper Bar + 1 Weak Flux",
             spell = 3924, reagents = {{2840, 2}, {2880, 1}}},
            {75, "Coarse Blasting Powder", "1 Coarse Stone",
             spell = 3929, reagents = {{2836, 1}}},
            {90, "Copper Modulator", "2 Handful of Copper Bolts + 1 Copper Bar + 2 Linen Cloth",
             spell = 3926, reagents = {{4359, 2}, {2840, 1}, {2589, 2}}},
            {105, "Bronze Tube", "2 Bronze Bar + 1 Weak Flux",
             spell = 3938, reagents = {{2841, 2}, {2880, 1}}},
            {125, "Heavy Blasting Powder", "1 Heavy Stone",
             spell = 3945, reagents = {{2838, 1}}},
            {135, "Whirring Bronze Gizmo", "2 Bronze Bar + 1 Wool Cloth",
             spell = 3942, reagents = {{2841, 2}, {2592, 1}}},
            {150, "Bronze Framework", "2 Bronze Bar + 1 Medium Leather + 1 Wool Cloth",
             spell = 3953, reagents = {{2841, 2}, {2319, 1}, {2592, 1}}},
            {160, "Iron Strut", "2 Iron Bar",
             spell = 3958, reagents = {{3575, 2}}},
            {170, "Gyrochronatom", "1 Iron Bar + 1 Gold Power Core",
             spell = 3961, reagents = {{3575, 1}, {10558, 1}}},
            {175, "Solid Blasting Powder", "2 Solid Stone",
             spell = 12585, reagents = {{7912, 2}}},
            {185, "Iron Grenade", "1 Iron Bar + 1 Heavy Blasting Powder + 1 Silk Cloth (makes 2-4)",
             spell = 3962, reagents = {{3575, 1}, {4377, 1}, {4306, 1}}, makes = "2-4"},
            {195, "Mithril Tube", "3 Mithril Bar",
             spell = 12589, reagents = {{3860, 3}}},
            {215, "Mithril Casing", "3 Mithril Bar",
             spell = 12599, reagents = {{3860, 3}}},
            {235, "Hi-Explosive Bomb", "2 Mithril Casing + 1 Unstable Trigger + 2 Solid Blasting Powder (makes 4)",
             spell = 12619, reagents = {{10561, 2}, {10560, 1}, {10505, 2}}, makes = 4},
            {245, "Mithril Gyro-Shot", "2 Mithril Bar + 2 Solid Blasting Powder (makes 200)",
             spell = 12621, reagents = {{3860, 2}, {10505, 2}}, makes = 200},
            {250, "Dense Blasting Powder", "2 Dense Stone",
             spell = 19788, reagents = {{12365, 2}}},
            {255, "Dense Dynamite", "2 Dense Blasting Powder + 3 Runecloth (makes 2)",
             spell = 23070, reagents = {{15992, 2}, {14047, 3}}, makes = 2},
            {260, "Thorium Widget", "3 Thorium Bar + 1 Runecloth",
             spell = 19791, reagents = {{12359, 3}, {14047, 1}}, source = {A = "Schematic (about 1g 20s, limited stock): Gearcutter Cogspinner - Ironforge",
                       H = "Schematic (about 1g 20s, limited stock): Sovik - Orgrimmar"}},
            {290, "Thorium Tube", "6 Thorium Bar",
             spell = 19795, reagents = {{12359, 6}}, source = "Schematic (limited stock): Xizzer Fizzbolt - Everlook, Winterspring"}
        },
        foreverRoute = {
            {1, "Rough Blasting Powder", "1 Rough Stone",
             spell = 3918, reagents = {{2835, 1}}},
            {30, "Handful of Copper Bolts", "1 Copper Bar",
             spell = 3922, reagents = {{2840, 1}}},
            {50, "Arclight Spanner", "6 Copper Bar",
             spell = 7430, reagents = {{2840, 6}}},
            {51, "Copper Tube", "2 Copper Bar + 1 Weak Flux",
             spell = 3924, reagents = {{2840, 2}, {2880, 1}}},
            {75, "Coarse Blasting Powder", "1 Coarse Stone",
             spell = 3929, reagents = {{2836, 1}}},
            {90, "Copper Modulator", "2 Handful of Copper Bolts + 1 Copper Bar + 2 Linen Cloth",
             spell = 3926, reagents = {{4359, 2}, {2840, 1}, {2589, 2}}},
            {105, "Bronze Tube", "2 Bronze Bar + 1 Weak Flux",
             spell = 3938, reagents = {{2841, 2}, {2880, 1}}},
            {125, "Heavy Blasting Powder", "1 Heavy Stone",
             spell = 3945, reagents = {{2838, 1}}},
            {135, "Whirring Bronze Gizmo", "2 Bronze Bar + 1 Wool Cloth",
             spell = 3942, reagents = {{2841, 2}, {2592, 1}}},
            {150, "Bronze Framework", "2 Bronze Bar + 1 Medium Leather + 1 Wool Cloth",
             spell = 3953, reagents = {{2841, 2}, {2319, 1}, {2592, 1}}},
            {160, "Iron Strut", "2 Iron Bar",
             spell = 3958, reagents = {{3575, 2}}},
            {170, "Gyrochronatom", "1 Iron Bar + 1 Gold Power Core",
             spell = 3961, reagents = {{3575, 1}, {10558, 1}}},
            {175, "Solid Blasting Powder", "2 Solid Stone",
             spell = 12585, reagents = {{7912, 2}}},
            {185, "Iron Grenade", "1 Iron Bar + 1 Heavy Blasting Powder + 1 Silk Cloth (makes 3)",
             spell = 3962, reagents = {{3575, 1}, {4377, 1}, {4306, 1}}, makes = 3},
            {195, "Mithril Tube", "3 Mithril Bar",
             spell = 12589, reagents = {{3860, 3}}},
            {215, "Mithril Casing", "3 Mithril Bar",
             spell = 12599, reagents = {{3860, 3}}},
            {235, "Hi-Explosive Bomb", "2 Mithril Casing + 1 Unstable Trigger + 2 Solid Blasting Powder (makes 4)",
             spell = 12619, reagents = {{10561, 2}, {10560, 1}, {10505, 2}}, makes = 4},
            {245, "Mithril Gyro-Shot", "2 Mithril Bar + 2 Solid Blasting Powder (makes 200)",
             spell = 12621, reagents = {{3860, 2}, {10505, 2}}, makes = 200},
            {250, "Dense Blasting Powder", "2 Dense Stone",
             spell = 19788, reagents = {{12365, 2}}},
            {255, "Dense Dynamite", "2 Dense Blasting Powder + 3 Runecloth (makes 2)",
             spell = 23070, reagents = {{15992, 2}, {14047, 3}}, makes = 2},
            {260, "Thorium Widget", "3 Thorium Bar + 1 Runecloth",
             spell = 19791, reagents = {{12359, 3}, {14047, 1}}, source = {A = "Schematic (about 1g 20s, limited stock): Gearcutter Cogspinner - Ironforge",
                       H = "Schematic (about 1g 20s, limited stock): Sovik - Orgrimmar"}},
            {290, "Thorium Tube", "6 Thorium Bar",
             spell = 19795, reagents = {{12359, 6}}, source = "Schematic: Kor'gar - Powderfuse Port, Riverglades (boat from Steamwheedle Port), or Xizzer Fizzbolt - Everlook (limited stock)"}
        },
        notes = {
            {1, "Pairs best with Mining"},
            {150, {A = "Expert rank: Springspindle Fizzlegear - Tinker Town, Ironforge", H = "Expert rank: Roxxik - Valley of Honor, Orgrimmar"},
             req = 125, gate = 150, clients = ERA},
            {200, "At 200 (level 30+): choose Gnomish or Goblin specialization - an Engineering trainer has the quest"},
            {225, "Artisan trainer: Buzzek Bracketswing - Gadgetzan, Tanaris", req = 200, gate = 225, clients = ERA}
        },
        foreverNotes = {
            {1, "Pairs best with Mining"},
            {30, "Most Engineering parts are made at an anvil with a Blacksmith Hammer (trade supplies vendors) - keep your Arclight Spanner too"},
            {200, "At 200 (level 30+): choose Gnomish or Goblin specialization - an Engineering trainer has the quest"},
            {225, "Artisan trainer: Buzzek Bracketswing - Gadgetzan, Tanaris; or Kaylaena Springwhisper - Mount Hyjal", req = 200, gate = 225}
        }
    },
    ["Leatherworking"] = {
        primary = true,
        route = {
            {1, "Light Armor Kit", "1 Light Leather",
             spell = 2152, reagents = {{2318, 1}}},
            {20, "Handstitched Leather Boots", "2 Light Leather + 1 Coarse Thread",
             spell = 2149, reagents = {{2318, 2}, {2320, 1}}},
            {55, "Embossed Leather Gloves", "3 Light Leather + 2 Coarse Thread",
             spell = 3756, reagents = {{2318, 3}, {2320, 2}}},
            {85, "Fine Leather Belt", "6 Light Leather + 2 Coarse Thread",
             spell = 3763, reagents = {{2318, 6}, {2320, 2}}},
            {100, "Dark Leather Boots", "4 Medium Leather + 2 Fine Thread + 1 Gray Dye",
             spell = 2167, reagents = {{2319, 4}, {2321, 2}, {4340, 1}}},
            {125, "Dark Leather Belt", "1 Fine Leather Belt + 1 Cured Medium Hide + 2 Fine Thread + 1 Gray Dye",
             spell = 3766, reagents = {{4246, 1}, {4233, 1}, {2321, 2}, {4340, 1}}},
            {150, "Heavy Armor Kit", "5 Heavy Leather + 1 Fine Thread",
             spell = 3780, reagents = {{4234, 5}, {2321, 1}}},
            {175, "Barbaric Shoulders", "8 Heavy Leather + 1 Cured Heavy Hide + 2 Fine Thread",
             spell = 7151, reagents = {{4234, 8}, {4236, 1}, {2321, 2}}, tbcSource = "", source = {A = "Expert trainer: Telonis - Darnassus, or Drakk Stonehand - Aerie Peak (Hinterlands)",
                       H = "Expert trainer: Una - Thunder Bluff, or Hahrana Ironhide - Camp Mojache (Feralas)"}},
            {205, "Nightscape Headband", "5 Thick Leather + 2 Silken Thread",
             spell = 10507, reagents = {{4304, 5}, {4291, 2}}, tbcSource = "", source = {A = "Expert trainer: Telonis - Darnassus, or Drakk Stonehand - Aerie Peak (Hinterlands)",
                       H = "Expert trainer: Una - Thunder Bluff, or Hahrana Ironhide - Camp Mojache (Feralas)"}},
            {235, "Nightscape Pants", "14 Thick Leather + 4 Silken Thread",
             spell = 10548, reagents = {{4304, 14}, {4291, 4}}, tbcSource = "", source = {A = "Artisan trainer: Drakk Stonehand - Aerie Peak, The Hinterlands",
                       H = "Artisan trainer: Hahrana Ironhide - Camp Mojache, Feralas"}},
            {250, "Rugged Armor Kit", "5 Rugged Leather",
             spell = 19058, reagents = {{8170, 5}}, tbcSource = "", source = {A = "Artisan trainer: Drakk Stonehand - Aerie Peak, The Hinterlands",
                       H = "Artisan trainer: Hahrana Ironhide - Camp Mojache, Feralas"}},
            {265, "Wicked Leather Bracers / Wicked Leather Gauntlets", "8 Rugged Leather + 1 Black Dye + 1 Rune Thread",
             spell = {19052, 19049}, reagents = {{{8170, 8}, {2325, 1}, {14341, 1}}, {{8170, 8}, {2325, 1}, {14341, 1}}}, tbcSource = "", source = {A = "Gauntlets pattern (limited stock): Leonard Porter - Chillwind Camp, Western Plaguelands",
                       H = "Gauntlets pattern (limited stock): Werg Thickblade - The Bulwark, Tirisfal Glades"}},
            {285, "Wicked Leather Headband / Wicked Leather Gauntlets", "12 Rugged Leather + 1 Black Dye + 1 Rune Thread / 8 Rugged Leather + 1 Black Dye + 1 Rune Thread",
             spell = {19071, 19049}, reagents = {{{8170, 12}, {2325, 1}, {14341, 1}}, {{8170, 8}, {2325, 1}, {14341, 1}}}, tbcSource = "", source = "Headband pattern: drops from Jadefire satyrs in Felwood, or the Auction House - or keep making the Gauntlets"},
            {290, "Wicked Leather Headband / Runic Leather Headband", "12 Rugged Leather + 1 Black Dye + 1 Rune Thread / 14 Rugged Leather + 10 Runecloth + 1 Rune Thread",
             spell = {19071, 19082}, reagents = {{{8170, 12}, {2325, 1}, {14341, 1}}, {{8170, 14}, {14047, 10}, {14341, 1}}}, tbcSource = "", source = "Runic Leather Headband pattern (limited stock): Jase Farlane - Light's Hope Chapel"}
        },
        foreverRoute = {
            {1, "Light Armor Kit", "1 Light Leather",
             spell = 2152, reagents = {{2318, 1}}},
            {20, "Handstitched Leather Boots", "2 Light Leather + 1 Coarse Thread",
             spell = 2149, reagents = {{2318, 2}, {2320, 1}}},
            {55, "Embossed Leather Gloves", "3 Light Leather + 2 Coarse Thread",
             spell = 3756, reagents = {{2318, 3}, {2320, 2}}},
            {85, "Fine Leather Belt", "6 Light Leather + 2 Coarse Thread",
             spell = 3763, reagents = {{2318, 6}, {2320, 2}}},
            {100, "Dark Leather Cloak", "8 Medium Leather + 1 Fine Thread + 1 Gray Dye",
             spell = 2168, reagents = {{2319, 8}, {2321, 1}, {4340, 1}}},
            {115, "Dark Leather Belt", "1 Fine Leather Belt + 1 Cured Medium Hide + 2 Fine Thread + 1 Gray Dye",
             spell = 3766, reagents = {{4246, 1}, {4233, 1}, {2321, 2}, {4340, 1}}},
            {137, "Heavy Armor Kit", "5 Heavy Leather + 1 Fine Thread",
             spell = 3780, reagents = {{4234, 5}, {2321, 1}}},
            {155, "Barbaric Shoulders", "8 Heavy Leather + 1 Cured Heavy Hide + 2 Fine Thread",
             spell = 7151, reagents = {{4234, 8}, {4236, 1}, {2321, 2}}, source = {A = "Expert trainer: Telonis - Darnassus, or Drakk Stonehand - Aerie Peak (Hinterlands)",
                       H = "Expert trainer: Una - Thunder Bluff, or Hahrana Ironhide - Camp Mojache (Feralas)"}},
            {180, "Guardian Gloves", "4 Heavy Leather + 1 Cured Heavy Hide + 1 Silken Thread",
             spell = 7156, reagents = {{4234, 4}, {4236, 1}, {4291, 1}}, source = {A = "Expert trainer: Telonis - Darnassus, or Drakk Stonehand - Aerie Peak (Hinterlands)",
                       H = "Expert trainer: Una - Thunder Bluff, or Hahrana Ironhide - Camp Mojache (Feralas)"}},
            {195, "Nightscape Headband", "5 Thick Leather + 2 Silken Thread",
             spell = 10507, reagents = {{4304, 5}, {4291, 2}}, source = {A = "Expert trainer: Telonis - Darnassus, or Drakk Stonehand - Aerie Peak (Hinterlands)",
                       H = "Expert trainer: Una - Thunder Bluff, or Hahrana Ironhide - Camp Mojache (Feralas)"}},
            {210, "Thick Leather Ammo Pouch", "10 Thick Leather + 1 Cured Thick Hide + 1 Elixir of Defense + 6 Silken Thread",
             spell = 14932, reagents = {{4304, 10}, {8172, 1}, {8951, 1}, {4291, 6}}, source = {A = "Expert trainer: Telonis - Darnassus, or Drakk Stonehand - Aerie Peak (Hinterlands)",
                       H = "Expert trainer: Una - Thunder Bluff, or Hahrana Ironhide - Camp Mojache (Feralas)"}},
            {235, "Wicked Leather Gauntlets", "8 Rugged Leather + 1 Black Dye + 1 Rune Thread",
             spell = 19049, reagents = {{8170, 8}, {2325, 1}, {14341, 1}}, source = {A = "Pattern (1g 20s, limited stock): Leonard Porter - Chillwind Camp, Western Plaguelands",
                       H = "Pattern (1g 20s, limited stock): Werg Thickblade - The Bulwark, Tirisfal Glades"}},
            {265, "Runic Leather Headband", "14 Rugged Leather + 10 Runecloth + 1 Rune Thread",
             spell = 19082, reagents = {{8170, 14}, {14047, 10}, {14341, 1}}, source = "Pattern (about 2g 30s, limited stock): Jase Farlane - Light's Hope Chapel, Eastern Plaguelands"}
        },
        notes = {
            {1, "Pairs best with Skinning"},
            {150, {A = "Expert rank: Telonis - Darnassus, or Drakk Stonehand - Aerie Peak (Hinterlands)",
                   H = "Expert rank: Una - Thunder Bluff, or Hahrana Ironhide - Camp Mojache (Feralas)"},
             req = 125, gate = 150, clients = ERA},
            {225, {A = "Artisan trainer: Drakk Stonehand - Aerie Peak, The Hinterlands",
                   H = "Artisan trainer: Hahrana Ironhide - Camp Mojache, Feralas"},
             req = 200, gate = 225, clients = ERA}
        },
        foreverNotes = {
            {1, "Pairs best with Skinning"},
            {150, {A = "Expert rank: Telonis - Darnassus, or Drakk Stonehand - Aerie Peak, The Hinterlands",
                   H = "Expert rank: Una - Thunder Bluff, or Hahrana Ironhide - Camp Mojache, Feralas"},
             req = 125, gate = 150},
            {225, {A = "Artisan trainer: Drakk Stonehand - Aerie Peak, The Hinterlands",
                   H = "Artisan trainer: Hahrana Ironhide - Camp Mojache, Feralas"},
             req = 200, gate = 225}
        }
    },
    ["Tailoring"] = {
        primary = true,
        route = {
            {1, "Bolt of Linen Cloth", "2 Linen Cloth",
             spell = 2963, reagents = {{2589, 2}}},
            {37, "Linen Belt", "1 Bolt of Linen Cloth + 1 Coarse Thread",
             spell = 8776, reagents = {{2996, 1}, {2320, 1}}},
            {45, "Linen Bag", "3 Bolt of Linen Cloth + 3 Coarse Thread",
             spell = 3755, reagents = {{2996, 3}, {2320, 3}}},
            {70, "Reinforced Linen Cape", "2 Bolt of Linen Cloth + 3 Coarse Thread",
             spell = 2397, reagents = {{2996, 2}, {2320, 3}}},
            {75, "Bolt of Woolen Cloth", "3 Wool Cloth",
             spell = 2964, reagents = {{2592, 3}}},
            {100, "Gray Woolen Shirt", "2 Bolt of Woolen Cloth + 1 Fine Thread + 1 Gray Dye",
             spell = 2406, reagents = {{2997, 2}, {2321, 1}, {4340, 1}}},
            {110, "Double-stitched Woolen Shoulders", "3 Bolt of Woolen Cloth + 2 Fine Thread",
             spell = 3848, reagents = {{2997, 3}, {2321, 2}}},
            {125, "Bolt of Silk Cloth", "4 Silk Cloth",
             spell = 3839, reagents = {{4306, 4}}},
            {145, "Azure Silk Hood", "2 Bolt of Silk Cloth + 2 Blue Dye + 1 Fine Thread",
             spell = 8760, reagents = {{4305, 2}, {6260, 2}, {2321, 1}}},
            {160, "Silk Headband", "3 Bolt of Silk Cloth + 2 Fine Thread",
             spell = 8762, reagents = {{4305, 3}, {2321, 2}}},
            {175, "Bolt of Mageweave", "5 Mageweave Cloth",
             spell = 3865, reagents = {{4338, 5}}},
            {185, "Crimson Silk Vest", "4 Bolt of Silk Cloth + 2 Red Dye + 2 Fine Thread",
             spell = 8791, reagents = {{4305, 4}, {2604, 2}, {2321, 2}}},
            {205, "Black Mageweave Leggings", "2 Bolt of Mageweave + 3 Silken Thread",
             spell = 12049, reagents = {{4339, 2}, {4291, 3}}},
            {215, "Black Mageweave Gloves", "2 Bolt of Mageweave + 2 Heavy Silken Thread",
             spell = 12053, reagents = {{4339, 2}, {8343, 2}}},
            {230, "Black Mageweave Headband / Black Mageweave Shoulders", "3 Bolt of Mageweave + 2 Heavy Silken Thread",
             spell = {12072, 12074}, reagents = {{{4339, 3}, {8343, 2}}, {{4339, 3}, {8343, 2}}}},
            {250, "Bolt of Runecloth", "5 Runecloth",
             spell = 18401, reagents = {{14047, 5}}},
            {255, "Runecloth Belt", "3 Bolt of Runecloth + 1 Rune Thread",
             spell = 18402, reagents = {{14048, 3}, {14341, 1}}},
            {285, "Runecloth Gloves", "4 Bolt of Runecloth + 4 Rugged Leather + 1 Rune Thread",
             spell = 18417, reagents = {{14048, 4}, {8170, 4}, {14341, 1}}, tbcSource = "", source = "Pattern (limited stock): Qia - Everlook, Winterspring; without it, Runecloth Belt (green)"}
        },
        foreverRoute = {
            -- Forever's ranges are 20-45 below Classic's: Linen Bag greys at 65
            {1, "Bolt of Linen Cloth", "2 Linen Cloth",
             spell = 2963, reagents = {{2589, 2}}},
            {37, "Linen Belt", "1 Bolt of Linen Cloth + 1 Coarse Thread",
             spell = 8776, reagents = {{2996, 1}, {2320, 1}}},
            {55, "Bolt of Woolen Cloth", "3 Wool Cloth",
             spell = 2964, reagents = {{2592, 3}}},
            {70, "Woolen Cape", "1 Bolt of Woolen Cloth + 1 Fine Thread",
             spell = 2402, reagents = {{2997, 1}, {2321, 1}}},
            {100, "Bolt of Silk Cloth", "4 Silk Cloth",
             spell = 3839, reagents = {{4306, 4}}},
            {110, "Double-Stitched Woolen Shoulders", "3 Bolt of Woolen Cloth + 2 Fine Thread",
             spell = 3848, reagents = {{2997, 3}, {2321, 2}}},
            {120, "Azure Silk Hood", "2 Bolt of Silk Cloth + 2 Blue Dye + 1 Fine Thread",
             spell = 8760, reagents = {{4305, 2}, {6260, 2}, {2321, 1}}},
            {135, "Formal White Shirt", "3 Bolt of Silk Cloth + 2 Bleach + 1 Fine Thread",
             spell = 3871, reagents = {{4305, 3}, {2324, 2}, {2321, 1}}},
            {150, "Crimson Silk Vest", "4 Bolt of Silk Cloth + 2 Red Dye + 2 Fine Thread",
             spell = 8791, reagents = {{4305, 4}, {2604, 2}, {2321, 2}}},
            {170, "Black Mageweave Leggings / Black Mageweave Vest", "2 Bolt of Mageweave + 3 Silken Thread",
             spell = {12049, 12048}, reagents = {{{4339, 2}, {4291, 3}}, {{4339, 2}, {4291, 3}}}},
            {185, "Black Mageweave Gloves", "2 Bolt of Mageweave + 2 Heavy Silken Thread",
             spell = 12053, reagents = {{4339, 2}, {8343, 2}}},
            {210, "Mageweave Bag", "4 Bolt of Mageweave + 2 Silken Thread",
             spell = 12065, reagents = {{4339, 4}, {4291, 2}}},
            {220, "Runecloth Cloak", "4 Bolt of Runecloth + 1 Ironweb Spider Silk + 1 Rune Thread",
             spell = 18409, reagents = {{14048, 4}, {14227, 1}, {14341, 1}}, source = "Pattern (1g 20s, limited stock): Darnall - Nighthaven, Moonglade"},
            {230, "Runecloth Gloves", "4 Bolt of Runecloth + 4 Rugged Leather + 1 Rune Thread",
             spell = 18417, reagents = {{14048, 4}, {8170, 4}, {14341, 1}}, source = "Pattern (1g 68s, limited stock): Qia - Everlook, Winterspring"},
            {250, "Runecloth Boots", "4 Bolt of Runecloth + 2 Ironweb Spider Silk + 4 Rugged Leather + 1 Rune Thread",
             spell = 18423, reagents = {{14048, 4}, {14227, 2}, {8170, 4}, {14341, 1}}, source = "Pattern (2g, limited stock): Darnall - Nighthaven, Moonglade"},
            {265, "Runecloth Shoulders / Runecloth Headband", "7 Bolt of Runecloth + 2 Ironweb Spider Silk + 4 Rugged Leather + 1 Rune Thread / 4 Bolt of Runecloth + 2 Ironweb Spider Silk + 1 Rune Thread",
             spell = {18449, 18444}, reagents = {{{14048, 7}, {14227, 2}, {8170, 4}, {14341, 1}}, {{14048, 4}, {14227, 2}, {14341, 1}}}, source = "Patterns: rare drops (Molten Core, Blackrock Spire, Stratholme, Thorium Lockboxes) - check the Auction House"}
        },
        notes = {
            {150, {A = "Expert rank: Georgio Bolero - Mage Quarter, Stormwind", H = "Expert rank: Josef Gregorian - Undercity"},
             req = 125, gate = 150, clients = ERA},
            {225, {A = "Artisan trainer: Timothy Worthington - Theramore Isle, Dustwallow Marsh",
                   H = "Artisan trainer: Daryl Stack - Tarren Mill, Hillsbrad Foothills"},
             req = 200, gate = 225, clients = ERA}
        },
        foreverNotes = {
            {210, "Bolt of Runecloth: the Artisan trainer teaches it (likely about 205, not confirmed on Forever yet) - buy bolts if it won't yet"},
            {225, {A = "Artisan trainer: Timothy Worthington - Theramore Isle, Dustwallow Marsh",
                   H = "Artisan trainer: Daryl Stack - Tarren Mill, Hillsbrad Foothills"},
             req = 200, gate = 225},
            {255, "From 265 the patterns are scarce: Runecloth Shoulders (rare drop) lasts to 299; Runecloth Headband (drop) and Runecloth Cuffs (Pexmit, a rare vendor in Mount Hyjal) are yellow to 279"}
        }
    },
    ["Enchanting"] = {
        primary = true,
        route = {
            {1, "Runed Copper Rod", "1 Copper Rod + 1 Strange Dust + 1 Lesser Magic Essence",
             spell = 7421, reagents = {{6217, 1}, {10940, 1}, {10938, 1}}},
            {2, "Enchant Bracer - Minor Health", "1 Strange Dust",
             spell = 7418, reagents = {{10940, 1}}},
            {70, "Enchant Bracer - Minor Stamina", "3 Strange Dust",
             spell = 7457, reagents = {{10940, 3}}},
            {110, "Runed Silver Rod", "1 Silver Rod + 6 Strange Dust + 3 Greater Magic Essence + 1 Shadowgem",
             tbcMats = "1 Silver Rod + 6 Strange Dust + 3 Greater Magic Essence + 1 Runed Copper Rod", spell = 7795, reagents = {{6338, 1}, {10940, 6}, {10939, 3}, {1210, 1}}, tbcReagents = {{6338, 1}, {10940, 6}, {10939, 3}, {6218, 1}}},
            {111, "Enchant Shield - Minor Stamina", "1 Lesser Astral Essence + 2 Strange Dust",
             spell = 13378, reagents = {{10998, 1}, {10940, 2}}},
            {130, "Enchant Bracer - Lesser Stamina", "2 Soul Dust",
             spell = 13501, reagents = {{11083, 2}}},
            {165, "Runed Golden Rod", "1 Golden Rod + 1 Iridescent Pearl + 2 Greater Astral Essence + 2 Soul Dust",
             tbcMats = "1 Golden Rod + 1 Iridescent Pearl + 2 Greater Astral Essence + 2 Soul Dust + 1 Runed Silver Rod", spell = 13628, reagents = {{11128, 1}, {5500, 1}, {11082, 2}, {11083, 2}}, tbcReagents = {{11128, 1}, {5500, 1}, {11082, 2}, {11083, 2}, {6339, 1}}},
            {166, "Enchant Bracer - Spirit", "1 Lesser Mystic Essence",
             spell = 13642, reagents = {{11134, 1}}},
            {180, "Enchant Bracer - Strength", "1 Vision Dust",
             spell = 13661, reagents = {{11137, 1}}},
            {205, "Runed Truesilver Rod", "1 Truesilver Rod + 1 Black Pearl + 2 Greater Mystic Essence + 2 Vision Dust",
             tbcMats = "1 Truesilver Rod + 1 Black Pearl + 2 Greater Mystic Essence + 2 Vision Dust + 1 Runed Golden Rod", spell = 13702, reagents = {{11144, 1}, {7971, 1}, {11135, 2}, {11137, 2}}, tbcReagents = {{11144, 1}, {7971, 1}, {11135, 2}, {11137, 2}, {11130, 1}}},
            {206, "Enchant Cloak - Greater Defense", "3 Vision Dust",
             spell = 13746, reagents = {{11137, 3}}},
            {240, "Enchant Bracer - Greater Strength", "2 Dream Dust + 1 Greater Nether Essence",
             spell = 13939, reagents = {{11176, 2}, {11175, 1}}},
            {285, "Enchant Cloak - Superior Defense / Enchant Shield - Greater Stamina", "8 Illusion Dust / 10 Dream Dust",
             spell = {20015, 20017}, reagents = {{{16204, 8}}, {{11176, 10}}}, source = {A = "Formulas (limited stock): cloak - Lorelae Wintersong, Nighthaven, Moonglade; shield - Mythrin'dir, Darnassus",
                       H = "Formulas (limited stock): cloak - Lorelae Wintersong, Nighthaven, Moonglade; shield - Daniel Bartlett, Undercity"}}
        },
        foreverRoute = {
            -- Forever renamed Minor Health "Inferior Stamina" (greys at 25)
            {1, "Runed Copper Rod", "1 Copper Rod + 1 Mote of Magic",
             spell = 7421, reagents = {{6217, 1}, {247786, 1}}},
            {2, "Enchant Bracer - Inferior Stamina", "1 Mote of Magic",
             spell = 7418, reagents = {{247786, 1}}},
            {22, "Enchant Chest - Inferior Stamina", "1 Strange Dust",
             spell = 7420, reagents = {{10940, 1}}},
            {70, "Enchant Bracer - Minor Stamina", "2 Strange Dust",
             spell = 7457, reagents = {{10940, 2}}},
            {100, "Runed Silver Rod", "1 Silver Rod + 3 Strange Dust + 4 Lesser Magic Essence + 1 Shadowgem",
             spell = 7795, reagents = {{6338, 1}, {10940, 3}, {10938, 4}, {1210, 1}}},
            {101, "Enchant Cloak - Minor Protection", "2 Strange Dust",
             spell = 7771, reagents = {{10940, 2}}},
            {130, "Enchant Bracer - Lesser Stamina", "1 Soul Dust",
             spell = 13501, reagents = {{11083, 1}}},
            {160, "Runed Golden Rod", "1 Golden Rod + 1 Iridescent Pearl + 1 Greater Astral Essence + 1 Soul Dust",
             spell = 13628, reagents = {{11128, 1}, {5500, 1}, {11082, 1}, {11083, 1}}},
            {161, "Enchant Boots - Lesser Agility", "1 Soul Dust",
             spell = 13637, reagents = {{11083, 1}}},
            {180, "Enchant Bracer - Strength", "1 Vision Dust",
             spell = 13661, reagents = {{11137, 1}}},
            {205, "Runed Truesilver Rod", "1 Truesilver Rod + 1 Black Pearl + 1 Greater Mystic Essence + 1 Vision Dust",
             spell = 13702, reagents = {{11144, 1}, {7971, 1}, {11135, 1}, {11137, 1}}},
            {206, "Enchant Cloak - Greater Defense", "1 Vision Dust",
             spell = 13746, reagents = {{11137, 1}}},
            {245, "Enchant Bracer - Greater Strength", "1 Dream Dust + 2 Lesser Nether Essence",
             spell = 13939, reagents = {{11176, 1}, {11174, 2}}},
            {285, "Enchant Cloak - Superior Defense / Enchant Shield - Greater Stamina", "8 Illusion Dust / 6 Dream Dust",
             spell = {20015, 20017}, reagents = {{{16204, 8}}, {{11176, 6}}}, source = {A = "Formulas (limited stock): cloak - Lorelae Wintersong, Nighthaven, Moonglade; shield - Mythrin'dir, Darnassus",
                       H = "Formulas (limited stock): cloak - Lorelae Wintersong, Nighthaven, Moonglade; shield - Daniel Bartlett, Undercity"}}
        },
        notes = {
            {1, "Disenchant unneeded greens for dusts/essences"},
            {150, {A = "Expert rank: Kitta Firewind - Tower of Azora, Elwynn Forest", H = "Expert rank: Hgarth - Sun Rock Retreat, Stonetalon Mountains"},
             req = 125, gate = 150, clients = ERA},
            {225, "Artisan trainer: Annora, Uldaman (inside the dungeon)", req = 200, gate = 225, clients = ERA}
        },
        foreverNotes = {
            {1, "Disenchant unneeded greens for dusts/essences"},
            {1, "Mote of Magic: make them from Strange Dust (the Mote of Magic recipe)"},
            {225, "Artisan trainer: Annora, Uldaman (inside the dungeon)", req = 200, gate = 225}
        }
    },
    ["Cooking"] = {
        route = {
            {1, "Charred Wolf Meat", "1 Stringy Wolf Meat",
             spell = 2538, reagents = {{2672, 1}}, source = "Learned with Apprentice Cooking at any Cooking trainer"},
            {40, "Smoked Bear Meat", "1 Bear Meat",
             spell = 8607, reagents = {{3173, 1}}, source = {A = "Recipe: Drac Roughcut - Thelsamar, Loch Modan",
                       H = "Recipe: Andrew Hilbert - The Sepulcher, Silverpine Forest"}},
            {80, "Crab Cake / Dry Pork Ribs", "1 Crawler Meat + 1 Mild Spices / 1 Boar Ribs + 1 Mild Spices",
             spell = {2544, 2546}, reagents = {{{2674, 1}, {2678, 1}}, {{2677, 1}, {2678, 1}}}, source = "Cooking trainer (Crab Cake at 75, Dry Pork Ribs at 80)"},
            {125, "Goblin Deviled Clams", "1 Tangy Clam Meat + 1 Hot Spices",
             spell = 6500, reagents = {{5504, 1}, {2692, 1}}, source = "Cooking trainer (125, 3s)"},
            {175, "Roast Raptor", "1 Raptor Flesh + 1 Hot Spices",
             spell = 15855, reagents = {{12184, 1}, {2692, 1}}, source = {A = "Recipe (50s): Corporal Bluth - Rebel Camp, Stranglethorn; Hammon Karwn - Refuge Pointe, Arathi; Helenia Olden - Theramore",
                       H = "Recipe (50s): Nerrist - Grom'gol, Stranglethorn; Keena - Hammerfall, Arathi; Ogg'marr - Brackenwall, Dustwallow Marsh"}},
            {200, "Spider Sausage", "2 White Spider Meat",
             spell = 21175, reagents = {{12205, 2}}, source = "Cooking trainer (200, 40s)"},
            {225, "Monster Omelet", "1 Giant Egg + 2 Soothing Spices",
             spell = 15933, reagents = {{12207, 1}, {3713, 2}}, source = {A = "Recipe (1g 20s): Himmik - Everlook, Winterspring; or Malygen - Talonbranch Glade, Felwood",
                       H = "Recipe (1g 20s): Himmik - Everlook, Winterspring; or Bale - Bloodvenom Post, Felwood"}},
            {250, "Tender Wolf Steak", "1 Tender Wolf Meat + 1 Soothing Spices",
             spell = 22480, reagents = {{12208, 1}, {3713, 1}}, source = {A = "Recipe (1g 20s): Dirge Quikcleave - Gadgetzan, Tanaris; or Truk Wildbeard - Aerie Peak, Hinterlands",
                       H = "Recipe (1g 20s): Dirge Quikcleave - Gadgetzan, Tanaris"}},
            {262, "Nightfin Soup / Poached Sunscale Salmon / Tender Wolf Steak", "1 Raw Nightfin Snapper + 1 Refreshing Spring Water / 1 Raw Sunscale Salmon / 1 Tender Wolf Meat + 1 Soothing Spices",
             spell = {18243, 18244, 22480}, reagents = {{{13759, 1}, {159, 1}}, {{13760, 1}}, {{12208, 1}, {3713, 1}}}, source = "Fish recipes (2g each): Gikkix - Steamwheedle Port, Tanaris. On Era, Tender Wolf Steak still skills up here"},
            {285, "Smoked Desert Dumplings", "1 Sandworm Meat + 1 Soothing Spices",
             spell = 24801, reagents = {{20424, 1}, {3713, 1}}, source = "Quest 'Sharing the Knowledge' (level 54): the Sandy Cookbook in Silithus, back to Calandrath at Cenarion Hold"}
        },
        foreverRoute = {
            {1, "Charred Wolf Meat / Roasted Boar Meat", "1 Stringy Wolf Meat / 1 Chunk of Boar Meat",
             spell = {2538, 2540}, reagents = {{{2672, 1}}, {{769, 1}}}, source = "Learned automatically with Apprentice Cook at any Cooking trainer (1s)"},
            {40, "Spiced Wolf Meat", "1 Stringy Wolf Meat + 1 Mild Spices",
             spell = 2539, reagents = {{2672, 1}, {2678, 1}}, source = "Cooking trainer, from skill 10 (50c)"},
            {50, "Coyote Steak / Boiled Clams", "1 Coyote Meat / 1 Clam Meat + 1 Refreshing Spring Water",
             spell = {2541, 6499}, reagents = {{{2673, 1}}, {{5503, 1}, {159, 1}}}, source = "Cooking trainer, from skill 50 (1s each); train Journeyman Cook there too (5s)"},
            {80, "Crab Cake / Dry Pork Ribs", "1 Crawler Meat + 1 Mild Spices / 1 Boar Ribs + 1 Mild Spices",
             spell = {2544, 2546}, reagents = {{{2674, 1}, {2678, 1}}, {{2677, 1}, {2678, 1}}}, source = "Cooking trainer: Crab Cake from skill 75 (2s), Dry Pork Ribs from skill 80 (1s 50c)"},
            {125, "Goblin Deviled Clams", "1 Tangy Clam Meat + 1 Hot Spices",
             spell = 6500, reagents = {{5504, 1}, {2692, 1}}, source = "Cooking trainer, from skill 125 (3s)"},
            {175, "Roast Raptor", "1 Raptor Flesh + 1 Hot Spices",
             spell = 15855, reagents = {{12184, 1}, {2692, 1}}, source = {A = "Recipe (50s): Corporal Bluth - Rebel Camp, Stranglethorn; Hammon Karwn - Refuge Pointe, Arathi; Helenia Olden - Theramore",
                       H = "Recipe (50s): Nerrist - Grom'gol, Stranglethorn; Keena - Hammerfall, Arathi; Ogg'marr - Brackenwall, Dustwallow Marsh"}},
            {200, "Spider Sausage", "2 White Spider Meat",
             spell = 21175, reagents = {{12205, 2}}, source = "Cooking trainer, from skill 200 (40s)"},
            {225, "Monster Omelet", "1 Giant Egg + 2 Soothing Spices",
             spell = 15933, reagents = {{12207, 1}, {3713, 2}}, source = {A = "Recipe (1g 20s): Himmik - Everlook, Winterspring; or Malygen - Talonbranch Glade, Felwood",
                       H = "Recipe (1g 20s): Himmik - Everlook, Winterspring; or Bale - Bloodvenom Post, Felwood"}},
            {250, "Tender Wolf Steak", "1 Tender Wolf Meat + 1 Soothing Spices",
             spell = 22480, reagents = {{12208, 1}, {3713, 1}}, source = {A = "Recipe (1g 20s): Dirge Quikcleave - Gadgetzan, Tanaris; or Truk Wildbeard - Aerie Peak, Hinterlands",
                       H = "Recipe (1g 20s): Dirge Quikcleave - Gadgetzan, Tanaris"}},
            {285, "Nightfin Soup", "1 Raw Nightfin Snapper + 1 Refreshing Spring Water",
             spell = 18243, reagents = {{13759, 1}, {159, 1}}, source = "Recipe (1g 80s): Gikkix - Steamwheedle Port, Tanaris"}
        },
        notes = {
            {150, {A = "Expert rank: buy |cFFFFCC00Expert Cookbook|r from Shandrina - Ashenvale (49, 67)",
                   H = "Expert rank: buy |cFFFFCC00Expert Cookbook|r from Wulan - Shadowprey Village, Desolace (26, 70)"},
             req = 125, gate = 150, clients = BOOKS},
            {225, "Artisan rank: |cFFFFCC00Clamlette Surprise|r quest (level 35) - Dirge Quikcleave, Gadgetzan",
             req = 225, gate = 225, clients = BOOKS},
            {285, "Dumplings recipe: quest in Silithus (level 54)"},
            {300, {A = "Master rank (Outland): |cFFFFCC00Master Cookbook|r - Gaston, Honor Hold (Hellfire Peninsula), or Naka, Cenarion Refuge (Zangarmarsh)",
                   H = "Master rank (Outland): |cFFFFCC00Master Cookbook|r - Baxter, Thrallmar (Hellfire Peninsula), or Naka, Cenarion Refuge (Zangarmarsh)"},
             req = 290, gate = 300, clients = TBC}
        },
        foreverNotes = {
            {150, {A = "Expert rank: buy |cFFFFCC00Expert Cookbook|r from Shandrina - Ashenvale (49, 67)",
                   H = "Expert rank: buy |cFFFFCC00Expert Cookbook|r from Wulan - Shadowprey Village, Desolace (26, 70)"},
             req = 125, gate = 150},
            {225, "Artisan rank: |cFFFFCC00Clamlette Surprise|r quest (level 35) - Dirge Quikcleave, Gadgetzan",
             req = 225, gate = 225},
            {260, "Forever: Smoked Desert Dumplings, Baked Salmon and the other top dishes need an Iron Oven - this route sticks to campfire recipes"}
        }
    }
}

-- Fishing + Cooking combo: when both are tracked, Cooking levels off your
-- catches and Fishing tells you which fish (and waters) feed the next
-- Cooking bracket. {from-cooking-skill, cooked dish, fish, where-to-fish}
-- Fish dishes are NOT trainer-taught: each recipe is a scroll sold by
-- vendors (fishing suppliers stock the low ones).
-- Notable fishing waters per zone (inland vs coast), used to turn "inland
-- lakes & rivers" into "Lake Everstill" when we know the player's zone.
-- map = the zone's uiMapID on Classic Era, TBC and Forever (Core.lua finds
-- the player's zone by it in any language; Mists numbers maps otherwise)
ns.ZONE_WATERS = {
    ["Elwynn Forest"] = {map = 1429, minskill = 25, lvl = 5, inland = "Crystal Lake at Goldshire / Stone Cairn Lake"},
    ["Redridge Mountains"] = {map = 1433, minskill = 55, lvl = 20, inland = "Lake Everstill"},
    ["Duskwood"] = {map = 1431, minskill = 130, lvl = 25, inland = "the northern river"},
    ["Westfall"] = {map = 1436, minskill = 55, lvl = 15, coast = "Longshore (west coast)"},
    ["Loch Modan"] = {map = 1432, minskill = 55, lvl = 15, inland = "the Loch"},
    ["Wetlands"] = {map = 1437, minskill = 130, lvl = 25, coast = "the Baradin Bay coast", inland = "the inland pools"},
    ["Darkshore"] = {map = 1439, minskill = 55, lvl = 15, coast = "the Darkshore coastline"},
    ["Teldrassil"] = {map = 1438, minskill = 25, lvl = 5, inland = "the ponds near Dolanaar"},
    ["Ashenvale"] = {map = 1440, minskill = 130, lvl = 25, inland = "Mystral Lake / Falfarren River"},
    ["The Barrens"] = {map = 1413, minskill = 55, lvl = 15, inland = "the oases", coast = "the coast at Ratchet"},
    ["Durotar"] = {map = 1411, minskill = 25, lvl = 5, inland = "Southfury River", coast = "the Sen'jin coast"},
    ["Mulgore"] = {map = 1412, minskill = 25, lvl = 5, inland = "Stonebull Lake"},
    ["Tirisfal Glades"] = {map = 1420, minskill = 25, lvl = 5, inland = "Brightwater Lake"},
    ["Silverpine Forest"] = {map = 1421, minskill = 55, lvl = 15, inland = "Lordamere Lake"},
    ["Hillsbrad Foothills"] = {map = 1424, minskill = 130, lvl = 25, inland = "the streams", coast = "the western coast"},
    ["Arathi Highlands"] = {map = 1417, minskill = 205, lvl = 35, coast = "Faldir's Cove", inland = "the streams"},
    ["Stranglethorn Vale"] = {map = 1434, minskill = 205, lvl = 40, coast = "anywhere along the coast", inland = "Lake Nazferiti"},
    ["Swamp of Sorrows"] = {map = 1435, minskill = 205, lvl = 40, inland = "the swamp pools", coast = "the eastern coast"},
    ["Dustwallow Marsh"] = {map = 1445, minskill = 205, lvl = 40, coast = "the coast by Theramore", inland = "the marsh waters"},
    ["Desolace"] = {map = 1443, minskill = 205, lvl = 35, coast = "the western coast"},
    ["Tanaris"] = {map = 1446, minskill = 255, lvl = 45, coast = "the Steamwheedle Port coast"},
    ["Feralas"] = {map = 1444, minskill = 255, lvl = 45, coast = "the Feathermoon coast", inland = "the rivers"},
    ["The Hinterlands"] = {map = 1425, minskill = 255, lvl = 45, coast = "the eastern coast", inland = "the river"},
    ["Azshara"] = {map = 1447, minskill = 330, lvl = 50, coast = "the bays", inland = "the rivers"},
    ["Un'Goro Crater"] = {map = 1449, minskill = 330, lvl = 52, inland = "the pools"},
    ["Felwood"] = {map = 1448, minskill = 330, lvl = 50, inland = "the ponds and rivers"},
    ["Winterspring"] = {map = 1452, minskill = 330, lvl = 55, inland = "Lake Kel'Theril"},
    ["Western Plaguelands"] = {map = 1422, minskill = 330, lvl = 55, inland = "the lakes"},
    ["Moonglade"] = {map = 1450, minskill = 330, lvl = 55, inland = "Lake Elune'ara"},
    ["Stormwind City"] = {map = 1453, minskill = 55, lvl = 5, inland = "the canals"},
    ["Orgrimmar"] = {map = 1454, minskill = 55, lvl = 5, inland = "the Valley of Honor pond"},
    ["Ironforge"] = {map = 1455, lvl = 5, inland = "the Forlorn Cavern pool"}
}

-- spell = the dish's recipe and fishItem = the fish, so the game names
-- both in its own language; where = a sentence in Locales.lua, its %s the
-- whereZones, which the game names by map ID (ZONE_WATERS, ns.ZONE_MAPS)
-- zones named in the fishing advice that have no ZONE_WATERS entry
ns.ZONE_MAPS = {["Eastern Plaguelands"] = 1423, ["Deadwind Pass"] = 1430}

ns.FISH_COOKING = {
    {1, "Brilliant Smallfish", spell = 7751, fishItem = 6291, band = {1, 12}, fish = "Raw Brilliant Smallfish",
     where = "starting-zone lakes & rivers", water = "inland",
     recipe = {A = "Catherine Leland - Stormwind canals (by the fishing trainer)",
               H = "Harn Longcast - Bloodhoof Village, or Martine Tramblay - Tirisfal Glades (none in Orgrimmar)"}},
    {50, "Longjaw Mud Snapper", spell = 7753, fishItem = 6289, band = {1, 25}, fish = "Raw Longjaw Mud Snapper",
     where = "inland lakes & rivers", water = "inland",
     recipe = {A = "Tharynn Bouden - Goldshire, or Khara Deepwater - Loch Modan",
               H = "Harn Longcast - Bloodhoof Village, or Killian Sanatha - Silverpine Forest coast"}},
    {100, "Bristle Whisker Catfish", spell = 7755, fishItem = 6308, band = {12, 35}, fish = "Raw Bristle Whisker Catfish",
     where = "rivers in 10-30 zones", water = "inland",
     recipe = {A = "Catherine Leland - Stormwind canals, or Lindea Rabonne - Southshore",
               H = "Kilxx - Ratchet, or Derak Nightfall - Tarren Mill"}},
    {175, "Rockscale Cod", spell = 7828, fishItem = 6362, band = {30, 45}, fish = "Raw Rockscale Cod",
     where = "coasts of 30-45 zones (%s)", whereZones = {"Swamp of Sorrows", "Dustwallow Marsh", "Stranglethorn Vale", "Desolace"},
     water = "coast",
     recipe = {A = "Stuart Fleming - Menethil Harbor, or Kelsey Yance - Booty Bay",
               H = "Shankys - Orgrimmar, Valley of Honor, or Kelsey Yance - Booty Bay"}},
    {225, "Spotted Yellowtail", spell = 18238, fishItem = 4603, band = {28, 50}, fish = "Raw Spotted Yellowtail",
     where = "coasts of %s", whereZones = {"Stranglethorn Vale", "Tanaris"}, water = "coast",
     recipe = "Gikkix - Steamwheedle Port, Tanaris"},
    -- zones = where the fish is really caught (a zone's level alone also
    -- let in Stranglethorn, Dustwallow and the Swamp for Nightfin)
    {250, "Nightfin Soup", spell = 18243, fishItem = 13759, band = {40, 60}, fish = "Raw Nightfin Snapper",
     zones = {["Feralas"] = true, ["The Hinterlands"] = true, ["Felwood"] = true, ["Un'Goro Crater"] = true,
              ["Winterspring"] = true, ["Western Plaguelands"] = true, ["Moonglade"] = true},
     where = "high-level inland waters, at night", water = "inland",
     recipe = "Gikkix - Steamwheedle Port, Tanaris"},
    {285, "Baked Salmon", spell = 18247, fishItem = 13889, band = {55, 60}, fish = "Raw Whitescale Salmon", zones = {["Winterspring"] = true},
     where = "inland waters of %s", whereZones = {"Winterspring", "Eastern Plaguelands", "Deadwind Pass"}, water = "inland",
     recipe = {A = "Vivianna - Feathermoon Stronghold, Feralas",
               H = "Sheendra Tallgrass - Camp Mojache, Feralas"}}
}

ns.FISHING_NOTES = {
    {130, "Expert rank: book |cFFFFCC00Expert Fishing - The Bass and You|r - Old Man Heming, Booty Bay",
     req = 125, gate = 150, clients = BOOKS},
    {225, "Artisan rank: Nat Pagle quest (level 35) - Dustwallow Marsh",
     req = 225, gate = 225, clients = BOOKS},
    {275, "Master rank (Outland): book |cFFFFCC00Master Fishing - The Art of Angling|r (level 45) - Juno Dufrain, Cenarion Refuge (Zangarmarsh)",
     req = 275, gate = 300, clients = TBC}
}

-- Skill-line IDs (the same in every language and on every client)
ns.SKILL_LINES = {
    [186] = "Mining", [182] = "Herbalism", [393] = "Skinning", [356] = "Fishing",
    [129] = "First Aid", [171] = "Alchemy", [164] = "Blacksmithing", [202] = "Engineering",
    [165] = "Leatherworking", [197] = "Tailoring", [333] = "Enchanting", [185] = "Cooking"
}

-- Professions the tracker understands, by their English names (Core.lua
-- ns.ProfKey finds them on other clients)
ns.TRACKED = {
    ["Mining"] = "gather",
    ["Herbalism"] = "gather",
    ["Skinning"] = "skinning",
    ["Fishing"] = "fishing",
    ["First Aid"] = "craft",
    ["Alchemy"] = "craft",
    ["Blacksmithing"] = "craft",
    ["Engineering"] = "craft",
    ["Leatherworking"] = "craft",
    ["Tailoring"] = "craft",
    ["Enchanting"] = "craft",
    ["Cooking"] = "craft"
}

-- Apprentice trainers per faction: NPC, city, district. Capital-city guards
-- can pin any of these on the map, so districts beat raw coordinates.
ns.TRAINERS = {
    ["Alchemy"] = {
        A = "Lilyssia Nightbreeze - Stormwind, Mage Quarter (Alchemy Needs)",
        H = "Yelmak - Orgrimmar, The Drag"
    },
    ["Herbalism"] = {
        A = "Tannysa - Stormwind, Mage Quarter (by Alchemy Needs)",
        H = "Jandi - Orgrimmar, The Drag"
    },
    ["Mining"] = {
        A = "Gelman Stonehand - Stormwind, Dwarven District",
        H = "Makaru - Orgrimmar, Valley of Honor"
    },
    ["Blacksmithing"] = {
        A = "Therum Deepforge - Stormwind, Dwarven District",
        H = "Saru Steelfury - Orgrimmar, Valley of Honor"
    },
    ["Engineering"] = {
        A = "Lilliam Sparkspindle - Stormwind, Dwarven District",
        H = "Thund - Orgrimmar, Valley of Honor"
    },
    ["Leatherworking"] = {
        A = "Simon Tanner - Stormwind, Old Town",
        H = "Karolek - Orgrimmar, The Drag (Kodohide Leatherworkers)"
    },
    ["Skinning"] = {
        A = "Maris Granger - Stormwind, Old Town",
        H = "Thuwd - Orgrimmar, The Drag"
    },
    ["Tailoring"] = {
        A = "Georgio Bolero - Stormwind, Mage Quarter",
        H = "Magar - Orgrimmar, The Drag"
    },
    ["Enchanting"] = {
        A = "Lucan Cordell - Stormwind, Mage Quarter",
        H = "Godan - Orgrimmar, The Drag"
    },
    ["Cooking"] = {
        A = "Stephen Ryback - Stormwind, Old Town",
        H = "Zamja - Orgrimmar, The Drag"
    },
    ["First Aid"] = {
        A = "Shaina Fuller - Stormwind, Cathedral Square",
        H = "Arnok - Orgrimmar, Valley of Spirits"
    },
    ["Fishing"] = {
        A = "Arnold Leland - Stormwind, canal dock at the west corner of the Trade District",
        H = "Lumak - Orgrimmar, Valley of Honor"
    }
}

-- Starting-village trainers by race, shown while you're still low level -
-- much closer than the capital. Only entries we're confident about; other
-- professions fall back to the capital trainer above.
local goldshire = {
    ["Alchemy"] = "Alchemist Mallory - farmhouse north of Goldshire",
    ["Herbalism"] = "Herbalist Pomeroy - farmhouse north of Goldshire (with Alchemist Mallory)",
    ["Blacksmithing"] = "Smith Argus - Goldshire",
    ["Leatherworking"] = "Adele Fielder - camp by Crystal Lake, northeast of Goldshire",
    ["Skinning"] = "Helene Peltskinner - camp by Crystal Lake, northeast of Goldshire",
    ["Cooking"] = "Tomas - Lion's Pride Inn kitchen, Goldshire",
    ["First Aid"] = "Michelle Belle - Lion's Pride Inn, Goldshire",
    ["Fishing"] = "Lee Brown - Crystal Lake, Elwynn Forest"
}
local kharanos = {
    ["Blacksmithing"] = "Tognus Flintfire - Kharanos",
    ["Mining"] = "Yarr Hammerstone - Steelgrill's Depot, Kharanos",
    ["Engineering"] = "Bronk Guzzlegear - Steelgrill's Depot, Kharanos",
    ["First Aid"] = "Thamner Pol - Kharanos"
}
local dolanaar = {
    ["Alchemy"] = "Cyndra Kindwhisper - Dolanaar",
    ["Herbalism"] = "Malorne Bladeleaf - Dolanaar",
    ["Skinning"] = "Radnaal Maneweaver - hut west-northwest of Dolanaar",
    ["Leatherworking"] = "Nadyia Maneweaver - hut west-northwest of Dolanaar",
    ["Cooking"] = "Zarrin - Dolanaar",
    ["First Aid"] = "Byancie - Dolanaar"
}
local durotar = {
    ["Alchemy"] = "Miao'zan - Sen'jin Village",
    ["Herbalism"] = "Mishiki - Sen'jin Village",
    ["Mining"] = "Krunn - Razor Hill",
    ["Engineering"] = "Mukdrak - Razor Hill",
    ["First Aid"] = "Rawrk - Razor Hill",
    ["Fishing"] = "Lau'Tiki - Sen'jin Village coast"
}
local mulgore = {
    ["Leatherworking"] = "Chaw Stronghide - Bloodhoof Village",
    ["Skinning"] = "Yonn Deepcut - Bloodhoof Village",
    ["First Aid"] = "Vira Younghoof - Bloodhoof Village",
    ["Fishing"] = "Uthan Stillwater - Bloodhoof Village pond",
    ["Cooking"] = "Pyall Silentstride - Bloodhoof Village"
}
local tirisfal = {
    ["Alchemy"] = "Carolai Anise - Brill",
    ["Herbalism"] = "Faruza - Brill",
    ["Tailoring"] = "Bowen Brisboise - Cold Hearth Manor, west of Brill",
    ["Leatherworking"] = "Shelene Rhobart - farm southeast of Brill",
    ["Skinning"] = "Rand Rhobart - farm southeast of Brill",
    ["Enchanting"] = "Vance Undergloom - Brill",
    ["First Aid"] = "Nurse Neela - Brill",
    ["Fishing"] = "Clyde Kellen - Brill lake"
}

-- keyed by the race token from UnitRace (undead = "Scourge")
ns.VILLAGE_TRAINERS = {
    Human = goldshire,
    Dwarf = kharanos,
    Gnome = kharanos,
    NightElf = dolanaar,
    Orc = durotar,
    Troll = durotar,
    Tauren = mulgore,
    Scourge = tirisfal,
    -- WoW Forever's new race starts on Zephras Isle; Shen'dar Village has
    -- a trainer for every profession
    Skyborne = {
        ["Alchemy"] = "Nyassa Swiftdraught - Shen'dar Village, Zephras Isle",
        ["Blacksmithing"] = "Aedi Thriceforged - Shen'dar Village",
        ["Cooking"] = "Zerril Softbreeze - Shen'dar Village",
        ["Enchanting"] = "Nasalanna Windsinger - Shen'dar Village",
        ["Engineering"] = "Strange Hermit - Shadowgale Forest, east of Shen'dar Village",
        ["First Aid"] = "Naleeia Tattermend - Shen'dar Village",
        ["Fishing"] = "Fenn Fairweather - south edge of Shen'dar Village",
        ["Herbalism"] = "Halassa Fernbreeze - Shen'dar Village",
        ["Leatherworking"] = "Indari Sunseam - Shen'dar Village",
        ["Mining"] = "Messana Crestwind - Shen'dar Village",
        ["Skinning"] = "Mendalass Tattermend - Shen'dar Village",
        ["Tailoring"] = "Taleen Shimmerthread - Shen'dar Village"
    }
}

-- WoW Forever only: its starting areas gained "Junior" Mining, Herbalism
-- and Skinning trainers (Apprentice only) and two village trainers. They
-- fill the gaps above; an entry above is never replaced.
ns.FOREVER_VILLAGE = {
    Human = {["Mining"] = "Kelsey Fargo - Northshire Valley, north of the Abbey"},
    Dwarf = {["Herbalism"] = "Emrys Flintbeard - Anvilmar, Coldridge Valley",
             ["Skinning"] = "Brighid Stormflayer - Anvilmar, Coldridge Valley"},
    NightElf = {["Mining"] = "Fanorran Stilloak - Aldrassil, Shadowglen"},
    Orc = {["Skinning"] = "Kagil - Valley of Trials", ["Enchanting"] = "Pa'zula - Sen'jin Village"},
    Tauren = {["Herbalism"] = "Garan Sunstrider - Camp Narache", ["Mining"] = "Vartha Rockmane - Camp Narache"},
    Scourge = {["Mining"] = "Walter Mason - Deathknell", ["Cooking"] = "William Pickman - Brill"}
}

-- WoW Forever replaces these tables whole (Core.lua). Its top fish dish,
-- Baked Salmon, needs an Iron Oven there, so Nightfin Soup runs to 300.
ns.FOREVER = {
    FISH_COOKING = {ns.FISH_COOKING[1], ns.FISH_COOKING[2], ns.FISH_COOKING[3],
                    ns.FISH_COOKING[4], ns.FISH_COOKING[5], ns.FISH_COOKING[6]},
    FISHING_NOTES = {
        {130, "Expert rank: book |cFFFFCC00Expert Fishing - The Bass and You|r (needs level 20) - Old Man Heming, Booty Bay",
         req = 125, gate = 150},
        {225, "Artisan rank: Nat Pagle quest (level 35) - Dustwallow Marsh",
         req = 225, gate = 225}
    }
}

-- Materials the routes use that no route row makes, but a profession
-- does from what you gather: bars smelted from ore, the bolts Forever's
-- Tailoring route uses without a row for them, cured hides, grinding
-- stones and two Engineering parts. The item tooltips (Inventory.lua)
-- follow a route's reagent down to these, when the profession that makes
-- it is one you picked (no Mining picked: ore is not kept for bars).
-- Classic Era's counts; a route row that makes the same item wins.
--   {item, "English name", profession, {{reagent, count}, ...}, makes = n}
-- (Leather is not combined here: skinning gives the heavier leather, so
-- light leather kept for medium would mostly be kept for nothing.)
ns.REFINE = {
    {2840, "Copper Bar", "Mining", {{2770, 1}}},
    {3576, "Tin Bar", "Mining", {{2771, 1}}},
    {2841, "Bronze Bar", "Mining", {{2840, 1}, {3576, 1}}, makes = 2},
    {3575, "Iron Bar", "Mining", {{2772, 1}}},
    {3859, "Steel Bar", "Mining", {{3575, 1}, {3857, 1}}},
    {3577, "Gold Bar", "Mining", {{2776, 1}}},
    {3860, "Mithril Bar", "Mining", {{3858, 1}}},
    {12359, "Thorium Bar", "Mining", {{10620, 1}}},
    {2996, "Bolt of Linen Cloth", "Tailoring", {{2589, 2}}},
    {2997, "Bolt of Woolen Cloth", "Tailoring", {{2592, 3}}},
    {4305, "Bolt of Silk Cloth", "Tailoring", {{4306, 4}}},
    {4339, "Bolt of Mageweave", "Tailoring", {{4338, 5}}},
    {14048, "Bolt of Runecloth", "Tailoring", {{14047, 5}}},
    {4233, "Cured Medium Hide", "Leatherworking", {{4232, 1}, {4289, 1}}},
    {4236, "Cured Heavy Hide", "Leatherworking", {{4235, 1}, {4289, 3}}},
    {8172, "Cured Thick Hide", "Leatherworking", {{8169, 1}, {8150, 1}}},
    {3478, "Coarse Grinding Stone", "Blacksmithing", {{2836, 2}}},
    {3486, "Heavy Grinding Stone", "Blacksmithing", {{2838, 3}}},
    {7966, "Solid Grinding Stone", "Blacksmithing", {{7912, 4}}},
    {10558, "Gold Power Core", "Engineering", {{3577, 1}}},
    {10560, "Unstable Trigger", "Engineering", {{3860, 1}, {4338, 1}, {10505, 1}}}
}

-- shown in the first-launch setup window, in this order
ns.CHOOSABLE = {
    "Herbalism", "Mining", "Skinning", "Alchemy", "Blacksmithing",
    "Enchanting", "Engineering", "Leatherworking", "Tailoring", "Cooking",
    "First Aid", "Fishing"
}
