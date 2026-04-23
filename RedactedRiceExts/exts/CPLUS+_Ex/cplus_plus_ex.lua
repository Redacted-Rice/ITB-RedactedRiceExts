-- CPLUS+ Extension Main Module
-- Coordinates skill modules and manages save/load operations

-- Create global cplus_plus_ex object
cplus_plus_ex = cplus_plus_ex or {}

local path = GetParentPath(...)

-- Debugging configuration to enable debugging for modules
cplus_plus_ex.DEBUG = {
	ENABLED = false,  -- Disable/enable all debug logging
	TRIGGER_EVENTS = false,
	CONFIG = true,
	REGISTRY = true,
	SELECTION = true,
	CONSTRAINTS = true,
	STATE_TRACKER = false,
	TIME_TRAVELER = false,
	HOOKS = false,
	UI = false,
}

local logger = memhack.logger
local TRIGGER_EVENTS = logger.register("CPLUS+", "Trigger Events", cplus_plus_ex.DEBUG.TRIGGER_EVENTS and cplus_plus_ex.DEBUG.ENABLED)

-- Constants
cplus_plus_ex.MAX_SKILL_SLOTS = 2  -- Maximum number of skill slots per pilot

cplus_plus_ex.REUSABLILITY = { [1] = "REUSABLE", REUSABLE = 1, [2] = "PER_PILOT", PER_PILOT = 2, [3] = "PER_RUN", PER_RUN = 3}
local REUSABLE = cplus_plus_ex.REUSABLILITY.REUSABLE
local PER_PILOT = cplus_plus_ex.REUSABLILITY.PER_PILOT

cplus_plus_ex.SLOT_RESTRICTION = { [1] = "ANY", ANY = 1, [2] = "FIRST", FIRST = 2, [3] = "SECOND", SECOND = 3}

-- Core skill icons since they don't have any
local customVanillaIcons = {
	"img/combat/icons/icon_Pilot_Health.png",
	"img/combat/icons/icon_Pilot_Move.png",
	"img/combat/icons/icon_Pilot_Grid.png",
	"img/combat/icons/icon_Pilot_Reactor.png",
	"img/advanced/combat/icons/icon_Pilot_Skilled.png"
}

local resourcePath = mod_loader.mods[modApi.currentMod].resourcePath
for _, iconPath in ipairs(customVanillaIcons) do
	modApi:appendAsset(iconPath, resourcePath..iconPath)
