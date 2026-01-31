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

function cplus_plus_ex:init()
	self:initModules()
	self:exposeAPI()

	-- Add events
	self:addEvents()
end

function cplus_plus_ex:load(options)
	-- Load submodules that need loading
	hooks:load()
	skill_state_tracker:load()
	time_traveler:load()
end

function cplus_plus_ex:addEvents()
	-- Subscribe to top-level events
	modApi.events.onModsFirstLoaded:subscribe(function()
		cplus_plus_ex:postModsLoaded()
	end)
end

function cplus_plus_ex:postModsLoaded()
	-- post load on modules that need it
	skill_registry:postModsLoaded()
	skill_config:postModsLoaded()
end