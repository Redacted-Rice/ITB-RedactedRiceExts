local Pilot = memhack.structManager.define("Pilot", {
	name = { offset = 0x14, type = "struct", subType = "ItBString" },
	xp = { offset = 0x30, type = "int", hideSetter = true},
	levelUpXp = { offset = 0x34, type = "int", hideSetter = true},
	level = { offset = 0x5C, type = "int", hideSetter = true},
	skill = { offset = 0x60, type = "struct", subType = "ItBString" },
	id = { offset = 0x78, type = "struct", subType = "ItBString" },
	lvlUpSkills = { offset = 0xCC, type = "pointer", subType = "PilotLvlUpSkillsArray"},
	prevTimelines = { offset = 0x27C, type = "int" },
})

local itbStrGetterName = memhack.structs.ItBString.makeItBStringGetterName

-- State definition used for tracking changes to pilots via hooks
Pilot.stateDefinition = {
	name = itbStrGetterName("name"),
	"xp", "levelUpXp", "level",
	skill = itbStrGetterName("skill"),
	id = itbStrGetterName("id"),
	-- lvl up skills specifically excluded - separate trigger for that
	"prevTimelines",
}

-- todo: add vftable ref? 0x008320d4
-- pilot pointer vtable ref 00828790
-- skill pointer vtable ref 008287a4
-- Skill has no vtable
-- Smart pointer - two pointers - struct addr, mem_management addr
-- TODO: Add a "verify" function generated that checks the struct looks valid?
-- Checks address is not nil, checks vtable, spot checks fields? e.g. for pilot,
-- getId, check it looks like a string, check it matches somthing in _G, check
-- that that looks like a pilot

local methodGen = memhack.structManager._methodGeneration
local genItBStrGetSetWrappers = memhack.structs.ItBString.makeItBStringGetSetWrappers

