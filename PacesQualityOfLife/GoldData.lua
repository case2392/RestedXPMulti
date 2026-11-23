-- Pace's Quality of Life - Gold finder: what the game doesn't tell an add-on
--
-- Vanilla's numbers, as players wrote them down: what disenchanting gives,
-- which essences convert into which, and what the trade vendors charge for
-- the reagents every profession buys. None of it was checked on Forever, so
-- everything worked out from this file is shown as an estimate, and a price
-- a merchant actually showed always wins over a seed price here.
-- (Recipes are not in here: Forever changed some, so they are read from the
-- profession window itself.)

local addonName, ns = ...

local D = {}
ns.GoldData = D

-- dusts
local STRANGE, SOUL, VISION, DREAM, ILLUSION = 10940, 11083, 11137, 11176, 16204
-- essences, lesser and greater
local MAGIC_L, MAGIC_G = 10938, 10939
local ASTRAL_L, ASTRAL_G = 10998, 11082
local MYSTIC_L, MYSTIC_G = 11134, 11135
local NETHER_L, NETHER_G = 11174, 11175
local ETERNAL_L, ETERNAL_G = 16202, 16203
-- shards, small and large, and the crystal
local GLIMMER_S, GLIMMER_L = 10978, 11084
local GLOWING_S, GLOWING_L = 11138, 11139
local RADIANT_S, RADIANT_L = 11177, 11178
local BRILLIANT_S, BRILLIANT_L = 14343, 14344
local NEXUS = 20725

-- every enchanting material (the item check prices them all for an enchanter)
D.materials = {
    STRANGE, SOUL, VISION, DREAM, ILLUSION,
    MAGIC_L, MAGIC_G, ASTRAL_L, ASTRAL_G, MYSTIC_L, MYSTIC_G, NETHER_L, NETHER_G, ETERNAL_L, ETERNAL_G,
    GLIMMER_S, GLIMMER_L, GLOWING_S, GLOWING_L, RADIANT_S, RADIANT_L, BRILLIANT_S, BRILLIANT_L, NEXUS
}

-- {lesser, greater}: three lesser make one greater, and back (right-click)
D.essences = {
    {MAGIC_L, MAGIC_G}, {ASTRAL_L, ASTRAL_G}, {MYSTIC_L, MYSTIC_G}, {NETHER_L, NETHER_G}, {ETERNAL_L, ETERNAL_G}
}

-- uncommon (green) gear by item level:
-- {from, to, dust, least, most, essence, least, most, shard or false,
--  armor's chances of dust / essence / shard, a weapon's}
D.uncommon = {
    {5, 15, STRANGE, 1, 2, MAGIC_L, 1, 2, false, 0.80, 0.20, 0, 0.20, 0.80, 0},
    {16, 20, STRANGE, 2, 3, MAGIC_G, 1, 2, GLIMMER_S, 0.75, 0.20, 0.05, 0.20, 0.75, 0.05},
    {21, 25, STRANGE, 4, 6, ASTRAL_L, 1, 2, GLIMMER_S, 0.75, 0.15, 0.10, 0.15, 0.75, 0.10},
    {26, 30, SOUL, 1, 2, ASTRAL_G, 1, 2, GLIMMER_L, 0.75, 0.20, 0.05, 0.20, 0.75, 0.05},
    {31, 35, SOUL, 2, 5, MYSTIC_L, 1, 2, GLOWING_S, 0.75, 0.20, 0.05, 0.20, 0.75, 0.05},
    {36, 40, VISION, 1, 2, MYSTIC_G, 1, 2, GLOWING_L, 0.75, 0.20, 0.05, 0.20, 0.75, 0.05},
    {41, 45, VISION, 2, 5, NETHER_L, 1, 2, RADIANT_S, 0.75, 0.20, 0.05, 0.20, 0.75, 0.05},
    {46, 50, DREAM, 1, 2, NETHER_G, 1, 2, RADIANT_L, 0.75, 0.20, 0.05, 0.20, 0.75, 0.05},
    {51, 55, DREAM, 2, 5, ETERNAL_L, 1, 2, BRILLIANT_S, 0.75, 0.20, 0.05, 0.20, 0.75, 0.05},
    {56, 60, ILLUSION, 1, 2, ETERNAL_G, 1, 2, BRILLIANT_L, 0.75, 0.20, 0.05, 0.20, 0.75, 0.05},
    {61, 65, ILLUSION, 2, 5, ETERNAL_G, 2, 3, BRILLIANT_L, 0.75, 0.20, 0.05, 0.20, 0.75, 0.05}
}