end
cplus_plus_ex.DEFAULT_REUSABILITY = PER_PILOT
cplus_plus_ex.DEFAULT_SLOT_RESTRICTION = cplus_plus_ex.SLOT_RESTRICTION.ANY
cplus_plus_ex.DEFAULT_WEIGHT = 1.0
cplus_plus_ex.VANILLA_SKILLS = {
	{id = "Health", icon = "img/combat/icons/icon_Pilot_Health.png", shortName = "Pilot_HealthShort", fullName = "Pilot_HealthName", description= "Pilot_HealthDesc", bonuses = {health = 2}, saveVal = 0, reusability = REUSABLE },
	{id = "Move", icon = "img/combat/icons/icon_Pilot_Move.png", shortName = "Pilot_MoveShort", fullName = "Pilot_MoveName", description= "Pilot_MoveDesc", bonuses = {move = 1}, saveVal = 1, reusability = REUSABLE },
	{id = "Grid", icon = "img/combat/icons/icon_Pilot_Grid.png", shortName = "Pilot_GridShort", fullName = "Pilot_GridName", description= "Pilot_GridDesc", bonuses = {grid = 3}, saveVal = 2, reusability = REUSABLE },
	{id = "Reactor", icon = "img/combat/icons/icon_Pilot_Reactor.png", shortName = "Pilot_ReactorShort", fullName = "Pilot_ReactorName", description= "Pilot_ReactorDesc", bonuses = {cores = 1}, saveVal = 3, reusability = REUSABLE },
	{id = "Opener", icon = "img/advanced/combat/icons/icon_Pilot_Opener.png", shortName = "Pilot_OpenerName", fullName = "Pilot_OpenerName", description= "Pilot_OpenerDesc", saveVal = 4, reusability = PER_PILOT }, -- doesn't work
	{id = "Closer", icon = "img/advanced/combat/icons/icon_Pilot_Closer.png", shortName = "Pilot_CloserName", fullName = "Pilot_CloserName", description= "Pilot_CloserDesc", saveVal = 5, reusability = PER_PILOT }, -- doesn't work
	{id = "Popular", icon = "img/advanced/combat/icons/icon_Pilot_Popular.png", shortName = "Pilot_PopularName", fullName = "Pilot_PopularName", description= "Pilot_PopularDesc", saveVal = 6, reusability = PER_PILOT }, -- doesn't work
	{id = "Thick", icon = "img/advanced/combat/icons/icon_Pilot_Thick.png", shortName = "Pilot_ThickName", fullName = "Pilot_ThickName", description= "Pilot_ThickDesc", saveVal = 7, reusability = PER_PILOT }, -- doesn't make sense
	{id = "Skilled", icon = "img/advanced/combat/icons/icon_Pilot_Skilled.png", shortName = "Pilot_SkilledName", fullName = "Pilot_SkilledName", description= "Pilot_SkilledDesc", bonuses = {health = 2, move = 1}, saveVal = 8, reusability = REUSABLE },
	{id = "Invulnerable", icon = "img/advanced/combat/icons/icon_Pilot_Invulnerable.png", shortName = "Pilot_InvulnerableName", fullName = "Pilot_InvulnerableName", description= "Pilot_InvulnerableDesc", saveVal = 9, reusability = PER_PILOT }, -- doesn't make sense
	{id = "Adrenaline", icon = "img/advanced/combat/icons/icon_Pilot_Adrenaline.png", shortName = "Pilot_AdrenalineName", fullName = "Pilot_AdrenalineName", description= "Pilot_AdrenalineDesc", saveVal = 10, reusability = PER_PILOT }, -- doesn't work
	{id = "Pain", icon = "img/advanced/combat/icons/icon_Pilot_Pain.png", shortName = "Pilot_PainName", fullName = "Pilot_PainName", description= "Pilot_PainDesc", saveVal = 11, reusability = PER_PILOT }, -- doesn't work
	{id = "Regen", icon = "img/advanced/combat/icons/icon_Pilot_Regen.png", shortName = "Pilot_RegenName", fullName = "Pilot_RegenName", description= "Pilot_RegenDesc", saveVal = 12, reusability = PER_PILOT }, -- doesn't work
	{id = "Conservative", icon = "img/advanced/combat/icons/icon_Pilot_Conservative.png", shortName = "Pilot_ConservativeName", fullName = "Pilot_ConservativeName", description= "Pilot_ConservativeDesc", saveVal = 13, reusability = PER_PILOT }, -- doesn't work
}

cplus_plus_ex._subobjects = {}
cplus_plus_ex._subobjects.utils = require(path.."scripts/utils")
cplus_plus_ex._subobjects.skill_registry = require(path.."scripts/skill_registry")
cplus_plus_ex._subobjects.skill_config = require(path.."scripts/skill_config")
cplus_plus_ex._subobjects.skill_selection = require(path.."scripts/skill_selection")
cplus_plus_ex._subobjects.skill_constraints = require(path.."scripts/skill_constraints")
cplus_plus_ex._subobjects.time_traveler = require(path.."scripts/time_traveler")
cplus_plus_ex._subobjects.hooks = require(path.."scripts/hooks")
cplus_plus_ex._subobjects.skill_state_tracker = require(path.."scripts/skill_state_tracker")
cplus_plus_ex._subobjects.modify_pilot_skills_ui = require(path.."scripts/modify_pilot_skills_ui")

-- Local references to submodules for convenient access in this file
local utils = cplus_plus_ex._subobjects.utils
local skill_registry = cplus_plus_ex._subobjects.skill_registry
local skill_config = cplus_plus_ex._subobjects.skill_config
local skill_selection = cplus_plus_ex._subobjects.skill_selection
local skill_constraints = cplus_plus_ex._subobjects.skill_constraints
local time_traveler = cplus_plus_ex._subobjects.time_traveler
local hooks = cplus_plus_ex._subobjects.hooks
local skill_state_tracker = cplus_plus_ex._subobjects.skill_state_tracker
local modify_pilot_skills_ui = cplus_plus_ex._subobjects.modify_pilot_skills_ui

