-- RestedXP Professions - static profession data (WoW Classic 1-300)
-- Routes are the standard community leveling paths; skill-up RNG means
-- brackets can shift by a few points in practice.

local addonName, ns = ...

-- Rank progression: at `trainAt` skill you can (and should) learn the rank
-- that raises your cap to the next tier.
ns.RANKS = {
    {cap = 75, trainAt = 50, nextRank = "Journeyman"},
    {cap = 150, trainAt = 125, nextRank = "Expert"},
    {cap = 225, trainAt = 200, nextRank = "Artisan"},
    {cap = 300, trainAt = 275, nextRank = "Master"}, -- TBC only
    {cap = 375}
}

-- Gathering professions: what unlocks at which skill. Sorted ascending.
ns.GATHER = {
    ["Mining"] = {
        verb = "Mine",
        tiers = {
            {1, "Copper Vein"},
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
            {1, "Peacebloom / Silverleaf"},
            {15, "Earthroot"},
            {50, "Mageroyal"},
            {70, "Briarthorn"},
            {85, "Stranglekelp"},
            {100, "Bruiseweed"},
            {115, "Wild Steelbloom"},
            {125, "Kingsblood"},
            {150, "Liferoot"},
            {170, "Goldthorn"},
            {185, "Khadgar's Whisker"},
            {205, "Firebloom"},
            {210, "Purple Lotus"},
            {230, "Sungrass"},
            {245, "Ghost Mushroom"},
            {250, "Gromsblood"},
            {260, "Golden Sansam"},
            {270, "Dreamfoil"},
            {280, "Mountain Silversage"},
            {285, "Plaguebloom"},
            {290, "Icecap"}
        }
    }
}

