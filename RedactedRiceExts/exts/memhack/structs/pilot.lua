local PilotLvlUpSkill = memhack.structManager.define("PilotLvlUpSkill", {
	-- This is the main value used to determine skill effect in game. Note that the + move, hp, & cores
	-- skills use the bonus values below instead
	id = { offset = 0x0, type = "struct", structType = "ItBString" },
	-- Displayed in the small box in UI
	shortName = { offset = 0x18, type = "struct", structType = "ItBString" },
	-- Displayed when hovering over skill
	fullName = { offset = 0x30, type = "struct", structType = "ItBString" },
	-- Displayed when hovering over skill
	description = { offset = 0x48, type = "struct", structType = "ItBString" },
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

local Pilot = memhack.structManager.define("Pilot", {
	-- Any other interesting values to pull out? (other than skills)
	-- Maybe pilot skill?
	-- TODO: Are name and id ItBStrings as well?
	name = { offset = 0x20, type = "string", maxLength = 15}, -- including null term. 15 instead of 16 for some reason
	xp = { offset = 0x3C, type = "int", hideSetter = true},
	levelUpXp = { offset = 0x40, type = "int", hideSetter = true},
	level = { offset = 0x68, type = "int", hideSetter = true},
	id = { offset = 0x84, type = "string", maxLength = 15}, -- guess
	lvlUpSkills = { offset = 0xD8, type = "pointer", pointedType = "PilotLvlUpSkillsArray"},
})

function addPawnGetPilotFunc(BoardPawn, pawn)
	BoardPawn.GetPilot = function(self)
		-- Pawn contains a double pointer at 0x980 and 0x984 to
		-- the same memory offset by 12 bytes. Just use the second
		-- because it points to the lower of the two addresses, presumably
		-- the wrapper class around pilot - maybe an AE pilot struct?
		local pilotPtr = memhack.dll.memory.readPointer(memhack.dll.memory.getUserdataAddr(self) + 0x984)
		-- If no pilot, address will be set to 0
		if pilotPtr == nil or pilotPtr == 0 then
			return nil
		end
		return memhack.structs.Pilot.new(pilotPtr)
	end
end

function createPilotFuncs()
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

function createPilotLvlUpSkillFuncs()
	-- Convinience wrappers for level up skills
	-- idx is either 1 or 2 for the respective skill
	-- PilotLvlUpSkill.Set for other arg defs
	Pilot.SetLvlUpSkill = function(self, index, idOrStruct, shortName, fullName, description, saveVal, bonuses)
		if idx == 1 then
			self:GetLvlUpSkills():SetSkill1(idOrStruct, shortName, fullName, description, saveVal, bonuses)
		elseif idx == 2 then
			self:GetLvlUpSkills():SetSkill2(idOrStruct, shortName, fullName, description, saveVal, bonuses)
		else
			error(string.format("Unexpected index %d. Should be 1 or 2", idx))
		end
	end
	
	-- Convinience wrappers for level up skills array values
	-- See PilotLvlUpSkill.Set for arg defs
	memhack.structManager.makeStructSetterWrapper(PilotLvlUpSkillsArray, "Skill1")
	memhack.structManager.makeStructSetterWrapper(PilotLvlUpSkillsArray, "Skill2")
	
	-- Convinience wrappers for lvl up skills strings
	memhack.structManager.makeStructSetterWrapper(PilotLvlUpSkill, "Id")
	memhack.structManager.makeStructSetterWrapper(PilotLvlUpSkill, "ShortName")
	memhack.structManager.makeStructSetterWrapper(PilotLvlUpSkill, "FullName")
	memhack.structManager.makeStructSetterWrapper(PilotLvlUpSkill, "Description")
	memhack.structs.ItBString._makeDirectGetterWrapper(PilotLvlUpSkill, "Id")
	memhack.structs.ItBString._makeDirectGetterWrapper(PilotLvlUpSkill, "ShortName")
	memhack.structs.ItBString._makeDirectGetterWrapper(PilotLvlUpSkill, "FullName")
	memhack.structs.ItBString._makeDirectGetterWrapper(PilotLvlUpSkill, "Description")
	
	-- Takes either another PilotLvlUpSkill to (deep) copy or the values
	-- to create the skill
	-- bonuses is an optional table that can optionally define "cores", "health", and "move"
	-- Any not included will default to 0
	PilotLvlUpSkill.Set = function(self, idOrStruct, shortName, fullName, description, saveVal, bonuses)
		local coresBonus = bonuses and bonuses.cores or 0
		local healthBonus = bonuses and bonuses.health or 0
		local moveBonus = bonuses and bonuses.move or 0
		local id = idOrStruct
		
		if type(idOrStruct) == "PilotLvlUpSkill" then
			id = idOrStruct:GetId()
			shortName = idOrStruct:GetShortName()
			fullName = idOrStruct:GetFullName()
			description = idOrStruct:GetDescription()
			saveVal = idOrStruct:GetSaveVal()
			
			coresBonus = idOrStruct:GetCoresBonus()
			healthBonus = idOrStruct:GetHealthBonus()
			moveBonus = idOrStruct:GetMoveBonus()
		end
		
		self:SetId(id)
		self:SetShortName(shortName)
		self:SetFullName(fullName)
		self:SetDescription(description)
		self:SetSaveVal(saveVal)
		
		self:SetCoresBonus(coresBonus)
		self:SetCoresBonus(healthBonus)
		self:SetCoresBonus(moveBonus)
	end
end

function onModsFirstLoaded()
	createPilotFuncs()
	createPilotLvlUpSkillFuncs()
end

modApi.events.onModsFirstLoaded:subscribe(onModsFirstLoaded)
modApi.events.onPawnClassInitialized:subscribe(addPawnGetPilotFunc)