-- Initialize modules
function cplus_plus_ex:initModules()
	-- Initialize submodules (they will set their local references here)
	hooks:init()
	skill_state_tracker:init()
	skill_config:init()
	skill_constraints:init()
	skill_registry:init()
	skill_selection:init()
	time_traveler:init()
	modify_pilot_skills_ui:init()
end

-- Helper function that returns the pawn struct if the pilot corresponds to a TechnoVek cyborg
-- Returns the pawn struct if it exists and has Class == "TechnoVek", otherwise returns nil
function cplus_plus_ex.getTechnoVekPawn(pilotId)
	if not pilotId or type(pilotId) ~= "string" then
		return nil
	end
	
	-- Extract pawn name from pilot ID (e.g., "Pilot_BeetleMech" -> "BeetleMech")
	local pawnName = pilotId:match("^Pilot_(.+)$")
	if not pawnName then
		return nil
	end
	
	-- Check if the pawn exists and is a TechnoVek
	local pawn = _G[pawnName]
	if pawn and type(pawn) == "table" and pawn.Class == "TechnoVek" then
		return pawn
	end
	
	return nil
end

-- Checks if a pilot ID corresponds to a cyborg pilot
-- Cyborgs are identified by their pawn having Class == "TechnoVek"
function cplus_plus_ex.isCyborg(pilotId)
	return cplus_plus_ex.getTechnoVekPawn(pilotId) ~= nil
end

-- Checks if a pilot ID corresponds to a flying cyborg
-- This checks both that the pilot is a cyborg AND that their pawn has Flying = true
function cplus_plus_ex.isFlyingCyborg(pilotId)
	local pawn = cplus_plus_ex.getTechnoVekPawn(pilotId)
	return pawn ~= nil and pawn.Flying == true
end

