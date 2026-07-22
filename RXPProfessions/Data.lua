-- RestedXP Professions - static profession data (Classic Era / TBC values)

local addonName, ns = ...

-- Rank progression: at `trainAt` skill you can (and should) learn the rank
-- that raises your cap to `nextCap`.
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

-- First Aid: which bandage to craft in each skill bracket. Sorted ascending.
ns.FIRSTAID = {
    {1, "Linen Bandage"},
    {40, "Heavy Linen Bandage"},
    {80, "Wool Bandage"},
    {115, "Heavy Wool Bandage"},
    {150, "Silk Bandage"},
    {180, "Heavy Silk Bandage"},
    {210, "Mageweave Bandage"},
    {240, "Heavy Mageweave Bandage"},
    {260, "Runecloth Bandage"},
    {290, "Heavy Runecloth Bandage"}
}

-- One-off First Aid milestones that need more than a trainer visit
ns.FIRSTAID_NOTES = {
    {150, "Expert rank needs the book |cFFFFCC00Expert First Aid - Under Wraps|r (vendor)"},
    {225, "Artisan rank needs the |cFFFFCC00Triage|r quest (Theramore / Hammerfall)"}
}

-- Alchemy leveling route (approximate, classic standard): what to craft in
-- each bracket and what it takes. {from, item, mats}
ns.ALCHEMY = {
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
}

-- Professions the tracker understands (skill line names, English clients)
ns.TRACKED = {
    ["Mining"] = "gather",
    ["Herbalism"] = "gather",
    ["Skinning"] = "skinning",
    ["First Aid"] = "firstaid",
    ["Alchemy"] = "craft"
}

-- shown in the first-launch setup window, in this order
ns.CHOOSABLE = {"Herbalism", "Mining", "Skinning", "First Aid", "Alchemy"}
