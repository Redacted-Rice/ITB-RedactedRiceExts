local PilotLvlUpSkill = memhack.structManager.define("PilotLvlUpSkill", {
	id = { offset = 0x0, type = "string", maxLength = 16},
	-- String indexes into global string map. Seem to behave a bit oddly. If not
	-- found they will display the index value. Some skills seem to have smaller
	-- size limit? Maybe AE (16) vs OG (15)? Was testing with Move Bonus and Thick Skin
	displayNameIdx = { offset = 0x18, type = "string", maxLength = 16}, -- string ref to string in global string map
	fullNameIdx = { offset = 0x30, type = "string", maxLength = 16}, -- string ref to string in global string map
	descriptionIdx = { offset = 0x48, type = "string", maxLength = 16}, -- string ref to string in global string map
	coresBonus = { offset = 0x64, type = "int"},
	healthBonus = { offset = 0x68, type = "int"},
	moveBonus = { offset = 0x6C, type = "int"},
	saveVal = { offset = 0x70, type = "int"}, -- must be between 0-13
})

-- Array of two PilotLvlUpSkill structs back to back
-- Note: PilotLvlUpSkill size is 0x74 bytes (is it 74 or 7C? I can't remember but think it might be the latter)
local PilotLvlUpSkillsArray = memhack.structManager.define("PilotLvlUpSkillsArray", {
	skill1 = { offset = 0x00, type = "struct", structType = "PilotLvlUpSkill" },
	skill2 = { offset = 0x74, type = "struct", structType = "PilotLvlUpSkill" },
})

local PilotStruct = memhack.structManager.define("Pilot", {
	-- Any other interesting values to pull out? (other than skills)
	-- Maybe pilot skill?
	name = { offset = 0x20, type = "string", maxLength = 15}, -- including null term. 15 instead of 16 for some reason
	xp = { offset = 0x3C, type = "int", hideSetter = true},
	levelUpXp = { offset = 0x40, type = "int", hideSetter = true},
	level = { offset = 0x68, type = "int", hideSetter = true},
	id = { offset = 0x84, type = "string", maxLength = 15}, -- guess
	lvlUpSkills = { offset = 0xD8, type = "pointer", pointedType = "PilotLvlUpSkillsArray"},
})

-- Convinience for defining fns
local Pilot = memhack.structs.Pilot

function onPawnClassInitialized(BoardPawn, pawn)
	-- TODO: any other functions?
	-- maybe one to change the pilot type?

	Pilot.LevelUp = function(self)
		local newLevel = self:GetLevel() + 1
		if newLevel <= 2 then
			self:_SetXp(0)
			self:_SetLevel(newLevel)
			self:_SetLevelUpXp((newLevel + 1) * 25)
		end
	end

	Pilot.LevelDown = function(self)
		local newLevel = self:GetLevel() - 1
		if newLevel >= 0 then
			self:_SetXp(0)
			self:_SetLevel(newLevel)
			self:_SetLevelUpXp((newLevel + 1) * 25)
		end
	end
end

-- Use on first load event or some other one?
modApi.events.onPawnClassInitialized:subscribe(onPawnClassInitialized)