function cplus_plus_ex:exposeAPI()
	-- Expose commonly used submodules/data at root level for easier external access
	self.hooks = hooks
	self.events = hooks.events
	self.config = skill_config.config
	self.SkillConfig = skill_config.SkillConfig
	self.RelationshipType = skill_config.RelationshipType

	-- Expose API functions that delegate to submodules
	function cplus_plus_ex:setSkillConfig(...) return skill_config:setSkillConfig(...) end
	function cplus_plus_ex:enableSkill(...) return skill_config:enableSkill(...) end
	function cplus_plus_ex:disableSkill(...) return skill_config:disableSkill(...) end
	function cplus_plus_ex:resetToDefaults() return skill_config:resetToDefaults() end
	function cplus_plus_ex:getAllowedReusability(...) return skill_config:getAllowedReusability(...) end
	function cplus_plus_ex:getEnabledSkillsSet() return skill_config:getEnabledSkillsSet() end
	function cplus_plus_ex:saveConfiguration() return skill_config:saveConfiguration() end
	function cplus_plus_ex:loadConfiguration() return skill_config:loadConfiguration() end

	-- Constraint functions
	function cplus_plus_ex:checkSkillConstraints(...) return skill_constraints:checkSkillConstraints(...) end
	function cplus_plus_ex:registerConstraintFunction(...) return skill_constraints:registerConstraintFunction(...) end

	-- Skill management functions
	function cplus_plus_ex:registerSkill(...) return skill_registry:registerSkill(...) end
	function cplus_plus_ex:registerPilotSkillExclusions(...) return skill_registry:registerPilotSkillExclusions(...) end
	function cplus_plus_ex:registerPilotSkillInclusions(...) return skill_registry:registerPilotSkillInclusions(...) end
	function cplus_plus_ex:registerSquadSkillExclusions(...) return skill_registry:registerSquadSkillExclusions(...) end
	function cplus_plus_ex:registerSquadSkillInclusions(...) return skill_registry:registerSquadSkillInclusions(...) end
	function cplus_plus_ex:registerSkillExclusion(...) return skill_registry:registerSkillExclusion(...) end
	-- Getters for info
	function cplus_plus_ex:isCodeDefinedRelationship(...) return skill_config:isCodeDefinedRelationship(...) end
	function cplus_plus_ex:getRelationshipMetadata(...) return skill_config:getRelationshipMetadata(...) end
	-- Used by UI Only
	function cplus_plus_ex:addRelationshipToRuntime(...) return skill_config:addRelationshipToRuntime(...) end
	function cplus_plus_ex:removeRelationshipFromRuntime(...) return skill_config:removeRelationshipFromRuntime(...) end

	-- Group management functions
	function cplus_plus_ex:registerSkillToGroup(...) return skill_registry:registerSkillToGroup(...) end
	-- Getters for info
	function cplus_plus_ex:getGroup(...) return skill_config:getGroup(...) end
	function cplus_plus_ex:listGroups(...) return skill_config:listGroups(...) end
	-- Used by UI Only
	function cplus_plus_ex:addGroupToRuntime(...) return skill_config:addGroupToRuntime(...) end
	function cplus_plus_ex:deleteGroupFromRuntime(...) return skill_config:deleteGroupFromRuntime(...) end
	function cplus_plus_ex:registerSkillToGroupToRuntime(...) return skill_config:registerSkillToGroupToRuntime(...) end
	function cplus_plus_ex:removeSkillFromGroupFromRuntime(...) return skill_config:removeSkillFromGroupFromRuntime(...) end
	function cplus_plus_ex:setGroupEnabled(...) return skill_config:setGroupEnabled(...) end

	-- Skill assignment functions
	function cplus_plus_ex:applySkillsToPilot(...) return skill_selection:applySkillsToPilot(...) end
	function cplus_plus_ex:applySkillIdsToPilot(...) return skill_selection:applySkillIdsToPilot(...) end
	function cplus_plus_ex:applySkillsToAllPilots() return skill_selection:applySkillsToAllPilots() end
	function cplus_plus_ex:selectRandomSkill(...) return skill_selection:selectRandomSkill(...) end
	function cplus_plus_ex:selectRandomSkills(...) return skill_selection:selectRandomSkills(...) end

	-- Skill state checking functions
	function cplus_plus_ex:isSkillEnabled(...) return skill_state_tracker:isSkillEnabled(...) end
	function cplus_plus_ex:isSkillInRun(...) return skill_state_tracker:isSkillInRun(...) end
	function cplus_plus_ex:isSkillActive(...) return skill_state_tracker:isSkillActive(...) end
	function cplus_plus_ex:isSkillOnPawn(...) return skill_state_tracker:isSkillOnPawn(...) end
	function cplus_plus_ex:isSkillOnPilot(...) return skill_state_tracker:isSkillOnPilot(...) end
	function cplus_plus_ex:isSkillOnPilots(...) return skill_state_tracker:isSkillOnPilots(...) end

	-- Get pilots/mechs with skills
	function cplus_plus_ex:getPilotsWithSkill(...) return skill_state_tracker:getPilotsWithSkill(...) end
	function cplus_plus_ex:getMechsWithSkill(...) return skill_state_tracker:getMechsWithSkill(...) end

	-- Get all skills by category
	function cplus_plus_ex:getSkillsEnabled(...) return skill_state_tracker:getSkillsEnabled(...) end
	function cplus_plus_ex:getSkillsInRun(...) return skill_state_tracker:getSkillsInRun(...) end
	function cplus_plus_ex:getSkillObjsInRun(...) return skill_state_tracker:getSkillObjsInRun(...) end
	function cplus_plus_ex:getSkillsActive(...) return skill_state_tracker:getSkillsActive(...) end
	function cplus_plus_ex:getSkillObjsActive(...) return skill_state_tracker:getSkillObjsActive(...) end

	-- Pilot skill tracking helpers
	function cplus_plus_ex:hasPilotEarnedSkillIndex(...) return skill_state_tracker:hasPilotEarnedSkillIndex(...) end
	function cplus_plus_ex:getPilotEarnedSkillIndexes(...) return skill_state_tracker:getPilotEarnedSkillIndexes(...) end
	function cplus_plus_ex:getPilotSkillIndices(...) return skill_state_tracker:getPilotSkillIndices(...) end

	-- Wrapper for potentialTimeTravelers since we can't do a ref as we reassign the ref each time we find the time traveler
	function cplus_plus_ex:getPotentialTimeTravelers() return time_traveler.potentialTimeTravelers end
end

-- Orchestrates skill assignment and persistent data saving workflow
function cplus_plus_ex:updateAndSaveSkills()
	-- These are done here instead of delegating to lower level files because we have a specific order
	-- we want these to happen in and they are dependent on each other
