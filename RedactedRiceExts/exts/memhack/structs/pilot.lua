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
	healthBonus = { offset = 0x60, type = "int"},
	coresBonus = { offset = 0x64, type = "int"},
	gridBonus = { offset = 0x68, type = "int"},
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
	name = { offset = 0x14, type = "struct", structType = "ItBString" },
	xp = { offset = 0x30, type = "int", hideSetter = true},
	levelUpXp = { offset = 0x34, type = "int", hideSetter = true},
	level = { offset = 0x5C, type = "int", hideSetter = true},
	skill = { offset = 0x60, type = "struct", structType = "ItBString" },
	id = { offset = 0x78, type = "struct", structType = "ItBString" },
	lvlUpSkills = { offset = 0xCC, type = "pointer", pointedType = "PilotLvlUpSkillsArray"},
	prevTimelines = { offset = 0x27C, type = "int" },
})

-- todo: add vftable ref? 0x008320d4
-- pilot pointer vtable ref 00828790
-- skill pointer vtable ref 008287a4
-- Skill has no vtable
-- Smart pointer - two pointers - struct addr, mem_management addr

local selfSetter = memhack.structManager.makeStdSelfSetterName()

function addPawnGetPilotFunc(BoardPawn, pawn)
	-- Upper case to align with BoardPawn conventions
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

	Pilot.levelUp = function(self)
		local previousLevel = self:getLevel()
		local previousXp = self:getXp()
		local newLevel = previousLevel + 1
		if newLevel <= 2 then
			self:_setXp(0)
			self:_setLevel(newLevel)
			self:_setLevelUpXp((newLevel + 1) * 25)

			-- Manually fire. This change will not by default cause a save game change which is our
			-- main trigger for the level change
			
			memhack.hooks.fireOnPilotLevelChanged(self, previousLevel, previousXp)
		end
	end

	Pilot.levelDown = function(self)
		local previousLevel = self:getLevel()
		local previousXp = self:getXp()
		local newLevel = previousLevel - 1
		if newLevel >= 0 then
			self:_setXp(0)
			self:_setLevel(newLevel)
			self:_setLevelUpXp((newLevel + 1) * 25)

			-- Manually fire. This change will not by default cause a save game change which is our
			-- main trigger for the level change
			memhack.hooks.fireOnPilotLevelChanged(self, previousLevel, previousXp)
		end
	end
end

function createPilotLvlUpSkillFuncs()
	-- Convinience wrappers for level up skills
	-- idx is either 1 or 2 for the respective skill
	-- PilotLvlUpSkill.set for other arg defs
	Pilot.setLvlUpSkill = function(self, index, idOrStruct, shortName, fullName, description, saveVal, bonuses)
		if index == 1 then
			self:getLvlUpSkills():setSkill1(idOrStruct, shortName, fullName, description, saveVal, bonuses)
		elseif index == 2 then
			self:getLvlUpSkills():setSkill2(idOrStruct, shortName, fullName, description, saveVal, bonuses)
		else
			error(string.format("Unexpected index %d. Should be 1 or 2", index))
		end
	end

	-- Convinience wrappers for pilot ItBStrings
	memhack.structManager.makeSetterWrapper(Pilot, "name")
	memhack.structManager.makeSetterWrapper(Pilot, "skill")
	memhack.structManager.makeSetterWrapper(Pilot, "id")
	memhack.structManager.makeItBStringGetterWrapper(Pilot, "name")
	memhack.structManager.makeItBStringGetterWrapper(Pilot, "skill")
	memhack.structManager.makeItBStringGetterWrapper(Pilot, "id")

	-- Convinience wrappers for level up skills array values
	-- See PilotLvlUpSkill.set for arg defs
	memhack.structManager.makeSetterWrapper(PilotLvlUpSkillsArray, "skill1")
	memhack.structManager.makeSetterWrapper(PilotLvlUpSkillsArray, "skill2")

	-- Convinience wrappers for lvl up skills ItBStrings
	memhack.structManager.makeSetterWrapper(PilotLvlUpSkill, "id")
	memhack.structManager.makeSetterWrapper(PilotLvlUpSkill, "shortName")
	memhack.structManager.makeSetterWrapper(PilotLvlUpSkill, "fullName")
	memhack.structManager.makeSetterWrapper(PilotLvlUpSkill, "description")
	memhack.structManager.makeItBStringGetterWrapper(PilotLvlUpSkill, "id")
	memhack.structManager.makeItBStringGetterWrapper(PilotLvlUpSkill, "shortName")
	memhack.structManager.makeItBStringGetterWrapper(PilotLvlUpSkill, "fullName")
	memhack.structManager.makeItBStringGetterWrapper(PilotLvlUpSkill, "description")

	-- Whole object setter for PilotLvlUpSkill
	-- Takes either another PilotLvlUpSkill to (deep) copy or the individual values
	-- to create the skill
	-- bonuses is an optional table that can optionally define "health", "cores", "grid", and "move"
	-- Any not included will default to 0

	PilotLvlUpSkill[selfSetter] = function(self, idOrStruct, shortName, fullName, description, saveVal, bonuses)
		local healthBonus = bonuses and bonuses.health or 0
		local coresBonus = bonuses and bonuses.cores or 0
		local gridBonus = bonuses and bonuses.grid or 0
		local moveBonus = bonuses and bonuses.move or 0
		local id = idOrStruct
		--LOG("bonuses = " .. healthBonus .. " ".. coresBonus .. " ".. gridBonus .. " ".. moveBonus)

		if type(idOrStruct) == "table" and getmetatable(idOrStruct) == PilotLvlUpSkill then
			id = idOrStruct:getIdStr()
			shortName = idOrStruct:getShortNameStr()
			fullName = idOrStruct:getFullNameStr()
			description = idOrStruct:getDescriptionStr()
			saveVal = idOrStruct:getSaveVal()

			healthBonus = idOrStruct:getHealthBonus()
			coresBonus = idOrStruct:getCoresBonus()
			gridBonus = idOrStruct:getGridBonus()
			moveBonus = idOrStruct:getMoveBonus()
		end

		self:setId(id)
		self:setShortName(shortName)
		self:setFullName(fullName)
		self:setDescription(description)
		self:setSaveVal(saveVal)

		self:setHealthBonus(healthBonus)
		self:setCoresBonus(coresBonus)
		self:setGridBonus(gridBonus)
		self:setMoveBonus(moveBonus)
	end
end

function onModsFirstLoaded()
	createPilotFuncs()
	createPilotLvlUpSkillFuncs()
end

modApi.events.onModsFirstLoaded:subscribe(onModsFirstLoaded)
modApi.events.onPawnClassInitialized:subscribe(addPawnGetPilotFunc)