-- rare (blue) gear: one shard; {from, to, shard, its chance, the rare extra, its chance}
D.rare = {
    {1, 25, GLIMMER_S, 1},
    {26, 30, GLIMMER_L, 1},
    {31, 35, GLOWING_S, 1},
    {36, 40, GLOWING_L, 1},
    {41, 45, RADIANT_S, 1},
    {46, 50, RADIANT_L, 1},
    {51, 55, BRILLIANT_S, 1},
    {56, 65, BRILLIANT_L, 0.995, NEXUS, 0.005}
}

-- epic (purple) gear: {from, to, material, least, most}
D.epic = {
    {40, 45, RADIANT_S, 2, 4},
    {46, 50, RADIANT_L, 2, 4},
    {51, 55, BRILLIANT_S, 2, 4},
    {56, 60, NEXUS, 1, 1},
    {61, 999, NEXUS, 1, 2}
}

-- gear that disenchanting won't take: what enchanters make (Gold.lua also
-- rules out whatever an enchanting recipe of the account's characters
-- makes; this covers the ones none of them knows)
D.noDisenchant = {
    [11287] = true, -- Lesser Magic Wand
    [11288] = true, -- Greater Magic Wand
    [11289] = true, -- Lesser Mystic Wand
    [11290] = true, -- Greater Mystic Wand
    [11811] = true  -- Smoking Heart of the Mountain
}

-- the Enchanting skill an item level asks for: {up to this item level, skill}
-- (a later expansion's rule, used only for the "may need skill" mark)
D.skill = {
    {20, 1}, {25, 25}, {30, 50}, {35, 75}, {40, 100}, {45, 125}, {50, 150}, {55, 175}, {60, 200}, {65, 225}
}

-- what trade vendors charge for one, in copper (itemID = price): used only
-- until a merchant has shown its own price, and shown as "not confirmed"
D.seed = {
    [2320] = 10,     -- Coarse Thread
    [2321] = 100,    -- Fine Thread
    [4291] = 500,    -- Silken Thread
    [8343] = 2000,   -- Heavy Silken Thread
    [14341] = 5000,  -- Rune Thread
    [2604] = 50,     -- Red Dye
    [6260] = 50,     -- Blue Dye
    [2605] = 100,    -- Green Dye
    [4340] = 350,    -- Gray Dye
    [4341] = 500,    -- Yellow Dye
    [6261] = 1000,   -- Orange Dye
    [2325] = 1000,   -- Black Dye
    [4342] = 2500,   -- Purple Dye
    [10290] = 2500,  -- Pink Dye
    [2324] = 25,     -- Bleach
    [4289] = 50,     -- Salt
    [2880] = 100,    -- Weak Flux
    [3466] = 2000,   -- Strong Flux
    [18567] = 150000, -- Elemental Flux
    [4399] = 200,    -- Wooden Stock
    [4400] = 2000,   -- Heavy Stock
    [10647] = 2000,  -- Engineer's Ink
    [3371] = 4,      -- Empty Vial
    [3372] = 40,     -- Leaded Vial
    [8925] = 500,    -- Crystal Vial
    [18256] = 4000,  -- Imbued Vial
    [6217] = 124,    -- Copper Rod
    [4470] = 38,     -- Simple Wood
    [11291] = 4500,  -- Star Wood
    [2678] = 2,      -- Mild Spices
    [2692] = 40,     -- Hot Spices
    [3713] = 160,    -- Soothing Spices
    [2665] = 20,     -- Stormwind Seasoning Herbs
    [159] = 5,       -- Refreshing Spring Water
    [1179] = 25,     -- Ice Cold Milk
    [2894] = 50,     -- Rhapsody Malt
    [6530] = 100,    -- Nightcrawlers
    [6529] = 50,     -- Shiny Bauble
    [2928] = 20,     -- Dust of Decay
    [2930] = 50,     -- Essence of Pain
    [5173] = 100,    -- Deathweed
    [8924] = 100,    -- Dust of Deterioration
    [8923] = 200,    -- Essence of Agony
    [3777] = 40      -- Lethargy Root
}