-- Crafting professions: route = {from, item, mats}, notes = {at, text}.
-- primary = counts against the ~5-skill-per-level pace check.
ns.CRAFT = {
    ["First Aid"] = {
        route = {
            {1, "Linen Bandage", "1 Linen Cloth"},
            {40, "Heavy Linen Bandage", "2 Linen Cloth"},
            {80, "Wool Bandage", "1 Wool Cloth"},
            {115, "Heavy Wool Bandage", "2 Wool Cloth"},
            {150, "Silk Bandage", "1 Silk Cloth"},
            {180, "Heavy Silk Bandage", "2 Silk Cloth"},
            {210, "Mageweave Bandage", "1 Mageweave Cloth"},
            {240, "Heavy Mageweave Bandage", "2 Mageweave Cloth"},
            {260, "Runecloth Bandage", "1 Runecloth"},
            {290, "Heavy Runecloth Bandage", "2 Runecloth"}
        },
        notes = {
            {150, "Expert rank: book |cFFFFCC00Expert First Aid - Under Wraps|r (vendor)"},
            {225, "Artisan rank: |cFFFFCC00Triage|r quest (Theramore / Hammerfall)"}
        }
    },
    ["Alchemy"] = {
        primary = true,
        route = {
            {1, "Minor Healing Potion", "Peacebloom + Silverleaf + Empty Vial"},
            {60, "Lesser Healing Potion", "Minor Healing Potion + Briarthorn"},
            {110, "Healing Potion", "Bruiseweed + Briarthorn + Leaded Vial"},
            {140, "Lesser Mana Potion", "Mageroyal + Stranglekelp + Empty Vial"},
            {155, "Greater Healing Potion", "Liferoot + Kingsblood + Leaded Vial"},
            {185, "Elixir of Agility", "Stranglekelp + Goldthorn + Leaded Vial"},
            {210, "Elixir of Greater Defense", "Wild Steelbloom + Goldthorn + Leaded Vial"},
            {215, "Superior Healing Potion", "Sungrass + Khadgar's Whisker + Crystal Vial"},
            {230, "Elixir of Detect Undead", "Arthas' Tears + Crystal Vial"},
            {250, "Elixir of Greater Agility", "Sungrass + Goldthorn + Crystal Vial"},
            {265, "Superior Mana Potion", "Sungrass + Blindweed + Crystal Vial"},
            {285, "Major Healing Potion", "Golden Sansam + Mountain Silversage + Crystal Vial"}
        },
        notes = {
            {1, "Vials: Alchemy supplies vendor (near trainers)"},
            {225, "Artisan trainer: Un'Goro Crater (Alliance) / Rogek path - see trainer dialog"}
        }
    },
    ["Blacksmithing"] = {
        primary = true,
        route = {
            {1, "Rough Sharpening Stone", "1 Rough Stone"},
            {25, "Rough Grinding Stone", "2 Rough Stone"},
            {75, "Coarse Grinding Stone", "2 Coarse Stone"},
            {90, "Runed Copper Belt", "10 Copper Bar"},
            {105, "Rough Bronze Leggings", "6 Bronze Bar"},
            {125, "Heavy Grinding Stone", "3 Heavy Stone (keep them!)"},
            {150, "Green Iron Leggings", "8 Iron Bar + Heavy Grinding Stone + Green Dye"},
            {165, "Green Iron Bracers", "6 Iron Bar + Green Dye"},
            {190, "Solid Grinding Stone", "4 Solid Stone"},
            {215, "Steel Plate Helm", "14 Steel Bar + Solid Grinding Stone"},
            {235, "Mithril Coif", "10 Mithril Bar + 6 Mageweave Cloth"},
            {250, "Dense Grinding Stone", "4 Dense Stone"},
            {275, "Thorium Bracers", "8 Thorium Bar (plans: vendor/AH)"}
        },
        notes = {
            {1, "Pairs best with Mining"},
            {225, "Artisan trainer: Brikk Keencraft, Booty Bay"}
        }
    },
    ["Engineering"] = {
        primary = true,
        route = {
            {1, "Rough Blasting Powder", "1 Rough Stone"},
            {30, "Handful of Copper Bolts", "1 Copper Bar"},
            {50, "Arclight Spanner, then Copper Tube", "6 Copper Bar; Tube: 2 Copper Bar + Weak Flux"},
            {75, "Coarse Blasting Powder", "1 Coarse Stone"},
            {90, "Whirring Bronze Gizmo", "2 Bronze Bar + 1 Wool Cloth"},
            {105, "Bronze Tube", "2 Bronze Bar + Weak Flux"},
            {125, "Heavy Blasting Powder", "1 Heavy Stone"},
            {150, "Iron Strut", "2 Iron Bar"},
            {155, "Gyrochronatom", "1 Iron Bar + 1 Gold Power Core"},
            {175, "Solid Blasting Powder", "2 Solid Stone"},
            {195, "Mithril Tube", "3 Mithril Bar"},
            {215, "Mithril Casing", "3 Mithril Bar"},
            {250, "Dense Blasting Powder", "2 Dense Stone"},
            {260, "Thorium Widget", "3 Thorium Bar + 1 Runecloth"},
            {290, "Thorium Tube", "6 Thorium Bar"}
        },
        notes = {
            {1, "Pairs best with Mining"},
            {200, "At 200: choose Gnomish or Goblin specialization"}
        }
    },
    ["Leatherworking"] = {
        primary = true,
        route = {
            {1, "Light Armor Kit", "1 Light Leather"},
            {20, "Handstitched Leather Boots", "2 Light Leather + Coarse Thread"},
            {30, "Embossed Leather Gloves", "3 Light Leather + Coarse Thread"},
            {55, "Fine Leather Belt", "6 Light Leather + Coarse Thread"},
            {85, "Cured Medium Hide", "1 Medium Hide + 1 Salt"},
            {100, "Dark Leather Boots", "4 Medium Leather + Fine Thread + Gray Dye"},
            {120, "Dark Leather Belt", "6 Medium Leather + Cured Medium Hide + Fine Thread"},
            {150, "Heavy Armor Kit", "5 Heavy Leather"},
            {170, "Barbaric Shoulders", "8 Heavy Leather + Fine Thread"},
            {200, "Nightscape Headband", "5 Thick Leather + 2 Silken Thread"},
            {230, "Nightscape Pants", "14 Thick Leather + 4 Silken Thread"},
            {250, "Rugged Armor Kit", "5 Rugged Leather"},
            {265, "Wicked Leather Bracers", "8 Rugged Leather + Black Dye (pattern: drop/AH)"},
            {285, "Wicked Leather Headband", "12 Rugged Leather + Black Dye"}
        },
        notes = {
            {1, "Pairs best with Skinning"},
            {225, "Artisan trainers: Feralas (both factions)"}
        }
    },
    ["Tailoring"] = {
        primary = true,
        route = {
            {1, "Bolt of Linen Cloth", "2 Linen Cloth"},
            {45, "Linen Bag", "3 Bolt of Linen + Coarse Thread"},
            {70, "Reinforced Linen Cape", "2 Bolt of Linen + 3 Coarse Thread"},
            {75, "Bolt of Woolen Cloth", "3 Wool Cloth"},
            {100, "Gray Woolen Shirt", "2 Bolt of Wool + Fine Thread + Gray Dye"},
            {110, "Double-stitched Woolen Shoulders", "3 Bolt of Wool + 2 Fine Thread"},
            {125, "Bolt of Silk Cloth", "4 Silk Cloth"},
            {145, "Azure Silk Hood", "2 Bolt of Silk + 2 Blue Dye"},
            {160, "Silk Headband", "3 Bolt of Silk + 2 Fine Thread"},
            {175, "Bolt of Mageweave", "5 Mageweave Cloth"},
            {185, "Crimson Silk Vest", "4 Bolt of Silk + 2 Red Dye"},
            {200, "Black Mageweave Leggings / Gloves", "2 Bolt of Mageweave + Silken Thread"},
            {215, "Black Mageweave Headband / Shoulders", "3 Bolt of Mageweave + Silken Thread"},
            {230, "Bolt of Runecloth", "5 Runecloth"},
            {250, "Runecloth Belt", "3 Bolt of Runecloth + Rune Thread"},
            {260, "Runecloth Gloves", "4 Bolt of Runecloth + 4 Rugged Leather"},
            {275, "Runecloth Bag", "5 Bolt of Runecloth + 2 Rugged Leather + Rune Thread"}
        },
        notes = {}
    },
    ["Enchanting"] = {
        primary = true,
        route = {
            {1, "Runed Copper Rod", "Copper Rod + Strange Dust + Lesser Magic Essence"},
            {2, "Enchant Bracer - Minor Health", "1 Strange Dust"},
            {50, "Enchant Bracer - Minor Deflection", "1 Lesser Magic Essence"},
            {60, "Enchant Bracer - Minor Stamina", "3 Strange Dust"},
            {110, "Enchant Bracer - Lesser Stamina", "2 Soul Dust"},
            {135, "Enchant Bracer - Spirit", "1 Lesser Mystic Essence"},
            {160, "Enchant Bracer - Strength", "1 Vision Dust"},
            {200, "Enchant Shield - Greater Stamina", "5 Dream Dust"},
            {230, "Enchant Bracer - Greater Strength", "2 Dream Dust"},
            {250, "Enchant Bracer - Greater Intellect", "3 Lesser Eternal Essence"},
            {275, "Enchant Cloak - Superior Defense", "8 Illusion Dust"}
        },
        notes = {
            {1, "Disenchant unneeded greens for dusts/essences"},
            {100, "Craft Runed Silver Rod (Silver Rod + dusts/essences)"},
            {155, "Craft Runed Golden Rod"},
            {200, "Craft Runed Truesilver Rod"},
            {225, "Artisan trainer: Annora, Uldaman (inside the dungeon)"},
            {290, "Craft Runed Arcanite Rod"}
        }
    },
    ["Cooking"] = {
        route = {
            {1, "Spice Bread / Charred Wolf Meat", "Simple Flour + Mild Spices / Stringy Wolf Meat"},
            {40, "Smoked Bear Meat", "1 Bear Meat"},
            {80, "Crab Cake / Dry Pork Ribs", "Crawler Meat / Boar Ribs + Mild Spices"},
            {130, "Curiously Tasty Omelet", "1 Raptor Egg + Mild Spices"},
            {175, "Roast Raptor", "1 Raptor Flesh + Hot Spices"},
            {225, "Monster Omelet", "1 Giant Egg + 2 Soothing Spices"},
            {250, "Tender Wolf Steak", "1 Tender Wolf Meat + Soothing Spices"},
            {285, "Smoked Desert Dumplings", "1 Sandworm Meat + Soothing Spices"}
        },
        notes = {
            {150, "Expert rank: |cFFFFCC00Expert Cookbook|r (vendors in Desolace / Shimmering Flats)"},
            {225, "Artisan rank: |cFFFFCC00Clamlette Surprise|r quest (Dirge, Gadgetzan)"},
            {285, "Dumplings recipe: quest in Silithus"}
        }
    }
}

ns.FISHING_NOTES = {
    {130, "Expert rank: book |cFFFFCC00Expert Fishing - The Bass and You|r (Booty Bay)"},
    {225, "Artisan rank: Nat Pagle quest (Dustwallow Marsh)"}
}

-- Professions the tracker understands (skill line names, English clients)
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
        H = "Karolek - Orgrimmar, Valley of Honor"
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
        A = "Arnold Leland - Stormwind, canals by Cathedral Square",
        H = "Lumak - Orgrimmar, Valley of Honor"
    }
}

-- shown in the first-launch setup window, in this order
ns.CHOOSABLE = {
    "Herbalism", "Mining", "Skinning", "Alchemy", "Blacksmithing",
    "Enchanting", "Engineering", "Leatherworking", "Tailoring", "Cooking",
    "First Aid", "Fishing"
}
