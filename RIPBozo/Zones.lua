-- RIP Bozo - where people die
--
-- Death announcements name the *subzone* ("Alexston Farmstead"), not the
-- zone. This file maps Classic subzones to their zone so the roast can look
-- up the zone's level range. Anything not listed here is learned as you
-- play (subzone -> zone recorded whenever you change areas) and saved.

local addonName, ns = ...

-- zone/dungeon/city -> {min, max}
ns.ZONES = {
    -- dungeons
    ["Ragefire Chasm"] = {13, 18, dungeon = true},
    ["Wailing Caverns"] = {17, 24, dungeon = true},
    ["The Deadmines"] = {17, 26, dungeon = true},
    ["Deadmines"] = {17, 26, dungeon = true},
    ["Shadowfang Keep"] = {22, 30, dungeon = true},
    ["The Stockade"] = {22, 30, dungeon = true},
    ["Stormwind Stockade"] = {22, 30, dungeon = true},
    ["Blackfathom Deeps"] = {24, 32, dungeon = true},
    ["Gnomeregan"] = {29, 38, dungeon = true},
    ["Razorfen Kraul"] = {29, 38, dungeon = true},
    ["Scarlet Monastery"] = {34, 45, dungeon = true},
    ["Razorfen Downs"] = {37, 46, dungeon = true},
    ["Uldaman"] = {41, 51, dungeon = true},
    ["Zul'Farrak"] = {44, 54, dungeon = true},
    ["Maraudon"] = {46, 55, dungeon = true},
    ["The Temple of Atal'Hakkar"] = {50, 60, dungeon = true},
    ["Sunken Temple"] = {50, 60, dungeon = true},
    ["Blackrock Depths"] = {52, 60, dungeon = true},
    ["Blackrock Spire"] = {55, 60, dungeon = true},
    ["Lower Blackrock Spire"] = {55, 60, dungeon = true},
    ["Upper Blackrock Spire"] = {58, 60, dungeon = true},
    ["Dire Maul"] = {55, 60, dungeon = true},
    ["Stratholme"] = {58, 60, dungeon = true},
    ["Scholomance"] = {58, 60, dungeon = true},
    -- cities
    ["Stormwind City"] = {1, 60, city = true},
    ["Ironforge"] = {1, 60, city = true},
    ["Darnassus"] = {1, 60, city = true},
    ["Orgrimmar"] = {1, 60, city = true},
    ["Thunder Bluff"] = {1, 60, city = true},
    ["Undercity"] = {1, 60, city = true},
    -- zones
    ["Elwynn Forest"] = {1, 10}, ["Dun Morogh"] = {1, 10}, ["Teldrassil"] = {1, 10},
    ["Durotar"] = {1, 10}, ["Mulgore"] = {1, 10}, ["Tirisfal Glades"] = {1, 10},
    ["Westfall"] = {10, 20}, ["Loch Modan"] = {10, 20}, ["Darkshore"] = {10, 20},
    ["The Barrens"] = {10, 25}, ["Silverpine Forest"] = {10, 20},
    ["Redridge Mountains"] = {15, 25}, ["Stonetalon Mountains"] = {15, 27},
    ["Duskwood"] = {18, 30}, ["Ashenvale"] = {18, 30}, ["Wetlands"] = {20, 30},
    ["Hillsbrad Foothills"] = {20, 30}, ["Thousand Needles"] = {25, 35},
    ["Desolace"] = {30, 40}, ["Arathi Highlands"] = {30, 40},
    ["Alterac Mountains"] = {30, 40}, ["Stranglethorn Vale"] = {30, 45},
    ["Dustwallow Marsh"] = {35, 45}, ["Badlands"] = {35, 45},
    ["Swamp of Sorrows"] = {35, 45}, ["The Hinterlands"] = {40, 50},
    ["Tanaris"] = {40, 50}, ["Feralas"] = {40, 50}, ["Searing Gorge"] = {43, 50},
    ["Azshara"] = {45, 55}, ["Blasted Lands"] = {45, 55},
    ["Un'Goro Crater"] = {48, 55}, ["Felwood"] = {48, 55},
    ["Burning Steppes"] = {50, 58}, ["Western Plaguelands"] = {51, 58},
    ["Eastern Plaguelands"] = {53, 60}, ["Winterspring"] = {53, 60},
    ["Silithus"] = {55, 60}, ["Deadwind Pass"] = {55, 60},
    ["Moonglade"] = {50, 60}
}