function createPilotFuncs()
	-- Auto inject parent references into struct getter already defined
	-- No setters defined for the skills array
	-- Leave the ptr getters/setters alone
	methodGen.wrapGetterToPreserveParent(Pilot, "getLvlUpSkills")

	-- Convinience getter and setters for pilot ItBStrings
	genItBStrGetSetWrappers(Pilot, "name")
	genItBStrGetSetWrappers(Pilot, "skill")
	genItBStrGetSetWrappers(Pilot, "id")

	Pilot.calculateLevelUpXp = function(level)
		return (level + 1) * 25
	end

	local function applyLevelChange(self, newLevel, previousLevel, previousXp, previousLevelUpXp)
		local newLevelUpXp = self.calculateLevelUpXp(newLevel)

		self:_setXp(0)
		self:_setLevel(newLevel)
		self:_setLevelUpXp(newLevelUpXp)

		-- Recombine bonuses based on new level
		self:combineBonuses()

		-- Build changes table and fire hook
		-- Hook fire function automatically updates state tracker to prevent double-fire
		local changes = {
			level = {old = previousLevel, new = newLevel},
			xp = {old = previousXp, new = 0},
			levelUpXp = {old = previousLevelUpXp, new = newLevelUpXp}
		}
		memhack.hooks.firePilotChangedHooks(self, changes)
	end


	Pilot.levelUp = function(self)
		local previousLevel = self:getLevel()
		local newLevel = previousLevel + 1

		if newLevel <= 2 then
			local previousXp = self:getXp()
			local previousLevelUpXp = self:getLevelUpXp()
			applyLevelChange(self, newLevel, previousLevel, previousXp, previousLevelUpXp)
		end
	end

	Pilot.levelDown = function(self)
		local previousLevel = self:getLevel()
		local newLevel = previousLevel - 1

		if newLevel >= 0 then
			local previousXp = self:getXp()
			local previousLevelUpXp = self:getLevelUpXp()
			applyLevelChange(self, newLevel, previousLevel, previousXp, previousLevelUpXp)
		end
	end

	Pilot.setLevel = function(self, newLevel)
		local currentLevel = self:getLevel()

		-- Call levelUp/levelDown as appropriate
		if newLevel > currentLevel then
			for i = 1, (newLevel - currentLevel) do
				self:levelUp()
			end
		elseif newLevel < currentLevel then
			for i = 1, (currentLevel - newLevel) do
				self:levelDown()
			end
		end
	end

	Pilot.setXp = function(self, newXp)
		local currentXp = self:getXp()
		local levelUpXp = self:getLevelUpXp()

		-- Check if we should level up
		if newXp >= levelUpXp then
			self:levelUp()
			return
		end

		-- Check if we should level down
		if newXp < 0 then
			self:levelDown()
			return
		end

		-- Xp change without level change
		if newXp ~= currentXp then
			self:_setXp(newXp)
			local changes = {xp = {old = currentXp, new = newXp}}
			-- Hook fire function automatically updates state tracker
			memhack.hooks.firePilotChangedHooks(self, changes)
		end
	end

	Pilot.addXp = function(self, xpToAdd)
		self:setXp(self:getXp() + xpToAdd)
	end

	-- Get the pawn ID (0-2) for this pilot if piloting a mech, nil otherwise
	Pilot.getPawnId = function(self)
		if not Game then return nil end

		local pilotAddr = self:getAddress()
		for pawnId = 0, 2 do
			local pawn = Game:GetPawn(pawnId)
			if pawn then
				local pawnPilot = pawn:GetPilot()
				if pawnPilot and pawnPilot:getAddress() == pilotAddr then
					return pawnId
				end
			end
		end
		return nil
	end

	-- Check if this pilot is currently piloting a mech
	Pilot.isPiloting = function(self)
		return self:getPawnId() ~= nil
	end

	-- Convenience getter for level up skill by index
	-- idx is either 1 or 2 for the respective skill
	-- Parent wrapping is already handled:
	--   1. getLvlUpSkills() is wrapped (line 74) to inject {Pilot = pilot} into the array
	--   2. getSkill1/2() are wrapped (lines 200-201) to copy parents and add the array
	--   Result: returned skill has _parent = {Pilot = pilot, PilotLvlUpSkillsArray = array}
	Pilot.getLvlUpSkill = function(self, index)
		if index == 1 then
			return self:getLvlUpSkills():getSkill1()
		elseif index == 2 then
			return self:getLvlUpSkills():getSkill2()
		else
			error(string.format("Unexpected index %d. Should be 1 or 2", index))
		end
	end

	-- Convenience setter for level up skills
	-- idx is either 1 or 2 for the respective skill
	-- PilotLvlUpSkill.set for other arg defs
	Pilot.setLvlUpSkill = function(self, index, structOrNewVals)
		if index == 1 then
			self:getLvlUpSkills():setSkill1(structOrNewVals)
		elseif index == 2 then
			self:getLvlUpSkills():setSkill2(structOrNewVals)
		else
			error(string.format("Unexpected index %d. Should be 1 or 2", index))
		end
	end

	-- Combine skill bonuses from both skills into skill1 when appropriate
	-- This handles the cores and grid bonus combining based on pilot level
	-- Called automatically when pilot level changes or skills are modified.
	--
	-- This should all be done transparently to external code. They should use
	-- typical getters and setters and they should behave as you would expect if
	-- they were as straight forward as health and move
	--
	-- Uses "Set" Values in state_tracker
	-- - "Set values" are what external code sees when accessing cores/gridBonus
	-- - "Memory values" are what's actually stored in game memory
	-- - When pilot level >= 2 and both skills have non-zero bonuses, we combine them:
	--   * Memory: skill1 gets sum, skill2 gets 0
	--   * Set: both skills keep their original values
	-- - This makes combining transparent to external code
	-- - External code always sees and sets the "base" values
	-- - Memhack handles combining automatically based on pilot level and setting
	--   memory to ther correct values
	Pilot.combineBonuses = function(self)
		local skill1 = self:getLvlUpSkill(1)
		local skill2 = self:getLvlUpSkill(2)

		if not skill1 or not skill2 then
			return
		end

		local pilotLevel = self:getLevel()

		-- Get set values for both skills. This will return default values
		-- if not yet set
		local skill1Set = memhack.stateTracker.getSkillSetValues(skill1)
		local skill2Set = memhack.stateTracker.getSkillSetValues(skill2)

		-- If level <= 1, restore to base (set) values
		if pilotLevel <= 1 then
			-- Set memory to set values (no combining)
			skill1:_setCoresBonus(skill1Set.coresBonus)
			skill1:_setGridBonus(skill1Set.gridBonus)
			skill2:_setCoresBonus(skill2Set.coresBonus)
			skill2:_setGridBonus(skill2Set.gridBonus)
		else
			-- Level >= 2: combine bonuses when both have non-zero values

			-- Handle cores
			if skill1Set.coresBonus > 0 and skill2Set.coresBonus > 0 then
				-- Both have cores - combine into skill1, zero skill2
				skill1:_setCoresBonus(skill1Set.coresBonus + skill2Set.coresBonus)
				skill2:_setCoresBonus(0) -- not strictly needed but just in case
			else
				-- At least one is zero - use set values as-is
				skill1:_setCoresBonus(skill1Set.coresBonus)
				skill2:_setCoresBonus(skill2Set.coresBonus)
			end

			-- Handle grid (same logic as cores)
			if skill1Set.gridBonus > 0 and skill2Set.gridBonus > 0 then
				-- Both have grid - combine into skill1, zero skill2
				skill1:_setGridBonus(skill1Set.gridBonus + skill2Set.gridBonus)
				skill2:_setGridBonus(0) -- not strictly needed but just in case
			else
				-- At least one is zero - use set values as-is
				skill1:_setGridBonus(skill1Set.gridBonus)
				skill2:_setGridBonus(skill2Set.gridBonus)
			end
		end
	end
end

function onModsFirstLoaded()
	createPilotFuncs()
end

modApi.events.onModsFirstLoaded:subscribe(onModsFirstLoaded)
