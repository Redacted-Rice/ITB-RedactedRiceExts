-- Base class for pilot skills that add trait icons to pawns
-- 
-- Usage:
--   local MySkillTrait = cplus_plus_ex.baseClasses.SkillTrait:new({
--       id = "MySkill",
--       name = "My Skill",
--       description = "Does something cool"
--   })
--
--   function MySkillTrait:applyTrait(pawnId, pawn, isActive)
--       -- Your implementation here
--   end

local SkillTrait = {}
SkillTrait.skills = {}

SkillTrait.__index = SkillTrait

SkillTrait.DEBUG = false
local logger = memhack.logger
local SUBMODULE = logger.register("CPLUS+ Ex", "SkillTrait", SkillTrait.DEBUG)

function SkillTrait:new(tbl)
	tbl = tbl or {}
	tbl.modified = {}
	setmetatable(tbl, self)
	self.skills[tbl.id] = tbl
	return tbl
end

-- Override this in derived classes to apply/remove trait effects
-- pawnId: 0-2 for player mechs
-- isActive: true when skill activates, false when it deactivates
function SkillTrait:applyTrait(pawnId, pawn, isActive)
	logger.logError(SUBMODULE, string.format("SkillTrait applyTrait not implemented for skill %s", self.id))
end

-- Internal: called once by cplus_plus_ex:init()
function SkillTrait:_baseInit()
	-- Guard against multiple calls
	if SkillTrait._baseInited then
		return
	end
	SkillTrait._baseInited = true
	cplus_plus_ex.events.onSkillActive:subscribe(SkillTrait.checkAndApplyTrait)
end

-- Internal callback
function SkillTrait.checkAndApplyTrait(skillId, isActive, pawnId, pilot, skill)
	logger.logDebug(SUBMODULE, "Checking trait skill %s", skillId)
	local skillClass = SkillTrait.skills[skillId]
	if skillClass then
		local pawn = Game:GetPawn(pawnId)
		logger.logDebug(SUBMODULE, "Applying trait %s for pawn id %d (isActive: %s)", skillId, pawnId, tostring(isActive))
		skillClass:applyTrait(pawnId, pawn, isActive)
	end
end

return SkillTrait
