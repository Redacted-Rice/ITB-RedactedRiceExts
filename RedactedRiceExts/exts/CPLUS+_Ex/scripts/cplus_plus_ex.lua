-- CPLUS+ Extension Main Module
-- Coordinates skill modules and manages save/load operations

-- Main extension object with state
cplus_plus_ex = {
	PLUS_DEBUG = true, -- eventually default to false
	PLUS_EXTRA_DEBUG = false,
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

local utils = nil
local skill_registry = nil
local skill_config = nil
local skill_selection = nil
local skill_constraints = nil
local time_traveler = nil

-- Initialize modules (called from init function)
function cplus_plus_ex:initModules(path)
	utils = require(path.."scripts/utils")
	skill_registry = require(path.."scripts/skill_registry")
	skill_config = require(path.."scripts/skill_config")
	skill_selection = require(path.."scripts/skill_selection")
	skill_constraints = require(path.."scripts/skill_constraints")
	time_traveler = require(path.."scripts/time_traveler")

	self._modules = {
		skill_config = skill_config,
		skill_constraints = skill_constraints,
		skill_registry = skill_registry,
		skill_selection = skill_selection,
		time_traveler = time_traveler,
		utils = utils,
	}

	skill_config.init(self)
	skill_constraints.init(self)
	skill_registry.init(self)
	skill_selection.init(self)
	time_traveler.init(self)

	-- Expose "public" module params/functions/classes APIs
	cplus_plus_ex.config = skill_config.config
	cplus_plus_ex.SkillConfig = skill_config.SkillConfig

	function cplus_plus_ex:setSkillConfig(...) return skill_config.setSkillConfig(...) end
	function cplus_plus_ex:enableSkill(...) return skill_config.enableSkill(...) end
	function cplus_plus_ex:disableSkill(...) return skill_config.disableSkill(...) end
	function cplus_plus_ex:removeSkillDependency(...) return skill_config.removeSkillDependency(...) end
	function cplus_plus_ex:setAdjustedWeightsConfigs() return skill_config.setAdjustedWeightsConfigs() end
	function cplus_plus_ex:resetToDefaults() return skill_config.resetToDefaults() end
	function cplus_plus_ex:getAllowedReusability(...) return skill_config.getAllowedReusability(...) end
	function cplus_plus_ex:saveConfiguration() return skill_config.saveConfiguration() end
	function cplus_plus_ex:loadConfiguration() return skill_config.loadConfiguration() end

	function cplus_plus_ex:checkSkillConstraints(...) return skill_constraints.checkSkillConstraints(...) end
	function cplus_plus_ex:registerConstraintFunction(...) return skill_constraints.registerConstraintFunction(...) end

	function cplus_plus_ex:registerSkill(...) return skill_registry.registerSkill(...) end
	function cplus_plus_ex:registerPilotSkillExclusions(...) return skill_registry.registerPilotSkillExclusions(...) end
	function cplus_plus_ex:registerPilotSkillInclusions(...) return skill_registry.registerPilotSkillInclusions(...) end
	function cplus_plus_ex:registerSkillExclusion(...) return skill_registry.registerSkillExclusion(...) end
	function cplus_plus_ex:registerSkillDependency(...) return skill_registry.registerSkillDependency(...) end

	function cplus_plus_ex:applySkillsToPilot(...) return skill_selection.applySkillsToPilot(...) end
	function cplus_plus_ex:applySkillsToAllPilots() return skill_selection.applySkillsToAllPilots() end

	-- Wrapper for time_traveler since we can't do a ref as we reassign the ref each time we find the time traveler
	function cplus_plus_ex:getTimeTraveler() return time_traveler.timeTraveler end
end

function cplus_plus_ex:init(path)
	-- Initialize modules
	self:initModules(path)

	-- Add events
	self:addEvents()
end

function cplus_plus_ex:load(options)
	-- Add the hooks - these are cleared each reload
	self:addHooks()
end

function cplus_plus_ex:addEvents()
	modApi.events.onMainMenuEntered:subscribe(function()
		time_traveler.clearGameData()
	end)
	modApi.events.onHangarEntered:subscribe(function()
		time_traveler.searchForTimeTraveler()
	end)
	modApi.events.onModsFirstLoaded:subscribe(function()
		cplus_plus_ex:postModsLoadedConfig()
	end)
	
	-- temp for testing
	modApi.events.onPerfectIslandWindowShown:subscribe(function()
		LOG("PERFECT ISALND DETECTED!!!")
	end)
	modApi.events.onPerfectIslandWindowHidden:subscribe(function()
		LOG("PERFECT ISALND GONE!!!")
	end)
	modApi.events.onPodWindowShown:subscribe(function()
		LOG("POD REWARD DETECTED!!!")
	end)
	modApi.events.onPodWindowHidden:subscribe(function()
		-- temp for testing
		LOG("POD REWARD GONE!!!")
	end)
	
	if self.PLUS_DEBUG then LOG("PLUS Ext: Initialized and subscribed to game events") end
end

function cplus_plus_ex:postModsLoadedConfig()
	-- Read vanilla pilot exclusions to support vanilla API
	skill_registry.readPilotExclusionsFromGlobal()

	-- Auto-adjust weights for dependencies
	self:setAdjustedWeightsConfigs()

	-- Set the defaults to our registered/setup values
	skill_config.captureDefaultConfigs()

	-- Load any saved configurations
	skill_config.loadConfiguration()
end

function cplus_plus_ex:addHooks()
	modApi:addSaveGameHook(function()
		self:updateAndSaveSkills()
	end)
	memhack.hooks:addPilotChangedHook(function(pilot)
		LOG("HOOKED PILOT CHANGED")
	end)
	memhack.hooks:addPilotLvlUpSkillChangedHook(function(pilot, skill)
		LOG("HOOKED PLUS CHANGED")
	end)

	if self.PLUS_DEBUG then LOG("PLUS Ext: Initialized and subscribed to game hooks") end
end

-- Do all time_traveler operations (refresh, load, apply, save)
function cplus_plus_ex:updateAndSaveSkills()
	time_traveler.refreshGameData()
	time_traveler.loadPersistentDataIfNeeded()
	self:applySkillsToAllPilots()
	time_traveler.savePersistentDataIfChanged()
end