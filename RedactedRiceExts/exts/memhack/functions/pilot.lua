-- This is a union... how to handle in struct?
-- Maybe just have overlap here and let modders add functions as needed
-- Add a disable all setters option?
local PilotLvlUpSkillTxtUnion = memhack.structManager.define("PilotLvlUpSkillTxtUnion", {
	-- If present in global texts, the text idx to display. Otherwise displays directly.
	-- Can only be used if size < 16. Otherwise it has to be stored with textIdPtr
	textIdx = { offset = 0x0, type = "string", maxLength = 16, hideSetter = true},
	-- Same idea as textIdx but a pointer to the value if its too large to fit locally
	textIdxPtr = { offset = 0x0, type = "pointer", hideSetter = true},
	-- Length of the textIdx/string pointed to by testIdxPtr. This is set the same regardless
	-- of which is used
	textIdxLen = { offset = 0x10, type = "int", hideSetter = true},
	-- Which one is used. If x0F, it will be treated as textIdx in place. If 0x1F, it will
	-- be treated as a pointer. Not sure if there are any other valid values
	unionType = { offset = 0x14, type = "int", hideSetter = true},
})

local PilotLvlUpSkill = memhack.structManager.define("PilotLvlUpSkill", {
	-- This is the main value used to determine skill effect in game. Note that the + move, hp, & cores
	-- skills use the bonus values below instead
	id = { offset = 0x0, type = "struct", structType = "PilotLvlUpSkillTxtUnion" },
	-- Displayed in the small box in UI
	shortName = { offset = 0x18, type = "struct", structType = "PilotLvlUpSkillTxtUnion" },
	-- Displayed when hovering over skill
	fullName = { offset = 0x30, type = "struct", structType = "PilotLvlUpSkillTxtUnion" },
	-- Displayed when hovering over skill
	description = { offset = 0x48, type = "struct", structType = "PilotLvlUpSkillTxtUnion" },
	coresBonus = { offset = 0x64, type = "int"},
	healthBonus = { offset = 0x68, type = "int"},
	moveBonus = { offset = 0x6C, type = "int"},
	-- Value used in save file. Does not directly change effect. ID does this
	-- Valid values are between 0-13. Other values will be saved but are clamped
	-- to this range before the onGameEntered event is fired
	saveVal = { offset = 0x70, type = "int"},
})

-- Array of two PilotLvlUpSkill structs back to back
-- PilotLvlUpSkill size is 0x74 bytes
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
	
	PilotLvlUpSkillTxtUnion.textIds = {}

	
	PilotLvlUpSkillTxtUnion.Set = function(self, textIdx)
		local txtLen = #textIdx
		if txtLen < 16 then -- < 16 for room for null term
			-- If its less than 16, we can store it locally
			self:_SetTextIdx(textIdx)
			self:_SetUnionType(0x0F)
		else 
			-- if we don't have a text idx already, create one
			if PilotLvlUpSkillTxtUnion.textIds[textIdx] == nil then
				PilotLvlUpSkillTxtUnion.textIds[textIdx] = memhack.dll.memory.allocCString(textIdx)
			end
			-- todo: fix awkward syntax
			self:_SetTextIdxPtrPtr(memhack.dll.memory.getUserdataAddr(PilotLvlUpSkillTxtUnion.textIds[textIdx]))
			self:_SetUnionType(0x1F)
		end
		self:_SetTextIdxLen(txtLen)
	end
end

-- Use on first load event or some other one?
modApi.events.onPawnClassInitialized:subscribe(onPawnClassInitialized)
