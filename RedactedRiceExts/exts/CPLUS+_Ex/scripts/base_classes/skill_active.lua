-- Base class for pilot skills that set up event handlers while active
-- Automatically manages event subscriptions and cleanup.
--
-- Usage:
--   local MySkillActive = cplus_plus_ex.baseClasses.SkillActive:new({
--       id = "MySkill",
--       name = "My Skill",
--       description = "Does something cool"
--   })
--
--   function MySkillActive:setupEffect()
--       -- Register event handlers here
--       -- Store subscriptions in self.events table
--       table.insert(self.events, modApi.events.onPawnKilled:subscribe(function(pawn)
--           -- Your logic here
--       end))
--   end
--
--   MySkillActive:baseInit()

local SkillActive = {}
SkillActive.skills = {}

SkillActive.__index = SkillActive

SkillActive.DEBUG = false
local logger = memhack.logger
local SUBMODULE = logger.register("CPLUS+ Ex", "SkillActive", SkillActive.DEBUG)

function SkillActive:new(tbl)
	tbl = tbl or {}
	tbl.events = {}
	setmetatable(tbl, self)
	self.skills[tbl.id] = tbl
	return tbl
end

-- Override this in derived classes to register event handlers
-- Store event subscriptions in self.events table for automatic cleanup
function SkillActive:setupEffect()
	logger.logError(SUBMODULE, string.format("SkillActive setupEffect not implemented for skill %s", self.id))
end

-- Automatically called when skill becomes inactive
function SkillActive:clearEvents()
	logger.logDebug(SUBMODULE, "Clearing events for %s", self.id)
	for _, event in pairs(self.events) do
		event:unsubscribe()
	end
	self.events = {}
end

-- Call this in your mod's load() function
function SkillActive:baseInit()
	cplus_plus_ex.events.onSkillActive:subscribe(self.clearAndReSetUpEffect)
end

-- Internal callback
function SkillActive.clearAndReSetUpEffect(skillId, isActive, pawnId, pilot, skillStruct)
	logger.logDebug(SUBMODULE, "Checking skill %s", skillId)
	local skillClass = SkillActive.skills[skillId]
	if skillClass then
		-- Clear events
		skillClass:clearEvents()

		-- Then add them back if any are active
		if cplus_plus_ex:isSkillActive(skillId) then
			logger.logDebug(SUBMODULE, "Setting up skill %s for pawn id %d", skillId, pawnId)
			skillClass:setupEffect()
		end
	end
end

return SkillActive
