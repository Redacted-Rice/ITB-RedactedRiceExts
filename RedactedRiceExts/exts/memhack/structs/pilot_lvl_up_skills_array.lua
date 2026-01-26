-- Array of two PilotLvlUpSkill structs back to back
-- PilotLvlUpSkill size is 0x74 bytes
local PilotLvlUpSkillsArray = memhack.structManager.define("PilotLvlUpSkillsArray", {
	skill1 = { offset = 0x00, type = "struct", subType = "PilotLvlUpSkill" },
	skill2 = { offset = 0x74, type = "struct", subType = "PilotLvlUpSkill" },
})

local methodGen = memhack.structManager._methodGeneration

function createPilotLvlUpSkillsArrayFuncs()
	-- Auto inject parent references into struct getters
	methodGen.wrapGetterToPreserveParent(PilotLvlUpSkillsArray, "getSkill1")
	methodGen.wrapGetterToPreserveParent(PilotLvlUpSkillsArray, "getSkill2")

	-- Add convenience Pilot parent getter method
	methodGen.makeParentGetterWrapper(PilotLvlUpSkillsArray, "Pilot")

	-- Convinience wrappers for level up skills array values
	-- See PilotLvlUpSkill.set for arg defs
	methodGen.makeStructSetWrapper(PilotLvlUpSkillsArray, "skill1")
	methodGen.makeStructSetWrapper(PilotLvlUpSkillsArray, "skill2")
end

function onModsFirstLoaded()
	createPilotLvlUpSkillsArrayFuncs()
end

modApi.events.onModsFirstLoaded:subscribe(onModsFirstLoaded)
