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

-- Recipe items, vanilla's: what each teaches - the profession, the skill it
-- needs, what it makes (the least and most a craft gives) and the materials.
-- Nothing in the game tells an add-on what a recipe it hasn't learned makes,
-- so this is the only way to price recipes that nobody on the account knows;
-- Forever changed some recipes, so whatever is worked out from it is shown as
-- an estimate.
-- [recipe item] = "profession|skill|made item|least|most|item:count,item:count"
--
-- Made from the wow-classic-items data set's 2020 release (0.8.2, vanilla
-- items only; https://github.com/nexus-devs/wow-classic-items):
--   MIT License. Copyright (c) 2019 Nakroma. Permission is hereby granted,
--   free of charge, to any person obtaining a copy of this software and
--   associated documentation files (the "Software"), to deal in the Software
--   without restriction, including without limitation the rights to use,
--   copy, modify, merge, publish, distribute, sublicense, and/or sell copies
--   of the Software, and to permit persons to whom the Software is furnished
--   to do so, subject to the following conditions: The above copyright notice
--   and this permission notice shall be included in all copies or substantial
--   portions of the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT
--   WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
--   WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
--   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
--   LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
--   CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH
--   THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
D.recipeItems = {
    [728] = "Cooking|75|733|1|1|729:1,730:1,731:1", -- Recipe: Westfall Stew
    [2406] = "Leatherworking|90|2307|1|1|2318:7,2320:2", -- Pattern: Fine Leather Boots
    [2407] = "Leatherworking|60|2311|1|1|2318:8,2320:2,2324:1", -- Pattern: White Leather Jerkin
    [2408] = "Leatherworking|75|2312|1|1|4231:1,2318:4,2320:2", -- Pattern: Fine Leather Gloves
    [2409] = "Leatherworking|100|2317|1|1|2319:6,2321:1,4340:1", -- Pattern: Dark Leather Tunic
    [2553] = "Alchemy|50|2457|1|1|2452:1,765:1,3371:1", -- Recipe: Elixir of Minor Agility
    [2555] = "Alchemy|60|2459|1|1|2452:1,2450:1,3371:1", -- Recipe: Swiftness Potion
    [2598] = "Tailoring|40|2572|1|1|2996:3,2320:2,2604:2", -- Pattern: Red Linen Robe
    [2601] = "Tailoring|105|2585|1|1|2997:4,2321:3,4340:1", -- Pattern: Gray Woolen Robe
    [2697] = "Cooking|50|724|1|1|723:1,2678:1", -- Recipe: Goretusk Liver Pie
    [2698] = "Cooking|85|2682|1|1|2675:1,2678:1", -- Recipe: Cooked Crab Claw
    [2699] = "Cooking|100|1082|1|1|1081:1,1080:1", -- Recipe: Redridge Goulash
    [2700] = "Cooking|110|2685|1|1|2677:2,2692:1", -- Recipe: Succulent Pork Ribs
    [2701] = "Cooking|100|1017|3|3|1015:2,2665:1", -- Recipe: Seasoned Wolf Kabob
    [2881] = "Blacksmithing|80|2864|1|1|2840:12,1210:1,3470:2", -- Plans: Runed Copper Breastplate
    [2882] = "Blacksmithing|125|3481|1|1|2841:8,2842:2,3478:2", -- Plans: Silvered Bronze Shoulders
    [2883] = "Blacksmithing|125|3490|1|1|2841:4,3466:1,2459:1,1210:2,3478:2,2319:2", -- Plans: Deadly Bronze Poniard
    [2889] = "Cooking|25|2888|1|1|2886:1,2894:1", -- Recipe: Beer Basted Boar Ribs
    [3393] = "Alchemy|110|3384|1|1|785:3,3355:1,3371:1", -- Recipe: Minor Magic Resistance Potion
    [3394] = "Alchemy|120|3386|1|1|1288:1,2453:1,3372:1", -- Recipe: Elixir of Poison Resistance
    [3395] = "Alchemy|250|3387|1|1|8839:2,8845:1,8925:1", -- Recipe: Limited Invulnerability Potion
    [3396] = "Alchemy|140|3390|1|1|3355:1,2452:1,3372:1", -- Recipe: Elixir of Lesser Agility
    [3608] = "Blacksmithing|145|3492|1|1|3575:6,3466:2,3391:1,1705:2,3478:2,2319:2", -- Plans: Mighty Iron Hammer
    [3609] = "Blacksmithing|35|3471|1|1|2840:8,774:1,3470:2", -- Plans: Copper Chain Vest
    [3610] = "Blacksmithing|60|3474|1|1|2840:8,818:1,774:1", -- Plans: Gemmed Copper Gauntlets
    [3611] = "Blacksmithing|145|3484|1|1|3575:4,1705:2,3478:2,2605:1", -- Plans: Green Iron Boots
    [3612] = "Blacksmithing|150|3485|1|1|3575:4,5498:2,3478:2,2605:1", -- Plans: Green Iron Gauntlets
    [3678] = "Cooking|80|3662|1|1|2924:1,2678:1", -- Recipe: Crocolisk Steak
    [3679] = "Cooking|60|3220|2|2|3173:1,3172:1,3174:1", -- Recipe: Blood Sausage
    [3680] = "Cooking|90|3663|1|1|1468:2,2692:1", -- Recipe: Murloc Fin Soup
    [3681] = "Cooking|120|3664|1|1|3667:1,2692:1", -- Recipe: Crocolisk Gumbo
    [3682] = "Cooking|130|3665|1|1|3685:1,2692:1", -- Recipe: Curiously Tasty Omelet
    [3683] = "Cooking|110|3666|1|1|2251:2,2692:1", -- Recipe: Gooey Spider Cake
    [3734] = "Cooking|110|3726|1|1|3730:1,2692:1", -- Recipe: Big Bear Steak
    [3735] = "Cooking|125|3727|1|1|3731:1,2692:1", -- Recipe: Hot Lion Chops
    [3736] = "Cooking|150|3728|1|1|3731:2,3713:1", -- Recipe: Tasty Lion Steak
    [3737] = "Cooking|175|3729|1|1|3712:1,3713:1", -- Recipe: Soothing Turtle Bisque
    [3830] = "Alchemy|175|3825|1|1|3355:1,3821:1,3372:1", -- Recipe: Elixir of Fortitude
    [3831] = "Alchemy|180|3826|1|1|3357:1,2453:1,3372:1", -- Recipe: Mighty Troll's Blood Potion
    [3832] = "Alchemy|195|3828|1|1|3358:1,3818:1,3372:1", -- Recipe: Elixir of Detect Lesser Invisibility
    [3866] = "Blacksmithing|175|3850|1|1|3575:8,3466:2,3486:2,1529:2,4234:3", -- Plans: Jade Serpentblade
    [3867] = "Blacksmithing|170|3852|1|1|3575:10,3577:4,1705:2,3466:2,4234:2,3486:2", -- Plans: Golden Iron Destroyer
    [3868] = "Blacksmithing|200|3854|1|1|3859:8,3466:2,3486:2,1529:2,3829:1,4234:4", -- Plans: Frost Tiger Blade
    [3869] = "Blacksmithing|200|3856|1|1|3859:10,3466:2,3486:3,3864:2,3824:1,4234:3", -- Plans: Shadow Crescent Axe
    [3870] = "Blacksmithing|160|3840|1|1|3575:7,3486:1,2605:1", -- Plans: Green Iron Shoulders
    [3871] = "Blacksmithing|175|3841|1|1|3859:6,3577:2,3486:1", -- Plans: Golden Scale Shoulders
    [3872] = "Blacksmithing|170|3843|1|1|3575:10,3577:2,3486:1", -- Plans: Golden Scale Leggings
    [3873] = "Blacksmithing|195|3845|1|1|3859:12,3577:2,3486:4,1529:2", -- Plans: Golden Scale Cuirass
    [3874] = "Blacksmithing|185|3846|1|1|3859:8,3864:1,1705:1,3486:2", -- Plans: Polished Steel Boots
    [3875] = "Blacksmithing|200|3847|1|1|3859:10,3577:4,3486:4,3864:1", -- Plans: Golden Scale Boots
    [4292] = "Tailoring|95|4241|1|1|2997:4,2605:1,2321:1", -- Pattern: Green Woolen Bag
    [4293] = "Leatherworking|100|4244|1|1|4243:1,4231:2,2320:2", -- Pattern: Hillman's Leather Vest
    [4294] = "Leatherworking|120|4250|1|1|2319:8,3383:1,2321:2", -- Pattern: Hillman's Belt
    [4296] = "Leatherworking|140|4252|1|1|2319:12,3390:1,4340:1,2321:2", -- Pattern: Dark Leather Shoulders
    [4297] = "Leatherworking|150|4254|1|1|4234:6,5637:2,2321:1", -- Pattern: Barbaric Gloves
    [4298] = "Leatherworking|170|4258|1|1|4236:2,4234:4,2321:1,7071:1", -- Pattern: Guardian Belt
    [4299] = "Leatherworking|175|4256|1|1|4236:2,4234:12,3824:1,2321:2", -- Pattern: Guardian Armor
    [4300] = "Leatherworking|195|4260|1|1|4234:6,4236:2,4291:1", -- Pattern: Guardian Leather Bracers
    [4301] = "Leatherworking|200|4264|1|1|4234:6,4236:2,4096:2,5633:1,4291:1,7071:1", -- Pattern: Barbaric Belt
    [4345] = "Tailoring|95|4313|1|1|2997:4,2318:2,2321:1,2604:2", -- Pattern: Red Woolen Boots
    [4346] = "Tailoring|100|4311|1|1|2997:3,2321:2,5498:2", -- Pattern: Heavy Woolen Cloak
    [4347] = "Tailoring|120|4315|1|1|2997:6,2319:2,2321:2", -- Pattern: Reinforced Woolen Shoulders
    [4348] = "Tailoring|125|4331|1|1|2997:4,5500:1,2321:4,2324:2", -- Pattern: Phoenix Gloves
    [4349] = "Tailoring|125|4317|1|1|2997:6,5500:1,2321:3", -- Pattern: Phoenix Pants
    [4350] = "Tailoring|140|4321|1|1|4305:3,3182:1,2321:2", -- Pattern: Spider Silk Slippers
    [4351] = "Tailoring|170|4323|1|1|4305:4,4291:1,3824:1", -- Pattern: Shadow Hood
    [4352] = "Tailoring|175|4325|1|1|4305:4,4291:1,4337:2", -- Pattern: Boots of the Enchanter
    [4353] = "Tailoring|180|4328|1|1|4305:4,4337:2,7071:1", -- Pattern: Spider Belt
    [4354] = "Tailoring|185|4335|1|1|4305:4,4342:1,4291:1", -- Pattern: Rich Purple Silk Shirt
    [4355] = "Tailoring|200|4327|1|1|4339:3,4291:2,3829:1,4337:2", -- Pattern: Icy Cloak
    [4356] = "Tailoring|200|4329|1|1|4339:4,4234:4,3864:1,7071:1,4291:1", -- Pattern: Star Belt
    [4408] = "Engineering|75|4401|1|1|4363:1,4359:1,2840:1,774:2", -- Schematic: Mechanical Squirrel
    [4409] = "Engineering|100|4367|1|1|4364:2,4363:1,2318:1,159:1", -- Schematic: Small Seaforium Charge
    [4410] = "Engineering|120|4373|1|1|2319:4,1210:2", -- Schematic: Shadow Goggles
    [4411] = "Engineering|125|4376|1|1|4375:1,4402:1", -- Schematic: Flame Deflector
    [4412] = "Engineering|145|4383|1|1|4371:3,4375:3,4400:1,1705:2", -- Schematic: Moonsight Rifle
    [4413] = "Engineering|160|4388|1|1|4375:3,4306:2,1529:1,4371:1", -- Schematic: Discombobulator Ray
    [4414] = "Engineering|165|4403|1|1|4371:4,4387:1,4377:4,2319:4", -- Schematic: Portable Bronze Mortar
    [4415] = "Engineering|185|4393|1|1|4234:6,3864:2", -- Schematic: Craftsman's Monocle
    [4416] = "Engineering|195|4395|1|1|4377:3,3575:2,4389:1", -- Schematic: Goblin Land Mine
    [4417] = "Engineering|200|4398|1|1|10505:2,4234:2,159:1", -- Schematic: Large Seaforium Charge
    [4597] = "Alchemy|50|4596|1|1|3164:1,2447:1,3371:1", -- Recipe: Discolored Healing Potion
    [4609] = "Cooking|175|4457|1|1|3404:1,2692:1", -- Recipe: Barbecued Buzzard Wing
    [4624] = "Alchemy|215|4623|1|1|3858:1,3821:1,3372:1", -- Recipe: Lesser Stoneshield Potion
    [5083] = "Leatherworking|40|5081|1|1|5082:3,2318:4,2320:1", -- Pattern: Kodo Hide Bag
    [5482] = "Cooking|10|5472|1|1|5465:1", -- Recipe: Kaldorei Spider Kabob
    [5483] = "Cooking|20|5473|1|1|5466:1", -- Recipe: Scorpid Surprise
    [5484] = "Cooking|35|5474|2|2|5467:1,2678:1", -- Recipe: Roasted Kodo Meat
    [5485] = "Cooking|50|5476|2|2|5468:1,2678:1", -- Recipe: Fillet of Frenzy
    [5486] = "Cooking|50|5477|2|2|5469:1,4536:1", -- Recipe: Strider Stew
    [5487] = "Cooking|90|5478|2|2|5051:1", -- Recipe: Dig Rat Stew
    [5488] = "Cooking|100|5479|2|2|5470:1,2692:1", -- Recipe: Crispy Lizard Tail
    [5489] = "Cooking|110|5480|2|2|5471:1,2678:4", -- Recipe: Lean Venison
    [5528] = "Cooking|90|5526|1|1|5503:1,1179:1,2678:1", -- Recipe: Clam Chowder
    [5543] = "Blacksmithing|140|5541|1|1|2841:10,3466:1,5500:1,3478:2,2319:2", -- Plans: Iridescent Hammer
    [5578] = "Blacksmithing|130|2869|1|1|2841:10,2842:2,3478:2,1705:1", -- Plans: Silvered Bronze Breastplate
    [5640] = "Alchemy|60|5631|1|1|5635:1,2450:1,3371:1", -- Recipe: Rage Potion
    [5642] = "Alchemy|150|5634|1|1|6370:2,3820:1,3372:1", -- Recipe: Free Action Potion
    [5643] = "Alchemy|175|5633|1|1|5637:1,3356:1,3372:1", -- Recipe: Great Rage Potion
    [5771] = "Tailoring|70|5762|1|1|2996:4,2321:1,2604:1", -- Pattern: Red Linen Bag
    [5772] = "Tailoring|115|5763|1|1|2997:4,2604:1,2321:1", -- Pattern: Red Woolen Bag
    [5773] = "Tailoring|150|5770|1|1|4305:4,2321:2,3182:2", -- Pattern: Robes of Arcana
    [5774] = "Tailoring|175|5764|1|1|4305:4,4234:3,2321:3,2605:1", -- Pattern: Green Silk Pack
    [5775] = "Tailoring|185|5765|1|1|4305:5,2325:1,2321:4", -- Pattern: Black Silk Pack
    [5786] = "Leatherworking|90|5780|1|1|5784:8,2318:6,2321:1", -- Pattern: Murloc Scale Belt
    [5787] = "Leatherworking|95|5781|1|1|5784:12,4231:1,2318:8,2321:1", -- Pattern: Murloc Scale Breastplate
    [5788] = "Leatherworking|170|5782|1|1|5785:12,4236:1,4234:10,2321:3", -- Pattern: Thick Murloc Armor
    [5789] = "Leatherworking|190|5783|1|1|5785:16,4236:1,4234:14,4291:1", -- Pattern: Murloc Scale Bracers
    [5972] = "Leatherworking|105|5958|1|1|2319:8,2997:1,2321:1", -- Pattern: Fine Leather Pants
    [5973] = "Leatherworking|170|5963|1|1|4234:10,2321:2,1206:1", -- Pattern: Barbaric Leggings
    [5974] = "Leatherworking|185|5965|1|1|4234:14,4305:2,4291:2", -- Pattern: Guardian Cloak
    [6039] = "Cooking|175|6038|1|1|4655:1,2692:1", -- Recipe: Giant Clam Scorcho
    [6044] = "Blacksmithing|150|6042|1|1|3575:6,3478:4", -- Plans: Iron Shield Spike
    [6045] = "Blacksmithing|165|6043|1|1|3575:4,3478:2,1705:1", -- Plans: Iron Counterweight
    [6046] = "Blacksmithing|190|6041|1|1|3859:8,3486:2,4234:4", -- Plans: Steel Weapon Chain
    [6047] = "Blacksmithing|190|3837|1|1|3859:8,3577:2,3486:2", -- Plans: Golden Scale Coif
    [6053] = "Alchemy|100|6051|1|1|2453:1,2452:1,3371:1", -- Recipe: Holy Protection Potion
    [6054] = "Alchemy|135|6048|1|1|3369:1,3356:1,3372:1", -- Recipe: Shadow Protection Potion
    [6055] = "Alchemy|165|6049|1|1|4402:1,6371:1,3372:1", -- Recipe: Fire Protection Potion
    [6056] = "Alchemy|190|6050|1|1|3819:1,3821:1,3372:1", -- Recipe: Frost Protection Potion
    [6057] = "Alchemy|190|6052|1|1|3357:1,3820:1,3372:1", -- Recipe: Nature Protection Potion
    [6068] = "Alchemy|165|3824|1|1|3818:4,3369:4,3372:1", -- Recipe: Shadow Oil
    [6211] = "Alchemy|150|3391|1|1|2449:1,3356:1,3372:1", -- Recipe: Elixir of Ogre's Strength
    [6270] = "Tailoring|55|6240|1|1|2996:3,2320:1,6260:1", -- Pattern: Blue Linen Vest
    [6271] = "Tailoring|55|6239|1|1|2996:3,2320:1,2604:1", -- Pattern: Red Linen Vest
    [6272] = "Tailoring|70|6242|1|1|2996:4,2320:2,6260:2", -- Pattern: Blue Linen Robe
    [6274] = "Tailoring|100|6263|1|1|2997:4,2321:2,6260:2", -- Pattern: Blue Overalls
    [6275] = "Tailoring|115|6264|1|1|2997:5,2321:3,2604:3", -- Pattern: Greater Adept's Robe
    [6325] = "Cooking|1|6290|1|1|6291:1", -- Recipe: Brilliant Smallfish
    [6326] = "Cooking|1|787|1|1|6303:1", -- Recipe: Slitherskin Mackerel
    [6328] = "Cooking|50|4592|1|1|6289:1", -- Recipe: Longjaw Mud Snapper
    [6329] = "Cooking|50|6316|1|1|6317:1,2678:1", -- Recipe: Loch Frenzy Delight
    [6330] = "Cooking|100|4593|1|1|6308:1", -- Recipe: Bristle Whisker Catfish
    [6368] = "Cooking|50|5095|1|1|6361:1", -- Recipe: Rainbow Fin Albacore
    [6369] = "Cooking|175|4594|1|1|6362:1", -- Recipe: Rockscale Cod
    [6390] = "Tailoring|120|6384|1|1|2997:4,6260:2,4340:1,2321:1", -- Pattern: Stylish Blue Shirt
    [6391] = "Tailoring|120|6385|1|1|2997:4,2605:2,4340:1,2321:1", -- Pattern: Stylish Green Shirt
    [6401] = "Tailoring|155|4333|1|1|4305:2,4340:2,2321:1", -- Pattern: Dark Silk Shirt
    [6454] = "First Aid|130|6453|3|3|1288:1", -- Manual: Strong Anti-Venom
    [6474] = "Leatherworking|90|6466|1|1|6470:8,4231:1,2321:1", -- Pattern: Deviate Scale Cloak
    [6475] = "Leatherworking|105|6467|1|1|6471:2,6470:6,2321:2", -- Pattern: Deviate Scale Gloves
    [6476] = "Leatherworking|115|6468|1|1|6471:10,6470:10,2321:2", -- Pattern: Deviate Scale Belt
    [6661] = "Cooking|85|6657|1|1|6522:1,2678:1", -- Recipe: Savory Deviate Delight
    [6663] = "Alchemy|90|6662|1|1|6522:1,2449:1,3371:1", -- Recipe: Elixir of Giant Growth
    [6672] = "Engineering|185|4852|1|1|4611:1,4377:1,4306:1", -- Schematic: Flash Bomb
    [6710] = "Leatherworking|90|6709|1|1|2318:6,4231:1,2320:4,5498:1", -- Pattern: Moonglow Vest
    [6716] = "Engineering|100|6714|1|3|4364:4,2592:1", -- Schematic: EZ-Thro Dynamite
    [6735] = "Blacksmithing|100|6731|1|1|2840:16,818:2,3470:3", -- Plans: Ironforge Breastplate
    [6891] = "Cooking|1|6888|1|1|6889:1,2678:1", -- Recipe: Herb Baked Egg
    [6892] = "Cooking|40|6890|1|1|3173:1", -- Recipe: Smoked Bear Meat
    [7084] = "Tailoring|190|7059|1|1|4305:5,6371:2,2604:2,4291:2", -- Pattern: Crimson Silk Shoulders
    [7085] = "Tailoring|190|7060|1|1|4305:6,7072:2,6260:2,4291:2", -- Pattern: Azure Shoulders
    [7086] = "Tailoring|195|7061|1|1|4305:5,7067:4,4234:4,7071:1,4291:2", -- Pattern: Earthen Silk Belt
    [7087] = "Tailoring|180|7056|1|1|4305:5,2604:2,6371:2,4291:1", -- Pattern: Crimson Silk Cloak
    [7088] = "Tailoring|205|7063|1|1|4305:8,7068:4,3827:2,2604:4,4291:1", -- Pattern: Crimson Silk Robe
    [7089] = "Tailoring|175|7053|1|1|4305:3,6260:2,2321:2", -- Pattern: Azure Silk Cloak
    [7090] = "Tailoring|165|7065|1|1|4305:5,2605:2,4291:1", -- Pattern: Green Silk Armor
    [7091] = "Tailoring|150|7049|1|1|4305:3,4234:2,929:4,2321:1", -- Pattern: Truefaith Gloves
    [7092] = "Tailoring|145|7047|1|1|4305:3,4234:2,6048:2,2321:2", -- Pattern: Hands of Darkness
    [7114] = "Tailoring|145|4319|1|1|4305:3,4234:2,6260:2,2321:2", -- Pattern: Azure Silk Gloves
    [7288] = "Leatherworking|35|7280|1|1|2318:5,2320:5", -- Pattern: Rugged Leather Pants
    [7289] = "Leatherworking|100|7283|1|1|7286:12,2319:4,2321:1", -- Pattern: Black Whelp Cloak
    [7290] = "Leatherworking|120|7284|1|1|7287:6,2319:4,2321:1", -- Pattern: Red Whelp Gloves
    [7360] = "Leatherworking|120|4248|1|1|2312:1,4233:1,2321:1,4340:1", -- Pattern: Dark Leather Gloves
    [7361] = "Leatherworking|135|7349|1|1|2319:8,3356:4,2321:2", -- Pattern: Herbalist's Gloves
    [7362] = "Leatherworking|135|7352|1|1|2319:6,7067:1,2321:2", -- Pattern: Earthen Leather Shoulders
    [7363] = "Leatherworking|140|7358|1|1|2319:10,5373:2,2321:2", -- Pattern: Pilferer's Gloves
    [7364] = "Leatherworking|145|7359|1|1|2319:12,7067:2,2997:2,2321:2", -- Pattern: Heavy Earthen Gloves
    [7449] = "Leatherworking|165|7373|1|1|4234:10,2325:1,2321:2", -- Pattern: Dusky Leather Leggings
    [7450] = "Leatherworking|175|7375|1|1|7392:4,4234:10,2321:2", -- Pattern: Green Whelp Armor
    [7451] = "Leatherworking|190|7386|1|1|7392:6,4234:8,4291:2", -- Pattern: Green Whelp Bracers
    [7452] = "Leatherworking|200|7390|1|1|4234:8,7428:2,3824:1,4291:2", -- Pattern: Dusky Boots
    [7453] = "Leatherworking|200|7391|1|1|4234:10,2459:2,4337:2,4291:1", -- Pattern: Swift Boots
    [7560] = "Engineering|125|7506|1|1|2841:6,4375:1,814:2,818:1,774:1", -- Schematic: Gnomish Universal Remote
    [7561] = "Engineering|165|7148|1|1|3575:6,4375:2,814:2,4306:2,1210:2,7191:1", -- Schematic: Goblin Jumper Cables
    [7613] = "Leatherworking|155|4255|1|1|4234:9,2605:2,2321:4", -- Pattern: Green Leather Armor
    [7742] = "Engineering|200|4397|1|1|4389:4,1529:2,1705:2,3864:2,7191:1", -- Schematic: Gnomish Cloaking Device
    [7975] = "Blacksmithing|210|7921|1|1|3860:10,1705:2", -- Plans: Heavy Mithril Pants
    [7976] = "Blacksmithing|215|7967|1|1|3860:4,6037:2,7966:4", -- Plans: Mithril Shield Spike
    [7978] = "Blacksmithing|160|7913|1|1|3575:8,5635:4,1210:2,3486:2", -- Plans: Barbaric Iron Shoulders
    [7979] = "Blacksmithing|160|7914|1|1|3575:20,3486:4", -- Plans: Barbaric Iron Breastplate
    [7980] = "Blacksmithing|175|7915|1|1|3575:10,5637:2,5635:2", -- Plans: Barbaric Iron Helm
    [7981] = "Blacksmithing|180|7916|1|1|3575:12,5637:4,818:4,3486:2", -- Plans: Barbaric Iron Boots
    [7982] = "Blacksmithing|185|7917|1|1|3575:14,3486:3,5637:2", -- Plans: Barbaric Iron Gloves
    [7983] = "Blacksmithing|220|7926|1|1|3860:12,6037:1,7966:1,7909:1", -- Plans: Ornate Mithril Pants
    [7984] = "Blacksmithing|220|7927|1|1|3860:10,4338:6,6037:1,7966:1", -- Plans: Ornate Mithril Gloves
    [7985] = "Blacksmithing|225|7928|1|1|3860:12,6037:1,4304:6", -- Plans: Ornate Mithril Shoulder
    [7986] = "Blacksmithing|240|7935|1|1|3860:16,6037:6,7077:1,7966:1", -- Plans: Ornate Mithril Breastplate
    [7987] = "Blacksmithing|245|7937|1|1|3860:16,6037:2,7971:1,7966:1", -- Plans: Ornate Mithril Helm
    [7988] = "Blacksmithing|245|7936|1|1|3860:14,6037:2,4304:4,7966:1,7909:1", -- Plans: Ornate Mithril Boots
    [7989] = "Blacksmithing|235|7969|1|1|3860:4,7966:3", -- Plans: Mithril Spurs
    [7990] = "Blacksmithing|245|7934|1|1|3860:14,7909:1", -- Plans: Heavy Mithril Helm
    [7991] = "Blacksmithing|235|7932|1|1|3860:14,4304:4,3864:4", -- Plans: Mithril Scale Shoulders
    [7992] = "Blacksmithing|220|7942|1|1|3860:16,7909:2,7966:1,4304:4", -- Plans: Blue Glittering Axe
    [7993] = "Blacksmithing|240|7944|1|1|3860:14,7909:1,1705:2,1206:2,7966:1,4338:2", -- Plans: Dazzling Mithril Rapier
    [7994] = "Blacksmithing|230|7929|1|1|3860:12,7067:1", -- Plans: Orcish War Leggings
    [7995] = "Blacksmithing|215|7924|1|1|3860:8,3864:2", -- Plans: Mithril Scale Bracers
    [8028] = "Blacksmithing|245|7946|1|1|3860:18,7075:2,7966:1,4304:4", -- Plans: Runed Mithril Hammer
    [8029] = "Blacksmithing|225|7943|1|1|3860:14,6037:4,7966:1,4304:2", -- Plans: Wicked Mithril Blade
    [8030] = "Blacksmithing|255|7947|1|1|3860:12,6037:6,7910:2,7966:1,4304:2", -- Plans: Ebon Shiv
    [8384] = "Leatherworking|200|8174|1|1|4234:12,4236:2,4291:2", -- Pattern: Comfortable Leather Hat
    [8385] = "Leatherworking|205|8187|1|1|4304:6,8167:8,8343:1", -- Pattern: Turtle Scale Gloves
    [8386] = "Leatherworking|215|8200|1|1|4304:10,8151:4,8343:1", -- Pattern: Big Voodoo Robe
    [8387] = "Leatherworking|220|8201|1|1|4304:8,8151:6,8343:1", -- Pattern: Big Voodoo Mask
    [8389] = "Leatherworking|240|8202|1|1|4304:10,8152:6,8343:2", -- Pattern: Big Voodoo Pants
    [8390] = "Leatherworking|240|8216|1|1|4304:14,8152:4,8343:2", -- Pattern: Big Voodoo Cloak
    [8395] = "Leatherworking|220|8203|1|1|4304:12,8154:12,4291:4", -- Pattern: Tough Scorpid Breastplate
    [8397] = "Leatherworking|220|8205|1|1|4304:10,8154:4,4291:2", -- Pattern: Tough Scorpid Bracers
    [8398] = "Leatherworking|225|8204|1|1|4304:6,8154:8,4291:2", -- Pattern: Tough Scorpid Gloves
    [8399] = "Leatherworking|235|8209|1|1|4304:12,8154:12,4291:6", -- Pattern: Tough Scorpid Boots
    [8400] = "Leatherworking|240|8207|1|1|4304:12,8154:16,8343:2", -- Pattern: Tough Scorpid Shoulders
    [8401] = "Leatherworking|245|8206|1|1|4304:14,8154:8,8343:2", -- Pattern: Tough Scorpid Leggings
    [8402] = "Leatherworking|250|8208|1|1|4304:10,8154:20,8343:2", -- Pattern: Tough Scorpid Helm
    [8403] = "Leatherworking|220|8210|1|1|4304:10,8153:1,8172:1", -- Pattern: Wild Leather Shoulders
    [8404] = "Leatherworking|225|8211|1|1|4304:12,8153:2,8172:1", -- Pattern: Wild Leather Vest
    [8405] = "Leatherworking|225|8214|1|1|4304:10,8153:2,8172:1", -- Pattern: Wild Leather Helmet
    [8406] = "Leatherworking|245|8213|1|1|4304:14,8153:4,8172:2", -- Pattern: Wild Leather Boots
    [8407] = "Leatherworking|250|8212|1|1|4304:16,8153:6,8172:2", -- Pattern: Wild Leather Leggings
    [8408] = "Leatherworking|250|8215|1|1|4304:16,8153:6,8172:2", -- Pattern: Wild Leather Cloak
    [8409] = "Leatherworking|210|8192|1|1|4304:8,4338:6,4291:3", -- Pattern: Nightscape Shoulders
    [9293] = "Alchemy|210|9036|1|1|3358:1,8831:1,8925:1", -- Recipe: Magic Resistance Potion
    [9294] = "Alchemy|225|9144|1|1|8153:1,8831:1,8925:1", -- Recipe: Wildvine Potion
    [9295] = "Alchemy|235|9172|1|1|8845:1,8838:1,8925:1", -- Recipe: Invisibility Potion
    [9296] = "Alchemy|240|9088|1|1|8836:1,8839:1,8925:1", -- Recipe: Gift of Arthas
    [9297] = "Alchemy|240|9197|1|1|8831:3,8925:1", -- Recipe: Elixir of Dream Vision
    [9298] = "Alchemy|245|9206|1|1|8838:1,8846:1,8925:1", -- Recipe: Elixir of Giants
    [9300] = "Alchemy|250|9224|1|1|8846:1,8845:1,8925:1", -- Recipe: Elixir of Demonslaying
    [9301] = "Alchemy|250|9264|1|1|8845:3,8925:1", -- Recipe: Elixir of Shadow Power
    [9302] = "Alchemy|245|9210|1|1|8845:2,4342:1,8925:1", -- Recipe: Ghost Dye
    [9303] = "Alchemy|225|9149|1|1|3575:4,9262:1,8831:4,4625:4", -- Recipe: Philosopher's Stone
    [9304] = "Alchemy|225|3577|1|1|3575:1", -- Recipe: Transmute Iron to Gold
    [9305] = "Alchemy|225|6037|1|1|3860:1", -- Recipe: Transmute Mithril to Truesilver
    [9367] = "Blacksmithing|205|9366|1|1|3859:10,3577:4,3486:4,3864:1", -- Plans: Golden Scale Gauntlets
    [10300] = "Tailoring|215|10007|1|1|4339:3,2604:2,8343:1", -- Pattern: Red Mageweave Vest
    [10301] = "Tailoring|215|10008|1|1|4339:1,2324:1,8343:1", -- Pattern: White Bandit Mask
    [10302] = "Tailoring|215|10009|1|1|4339:3,2604:2,8343:1", -- Pattern: Red Mageweave Pants
    [10311] = "Tailoring|220|10052|1|1|4339:2,6261:2,8343:1", -- Pattern: Orange Martial Shirt
    [10312] = "Tailoring|225|10018|1|1|4339:3,2604:2,8343:2", -- Pattern: Red Mageweave Gloves
    [10314] = "Tailoring|230|10054|1|1|4339:2,4342:2,8343:2", -- Pattern: Lavender Mageweave Shirt
    [10315] = "Tailoring|235|10029|1|1|4339:4,2604:2,8343:3", -- Pattern: Red Mageweave Shoulders
    [10316] = "Tailoring|120|10048|1|1|2997:5,2604:3,2321:1", -- Pattern: Colorful Kilt
    [10317] = "Tailoring|235|10055|1|1|4339:3,10290:1,8343:1", -- Pattern: Pink Mageweave Shirt
    [10318] = "Tailoring|240|10030|1|1|4339:3,4589:6,8343:2", -- Pattern: Admiral's Hat
    [10320] = "Tailoring|240|10033|1|1|4339:4,2604:2,8343:2", -- Pattern: Red Mageweave Headband
    [10321] = "Tailoring|240|10034|1|1|4339:4,8343:2", -- Pattern: Tuxedo Shirt
    [10323] = "Tailoring|245|10035|1|1|4339:4,8343:3", -- Pattern: Tuxedo Pants
    [10325] = "Tailoring|250|10040|1|1|4339:5,8343:3,2324:1", -- Pattern: White Wedding Dress
    [10326] = "Tailoring|250|10036|1|1|4339:5,8343:3", -- Pattern: Tuxedo Jacket
    [10424] = "Blacksmithing|155|10423|1|1|2841:12,2842:4,3478:2", -- Plans: Silvered Bronze Leggings
    [10463] = "Tailoring|245|10025|1|1|4339:2,10285:8,8343:2", -- Pattern: Shadoweave Mask
    [10601] = "Engineering|175|10499|1|1|4234:6,3864:2", -- Schematic: Bright-Eye Goggles
    [10602] = "Engineering|210|10546|1|1|10559:1,7909:2,4304:2", -- Schematic: Deadly Scope
    [10603] = "Engineering|220|10501|1|1|4304:4,7909:2,10592:1", -- Schematic: Catseye Ultra Goggles
    [10604] = "Engineering|220|10510|1|1|10559:2,10560:1,4400:1,3860:6,3864:2", -- Schematic: Mithril Heavy-bore Rifle
    [10605] = "Engineering|225|10502|1|1|4304:4,7910:2", -- Schematic: Spellpower Goggles Xtreme
    [10606] = "Engineering|225|10518|1|1|4339:4,10285:2,10560:1,10505:4", -- Schematic: Parachute Cloak
    [10607] = "Engineering|230|10506|1|1|3860:8,10561:1,6037:1,818:4,774:4", -- Schematic: Deepdive Helmet
    [10608] = "Engineering|240|10548|1|1|10559:1,7910:1,6037:2", -- Schematic: Sniper Scope
    [10609] = "Engineering|250|10576|1|1|3860:14,7077:4,6037:4,9060:2,9061:2,7910:2", -- Schematic: Mithril Mechanical Dragonling
    [10644] = "Alchemy|210|9061|1|1|4625:1,9260:1,3372:1", -- Recipe: Goblin Rocket Fuel
    [10713] = "Blacksmithing|200|9060|1|1|3860:5,3577:1,6037:1", -- Plans: Inlaid Mithril Cylinder
    [10728] = "Tailoring|200|4336|1|1|4305:5,2325:1,4291:1", -- Pattern: Black Swashbuckler's Shirt
    [10858] = "Blacksmithing|155|3851|1|1|3575:8,3466:2,3486:1,2842:4,4234:2", -- Plans: Solid Iron Maul
    [11610] = "Blacksmithing|265|11608|1|1|11371:18,7077:4", -- Plans: Dark Iron Pulverizer
    [11611] = "Blacksmithing|275|11607|1|1|11371:26,7077:4", -- Plans: Dark Iron Sunderer
    [11612] = "Blacksmithing|285|11604|1|1|11371:20,7077:8", -- Plans: Dark Iron Plate
    [11614] = "Blacksmithing|270|11606|1|1|11371:10,7077:2", -- Plans: Dark Iron Mail
    [11615] = "Blacksmithing|280|11605|1|1|11371:6,7077:1", -- Plans: Dark Iron Shoulders
    [11813] = "Enchanting|265|11811|1|1|11382:1,7078:1,14343:3", -- Formula: Smoking Heart of the Mountain
    [11827] = "Engineering|205|11826|1|1|7075:1,4389:2,7191:1,3860:2,6037:1", -- Schematic: Lil' Smoky
    [11828] = "Engineering|205|11825|1|1|4394:1,7077:1,7191:1,3860:6", -- Schematic: Pet Bombling
    [12162] = "Blacksmithing|160|3849|1|1|3575:6,3466:2,3486:1,1705:2,4234:3", -- Plans: Hardened Iron Shortsword
    [12163] = "Blacksmithing|180|3853|1|1|3859:8,3466:2,3486:2,1705:3,4234:3", -- Plans: Moonsteel Broadsword
    [12164] = "Blacksmithing|185|3855|1|1|3575:14,3466:2,3486:2,3577:4,4234:2", -- Plans: Massive Iron Axe
    [12226] = "Cooking|1|12224|1|1|12223:1,2678:1", -- Recipe: Crispy Bat Wing
    [12227] = "Cooking|125|12209|1|1|1015:1,2678:1", -- Recipe: Lean Wolf Steak
    [12228] = "Cooking|175|12210|1|1|12184:1,2692:1", -- Recipe: Roast Raptor
    [12229] = "Cooking|175|13851|1|1|12203:1,2692:1", -- Recipe: Hot Wolf Ribs
    [12231] = "Cooking|175|12212|2|2|12202:1,159:1,4536:2", -- Recipe: Jungle Stew
    [12232] = "Cooking|175|12213|1|1|12037:1,2692:1", -- Recipe: Carrion Surprise
    [12233] = "Cooking|175|12214|1|1|12037:1,2596:1", -- Recipe: Mystery Stew
    [12239] = "Cooking|200|12217|1|1|12037:1,4402:1,2692:1", -- Recipe: Dragonbreath Chili
    [12240] = "Cooking|200|12215|2|2|12204:2,3713:1,159:1", -- Recipe: Heavy Kodo Stew
    [12261] = "Blacksmithing|190|12260|1|1|3859:10,3577:4,7068:2,4234:2", -- Plans: Searing Golden Blade
    [12682] = "Blacksmithing|250|12405|1|1|12359:16,12361:1,11188:4", -- Plans: Thorium Armor
    [12683] = "Blacksmithing|250|12406|1|1|12359:12,11186:4", -- Plans: Thorium Belt
    [12684] = "Blacksmithing|255|12408|1|1|12359:12,11184:4", -- Plans: Thorium Bracers
    [12685] = "Blacksmithing|260|12416|1|1|12359:10,7077:2", -- Plans: Radiant Belt
    [12687] = "Blacksmithing|265|12428|1|1|12359:24,8170:6,3864:2", -- Plans: Imperial Plate Shoulders
    [12688] = "Blacksmithing|265|12424|1|1|12359:22,8170:6,7909:1", -- Plans: Imperial Plate Belt
    [12689] = "Blacksmithing|270|12415|1|1|12359:18,7077:2,7910:1", -- Plans: Radiant Breastplate
    [12690] = "Blacksmithing|270|12425|1|1|12359:20,7910:1", -- Plans: Imperial Plate Bracers
    [12691] = "Blacksmithing|270|12624|1|1|12359:40,12655:2,12803:4,8153:4,12364:1", -- Plans: Wildthorn Mail
    [12692] = "Blacksmithing|275|12645|1|1|12359:4,12644:4,7076:2", -- Plans: Thorium Shield Spike
    [12693] = "Blacksmithing|280|12409|1|1|12359:20,8170:8,11185:4", -- Plans: Thorium Boots
    [12694] = "Blacksmithing|280|12410|1|1|12359:24,7910:1,11188:4", -- Plans: Thorium Helm
    [12695] = "Blacksmithing|285|12418|1|1|12359:18,7077:4", -- Plans: Radiant Gloves
    [12696] = "Blacksmithing|285|12628|1|1|12359:40,12662:10,12361:4,7910:4", -- Plans: Demon Forged Breastplate
    [12697] = "Blacksmithing|290|12419|1|1|12359:14,7077:4", -- Plans: Radiant Boots
    [12698] = "Blacksmithing|290|12625|1|1|12359:20,12360:4,12364:2,7080:2", -- Plans: Dawnbringer Shoulders
    [12699] = "Blacksmithing|290|12631|1|1|12359:20,12655:6,7078:2,7910:4", -- Plans: Fiery Plate Gauntlets
    [12700] = "Blacksmithing|295|12426|1|1|12359:34,7910:1,7909:1", -- Plans: Imperial Plate Boots
    [12701] = "Blacksmithing|295|12427|1|1|12359:34,7910:2", -- Plans: Imperial Plate Helm
    [12702] = "Blacksmithing|295|12417|1|1|12359:18,7077:4", -- Plans: Radiant Circlet
    [12703] = "Blacksmithing|295|12632|1|1|12359:20,12655:4,7080:4,12361:4", -- Plans: Storm Gauntlets
    [12704] = "Blacksmithing|300|12414|1|1|12359:26,11186:4", -- Plans: Thorium Leggings
    [12705] = "Blacksmithing|300|12422|1|1|12359:40,7910:2", -- Plans: Imperial Plate Chest
    [12706] = "Blacksmithing|300|12610|1|1|12359:20,12360:2,3577:6", -- Plans: Runic Plate Shoulders
    [12707] = "Blacksmithing|300|12611|1|1|12359:20,12360:2,2842:10", -- Plans: Runic Plate Boots
    [12711] = "Blacksmithing|300|12633|1|1|12359:20,12655:4,6037:6,3577:6,12800:2", -- Plans: Whitesoul Helm
    [12713] = "Blacksmithing|300|12420|1|1|12359:20,7077:4", -- Plans: Radiant Leggings
    [12714] = "Blacksmithing|300|12612|1|1|12359:30,12360:2,6037:2,12364:1", -- Plans: Runic Plate Helm
    [12715] = "Blacksmithing|300|12429|1|1|12359:44,7910:2", -- Plans: Imperial Plate Leggings
    [12716] = "Blacksmithing|300|12636|1|1|12359:40,12655:4,8168:60,12799:6,12364:2", -- Plans: Helm of the Great Chief
    [12717] = "Blacksmithing|300|12640|1|1|12359:80,12360:12,8146:40,12361:10,12800:4", -- Plans: Lionheart Helm
    [12718] = "Blacksmithing|300|12613|1|1|12359:40,12360:2,7910:1", -- Plans: Runic Breastplate
    [12719] = "Blacksmithing|300|12614|1|1|12359:40,12360:2,7910:1", -- Plans: Runic Plate Leggings
    [12720] = "Blacksmithing|300|12639|1|1|12360:15,12655:20,7076:10,12361:4,12799:4", -- Plans: Stronghold Gauntlets
    [12725] = "Blacksmithing|300|12620|1|1|12360:6,12655:16,7076:6,12799:2,12800:1", -- Plans: Enchanted Thorium Helm
    [12726] = "Blacksmithing|300|12619|1|1|12360:10,12655:20,7080:6,12361:2,12364:1", -- Plans: Enchanted Thorium Leggings
    [12727] = "Blacksmithing|300|12618|1|1|12360:8,12655:24,7076:4,7080:4,12364:2,12800:2", -- Plans: Enchanted Thorium Breastplate
    [12728] = "Blacksmithing|300|12641|1|1|12360:30,12655:30,12364:6,12800:6", -- Plans: Invulnerable Mail
    [12819] = "Blacksmithing|275|12773|1|1|12359:20,12799:2,12644:2,8170:4", -- Plans: Ornate Thorium Handaxe
    [12821] = "Blacksmithing|275|12774|1|1|12359:30,12655:4,7910:4,12361:4,12644:2,8170:4", -- Plans: Dawn's Edge
    [12823] = "Blacksmithing|280|12775|1|1|12359:40,12644:6,8170:6", -- Plans: Huge Thorium Battleaxe
    [12824] = "Blacksmithing|280|12776|1|1|12359:20,12655:6,12364:2,12804:4,8170:4", -- Plans: Enchanted Battlehammer
    [12825] = "Blacksmithing|280|12777|1|1|12655:10,7078:4,7077:4,12800:2,12644:2", -- Plans: Blazing Rapier
    [12827] = "Blacksmithing|285|12781|1|1|12655:6,12360:2,12804:4,12799:2,12361:2,12364:1", -- Plans: Serenity
    [12828] = "Blacksmithing|290|12792|1|1|12359:30,7077:4,7910:4,8170:4", -- Plans: Volcanic Hammer
    [12830] = "Blacksmithing|290|12782|1|1|12359:40,12360:2,12662:16,12808:8,12361:2,12644:2,8170:4", -- Plans: Corruption
    [12833] = "Blacksmithing|300|12796|1|1|12359:50,12360:15,12809:4,12810:6,7076:10", -- Plans: Hammer of the Titans
    [12834] = "Blacksmithing|300|12790|1|1|12360:15,12800:8,12811:1,12799:4,12810:8,12644:2", -- Plans: Arcanite Champion
    [12835] = "Blacksmithing|300|12798|1|1|12359:40,12360:12,12808:10,12364:8,12644:2,12810:4", -- Plans: Annihilator
    [12836] = "Blacksmithing|300|12797|1|1|12360:18,12361:8,12800:8,7080:4,12644:2,12810:4", -- Plans: Frostguard
    [12837] = "Blacksmithing|300|12794|1|1|12655:20,12364:8,12799:8,7076:6,12810:4", -- Plans: Masterwork Stormhammer
    [12838] = "Blacksmithing|300|12784|1|1|12360:20,12810:6,12644:2", -- Plans: Arcanite Reaper
    [12839] = "Blacksmithing|300|12783|1|1|12360:10,12655:10,12810:2,7910:6,12800:6,12799:6,12644:4", -- Plans: Heartseeker
    [12958] = "Alchemy|275|12360|1|1|12359:1,12363:1", -- Recipe: Transmute Arcanite
    [13287] = "Leatherworking|165|4455|1|1|4461:6,4234:4,2321:2", -- Pattern: Raptor Hide Harness
    [13288] = "Leatherworking|165|4456|1|1|4461:4,4234:4,2321:2", -- Pattern: Raptor Hide Belt
    [13308] = "Engineering|155|4386|1|1|4375:1,3829:1", -- Schematic: Ice Deflector
    [13309] = "Engineering|120|4372|1|1|4371:2,4359:2,4400:1,1206:3", -- Schematic: Lovingly Crafted Boomstick
    [13310] = "Engineering|180|4407|1|1|4371:1,1529:1,3864:1", -- Schematic: Accurate Scope
    [13311] = "Engineering|200|4396|1|1|4382:1,4387:4,4389:4,3864:2,7191:1", -- Schematic: Mechanical Dragonling
    [13476] = "Alchemy|255|13442|1|1|8846:3,8925:1", -- Recipe: Mighty Rage Potion
    [13477] = "Alchemy|260|13443|1|1|8838:2,8839:2,8925:1", -- Recipe: Superior Mana Potion
    [13478] = "Alchemy|265|13445|1|1|13423:2,8838:1,8925:1", -- Recipe: Elixir of Superior Defense
    [13479] = "Alchemy|270|13447|1|1|13463:1,13466:2,8925:1", -- Recipe: Elixir of the Sages
    [13480] = "Alchemy|275|13446|1|1|13464:2,13465:1,8925:1", -- Recipe: Major Healing Potion
    [13481] = "Alchemy|275|13453|1|1|8846:2,13466:2,8925:1", -- Recipe: Elixir of Brute Force
    [13482] = "Alchemy|275|7078|1|1|7082:1", -- Recipe: Transmute Air to Fire
    [13483] = "Alchemy|275|7076|1|1|7078:1", -- Recipe: Transmute Fire to Earth
    [13484] = "Alchemy|275|7080|1|1|7076:1", -- Recipe: Transmute Earth to Water
    [13485] = "Alchemy|275|7082|1|1|7080:1", -- Recipe: Transmute Water to Air
    [13486] = "Alchemy|275|7080|1|1|12808:1", -- Recipe: Transmute Undeath to Water
    [13487] = "Alchemy|275|12808|1|1|7080:1", -- Recipe: Transmute Water to Undeath
    [13488] = "Alchemy|275|7076|1|1|12803:1", -- Recipe: Transmute Life to Earth
    [13489] = "Alchemy|275|12803|1|1|7076:1", -- Recipe: Transmute Earth to Life
    [13490] = "Alchemy|280|13455|1|1|13423:3,10620:1,8925:1", -- Recipe: Greater Stoneshield Potion
    [13491] = "Alchemy|280|13452|1|1|13465:2,13466:2,8925:1", -- Recipe: Elixir of the Mongoose
    [13492] = "Alchemy|285|13462|1|1|13467:2,13466:2,8925:1", -- Recipe: Purification Potion
    [13493] = "Alchemy|285|13454|1|1|13463:3,13465:1,8925:1", -- Recipe: Greater Arcane Elixir
    [13494] = "Alchemy|290|13457|1|1|7068:1,13463:1,8925:1", -- Recipe: Greater Fire Protection Potion
    [13495] = "Alchemy|290|13456|1|1|7070:1,13463:1,8925:1", -- Recipe: Greater Frost Protection Potion
    [13496] = "Alchemy|290|13458|1|1|7067:1,13463:1,8925:1", -- Recipe: Greater Nature Protection Potion
    [13497] = "Alchemy|290|13461|1|1|11176:1,13463:1,8925:1", -- Recipe: Greater Arcane Protection Potion
    [13499] = "Alchemy|290|13459|1|1|3824:1,13463:1,8925:1", -- Recipe: Greater Shadow Protection Potion
    [13501] = "Alchemy|295|13444|1|1|13463:3,13467:2,8925:1", -- Recipe: Major Mana Potion
    [13518] = "Alchemy|300|13506|1|1|13423:30,13465:10,13468:1,8925:1", -- Recipe: Flask of Petrification
    [13519] = "Alchemy|300|13510|1|1|8846:30,13423:10,13468:1,8925:1", -- Recipe: Flask of the Titans
    [13520] = "Alchemy|300|13511|1|1|13463:30,13467:10,13468:1,8925:1", -- Recipe: Flask of Distilled Wisdom
    [13521] = "Alchemy|300|13512|1|1|13463:30,13465:10,13468:1,8925:1", -- Recipe: Flask of Supreme Power
    [13522] = "Alchemy|300|13513|1|1|13467:30,13465:10,13468:1,8925:1", -- Recipe: Flask of Chromatic Resistance
    [13939] = "Cooking|225|6887|1|1|4603:1", -- Recipe: Spotted Yellowtail
    [13940] = "Cooking|225|13927|1|1|13754:1,3713:1", -- Recipe: Cooked Glossy Mightfish
    [13941] = "Cooking|225|13930|1|1|13758:1", -- Recipe: Filet of Redgill
    [13942] = "Cooking|240|13928|1|1|13755:1,3713:1", -- Recipe: Grilled Squid
    [13943] = "Cooking|240|13929|1|1|13756:1,2692:2", -- Recipe: Hot Smoked Bass
    [13945] = "Cooking|250|13931|1|1|13759:1,159:1", -- Recipe: Nightfin Soup
    [13946] = "Cooking|250|13932|1|1|13760:1", -- Recipe: Poached Sunscale Salmon
    [13947] = "Cooking|275|13933|1|1|13888:1,159:1", -- Recipe: Lobster Stew
    [13948] = "Cooking|275|13934|1|1|13893:1,2692:1,3713:1", -- Recipe: Mightfish Steak
    [13949] = "Cooking|275|13935|1|1|13889:1,3713:1", -- Recipe: Baked Salmon
    [14466] = "Tailoring|255|13869|1|1|14048:5,7079:2,14341:1", -- Pattern: Frostweave Tunic
    [14467] = "Tailoring|255|13868|1|1|14048:5,7079:2,14341:1", -- Pattern: Frostweave Robe
    [14468] = "Tailoring|260|14046|1|1|14048:5,8170:2,14341:1", -- Pattern: Runecloth Bag
    [14469] = "Tailoring|260|13858|1|1|14048:5,14227:1,14341:1", -- Pattern: Runecloth Robe
    [14470] = "Tailoring|260|13857|1|1|14048:5,14227:1,14341:1", -- Pattern: Runecloth Tunic
    [14471] = "Tailoring|260|14042|1|1|14048:5,7077:3,14341:1", -- Pattern: Cindercloth Vest
    [14472] = "Tailoring|265|13860|1|1|14048:4,14227:1,14341:1", -- Pattern: Runecloth Cloak
    [14473] = "Tailoring|265|14143|1|1|14048:3,9210:2,14227:1,14341:1", -- Pattern: Ghostweave Belt
    [14474] = "Tailoring|265|13870|1|1|14048:3,7080:1,14341:1", -- Pattern: Frostweave Gloves
    [14476] = "Tailoring|270|14043|1|1|14048:4,7077:3,14341:1", -- Pattern: Cindercloth Gloves
    [14477] = "Tailoring|270|14142|1|1|14048:4,9210:2,14227:1,14341:1", -- Pattern: Ghostweave Gloves
    [14478] = "Tailoring|270|14100|1|1|14048:5,3577:2,14341:1", -- Pattern: Brightcloth Robe
    [14479] = "Tailoring|270|14101|1|1|14048:4,3577:2,14341:1", -- Pattern: Brightcloth Gloves
    [14480] = "Tailoring|275|14141|1|1|14048:6,9210:4,14227:1,14341:1", -- Pattern: Ghostweave Vest
    [14481] = "Tailoring|275|13863|1|1|14048:4,8170:4,14341:1", -- Pattern: Runecloth Gloves
    [14482] = "Tailoring|275|14044|1|1|14048:5,7078:1,14341:1", -- Pattern: Cindercloth Cloak
    [14483] = "Tailoring|275|14107|1|1|14048:5,14256:4,14341:1", -- Pattern: Felcloth Pants
    [14484] = "Tailoring|275|14103|1|1|14048:4,3577:2,14341:1", -- Pattern: Brightcloth Cloak
    [14485] = "Tailoring|275|14132|1|1|14048:6,11176:1,14341:1", -- Pattern: Wizardweave Leggings
    [14486] = "Tailoring|275|14134|1|1|14048:6,7078:4,7077:4,7068:4,14341:1", -- Pattern: Cloak of Fire
    [14488] = "Tailoring|280|13864|1|1|14048:4,14227:2,8170:4,14341:1", -- Pattern: Runecloth Boots
    [14489] = "Tailoring|280|13871|1|1|14048:6,7080:1,14341:1", -- Pattern: Frostweave Pants
    [14490] = "Tailoring|280|14045|1|1|14048:6,7078:1,14341:1", -- Pattern: Cindercloth Pants
    [14491] = "Tailoring|285|13865|1|1|14048:6,14227:2,14341:1", -- Pattern: Runecloth Pants
    [14492] = "Tailoring|285|14108|1|1|14048:6,14256:4,8170:4,14341:1", -- Pattern: Felcloth Boots
    [14493] = "Tailoring|285|14136|1|1|14048:10,14256:12,12808:4,7080:4,14341:1", -- Pattern: Robe of Winter Night
    [14494] = "Tailoring|290|14104|1|1|14048:6,3577:4,14227:1,14341:1", -- Pattern: Brightcloth Pants
    [14495] = "Tailoring|290|14144|1|1|14048:6,9210:4,14341:1", -- Pattern: Ghostweave Pants
    [14496] = "Tailoring|290|14111|1|1|14048:5,14256:4,14341:1", -- Pattern: Felcloth Hood
    [14497] = "Tailoring|290|14137|1|1|14048:6,14342:4,14341:1", -- Pattern: Mooncloth Leggings
    [14498] = "Tailoring|295|13866|1|1|14048:4,14227:2,14341:1", -- Pattern: Runecloth Headband
    [14499] = "Tailoring|300|14155|1|1|14048:4,14342:1,14341:1", -- Pattern: Mooncloth Bag
    [14500] = "Tailoring|300|14128|1|1|14048:8,11176:2,14341:1", -- Pattern: Wizardweave Robe
    [14501] = "Tailoring|300|14138|1|1|14048:6,14342:4,14341:1", -- Pattern: Mooncloth Vest
    [14504] = "Tailoring|300|13867|1|1|14048:7,14227:2,8170:4,14341:1", -- Pattern: Runecloth Shoulders
    [14505] = "Tailoring|300|14130|1|1|14048:6,11176:4,7910:1,14341:1", -- Pattern: Wizardweave Turban
    [14506] = "Tailoring|300|14106|1|1|14048:8,14256:8,12662:4,14341:2", -- Pattern: Felcloth Robe
    [14507] = "Tailoring|300|14139|1|1|14048:5,14342:5,14341:1", -- Pattern: Mooncloth Shoulders
    [14508] = "Tailoring|300|14112|1|1|14048:7,14256:6,12662:4,8170:4,14341:2", -- Pattern: Felcloth Shoulders
    [14509] = "Tailoring|300|14140|1|1|14048:4,14342:6,12800:1,12810:2,14341:2", -- Pattern: Mooncloth Circlet
    [14510] = "Tailoring|300|14156|1|1|14048:8,14342:12,14344:2,17012:2,14341:2", -- Pattern: Bottomless Bag
    [14511] = "Tailoring|300|14146|1|1|14048:10,14342:10,9210:10,13926:6,12364:6,12810:8,14341:2", -- Pattern: Gloves of Spell Mastery
    [14512] = "Tailoring|300|14154|1|1|14048:12,14342:10,12811:4,13926:4,9210:10,14341:2", -- Pattern: Truefaith Vestments
    [14513] = "Tailoring|300|14152|1|1|14048:12,7078:10,7082:10,7076:10,7080:10,14341:2", -- Pattern: Robe of the Archmage
    [14514] = "Tailoring|300|14153|1|1|14048:12,12662:20,14256:40,7078:12,12808:12,14341:2", -- Pattern: Robe of the Void
    [14526] = "Tailoring|250|14342|1|1|14256:2", -- Pattern: Mooncloth
    [14627] = "Tailoring|135|4332|1|1|4305:1,4341:1,2321:1", -- Pattern: Bright Yellow Shirt
    [14630] = "Tailoring|165|4322|1|1|4305:3,2321:2,4337:2", -- Pattern: Enchanter's Cowl
    [14634] = "Alchemy|200|3829|1|1|3358:4,3819:2,3372:1", -- Recipe: Frost Oil
    [14635] = "Leatherworking|185|4262|1|1|4236:4,5500:2,1529:2,3864:1,2321:1", -- Pattern: Gem-studded Leather Belt
    [14639] = "Engineering|140|4381|1|1|4371:1,4375:2,2319:2,1206:1", -- Schematic: Minor Recombobulator
    [15724] = "Leatherworking|255|15077|1|1|8170:4,15408:4,14341:1", -- Pattern: Heavy Scorpid Bracers
    [15725] = "Leatherworking|260|15083|1|1|8170:8,2325:1,14341:1", -- Pattern: Wicked Leather Gauntlets
    [15726] = "Leatherworking|260|15045|1|1|8170:20,15412:25,14341:2", -- Pattern: Green Dragonscale Breastplate
    [15727] = "Leatherworking|265|15076|1|1|8170:6,15408:6,14341:1", -- Pattern: Heavy Scorpid Vest
    [15728] = "Leatherworking|265|15084|1|1|8170:8,2325:1,14341:1", -- Pattern: Wicked Leather Bracers
    [15729] = "Leatherworking|265|15074|1|1|8170:6,15423:6,14341:1", -- Pattern: Chimeric Gloves
    [15730] = "Leatherworking|300|15047|1|1|8170:40,15414:30,14341:1", -- Pattern: Red Dragonscale Breastplate
    [15731] = "Leatherworking|270|15091|1|1|8170:10,14047:6,14341:1", -- Pattern: Runic Leather Gauntlets
    [15732] = "Leatherworking|270|15054|1|1|8170:6,7078:1,7075:1,14341:1", -- Pattern: Volcanic Leggings
    [15733] = "Leatherworking|270|15046|1|1|8170:20,15412:25,14341:1", -- Pattern: Green Dragonscale Leggings
    [15734] = "Leatherworking|270|15061|1|1|8170:12,12803:4,14341:1", -- Pattern: Living Shoulders
    [15735] = "Leatherworking|270|15067|1|1|8170:24,15420:80,1529:2,14341:1", -- Pattern: Ironfeather Shoulders
    [15737] = "Leatherworking|275|15073|1|1|8170:4,15423:8,14341:1", -- Pattern: Chimeric Boots
    [15738] = "Leatherworking|275|15078|1|1|8170:6,15408:8,14341:1", -- Pattern: Heavy Scorpid Gauntlets
    [15739] = "Leatherworking|275|15092|1|1|8170:6,7971:1,14047:6,14341:1", -- Pattern: Runic Leather Bracers
    [15740] = "Leatherworking|275|15071|1|1|8170:4,15422:6,14341:1", -- Pattern: Frostsaber Boots
    [15741] = "Leatherworking|275|15057|1|1|8170:16,7080:2,7082:2,14341:1", -- Pattern: Stormshroud Pants
    [15742] = "Leatherworking|275|15064|1|1|8170:28,15419:12,14341:1", -- Pattern: Warbear Harness
    [15743] = "Leatherworking|280|15082|1|1|8170:6,15408:8,14341:1", -- Pattern: Heavy Scorpid Belt
    [15744] = "Leatherworking|280|15086|1|1|8170:12,2325:1,14341:1", -- Pattern: Wicked Leather Headband
    [15745] = "Leatherworking|280|15093|1|1|8170:12,14047:10,14341:1", -- Pattern: Runic Leather Belt
    [15746] = "Leatherworking|280|15072|1|1|8170:8,15423:8,14341:1", -- Pattern: Chimeric Leggings
    [15747] = "Leatherworking|285|15069|1|1|8170:6,15422:8,14341:1", -- Pattern: Frostsaber Leggings
    [15748] = "Leatherworking|285|15079|1|1|8170:8,15408:12,14341:1", -- Pattern: Heavy Scorpid Leggings
    [15749] = "Leatherworking|285|15053|1|1|8170:8,7078:1,7076:1,14341:1", -- Pattern: Volcanic Breastplate
    [15751] = "Leatherworking|285|15048|1|1|8170:28,15415:30,15407:1,14341:1", -- Pattern: Blue Dragonscale Breastplate
    [15752] = "Leatherworking|285|15060|1|1|8170:16,12803:6,15407:1,14341:1", -- Pattern: Living Leggings
    [15753] = "Leatherworking|285|15056|1|1|8170:16,7080:3,7082:3,15407:1,14341:1", -- Pattern: Stormshroud Armor
    [15754] = "Leatherworking|285|15065|1|1|8170:24,15419:14,14341:1", -- Pattern: Warbear Woolies
    [15755] = "Leatherworking|290|15075|1|1|8170:10,15423:10,14341:1", -- Pattern: Chimeric Vest
    [15756] = "Leatherworking|290|15094|1|1|8170:14,14047:10,14341:1", -- Pattern: Runic Leather Headband
    [15757] = "Leatherworking|290|15087|1|1|8170:16,15407:1,2325:3,14341:1", -- Pattern: Wicked Leather Pants
    [15758] = "Leatherworking|290|15063|1|1|8170:30,15417:8,14341:1", -- Pattern: Devilsaur Gauntlets
    [15759] = "Leatherworking|290|15050|1|1|8170:40,15416:60,15407:1,14341:2", -- Pattern: Black Dragonscale Breastplate
    [15760] = "Leatherworking|290|15066|1|1|8170:40,15420:120,1529:1,15407:1,14341:1", -- Pattern: Ironfeather Breastplate
    [15761] = "Leatherworking|295|15070|1|1|8170:6,15422:10,14341:1", -- Pattern: Frostsaber Gloves
    [15762] = "Leatherworking|295|15080|1|1|8170:8,15408:12,15407:1,14341:1", -- Pattern: Heavy Scorpid Helm
    [15763] = "Leatherworking|295|15049|1|1|8170:28,15415:30,12810:2,15407:1,14341:1", -- Pattern: Blue Dragonscale Shoulders
    [15764] = "Leatherworking|295|15058|1|1|8170:12,7080:3,7082:3,12810:2,14341:1", -- Pattern: Stormshroud Shoulders
    [15765] = "Leatherworking|300|15095|1|1|8170:18,14047:12,12810:2,14341:1", -- Pattern: Runic Leather Pants
    [15768] = "Leatherworking|300|15088|1|1|8170:14,2325:2,14341:2", -- Pattern: Wicked Leather Belt
    [15769] = "Leatherworking|300|15138|1|1|15410:1,14044:1,14341:1", -- Pattern: Onyxia Scale Cloak
    [15770] = "Leatherworking|300|15051|1|1|8170:44,15416:45,12810:2,15407:1,14341:1", -- Pattern: Black Dragonscale Shoulders
    [15771] = "Leatherworking|300|15059|1|1|8170:16,12803:8,14342:2,15407:1,14341:2", -- Pattern: Living Breastplate
    [15772] = "Leatherworking|300|15062|1|1|8170:30,15417:14,15407:1,14341:1", -- Pattern: Devilsaur Leggings
    [15773] = "Leatherworking|300|15085|1|1|8170:20,15407:2,14256:6,2325:4,14341:2", -- Pattern: Wicked Leather Armor
    [15774] = "Leatherworking|300|15081|1|1|8170:14,15408:14,15407:1,14341:2", -- Pattern: Heavy Scorpid Shoulders
    [15775] = "Leatherworking|300|15055|1|1|8170:10,7078:1,7076:1,14341:2", -- Pattern: Volcanic Shoulders
    [15776] = "Leatherworking|300|15090|1|1|8170:22,12810:4,14047:16,15407:1,14341:2", -- Pattern: Runic Leather Armor
    [15777] = "Leatherworking|300|15096|1|1|8170:16,12810:4,14047:18,15407:1,14341:2", -- Pattern: Runic Leather Shoulders
    [15779] = "Leatherworking|300|15068|1|1|8170:12,15422:12,15407:1,14341:2", -- Pattern: Frostsaber Tunic
    [15781] = "Leatherworking|300|15052|1|1|8170:40,15416:60,12810:4,15407:1,14341:2", -- Pattern: Black Dragonscale Leggings
    [16041] = "Engineering|260|15993|3|3|15994:1,12359:3,15992:3,14047:3", -- Schematic: Thorium Grenade
    [16042] = "Engineering|260|15994|1|1|12359:3,14047:1", -- Schematic: Thorium Widget
    [16043] = "Engineering|260|15995|1|1|10559:2,10561:2,15994:2,12359:4,10546:1", -- Schematic: Thorium Rifle
    [16044] = "Engineering|265|15996|1|1|12803:1,15994:4,10558:1,8170:1", -- Schematic: Lifelike Mechanical Toad
    [16045] = "Engineering|270|15999|1|1|10502:1,7910:4,12810:2,14047:8", -- Schematic: Spellpower Goggles Xtreme Plus
    [16046] = "Engineering|275|16023|1|1|10561:1,16000:1,15994:2,6037:1,8170:2,14047:4", -- Schematic: Masterwork Target Dummy
    [16047] = "Engineering|275|16000|1|1|12359:6", -- Schematic: Thorium Tube
    [16048] = "Engineering|275|16004|1|1|16000:2,11371:6,10546:2,12361:2,12799:2,8170:4", -- Schematic: Dark Iron Rifle
    [16049] = "Engineering|285|16005|3|3|15994:2,11371:1,15992:3,14047:3", -- Schematic: Dark Iron Bomb
    [16050] = "Engineering|285|16006|1|1|12360:1,14227:1", -- Schematic: Delicate Arcanite Converter
    [16051] = "Engineering|285|15997|200|200|12359:2,15992:1", -- Schematic: Thorium Shells
    [16052] = "Engineering|290|16009|1|1|16006:2,10558:1,15994:1,12799:1", -- Schematic: Voice Amplification Modulator
    [16053] = "Engineering|290|16008|1|1|10500:1,12364:2,12810:4", -- Schematic: Master Engineer's Goggles
    [16054] = "Engineering|300|16022|1|1|10576:1,16006:8,12655:10,15994:6,10558:4,12810:6", -- Schematic: Arcanite Dragonling
    [16055] = "Engineering|300|16040|3|3|16006:1,12359:3,14047:1", -- Schematic: Arcane Bomb
    [16056] = "Engineering|300|16007|1|1|12360:10,16000:2,7078:2,7076:2,12800:2,12810:2", -- Schematic: Flawless Arcanite Rifle
    [16110] = "Cooking|225|12218|1|1|12207:1,3713:2", -- Recipe: Monster Omelet
    [16111] = "Cooking|225|12216|1|1|12206:1,2692:2", -- Recipe: Spiced Chili Crab
    [16112] = "First Aid|180|6451|1|1|4306:2", -- Manual: Heavy Silk Bandage
    [16113] = "First Aid|210|8544|1|1|4338:1", -- Manual: Mageweave Bandage
    [16243] = "Enchanting|290|16207|1|1|16206:1,13926:1,16204:10,16203:4,14343:4,14344:2", -- Formula: Runed Arcanite Rod
    [16767] = "Cooking|225|16766|2|2|7974:2,2692:1,1179:1", -- Recipe: Undermine Clam Chowder
    [17017] = "Tailoring|300|16980|1|1|14048:12,17010:4,17011:4,12810:6,14341:2", -- Pattern: Flarecore Mantle
    [17018] = "Tailoring|300|16979|1|1|14048:8,17010:6,7078:4,12810:2,14341:2", -- Pattern: Flarecore Gloves
    [17022] = "Leatherworking|295|16982|1|1|17012:20,17010:6,17011:2,14341:2", -- Pattern: Corehound Boots
    [17023] = "Leatherworking|300|16983|1|1|17012:15,17010:3,17011:6,14341:2", -- Pattern: Molten Helm
    [17025] = "Leatherworking|300|16984|1|1|12810:6,15416:30,17010:4,17011:3,14341:2", -- Pattern: Black Dragonscale Boots
    [17049] = "Blacksmithing|295|16989|1|1|11371:6,17010:3,17011:3", -- Plans: Fiery Chain Girdle
    [17051] = "Blacksmithing|295|17014|1|1|11371:4,17010:2,17011:2", -- Plans: Dark Iron Bracers
    [17052] = "Blacksmithing|300|17013|1|1|11371:16,17010:4,17011:6", -- Plans: Dark Iron Leggings
    [17053] = "Blacksmithing|300|16988|1|1|11371:16,17010:4,17011:5", -- Plans: Fiery Chain Shoulders
    [17059] = "Blacksmithing|300|17015|1|1|11371:16,17010:12,11382:2,12810:2", -- Plans: Dark Iron Reaver
    [17060] = "Blacksmithing|300|17016|1|1|11371:18,17011:12,11382:2,12810:2", -- Plans: Dark Iron Destroyer
    [17062] = "Cooking|175|8364|1|1|8365:1", -- Recipe: Mithril Head Trout
    [17200] = "Cooking|1|17197|1|1|6889:1,17194:1", -- Recipe: Gingerbread Cookie
    [17201] = "Cooking|35|17198|1|1|6889:1,1179:1,17196:1,17194:1", -- Recipe: Egg Nog
    [17706] = "Blacksmithing|190|17704|1|1|3859:10,3829:1,7070:2,7069:2,4234:2", -- Plans: Edge of Winter
    [17709] = "Alchemy|190|17708|1|1|3819:2,3358:1,3372:1", -- Recipe: Elixir of Frost Power
    [17720] = "Engineering|190|17716|1|1|3860:8,4389:4,17202:4,3829:1", -- Schematic: Snowmaster 9000
    [17722] = "Leatherworking|190|17721|1|1|4234:8,7067:4,4291:1", -- Pattern: Gloves of the Greatfather
    [17724] = "Tailoring|190|17723|1|1|4305:5,2605:4,4291:1", -- Pattern: Green Holiday Shirt
    [18046] = "Cooking|225|18045|1|1|12208:1,3713:1", -- Recipe: Tender Wolf Steak
    [18160] = "Cooking|60|7676|1|1|2452:1,159:1", -- Recipe: Thistle Tea
    [18235] = "Engineering|300|18232|1|1|12359:12,8170:4,7191:1,7067:2,7068:1", -- Schematic: Field Repair Bot 74A
    [18239] = "Leatherworking|200|18238|1|1|4304:6,7428:8,7971:2,4236:2,1210:4,8343:1", -- Pattern: Shadowskin Gloves
    [18252] = "Leatherworking|300|18251|1|1|17012:3,14341:2", -- Pattern: Core Armor Kit
    [18257] = "Alchemy|300|18253|1|1|10286:1,13464:4,13463:4,18256:1", -- Recipe: Major Rejuvenation Potion
    [18264] = "Blacksmithing|300|18262|1|1|7067:2,12365:3", -- Plans: Elemental Sharpening Stone
    [18265] = "Tailoring|300|18263|1|1|14342:6,17010:8,7078:2,12810:6,14341:4", -- Pattern: Flarecore Wraps
    [18267] = "Cooking|275|18254|1|1|18255:1,3713:1", -- Recipe: Runn Tum Tuber Surprise
    [18290] = "Engineering|300|18283|1|1|17011:2,7076:2,16006:4,11371:6,16000:1", -- Schematic: Biznicks 247x128 Accurascope
    [18291] = "Engineering|300|18168|1|1|12360:6,16006:2,7082:8,12803:12,7076:8", -- Schematic: Force Reactive Disk
    [18292] = "Engineering|300|18282|1|1|17010:4,17011:2,12360:6,16006:2,16000:2", -- Schematic: Core Marksman Rifle
    [18414] = "Tailoring|300|18405|1|1|14048:16,9210:10,14342:10,7080:12,7078:12,14344:6,14341:6", -- Pattern: Belt of the Archmage
    [18415] = "Tailoring|300|18407|1|1|14048:12,14256:20,12662:6,12808:8,14341:2", -- Pattern: Felcloth Gloves
    [18416] = "Tailoring|300|18408|1|1|14048:12,7078:10,7910:2,14341:2", -- Pattern: Inferno Gloves
    [18417] = "Tailoring|300|18409|1|1|14048:12,14342:6,13926:2,14341:2", -- Pattern: Mooncloth Gloves
    [18418] = "Tailoring|300|18413|1|1|14048:12,12809:4,12360:1,14341:2", -- Pattern: Cloak of Warding
    [18487] = "Tailoring|300|18486|1|1|14048:6,14342:4,13926:2,14341:2", -- Pattern: Mooncloth Robe
    [18514] = "Leatherworking|300|18504|1|1|8170:12,12804:12,15407:2,14341:4", -- Pattern: Girdle of Insight
    [18515] = "Leatherworking|300|18506|1|1|8170:12,7082:6,11754:4,15407:2,14341:4", -- Pattern: Mongoose Boots
    [18516] = "Leatherworking|300|18508|1|1|8170:12,18512:8,15420:60,15407:4,14341:4", -- Pattern: Swift Flight Bracers
    [18517] = "Leatherworking|300|18509|1|1|8170:30,12607:12,15416:30,15414:30,15407:5,14341:8", -- Pattern: Chromatic Cloak
    [18518] = "Leatherworking|300|18510|1|1|8170:30,12803:12,7080:10,18512:8,15407:3,14341:8", -- Pattern: Hide of the Wild
    [18519] = "Leatherworking|300|18511|1|1|8170:30,7082:12,12753:4,12809:8,15407:4,14341:8", -- Pattern: Shifting Cloak
    [18592] = "Blacksmithing|300|17193|1|1|17203:8,11371:20,12360:50,7078:25,11382:10,17011:10,17010:10", -- Plans: Sulfuron Hammer
    [18647] = "Engineering|150|9318|3|3|4377:1,4234:1", -- Schematic: Red Firework
    [18648] = "Engineering|150|9313|3|3|4377:1,4234:1", -- Schematic: Green Firework
    [18649] = "Engineering|150|9312|3|3|4377:1,4234:1", -- Schematic: Blue Firework
    [18650] = "Engineering|200|18588|1|1|10505:1,4338:2", -- Schematic: EZ-Thro Dynamite II
    [18651] = "Engineering|260|18631|1|1|6037:2,7067:2,7069:1", -- Schematic: Truesilver Transformer
    [18652] = "Engineering|260|18634|1|1|15994:6,18631:2,12361:2,7078:4,3829:2,13467:4", -- Schematic: Gyrofreeze Ice Reflector
    [18653] = "Engineering|265|18587|1|1|15994:2,18631:2,7191:2,14227:2,7910:2", -- Schematic: Goblin Jumper Cables XL
    [18654] = "Engineering|265|18645|1|1|12359:4,15994:2,8170:4,7910:1,7191:1", -- Schematic: Gnomish Alarm-O-Bot
    [18655] = "Engineering|275|18637|1|1|16000:2,18631:1,14047:2", -- Schematic: Major Recombobulator
    [18656] = "Engineering|275|18594|1|1|15994:2,15992:3,8170:2,159:1", -- Schematic: Powerful Seaforium Charge
    [18657] = "Engineering|290|18638|1|1|11371:4,18631:3,7080:6,7910:4,12800:2", -- Schematic: Hyper-Radiant Flame Reflector
    [18658] = "Engineering|300|18639|1|1|11371:8,18631:4,12803:6,12808:4,12800:2,12799:2", -- Schematic: Ultra-Flash Shadow Reflector
    [18661] = "Engineering|260|18660|1|1|10561:1,15994:2,10558:1,10560:1,3864:1", -- Schematic: World Enlarger
    [18731] = "Leatherworking|150|18662|1|1|4234:2,2321:1", -- Pattern: Heavy Leather Ball
    [18949] = "Leatherworking|155|18948|1|1|4234:8,4236:2,5498:4,4461:1,5637:4", -- Pattern: Barbaric Bracers
    [19027] = "Engineering|250|19026|4|4|15992:2,14047:2,8150:1", -- Schematic: Snake Burst Firework
    [19202] = "Blacksmithing|290|19043|1|1|12359:12,7076:3,12803:3", -- Plans: Heavy Timbermaw Belt
    [19203] = "Blacksmithing|290|19051|1|1|12359:8,6037:6,12811:1", -- Plans: Girdle of the Dawn
    [19204] = "Blacksmithing|300|19048|1|1|12360:4,7076:6,12803:6", -- Plans: Heavy Timbermaw Boots
    [19205] = "Blacksmithing|300|19057|1|1|12360:2,6037:10,12811:1", -- Plans: Gloves of the Dawn
    [19206] = "Blacksmithing|300|19148|1|1|17011:4,17010:2,11371:4", -- Plans: Dark Iron Helm
    [19207] = "Blacksmithing|300|19164|1|1|17011:3,17010:5,17012:4,11371:4,11382:2", -- Plans: Dark Iron Gauntlets
    [19208] = "Blacksmithing|300|19166|1|1|17011:3,17010:6,12360:12,11382:1,11371:4", -- Plans: Black Amnesty
    [19209] = "Blacksmithing|300|19167|1|1|17011:5,17010:2,12360:16,11371:6", -- Plans: Blackfury
    [19210] = "Blacksmithing|300|19170|1|1|17011:4,17010:7,12360:12,11371:8,12800:4", -- Plans: Ebon Hand
    [19211] = "Blacksmithing|300|19168|1|1|17011:6,17010:6,12360:10,11371:6,12809:12", -- Plans: Blackguard
    [19212] = "Blacksmithing|300|19169|1|1|17011:8,17010:5,12360:10,11371:12,12364:4", -- Plans: Nightfall
    [19215] = "Tailoring|290|19047|1|1|14048:8,7076:3,12803:3,14227:2", -- Pattern: Wisdom of the Timbermaw
    [19216] = "Tailoring|290|19056|1|1|14048:6,12810:4,13926:2,12809:2,14227:2", -- Pattern: Argent Boots
    [19217] = "Tailoring|300|19059|1|1|14342:5,12809:2,14227:2", -- Pattern: Argent Shoulders
    [19218] = "Tailoring|300|19050|1|1|14342:5,7076:5,12803:5,14227:2", -- Pattern: Mantle of the Timbermaw
    [19219] = "Tailoring|300|19156|1|1|14342:10,17010:2,17011:3,7078:6,14227:4", -- Pattern: Flarecore Robe
    [19220] = "Tailoring|300|19165|1|1|14342:8,17010:5,17011:3,7078:10,14227:4", -- Pattern: Flarecore Leggings
    [19326] = "Leatherworking|290|19044|1|1|8170:30,12804:2,12803:4,15407:2,14341:2", -- Pattern: Might of the Timbermaw
    [19327] = "Leatherworking|300|19049|1|1|12810:8,12804:6,12803:6,15407:2,14227:2", -- Pattern: Timbermaw Brawlers
    [19328] = "Leatherworking|290|19052|1|1|8170:30,12809:2,7080:4,15407:2,14341:2", -- Pattern: Dawn Treaders
    [19329] = "Leatherworking|300|19058|1|1|12810:8,12803:4,12809:4,15407:2,14341:2", -- Pattern: Golden Mantle of the Dawn
    [19330] = "Leatherworking|300|19149|1|1|17011:5,15407:4,14227:4", -- Pattern: Lava Belt
    [19331] = "Leatherworking|300|19157|1|1|17010:5,17011:2,17012:4,12607:4,15407:4,14227:4", -- Pattern: Chromatic Gauntlets
    [19332] = "Leatherworking|300|19162|1|1|17010:8,17012:12,12810:10,15407:4,14227:4", -- Pattern: Corehound Belt
    [19333] = "Leatherworking|300|19163|1|1|17010:2,17011:7,7076:6,15407:4,14227:4", -- Pattern: Molten Belt
    [19442] = "First Aid|300|19440|1|1|19441:1", -- Formula: Powerful Anti-Venom
    [19764] = "Tailoring|300|19682|1|1|14342:3,19726:5,12804:4,14048:4,14227:2", -- Pattern: Bloodvine Vest
    [19765] = "Tailoring|300|19683|1|1|14342:4,19726:4,12804:4,14048:4,14227:2", -- Pattern: Bloodvine Leggings
    [19766] = "Tailoring|300|19684|1|1|14342:3,19726:3,12810:4,14048:4,14227:4", -- Pattern: Bloodvine Boots
    [19769] = "Leatherworking|300|19685|1|1|19767:14,15407:5,12803:4,14341:4", -- Pattern: Primal Batskin Jerkin
    [19770] = "Leatherworking|300|19686|1|1|19767:10,15407:4,12803:4,14341:3", -- Pattern: Primal Batskin Gloves
    [19771] = "Leatherworking|300|19687|1|1|19767:8,15407:3,12803:4,14341:3", -- Pattern: Primal Batskin Bracers
    [19772] = "Leatherworking|300|19688|1|1|19768:35,19726:2,15407:3,14341:3", -- Pattern: Blood Tiger Breastplate
    [19773] = "Leatherworking|300|19689|1|1|19768:25,19726:2,15407:3,14341:3", -- Pattern: Blood Tiger Shoulders
    [19776] = "Blacksmithing|300|19690|1|1|12359:20,19774:10,19726:2,7910:2", -- Plans: Bloodsoul Breastplate
    [19777] = "Blacksmithing|300|19691|1|1|12359:16,19774:8,19726:2,7910:1", -- Plans: Bloodsoul Shoulders
    [19778] = "Blacksmithing|300|19692|1|1|12359:12,19774:6,19726:2,12810:4", -- Plans: Bloodsoul Gauntlets
    [19779] = "Blacksmithing|300|19693|1|1|12359:20,19774:14,12799:2", -- Plans: Darksoul Breastplate
    [19780] = "Blacksmithing|300|19694|1|1|12359:18,19774:12,12799:2", -- Plans: Darksoul Leggings
    [19781] = "Blacksmithing|300|19695|1|1|12359:16,19774:10,12799:1", -- Plans: Darksoul Shoulders
    [20000] = "Engineering|300|19999|1|1|19726:4,19774:5,16006:2,12804:8,12810:4", -- Schematic: Bloodvine Goggles
    [20001] = "Engineering|300|19998|1|1|19726:5,19774:5,16006:1,12804:8,12810:4", -- Schematic: Bloodvine Lens
    [20011] = "Alchemy|275|20007|1|1|13463:1,13466:2,8925:1", -- Recipe: Mageblood Potion
    [20012] = "Alchemy|275|20002|1|1|13463:2,13464:1,8925:1", -- Recipe: Greater Dreamless Sleep
    [20013] = "Alchemy|285|20008|1|1|13467:2,13465:2,10286:2,8925:1", -- Recipe: Living Action Potion
    [20014] = "Alchemy|290|20004|1|1|8846:1,13466:2,8925:1", -- Recipe: Major Troll's Blood Potion
    [20040] = "Blacksmithing|300|20039|1|1|17011:3,17010:3,17012:4,11371:6", -- Plans: Dark Iron Boots
    [20075] = "Cooking|150|20074|1|1|3667:2,3713:1", -- Recipe: Heavy Crocolisk Stew
    [20253] = "Leatherworking|275|15064|1|1|8170:28,15419:12,14341:1", -- Pattern: Warbear Harness
    [20254] = "Leatherworking|285|15065|1|1|8170:24,15419:14,14341:1", -- Pattern: Warbear Woolies
    [20382] = "Leatherworking|300|20380|1|1|12810:12,20381:6,12803:4,15407:4,14227:6", -- Pattern: Dreamscale Breastplate
    [20506] = "Leatherworking|300|20481|1|1|20500:1,20498:20,7078:2", -- Pattern: Spitfire Bracers
    [20507] = "Leatherworking|300|20480|1|1|20500:2,20498:30,7078:2,15407:1", -- Pattern: Spitfire Gauntlets
    [20508] = "Leatherworking|300|20479|1|1|20500:3,20498:40,7078:2,15407:2", -- Pattern: Spitfire Breastplate
    [20509] = "Leatherworking|300|20476|1|1|20501:1,20498:20,18512:2", -- Pattern: Sandstalker Bracers
    [20510] = "Leatherworking|300|20477|1|1|20501:2,20498:30,18512:2,15407:1", -- Pattern: Sandstalker Gauntlets
    [20511] = "Leatherworking|300|20478|1|1|20501:3,20498:40,18512:2,15407:2", -- Pattern: Sandstalker Breastplate
    [20546] = "Tailoring|300|20538|1|1|14048:6,20520:8,14256:6,14227:2", -- Pattern: Runed Stygian Leggings
    [20547] = "Tailoring|300|20537|1|1|14048:4,20520:6,14256:4,12810:2,14227:2", -- Pattern: Runed Stygian Boots
    [20548] = "Tailoring|300|20539|1|1|14048:2,20520:6,14256:2,12810:2,14227:2", -- Pattern: Runed Stygian Belt
    [20553] = "Blacksmithing|300|20549|1|1|12359:12,20520:6,6037:6,12810:2", -- Plans: Darkrune Gauntlets
    [20554] = "Blacksmithing|300|20550|1|1|12359:20,20520:10,6037:10", -- Plans: Darkrune Breastplate
    [20555] = "Blacksmithing|300|20551|1|1|12359:16,20520:8,6037:8,11754:1", -- Plans: Darkrune Helm
    [20576] = "Leatherworking|100|20575|1|1|2319:8,7286:8,4231:1,2321:2", -- Pattern: Black Whelp Tunic
    [20752] = "Enchanting|150|20745|1|1|11083:3,17034:2,3372:1", -- Formula: Minor Mana Oil
    [20753] = "Enchanting|200|20746|1|1|11137:3,17035:2,3372:1", -- Formula: Lesser Wizard Oil
    [20754] = "Enchanting|250|20747|1|1|11176:3,8831:2,8925:1", -- Formula: Lesser Mana Oil
    [20755] = "Enchanting|275|20750|1|1|16204:3,4625:2,8925:1", -- Formula: Wizard Oil
    [20756] = "Enchanting|300|20749|1|1|14344:2,4625:3,18256:1", -- Formula: Brilliant Wizard Oil
    [20757] = "Enchanting|300|20748|1|1|14344:2,8831:3,18256:1", -- Formula: Brilliant Mana Oil
    [20758] = "Enchanting|45|20744|1|1|10940:2,17034:1,3371:1", -- Formula: Minor Wizard Oil
    [20761] = "Alchemy|300|7068|3|3|7077:1", -- Recipe: Transmute Elemental Fire
    [21025] = "Cooking|300|21023|5|5|2692:1,9061:1,8150:1,21024:1", -- Recipe: Dirge's Kickin' Chimaerok Chops
    [21099] = "Cooking|80|21072|1|1|21071:1,2678:1", -- Recipe: Smoked Sagefish
    [21219] = "Cooking|175|21217|1|1|21153:1,2692:1", -- Recipe: Sagefish Delight
    [21358] = "Tailoring|260|21340|1|1|14048:6,8170:4,7972:2,14341:1", -- Pattern: Soul Pouch
    [21369] = "Tailoring|285|21341|1|1|14256:12,12810:6,20520:2,14227:4", -- Pattern: Felcloth Bag
    [21371] = "Tailoring|300|21342|1|1|14256:20,17012:16,19726:8,7078:4,14227:4", -- Pattern: Core Felcloth Bag
    [21547] = "Alchemy|250|21546|1|1|6371:3,4625:3,8925:1", -- Recipe: Elixir of Greater Firepower
    [21548] = "Leatherworking|300|21278|1|1|12810:6,7080:4,7082:4,15407:2,14227:2", -- Pattern: Stormshroud Gloves
    [21722] = "Tailoring|250|21154|1|1|14048:4,4625:2,2604:2,14341:1", -- Pattern: Festival Dress
    [21723] = "Tailoring|250|21542|1|1|14048:4,4625:2,2604:2,14341:1", -- Pattern: Festival Suit
    [21724] = "Engineering|125|21558|3|3|4364:1,2319:1", -- Schematic: Small Blue Rocket
    [21725] = "Engineering|125|21559|3|3|4364:1,2319:1", -- Schematic: Small Green Rocket
    [21726] = "Engineering|125|21557|3|3|4364:1,2319:1", -- Schematic: Small Red Rocket
    [21727] = "Engineering|175|21589|3|3|4377:1,4234:1", -- Schematic: Large Blue Rocket
    [21728] = "Engineering|175|21590|3|3|4377:1,4234:1", -- Schematic: Large Green Rocket
    [21729] = "Engineering|175|21592|3|3|4377:1,4234:1", -- Schematic: Large Red Rocket
    [21730] = "Engineering|225|21571|3|3|10505:1,4304:1", -- Schematic: Blue Rocket Cluster
    [21731] = "Engineering|225|21574|3|3|10505:1,4304:1", -- Schematic: Green Rocket Cluster
    [21732] = "Engineering|225|21576|3|3|10505:1,4304:1", -- Schematic: Red Rocket Cluster
    [21733] = "Engineering|275|21714|3|3|15992:1,8170:1", -- Schematic: Large Blue Rocket Cluster
    [21734] = "Engineering|275|21716|3|3|15992:1,8170:1", -- Schematic: Large Green Rocket Cluster
    [21735] = "Engineering|275|21718|3|3|15992:1,8170:1", -- Schematic: Large Red Rocket Cluster
    [21737] = "Engineering|275|21570|1|1|9060:4,9061:4,18631:2,10561:1", -- Schematic: Cluster Launcher
    [21738] = "Engineering|225|21569|1|1|9060:1,9061:1,10560:1,10561:1", -- Schematic: Firework Launcher
    [22209] = "Blacksmithing|300|22197|1|1|22202:14,12655:4,7076:2", -- Plans: Heavy Obsidian Belt
    [22214] = "Blacksmithing|300|22195|1|1|22202:14,12810:4", -- Plans: Light Obsidian Belt
    [22219] = "Blacksmithing|300|22198|1|1|22203:8,22202:24,12655:8,7076:4", -- Plans: Jagged Obsidian Shield
    [22220] = "Blacksmithing|300|22194|1|1|22203:8,22202:24,12810:8,13512:1", -- Plans: Black Grasp of the Destroyer
    [22221] = "Blacksmithing|300|22191|1|1|22203:15,22202:36,12810:12,12809:10,12800:4", -- Plans: Obsidian Mail Tunic
    [22222] = "Blacksmithing|300|22196|1|1|22203:18,22202:40,12655:12,7076:10,12364:4", -- Plans: Thick Obsidian Breastplate
    [22307] = "Tailoring|225|22246|1|1|4339:4,11137:4,8343:2", -- Pattern: Enchanted Mageweave Pouch
    [22308] = "Tailoring|275|22248|1|1|14048:5,16203:2,14341:2", -- Pattern: Enchanted Runecloth Bag
    [22309] = "Tailoring|300|22249|1|1|14048:6,14344:4,12810:4,14227:4", -- Pattern: Big Bag of Enchantment
    [22310] = "Tailoring|275|22251|1|1|14048:5,8831:10,11040:8,14341:2", -- Pattern: Cenarion Herb Bag
    [22312] = "Tailoring|300|22252|1|1|14048:6,14342:2,13468:1,14227:4", -- Pattern: Satchel of Cenarius
    [22388] = "Blacksmithing|300|22385|1|1|12360:12,12655:20,7076:10,13510:2", -- Plans: Titanic Leggings
    [22389] = "Blacksmithing|300|22383|1|1|12360:12,20725:2,13512:2,12810:4", -- Plans: Sageblade
    [22390] = "Blacksmithing|300|22384|1|1|12360:15,11371:10,12808:20,20520:20,15417:10,12753:2", -- Plans: Persuader
    [22683] = "Tailoring|300|22660|1|1|19726:1,14342:2,12803:4,14227:4", -- Pattern: Gaea's Embrace
    [22684] = "Tailoring|300|22654|1|1|22682:5,14048:4,7080:4,14227:4", -- Pattern: Glacial Gloves
    [22685] = "Tailoring|300|22658|1|1|22682:5,14048:4,7080:2,14227:4", -- Pattern: Glacial Cloak
    [22686] = "Tailoring|300|22652|1|1|22682:7,14048:8,7080:6,14227:8", -- Pattern: Glacial Vest
    [22687] = "Tailoring|300|22655|1|1|22682:4,14048:2,7080:2,14227:4", -- Pattern: Glacial Wrists
    [22692] = "Leatherworking|300|22661|1|1|22682:7,12810:16,7080:2,15407:4,14227:4", -- Pattern: Polar Tunic
    [22694] = "Leatherworking|300|22662|1|1|22682:5,12810:12,7080:2,15407:3,14227:4", -- Pattern: Polar Gloves
    [22695] = "Leatherworking|300|22663|1|1|22682:4,12810:12,7080:2,15407:2,14227:4", -- Pattern: Polar Bracers
    [22696] = "Leatherworking|300|22664|1|1|22682:7,15408:24,7080:2,15407:4,14227:4", -- Pattern: Icy Scale Breastplate
    [22697] = "Leatherworking|300|22666|1|1|22682:5,15408:16,7080:2,15407:3,14227:4", -- Pattern: Icy Scale Gauntlets
    [22698] = "Leatherworking|300|22665|1|1|22682:4,15408:16,7080:2,15407:2,14227:4", -- Pattern: Icy Scale Bracers
    [22703] = "Blacksmithing|300|22669|1|1|22682:7,12359:16,12360:2,7080:4", -- Plans: Icebane Breastplate
    [22704] = "Blacksmithing|300|22670|1|1|22682:5,12359:12,12360:2,7080:2", -- Plans: Icebane Gauntlets
    [22705] = "Blacksmithing|300|22671|1|1|22682:4,12359:12,12360:2,7080:2", -- Plans: Icebane Bracers
    [22729] = "Engineering|275|22728|1|1|15994:2,10561:1,10558:1", -- Schematic: Steam Tonk Controller
    [22766] = "Blacksmithing|300|22762|1|1|12655:12,19726:2,12360:2,12803:2", -- Plans: Ironvine Breastplate
    [22767] = "Blacksmithing|300|22763|1|1|12655:8,19726:1,12803:2", -- Plans: Ironvine Gloves
    [22768] = "Blacksmithing|300|22764|1|1|12655:6,12803:2", -- Plans: Ironvine Belt
    [22769] = "Leatherworking|300|22761|1|1|12810:4,12803:2,15407:1", -- Pattern: Bramblewood Belt
    [22770] = "Leatherworking|300|22760|1|1|12810:6,18512:2,12803:2,15407:2", -- Pattern: Bramblewood Boots
    [22771] = "Leatherworking|300|22759|1|1|12810:12,19726:2,12803:2,15407:2", -- Pattern: Bramblewood Helm
    [22772] = "Tailoring|300|22758|1|1|14048:2,12803:4,14227:2", -- Pattern: Sylvan Shoulders
    [22773] = "Tailoring|300|22757|1|1|14048:4,14342:2,12803:2,14227:2", -- Pattern: Sylvan Crown
    [22774] = "Tailoring|300|22756|1|1|14048:4,19726:2,12803:2,14227:2" -- Pattern: Sylvan Vest
}
