-- CPLUS+ Extension Main Module
-- Coordinates skill modules and manages save/load operations

-- Create global cplus_plus_ex object
cplus_plus_ex = cplus_plus_ex or {}

local path = GetParentPath(...)

-- Debugging configuration to enable debugging for modules
cplus_plus_ex.DEBUG = {
	ENABLED = true,  -- Disable/enable all debug logging
	CONFIG = true,
	REGISTRY = true,
	SELECTION = true,
	CONSTRAINTS = true,
	STATE_TRACKER = true,
	TIME_TRAVELER = true,
	HOOKS = true,
	UI = false,
}

-- Constants
cplus_plus_ex.REUSABLILITY = { [1] = "REUSABLE", REUSABLE = 1, [2] = "PER_PILOT", PER_PILOT = 2, [3] = "PER_RUN", PER_RUN = 3}
local REUSABLE = cplus_plus_ex.REUSABLILITY.REUSABLE
local PER_PILOT = cplus_plus_ex.REUSABLILITY.PER_PILOT

cplus_plus_ex.DEFAULT_REUSABILITY = PER_PILOT
cplus_plus_ex.DEFAULT_WEIGHT = 1.0
cplus_plus_ex.VANILLA_SKILLS = {
	{id = "Health", shortName = "Pilot_HealthShort", fullName = "Pilot_HealthName", description= "Pilot_HealthDesc", bonuses = {health = 2}, saveVal = 0, reusability = REUSABLE },
	{id = "Move", shortName = "Pilot_MoveShort", fullName = "Pilot_MoveName", description= "Pilot_MoveDesc", bonuses = {move = 1}, saveVal = 1, reusability = REUSABLE },
	{id = "Grid", shortName = "Pilot_GridShort", fullName = "Pilot_GridName", description= "Pilot_GridDesc", bonuses = {grid = 3}, saveVal = 2, reusability = REUSABLE },
	{id = "Reactor", shortName = "Pilot_ReactorShort", fullName = "Pilot_ReactorName", description= "Pilot_ReactorDesc", bonuses = {cores = 1}, saveVal = 3, reusability = REUSABLE },
	{id = "Opener", shortName = "Pilot_OpenerName", fullName = "Pilot_OpenerName", description= "Pilot_OpenerDesc", saveVal = 4, reusability = PER_PILOT }, -- doesn't work
	{id = "Closer", shortName = "Pilot_CloserName", fullName = "Pilot_CloserName", description= "Pilot_CloserDesc", saveVal = 5, reusability = PER_PILOT }, -- doesn't work
	{id = "Popular", shortName = "Pilot_PopularName", fullName = "Pilot_PopularName", description= "Pilot_PopularDesc", saveVal = 6, reusability = PER_PILOT }, -- doesn't work
	{id = "Thick", shortName = "Pilot_ThickName", fullName = "Pilot_ThickName", description= "Pilot_ThickDesc", saveVal = 7, reusability = PER_PILOT }, -- doesn't make sense
	{id = "Skilled", shortName = "Pilot_SkilledName", fullName = "Pilot_SkilledName", description= "Pilot_SkilledDesc", bonuses = {health = 2, move = 1}, saveVal = 8, reusability = REUSABLE },
	{id = "Invulnerable", shortName = "Pilot_InvulnerableName", fullName = "Pilot_InvulnerableName", description= "Pilot_InvulnerableDesc", saveVal = 9, reusability = PER_PILOT }, -- doesn't make sense
	{id = "Adrenaline", shortName = "Pilot_AdrenalineName", fullName = "Pilot_AdrenalineName", description= "Pilot_AdrenalineDesc", saveVal = 10, reusability = PER_PILOT }, -- doesn't work
	{id = "Pain", shortName = "Pilot_PainName", fullName = "Pilot_PainName", description= "Pilot_PainDesc", saveVal = 11, reusability = PER_PILOT }, -- doesn't work
	{id = "Regen", shortName = "Pilot_RegenName", fullName = "Pilot_RegenName", description= "Pilot_RegenDesc", saveVal = 12, reusability = PER_PILOT }, -- doesn't work
	{id = "Conservative", shortName = "Pilot_ConservativeName", fullName = "Pilot_ConservativeName", description= "Pilot_ConservativeDesc", saveVal = 13, reusability = PER_PILOT }, -- doesn't work
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

function cplus_plus_ex:exposeAPI()
	-- Expose commonly used submodules/data at root level for easier external access
	self.hooks = hooks
	self.config = skill_config.config
	self.SkillConfig = skill_config.SkillConfig

	-- Expose API functions that delegate to submodules
	function cplus_plus_ex:setSkillConfig(...) return skill_config:setSkillConfig(...) end
	function cplus_plus_ex:enableSkill(...) return skill_config:enableSkill(...) end
	function cplus_plus_ex:disableSkill(...) return skill_config:disableSkill(...) end
	function cplus_plus_ex:resetToDefaults() return skill_config:resetToDefaults() end
	function cplus_plus_ex:getAllowedReusability(...) return skill_config:getAllowedReusability(...) end
	function cplus_plus_ex:saveConfiguration() return skill_config:saveConfiguration() end
	function cplus_plus_ex:loadConfiguration() return skill_config:loadConfiguration() end

	function cplus_plus_ex:checkSkillConstraints(...) return skill_constraints:checkSkillConstraints(...) end
	function cplus_plus_ex:registerConstraintFunction(...) return skill_constraints:registerConstraintFunction(...) end

	function cplus_plus_ex:registerSkill(...) return skill_registry:registerSkill(...) end
	function cplus_plus_ex:registerPilotSkillExclusions(...) return skill_registry:registerPilotSkillExclusions(...) end
	function cplus_plus_ex:registerPilotSkillInclusions(...) return skill_registry:registerPilotSkillInclusions(...) end
	function cplus_plus_ex:registerSkillExclusion(...) return skill_registry:registerSkillExclusion(...) end

	function cplus_plus_ex:applySkillsToPilot(...) return skill_selection:applySkillsToPilot(...) end
	function cplus_plus_ex:applySkillsToAllPilots() return skill_selection:applySkillsToAllPilots() end

	-- Skill state checking functions
	function cplus_plus_ex:isSkillEnabled(...) return skill_state_tracker:isSkillEnabled(...) end
	function cplus_plus_ex:isSkillInRun(...) return skill_state_tracker:isSkillInRun(...) end
	function cplus_plus_ex:isSkillActive(...) return skill_state_tracker:isSkillActive(...) end
	function cplus_plus_ex:isSkillOnPilot(...) return skill_state_tracker:isSkillOnPilot(...) end
	function cplus_plus_ex:isSkillOnPilots(...) return skill_state_tracker:isSkillOnPilots(...) end

	-- Get pilots/mechs with skills
	function cplus_plus_ex:getPilotsWithSkill(...) return skill_state_tracker:getPilotsWithSkill(...) end
	function cplus_plus_ex:getMechsWithSkill(...) return skill_state_tracker:getMechsWithSkill(...) end

	-- Get all skills by category
	function cplus_plus_ex:getSkillsEnabled(...) return skill_state_tracker:getSkillsEnabled(...) end
	function cplus_plus_ex:getSkillsInRun(...) return skill_state_tracker:getSkillsInRun(...) end
	function cplus_plus_ex:getSkillsActive(...) return skill_state_tracker:getSkillsActive(...) end

	-- Wrapper for time_traveler since we can't do a ref as we reassign the ref each time we find the time traveler
	function cplus_plus_ex:getTimeTraveler() return time_traveler.timeTraveler end
end

-- Orchestrates skill assignment and persistent data saving workflow
function cplus_plus_ex:updateAndSaveSkills()
	-- These are done here instead of delegating to lower level files because we have a specific order
	-- we want these to happen in and they are dependent on each other
	skill_selection:applySkillsToAllPilots()
	time_traveler:savePersistentDataIfChanged()
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

	-- Register hooks
	self:addHooks()
end

function cplus_plus_ex:addHooks()
	-- Save game hook
	-- There currently isn't an event equivalent
	modApi:addSaveGameHook(function()
		self:updateAndSaveSkills()
		skill_state_tracker:updateAllStates()
	end)
end

function cplus_plus_ex:addEvents()
	-- Subscribe to modApi events
	modApi.events.onModsFirstLoaded:subscribe(function()
		skill_registry:postModsLoaded()
		skill_config:postModsLoaded()
	end)

	modApi.events.onPodWindowShown:subscribe(function()
		skill_selection:applySkillToPodPilot()
	end)

	modApi.events.onPerfectIslandWindowShown:subscribe(function()
		skill_selection:applySkillToPerfectIslandPilot()
	end)

	modApi.events.onGameEntered:subscribe(function()
		skill_selection:clearPilotTracking()
		skill_state_tracker:resetAllTrackers()
		skill_state_tracker:updateAllStates()
	end)

	modApi.events.onModsLoaded:subscribe(function()
		skill_selection:clearPilotTracking()
		skill_state_tracker:resetAllTrackers()
	end)

	modApi.events.onGameExited:subscribe(function()
		skill_selection:clearPilotTracking()
		skill_state_tracker:updateAllStates()
	end)

	modApi.events.onGameVictory:subscribe(function()
		skill_selection:clearPilotTracking()
		skill_state_tracker:updateAllStates()
	end)

	modApi.events.onMainMenuEntered:subscribe(function()
		time_traveler:clearGameData()
	end)

	modApi.events.onHangarEntered:subscribe(function()
		time_traveler:searchForTimeTraveler()
	end)

	-- Memhack events for skill state tracking
	memhack.events.onPilotChanged:subscribe(function(pilot, changes)
		skill_state_tracker:updateStatesIfNeeded(pilot, changes)
	end)

	memhack.events.onPilotLvlUpSkillChanged:subscribe(function(pilot, skill, changes)
		skill_state_tracker:updateAllStates()
	end)

	-- Subscribe to our own events for skill state tracking as well
	hooks.events.onPostAssigningLvlUpSkills:subscribe(function()
		skill_state_tracker:updateAfterAssignment()
	end)
end