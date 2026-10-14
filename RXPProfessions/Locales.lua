-- RestedXP Professions - other languages.
-- The game names recipes, items and zones itself in the player's language
-- (Core.lua asks it by spell, item and map ID). What it cannot name for us
-- is here: the professions as its skill lists write them (so they are
-- found on every client), the rank names, the mining nodes, and the
-- addon's own sentences. A sentence with no translation reads in English.

local addonName, ns = ...

local locale = GetLocale and GetLocale() or "enUS"
if locale == "enGB" then locale = "enUS" end
ns.LOCALE = locale

-- The skill lines' names, per client language (English is the key).
ns.PROF_NAMES = {}

-- The rank names as the game writes them.
ns.RANK_NAMES = {}

-- Mining nodes (herbs are named through their items, Data.lua).
ns.NODE_NAMES = {}

-- The addon's own sentences, keyed by their English.
local T = {}

ns.L = setmetatable({}, {__index = function(_, key) return key end})
for key, text in pairs(T[locale] or {}) do ns.L[key] = text end
