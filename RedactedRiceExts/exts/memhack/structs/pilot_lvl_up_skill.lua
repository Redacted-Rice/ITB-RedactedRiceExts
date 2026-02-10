local PilotLvlUpSkill = memhack.structManager.define("PilotLvlUpSkill", {
	-- This is the main value used to determine skill effect in game. Note that the + move, hp, & cores
	-- skills use the bonus values below instead
	id = { offset = 0x0, type = "struct", subType = "ItBString" },
	-- Displayed in the small box in UI
	shortName = { offset = 0x18, type = "struct", subType = "ItBString" },
	-- Displayed when hovering over skill
	fullName = { offset = 0x30, type = "struct", subType = "ItBString" },
	-- Displayed when hovering over skill
	description = { offset = 0x48, type = "struct", subType = "ItBString" },
	healthBonus = { offset = 0x60, type = "int"},
	-- Hide getters/setters so we can define public ones that track what was set
	-- vs what we need to put in memory for these to combine correctly
	-- For cores and grid bonus. Multiple health and move are handled by game already
	coresBonus = { offset = 0x64, type = "int", hideGetter = true, hideSetter = true},
	gridBonus = { offset = 0x68, type = "int", hideGetter = true, hideSetter = true},
	moveBonus = { offset = 0x6C, type = "int"},
	-- Value used in save file. Does not directly change effect. ID does this
	-- Valid values are between 0-13. Other values will be saved but are clamped
	-- to this range before the onGameEntered event is fired
	saveVal = { offset = 0x70, type = "int"},
})

local itbStrGetterName = memhack.structs.ItBString.makeItBStringGetterName

-- State definition used for tracking changes to skills via hooks
PilotLvlUpSkill.stateDefinition = {
	id = itbStrGetterName("id"),
	shortName = itbStrGetterName("shortName"),
	fullName = itbStrGetterName("fullName"),
	description = itbStrGetterName("description"),
	-- Note we use the default public getter for grid & cores because we implement those to
	-- behave as someone would expect them to without having to deal with the combining
	"healthBonus", "coresBonus", "gridBonus", "moveBonus", "saveVal"
}

local selfSetter = memhack.structManager.makeStdSelfSetterName()
local methodGen = memhack.structManager._methodGeneration
local genItBStrGetSetWrappers = memhack.structs.ItBString.makeItBStringGetSetWrappers

-- Convinience wrappers for lvl up skills ItBStrings
genItBStrGetSetWrappers(PilotLvlUpSkill, "id")
genItBStrGetSetWrappers(PilotLvlUpSkill, "shortName")
genItBStrGetSetWrappers(PilotLvlUpSkill, "fullName")
genItBStrGetSetWrappers(PilotLvlUpSkill, "description")

-- Add convenience parent getter methods
methodGen.makeParentGetterWrapper(PilotLvlUpSkill, "Pilot")
methodGen.makeParentGetterWrapper(PilotLvlUpSkill, "PilotLvlUpSkillsArray")

-- Create public getters/setters for cores/grid that handle set value tracking
-- The raw memory getters/setters are hidden (prefixed with _) by the struct definition
-- and will be set by combineBonuses

-- Public getters return set values from state tracker
PilotLvlUpSkill.getCoresBonus = function(self)
	local result = memhack.stateTracker.getSkillSetValue(self, "coresBonus")
	return result
end

PilotLvlUpSkill.getGridBonus = function(self)
	local result = memhack.stateTracker.getSkillSetValue(self, "gridBonus")
	return result
end

-- Public setters track set values and trigger combining
PilotLvlUpSkill.setCoresBonus = function(self, value)
	-- Store new set value
	memhack.stateTracker.setSkillSetValue(self, "coresBonus", value)

	-- Trigger combining logic on parent pilot
	local pilot = self:getParentPilot()
	if pilot then
		-- combine will set memory values
		pilot:combineBonuses()
	else
		self:_setCoresBonus(value)
	end
end

PilotLvlUpSkill.setGridBonus = function(self, value)
	-- Store new set value
	memhack.stateTracker.setSkillSetValue(self, "gridBonus", value)

	-- Trigger combining logic on parent pilot
	local pilot = self:getParentPilot()
	if pilot then
		-- combine will set memory values
		pilot:combineBonuses()
	else
		self:_setGridBonus(value)
	end
end

-- Wrap setters to trigger skill changed hooks on change
local fireFn = memhack.hooks.firePilotLvlUpSkillChangedHooks
local defaultSetter = nil -- Means use default name convention for setter
-- For ItBString fields, pass nil for setterName and custom getter name as 5th arg
methodGen.wrapSetterToFireOnValueChange(PilotLvlUpSkill, "id", fireFn, defaultSetter, itbStrGetterName("id"))
methodGen.wrapSetterToFireOnValueChange(PilotLvlUpSkill, "shortName", fireFn, defaultSetter, itbStrGetterName("shortName"))
methodGen.wrapSetterToFireOnValueChange(PilotLvlUpSkill, "fullName", fireFn, defaultSetter, itbStrGetterName("fullName"))
methodGen.wrapSetterToFireOnValueChange(PilotLvlUpSkill, "description", fireFn, defaultSetter, itbStrGetterName("description"))
methodGen.wrapSetterToFireOnValueChange(PilotLvlUpSkill, "healthBonus", fireFn)
methodGen.wrapSetterToFireOnValueChange(PilotLvlUpSkill, "coresBonus", fireFn)
methodGen.wrapSetterToFireOnValueChange(PilotLvlUpSkill, "gridBonus", fireFn)
methodGen.wrapSetterToFireOnValueChange(PilotLvlUpSkill, "moveBonus", fireFn)
methodGen.wrapSetterToFireOnValueChange(PilotLvlUpSkill, "saveVal", fireFn)

-- generate full setter that triggers on change of any value
PilotLvlUpSkill[selfSetter] = methodGen.generateStructSetterToFireOnAnyValueChange(
		fireFn, PilotLvlUpSkill.stateDefinition)
