-- MechFORGE Extension Main Module
-- Coordinates and allows customized mech upgrades

-- Create global object
mech_forge = mech_forge or {}

local path = GetParentPath(...)

require(mod_loader.mods[modApi:getCurrentMod().parent].resourcePath .. "libs/inGameToolTip")

-- Debugging configuration to enable debugging for modules
mech_forge.DEBUG = {
	ENABLED = false,  -- Disable/enable all debug logging
	TRIGGER_EVENTS = false,
	HOOKS = false,
	REGISTRY = false,
	STATE_TRACKER = false,
	MANAGER = false,
	TEXTS = false,
}

local logger = memhack.logger
local TRIGGER_EVENTS = logger.register("MechFORGE", "Trigger Events", mech_forge.DEBUG.TRIGGER_EVENTS and mech_forge.DEBUG.ENABLED)

mech_forge.VANILLA_UPGRADES = {
	HEALTH = "health",
	MOVE = "move",
}

mech_forge.VANILLA_BONUSES = {
	HEALTH = 2,
	MOVE = 1,
}

mech_forge._subobjects = {}
mech_forge._subobjects.hooks = require(path.."scripts/hooks")
mech_forge._subobjects.utils = require(path.."scripts/utils")
mech_forge._subobjects.registry = require(path.."scripts/registry")
mech_forge._subobjects.manager = require(path.."scripts/manager")
mech_forge._subobjects.state_tracker = require(path.."scripts/state_tracker")
mech_forge._subobjects.texts = require(path.."scripts/texts")

-- Local references to submodules for convenient access in this file
local hooks = mech_forge._subobjects.hooks
local utils = mech_forge._subobjects.utils
local mf_registry = mech_forge._subobjects.registry
local mf_manager = mech_forge._subobjects.manager
local mf_state_tracker = mech_forge._subobjects.state_tracker
local mf_texts = mech_forge._subobjects.texts

function mech_forge:initModules()
	hooks:init()
	mf_manager:init()
	mf_state_tracker:init()
	mf_texts:init()
end

function mech_forge:exposeAPI()
	self.hooks = hooks
	self.events = hooks.events

	-- utils
	function mech_forge:isMechUpgradePowered(pawn, slot) return utils.isMechUpgradePowered(pawn, slot) end
	function mech_forge:getMechType(pawn) return utils.getMechType(pawn) end

	-- registry
	function mech_forge:registerMechUpgrade(...) return mf_registry:registerMechUpgrade(...) end
	function mech_forge:getCustomMechUpgradeConfigs(mechType) return mf_registry:getCustomMechUpgradeConfigs(mechType) end
	function mech_forge:getCustomMechUpgradeConfig(mechType, slot) return mf_registry:getCustomMechUpgradeConfig(mechType, slot) end
	function mech_forge:hasCustomMechUpgrades(mechType) return mf_registry:hasCustomMechUpgrades(mechType) end
	function mech_forge:hasCustomMechUpgrade(mechType, slot) return mf_registry:hasCustomMechUpgrade(mechType, slot) end
	function mech_forge:listMechsWithCustomUpgrades() return mf_registry:listMechsWithCustomUpgrades() end
end

function mech_forge:init()
	self:initModules()
	self:exposeAPI()
	self:addEvents()
end

function mech_forge:load(options)
	self.options = options or {}
	hooks:load()
end

function mech_forge:addEvents()
	-- modApi / memhack subscriptions
	modApi.events.onModsLoaded:subscribe(function()
		logger.logDebug(TRIGGER_EVENTS, "===== onModsLoaded event fired =====")

		mf_state_tracker:_resetAllTrackers()

		logger.logDebug(TRIGGER_EVENTS, "===== onModsLoaded processing complete =====")
	end)

	modApi.events.onGameExited:subscribe(function()
		logger.logDebug(TRIGGER_EVENTS, "onGameExited")
		mf_state_tracker:_resetAllTrackers()
	end)

	modApi.events.onGameVictory:subscribe(function()
		logger.logDebug(TRIGGER_EVENTS, "onGameVictory")
		mf_state_tracker:_resetAllTrackers()
	end)

	modApi.events.onFrameDrawStart:subscribe(function()
		mf_state_tracker:_updateAllStates()
	end)
end