end

function cplus_plus_ex:overwriteAeSkillsUiText()
	modApi.modLoaderDictionary["Toggle_NewPilotAbilities"] = "Abilities Overriden"
	modApi.modLoaderDictionary["TipTitle_New_PilotAbilities"] = "CPLUS+ Controls Abilities"
	modApi.modLoaderDictionary["TipText_New_PilotAbilities"] = "You can click this all you want but it won't do anything "..
		"other than change a few pixels.\n\nTo change what skills are enabled, probabilities and relationships, go to the "..
		"main menu, click the \"Mod Content\" button then the \"Modify Pilot Abilities\" button"
end

function cplus_plus_ex:init()
	self:initModules()
	self:exposeAPI()

	-- Add events
	self:addEvents()

	self:overwriteAeSkillsUiText()
end

function cplus_plus_ex:load(options)
	-- Load submodules that need loading
	hooks:load()
	time_traveler:load()
end

function cplus_plus_ex:addEvents()
	-- Save game event
	modApi.events.onSaveGame:subscribe(function()
		logger.logDebug(TRIGGER_EVENTS, "onSaveGame")
		skill_state_tracker:_updateAllStates()
		skill_selection:applySkillsToAllPilots()
		time_traveler:_updateDataOnSave()
	end)

	-- Subscribe to modApi events
	modApi.events.onModsFirstLoaded:subscribe(function()
		logger.logDebug(TRIGGER_EVENTS, "onModsFirstLoaded")
		skill_registry:_postModsLoaded()
		skill_config:_postModsLoaded()
	end)

	modApi.events.onPodWindowShown:subscribe(function()
		logger.logDebug(TRIGGER_EVENTS, "onPodWindowShown")
		skill_selection:_selectSkillsForPodPilot()
	end)

	modApi.events.onPerfectIslandWindowShown:subscribe(function()
		logger.logDebug(TRIGGER_EVENTS, "onPodWindowShown")
		skill_selection:_selectSkillsForPerfectIslandPilot()
	end)

	modApi.events.onGameEntered:subscribe(function()
		logger.logDebug(TRIGGER_EVENTS, "onGameEntered")
		--skill_selection:_clearPilotTracking()
		--skill_state_tracker:_resetAllTrackers()
	end)

	-- clear on load/reload
	modApi.events.onModsLoaded:subscribe(function()
		logger.logDebug(TRIGGER_EVENTS, "onModsLoaded")
		skill_selection:_clearPilotTracking()
		skill_state_tracker:_resetAllTrackers()
	end)

	modApi.events.onGameExited:subscribe(function()
		logger.logDebug(TRIGGER_EVENTS, "onGameExited")
		skill_selection:_clearPilotTracking()
		skill_state_tracker:_updateAllStates()
	end)

	modApi.events.onGameVictory:subscribe(function()
		logger.logDebug(TRIGGER_EVENTS, "onGameVictory")
		skill_selection:_clearPilotTracking()
		skill_state_tracker:_updateAllStates()
	end)

	modApi.events.onHangarEntered:subscribe(function()
		logger.logDebug(TRIGGER_EVENTS, "onHangarEntered")
		time_traveler:_searchForTimeTraveler()
	end)

	-- Memhack events for skill state tracking
	memhack.events.onPilotChanged:subscribe(function(pilot, changes)
		logger.logDebug(TRIGGER_EVENTS, "onPilotChanged")
		skill_state_tracker:_updateStatesIfNeeded(pilot, changes)
	end)

	memhack.events.onPilotLvlUpSkillChanged:subscribe(function(pilot, skill, changes)
		logger.logDebug(TRIGGER_EVENTS, "onPilotLvlUpSkillChanged")
		skill_state_tracker:_updateAllStates()
	end)

	-- Subscribe to our own events for skill state tracking as well
	hooks.events.onPreAssigningLvlUpSkills:subscribe(function()
		logger.logDebug(TRIGGER_EVENTS, "onPreAssigningLvlUpSkills")
		skill_state_tracker:_beginAssignment()
	end)

	hooks.events.onPostAssigningLvlUpSkills:subscribe(function()
		logger.logDebug(TRIGGER_EVENTS, "onPostAssigningLvlUpSkills")
		skill_state_tracker:_updateAfterAssignment()
	end)
end