-- zone -> list of its subzones (Classic Azeroth)
local SUB = {
    ["Elwynn Forest"] = {
        "Northshire", "Northshire Valley", "Northshire Abbey", "Northshire Vineyards",
        "Echo Ridge Mine", "Goldshire", "Lion's Pride Inn", "Crystal Lake",
        "Fargodeep Mine", "Jasperlode Mine", "Stone Cairn Lake",
        "Eastvale Logging Camp", "Brackwell Pumpkin Patch", "Ridgepoint Tower",
        "Tower of Azora", "Mirror Lake", "Mirror Lake Orchard", "Forest's Edge",
        "Westbrook Garrison", "Stonefield Farm", "The Stonefield Farm",
        "Maclure Vineyards", "The Maclure Vineyards", "Heroes' Vigil"
    },
    ["Westfall"] = {
        "Sentinel Hill", "Moonbrook", "Alexston Farmstead", "Furlbrow's Pumpkin Farm",
        "Jangolode Mine", "Saldean's Farm", "The Jansen Stead", "Dead Acre",
        "Gold Coast Quarry", "Demont's Place", "Longshore", "The Molsen Farm",
        "Stendel's Pond", "The Dagger Hills", "Westfall Lighthouse", "The Dust Plains"
    },
    ["Redridge Mountains"] = {
        "Lakeshire", "Lake Everstill", "Three Corners", "Alther's Mill",
        "Render's Camp", "Render's Valley", "Render's Rock", "Stonewatch",
        "Stonewatch Keep", "Stonewatch Falls", "Tower of Ilgalar",
        "Galardell Valley", "Redridge Canyons", "Lakeridge Highway",
        "Shalewind Canyon"
    },
    ["Duskwood"] = {
        "Darkshire", "Raven Hill", "Raven Hill Cemetery", "The Rotting Orchard",
        "Brightwood Grove", "Tranquil Gardens Cemetery", "Vul'Gol Ogre Mound",
        "Addle's Stead", "Twilight Grove", "The Twilight Grove", "Manor Mistmantle",
        "The Yorgen Farmstead", "The Hushed Bank", "The Darkened Bank",
        "Beggar's Haunt", "Forlorn Rowe"
    },
    ["Loch Modan"] = {
        "Thelsamar", "Algaz Station", "Stonewrought Dam", "The Loch",
        "Silver Stream Mine", "Grizzlepaw Ridge", "Mo'grosh Stronghold",
        "The Farstrider Lodge", "Ironband's Excavation Site", "Stonesplinter Valley",
        "Valley of Kings", "Dun Algaz"
    },
    ["Dun Morogh"] = {
        "Coldridge Valley", "Anvilmar", "Coldridge Pass", "Kharanos",
        "Steelgrill's Depot", "Chill Breeze Valley", "Frostmane Hold", "Frostmane Hovel",
        "Shimmer Ridge", "Iceflow Lake", "The Grizzled Den", "Gol'Bolar Quarry",
        "Helm's Bed Lake", "Amberstill Ranch", "Misty Pine Refuge", "Brewnall Village",
        "The Tundrid Hills", "North Gate Pass", "South Gate Pass",
        "Ironband's Compound", "Gates of Ironforge", "New Tinkertown"
    },
    ["Teldrassil"] = {
        "Shadowglen", "Aldrassil", "Dolanaar", "Lake Al'Ameth", "Ban'ethil Hollow",
        "Ban'ethil Barrow Den", "Starbreeze Village", "Fel Rock", "The Oracle Glade",
        "Wellspring Lake", "Wellspring River", "Gnarlpine Hold",
        "Pools of Arlithrien", "Rut'theran Village", "The Cleft"
    },
    ["Darkshore"] = {
        "Auberdine", "Bashal'Aran", "Ameth'Aran", "Cliffspring River",
        "Cliffspring Falls", "Grove of the Ancients", "Mist's Edge", "The Long Wash",
        "Twilight Vale", "Twilight Shore", "Remtravel's Excavation",
        "Tower of Althalaxx", "Ruins of Mathystra", "Wildbend River",
        "The Master's Glaive", "Blackwood Den", "Withering Thicket", "Nazj'vel"
    },
    ["Durotar"] = {
        "Valley of Trials", "Razor Hill", "Razor Hill Barracks", "Sen'jin Village",
        "Echo Isles", "Tiragarde Keep", "Razormane Grounds", "Drygulch Ravine",
        "Thunder Ridge", "Skull Rock", "Bladefist Bay", "Southfury River",
        "Kolkar Crag", "Dustwind Cave", "Burning Blade Coven", "Scuttle Coast",
        "Spitescale Cavern"
    },
    ["Mulgore"] = {
        "Camp Narache", "Red Cloud Mesa", "Bloodhoof Village", "Stonebull Lake",
        "Winterhoof Water Well", "Thunderhorn Water Well", "Wildmane Water Well",
        "Ravaged Caravan", "Palemane Rock", "The Venture Co. Mine", "Windfury Ridge",
        "Red Rocks", "The Golden Plains", "The Rolling Plains", "Kodo Rock",
        "Brambleblade Ravine", "Bael'dun Digsite"
    },
    ["Tirisfal Glades"] = {
        "Deathknell", "Shadow Grave", "Night Web's Hollow", "Brill", "Agamand Mills",
        "Agamand Family Crypt", "Garren's Haunt", "Cold Hearth Manor",
        "Solliden Farmstead", "Nightmare Vale", "Balnir Farmstead", "Venomweb Vale",
        "Whispering Gardens", "Crusader Outpost", "The Bulwark", "Stillwater Pond",
        "Brightwater Lake", "Calston Estate", "Gunther's Retreat",
        "Ruins of Lordaeron"
    },
    ["Silverpine Forest"] = {
        "The Sepulcher", "Ambermill", "Pyrewood Village", "The Dawning Isles",
        "Fenris Isle", "Fenris Keep", "Lordamere Lake", "North Tide's Run",
        "North Tide's Hollow", "Beren's Peril", "The Ivar Patch", "The Decrepit Ferry",
        "Deep Elem Mine", "The Greymane Wall", "Olsen's Farthing", "Malden's Orchard",
        "The Skittering Dark", "Valgan's Field"
    },
    ["The Barrens"] = {
        "The Crossroads", "Ratchet", "Camp Taurajo", "Northwatch Hold", "Grol'dom Farm",
        "The Sludge Fen", "Boulder Lode Mine", "The Mor'shan Rampart", "Far Watch Post",
        "The Stagnant Oasis", "The Forgotten Pools", "Lushwater Oasis", "Bael Modan",
        "Bael'dun Keep", "The Great Lift", "Thorn Hill", "Dreadmist Peak",
        "Blackthorn Ridge", "Fields of Giants", "Field of Giants", "Agama'gor",
        "Bramblescar", "The Merchant Coast", "The Dry Hills", "Honor's Stand",
        "Raptor Grounds", "Gold Road", "Southfury River", "Barrens"
    },
    ["Stonetalon Mountains"] = {
        "Stonetalon Peak", "Sun Rock Retreat", "Windshear Crag", "The Charred Vale",
        "Mirkfallon Lake", "Malaka'jin", "Grimtotem Post", "Cragpool Lake",
        "Boulderslide Ravine", "Webwinder Path", "Sishir Canyon", "The Talon Den",
        "Blackwolf River", "Greatwood Vale", "Stonetalon Pass", "Windshear Mine"
    },
    ["Ashenvale"] = {
        "Astranaar", "Splintertree Post", "Zoram'gar Outpost", "The Zoram Strand",
        "Maestra's Post", "Thistlefur Village", "Thistlefur Hold", "Iris Lake",
        "Lake Falathim", "The Shrine of Aessina", "Bathran's Haunt",
        "The Ruins of Ordil'Aran", "Ruins of Stardust", "Mystral Lake",
        "Silverwind Refuge", "Raynewood Retreat", "The Howling Vale", "Night Run",
        "Satyrnaar", "Xavian", "Felfire Hill", "Demon Fall Canyon",
        "Warsong Lumber Camp", "Warsong Labor Camp", "Fire Scar Shrine",
        "Nightsong Woods", "Forest Song", "Bloodtooth Camp", "Fallen Sky Lake",
        "Dor'Danil Barrow Den", "The Dor'Danil Barrow Den", "Bough Shadow",
        "Greenpaw Village", "Talondeep Path"
    },
    ["Wetlands"] = {
        "Menethil Harbor", "Menethil Bay", "Deepwater Tavern", "Dun Modr",
        "Whelgar's Excavation Site", "Angerfang Encampment", "Bluegill Marsh",
        "Saltspray Glen", "Sundown Marsh", "Black Channel Marsh", "Ironbeard's Tomb",
        "Direforge Hill", "Raptor Ridge", "Thelgen Rock", "Mosshide Fen",
        "The Green Belt", "Thandol Span", "Greenwarden's Grove"
    },
    ["Hillsbrad Foothills"] = {
        "Southshore", "Tarren Mill", "Hillsbrad Fields", "Hillsbrad", "Dun Garok",
        "Azurelode Mine", "Darrow Hill", "Nethander Stead", "Durnholde Keep",
        "Purgation Isle", "Western Strand", "Eastern Strand"
    },
    ["Alterac Mountains"] = {
        "Strahnbrad", "Ruins of Alterac", "Dandred's Fold", "Gallows' Corner",
        "Crushridge Hold", "Lordamere Internment Camp", "Sofera's Naze",
        "Chillwind Point", "The Uplands", "Growless Cave", "Gavin's Naze",
        "Slaughter Hollow", "Ravenholdt Manor", "Dalaran", "Dalaran Crater",
        "Corrahn's Dagger", "The Headland", "Misty Shore"
    },
    ["Arathi Highlands"] = {
        "Refuge Pointe", "Hammerfall", "Stromgarde Keep", "Stromgarde",
        "Thoradin's Wall", "Boulderfist Hall", "Northfold Manor", "Go'Shek Farm",
        "Dabyrie's Farmstead", "Circle of East Binding", "Circle of West Binding",
        "Circle of Inner Binding", "Circle of Outer Binding", "Witherbark Village",
        "Drywhisker Gorge", "Faldir's Cove", "Boulder'gor", "Galen's Fall",
        "The Tower of Arathor"
    },
    ["Thousand Needles"] = {
        "Freewind Post", "Darkcloud Pinnacle", "Whitereach Post", "Splithoof Hold",
        "Splithoof Crag", "Highperch", "The Shimmering Flats", "Mirage Raceway",
        "Windbreak Canyon", "Weazel's Crater", "Roguefeather Den", "Galak Hold",
        "Ironstone Camp", "Camp E'thok", "The Rustmaul Dig Site", "Tahonda Ruins"
    },
    ["Desolace"] = {
        "Nijel's Point", "Shadowprey Village", "Ghost Walker Post", "Kormek's Hut",
        "Sar'theris Strand", "Ethel Rethor", "Mannoroc Coven", "Valley of Spears",
        "Kolkar Village", "Magram Village", "Gelkis Village", "Kodo Graveyard",
        "Scrabblescrew's Camp", "Thunder Axe Fortress", "Bolgan's Hole",
        "Ranazjar Isle", "Tethris Aran", "Shok'Thokar", "Sargeron"
    },
    ["Stranglethorn Vale"] = {
        "Booty Bay", "Grom'gol Base Camp", "Nesingwary's Expedition", "Rebel Camp",
        "Kurzen's Compound", "Lake Nazferiti", "The Vile Reef", "Ruins of Zul'Kunda",
        "Ruins of Zul'Mamwe", "Bal'lal Ruins", "Balia'mah Ruins", "Ziata'jai Ruins",
        "Mizjah Ruins", "Mosh'Ogg Ogre Mound", "Venture Co. Base Camp",
        "Venture Co. Operations Center", "The Savage Coast", "Crystalvein Mine",
        "Gurubashi Arena", "Zuuldaia Ruins", "Bloodsail Compound", "Wild Shore",
        "The Cape of Stranglethorn", "Jaguero Isle", "Mistvale Valley",
        "Ruins of Aboraz", "Ruins of Jubuwal", "Janeiro's Point", "The Stockpile",
        "Nek'mani Wellspring", "Stranglethorn"
    },
    ["Dustwallow Marsh"] = {
        "Theramore Isle", "Theramore", "Brackenwall Village", "Witch Hill",
        "Sentry Point", "Alcaz Island", "Dreadmurk Shore", "Bluefen", "The Quagmire",
        "Stonemaul Ruins", "Den of Flame", "The Den of Flame", "Wyrmbog",
        "Tidefury Cove", "Darkmist Cavern", "Lost Point", "Beezil's Wreck",
        "Shady Rest Inn", "Direhorn Post", "Nat's Landing", "Swamplight Manor",
        "Blackhoof Village", "Mudsprocket"
    },
    ["Badlands"] = {
        "Kargath", "Angor Fortress", "Apocryphan's Rest", "Camp Boff", "Camp Cagg",
        "Camp Kosh", "Camp Wurg", "Hammertoe's Digsite", "Lethlor Ravine",
        "Agmond's End", "Mirage Flats", "The Dustbowl", "Valley of Fangs",
        "The Maker's Terrace", "Dustbelch Grotto"
    },
    ["Swamp of Sorrows"] = {
        "Stonard", "The Harborage", "Misty Valley", "Itharius's Cave", "Pool of Tears",
        "Sorrowmurk", "Splinterspear Junction", "Stagalbog", "Stagalbog Cave",
        "Fallow Sanctuary", "The Shifting Mire", "Misty Reed Strand",
        "Misty Reed Post"
    },
    ["The Hinterlands"] = {
        "Aerie Peak", "Wildhammer Keep", "Revantusk Village", "Jintha'Alor",
        "Shadra'Alor", "Seradane", "Skulk Rock", "Quel'Danil Lodge", "Zun'watha",
        "The Creeping Ruin", "Agol'watha", "Shaol'watha", "Hiri'watha",
        "Plaguemist Ravine", "Valorwind Lake", "The Overlook Cliffs",
        "Overlook Cliffs", "Altar of Zul"
    },
    ["Tanaris"] = {
        "Gadgetzan", "Steamwheedle Port", "Sandsorrow Watch", "Broken Pillar",
        "Valley of the Watchers", "Eastmoon Ruins", "Southmoon Ruins",
        "The Noxious Lair", "Dunemaul Compound", "Lost Rigger Cove",
        "The Gaping Chasm", "Caverns of Time", "Abyssal Sands", "Thistleshrub Valley",
        "Zalashji's Den", "Land's End Beach", "Waterspring Field", "Wavestrider Beach",
        "Southbreak Shore"
    },
    ["Feralas"] = {
        "Feathermoon Stronghold", "Camp Mojache", "Thalanaar", "The Twin Colossals",
        "Ruins of Isildien", "Grimtotem Compound", "Gordunni Outpost", "Lariss Pavilion",
        "Lower Wilds", "The Forgotten Coast", "Sardor Isle", "Isle of Dread",
        "High Wilderness", "Frayfeather Highlands", "Ruins of Ravenwind",
        "Rage Scar Hold", "Dream Bough", "Jademir Lake", "Ruins of Solarsal",
        "Feral Scar Vale", "Shalzaru's Lair", "The Writhing Deep", "Wildwind Lake",
        "Darkmist Ruins", "Oneiros"
    },
    ["Searing Gorge"] = {
        "Thorium Point", "The Cauldron", "Blackchar Cave", "Firewatch Ridge",
        "Dustfire Valley", "Grimesilt Dig Site", "The Sea of Cinders", "Tanner Camp",
        "The Slag Pit"
    },
    ["Azshara"] = {
        "Talrendis Point", "Valormok", "Bay of Storms", "Ravencrest Monument",
        "Bear's Head", "Bitter Reaches", "Forlorn Ridge", "Haldarr Encampment",
        "Hetaera's Clutch", "Jagged Reef", "Lake Mennar", "Legash Encampment",
        "Ruins of Eldarath", "Scalebeard's Cave", "Shadowsong Shrine",
        "Temple of Arkkoran", "Temple of Zin-Malor", "The Shattered Strand",
        "Thalassian Base Camp", "Tower of Eldara", "Ursolan"
    },
    ["Blasted Lands"] = {
        "Nethergarde Keep", "The Dark Portal", "Dreadmaul Hold", "Serpent's Coil",
        "Altar of Storms", "Rise of the Defiler", "Dreadmaul Post", "Garrison Armory",
        "The Tainted Scar"
    },
    ["Un'Goro Crater"] = {
        "Marshal's Refuge", "Fire Plume Ridge", "Golakka Hot Springs",
        "Ironstone Plateau", "Lakkari Tar Pits", "The Marshlands", "Terror Run",
        "The Slithering Scar", "Fungal Rock", "The Shaper's Terrace"
    },
    ["Felwood"] = {
        "Emerald Sanctuary", "Bloodvenom Post", "Talonbranch Glade", "Jaedenar",
        "Shatter Scar Vale", "Irontree Woods", "Irontree Cavern", "Felpaw Village",
        "Deadwood Village", "Ruins of Constellas", "Morlos'Aran", "Jadefire Glen",
        "Jadefire Run", "Bloodvenom Falls", "Bloodvenom River", "Timbermaw Hold",
        "Shadow Hold"
    },
    ["Burning Steppes"] = {
        "Flame Crest", "Morgan's Vigil", "Blackrock Mountain", "Blackrock Stronghold",
        "Dreadmaul Rock", "Ruins of Thaurissan", "Pillar of Ash", "The Pillar of Ash",
        "Terror Wing Path", "Draco'dar", "Blackrock Pass", "Slither Rock"
    },
    ["Western Plaguelands"] = {
        "Chillwind Camp", "Andorhal", "Ruins of Andorhal", "Hearthglen",
        "Mardenholde Keep", "Caer Darrow", "Sorrow Hill", "Felstone Field",
        "Dalson's Tears", "Gahrron's Withering", "The Writhing Haunt",
        "Northridge Lumber Camp", "The Weeping Cave", "Uther's Tomb",
        "Thondroril River"
    },
    ["Eastern Plaguelands"] = {
        "Light's Hope Chapel", "Corin's Crossing", "Darrowshire", "Crown Guard Tower",
        "Eastwall Tower", "Northpass Tower", "Plaguewood", "Plaguewood Tower",
        "Terrordale", "Tyr's Hand", "The Fungal Vale", "Blackwood Lake",
        "Lake Mereldar", "The Marris Stead", "The Noxious Glade", "Pestilent Scar",
        "The Undercroft", "Quel'Lithien Lodge", "Zul'Mashar", "The Infectis Scar",
        "Browman Mill"
    },
    ["Winterspring"] = {
        "Everlook", "Timbermaw Post", "Frostsaber Rock", "Ice Thistle Hills",
        "Lake Kel'Theril", "Mazthoril", "Owl Wing Thicket", "Starfall Village",
        "Winterfall Village", "Frostfire Hot Springs", "Darkwhisper Gorge",
        "The Hidden Grove", "Frostwhisper Gorge", "Dun Mandarr"
    },
    ["Silithus"] = {
        "Cenarion Hold", "Hive'Ashi", "Hive'Zora", "Hive'Regal", "The Scarab Wall",
        "Southwind Village", "Twilight Base Camp", "Twilight Outpost", "Twilight Post",
        "Valor's Rest", "Bronzebeard Encampment", "Staghelm Point",
        "The Swarming Pillar", "Ravaged Twilight Camp", "Ruins of Ahn'Qiraj"
    },
    ["Deadwind Pass"] = {"Karazhan", "Deadman's Crossing", "The Vice", "Ariden's Camp"},
    ["Moonglade"] = {
        "Nighthaven", "Lake Elune'ara", "Shrine of Remulos", "Stormrage Barrow Dens"
    },
    ["Stormwind City"] = {
        "Trade District", "Cathedral Square", "The Canals", "Old Town",
        "Dwarven District", "Mage Quarter", "The Park", "Stormwind Keep",
        "The Valley of Heroes", "Stormwind"
    },
    ["Ironforge"] = {
        "The Commons", "The Great Forge", "Tinker Town", "Hall of Explorers",
        "The Military Ward", "The Mystic Ward", "Forlorn Cavern", "Deeprun Tram"
    },
    ["Orgrimmar"] = {
        "Valley of Strength", "Valley of Honor", "Valley of Wisdom", "Valley of Spirits",
        "The Drag", "The Cleft of Shadow"
    },
    ["Thunder Bluff"] = {"Hunter Rise", "Elder Rise", "Spirit Rise", "The Pools of Vision"},
    ["Undercity"] = {
        "Trade Quarter", "The Apothecarium", "The Rogues' Quarter", "The Magic Quarter",
        "The War Quarter"
    },
    ["Darnassus"] = {
        "Craftsmen's Terrace", "Tradesmen's Terrace", "Warrior's Terrace",
        "Temple of the Moon", "Cenarion Enclave", "Temple Gardens"
    }
}

-- flattened: subzone (lower-case) -> zone
ns.SUBZONES = {}
for zone, list in pairs(SUB) do
    for _, sub in ipairs(list) do ns.SUBZONES[sub:lower()] = zone end
end
