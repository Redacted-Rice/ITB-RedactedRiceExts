-- MechFORGE Extension Main Module
-- Coordinates and allows customized mech upgrades

-- Create global object
mech_forge = mech_forge or {}

local path = GetParentPath(...)

-- Debugging configuration to enable debugging for modules
mech_forge.DEBUG = {
	ENABLED = true,  -- Disable/enable all debug logging
	TRIGGER_EVENTS = false,
	HOOKS = false,
	REGISTRY = false,
	STATE_TRACKER = false,
	MANAGER = true,
	TOOLTIPS = true,
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
mech_forge._subobjects.mech_upgrade_registry = require(path.."scripts/mech_upgrade_registry")
mech_forge._subobjects.mech_upgrade_manager = require(path.."scripts/mech_upgrade_manager")
mech_forge._subobjects.mech_upgrade_state_tracker = require(path.."scripts/mech_upgrade_state_tracker")
mech_forge._subobjects.mech_upgrade_tooltips = require(path.."scripts/mech_upgrade_tooltips")

-- Local references to submodules for convenient access in this file
local hooks = mech_forge._subobjects.hooks
local utils = mech_forge._subobjects.utils
local mech_upgrade_registry = mech_forge._subobjects.mech_upgrade_registry
local mech_upgrade_manager = mech_forge._subobjects.mech_upgrade_manager
local mech_upgrade_state_tracker = mech_forge._subobjects.mech_upgrade_state_tracker
local mech_upgrade_tooltips = mech_forge._subobjects.mech_upgrade_tooltips

function mech_forge:initModules()
	hooks:init()
	mech_upgrade_manager:init()
	mech_upgrade_state_tracker:init()
	mech_upgrade_tooltips:init()
end

function mech_forge:exposeAPI()
	self.hooks = hooks
	self.events = hooks.events

	-- utils
	function mech_forge:isMechUpgradePowered(pawn, slot) return utils.isMechUpgradePowered(pawn, slot) end
	function mech_forge:getMechType(pawn) return utils.getMechType(pawn) end

	-- registry
	function mech_forge:registerMechUpgrade(...) return mech_upgrade_registry:registerMechUpgrade(...) end
	function mech_forge:getCustomMechUpgradeConfigs(mechType) return mech_upgrade_registry:getCustomMechUpgradeConfigs(mechType) end
	function mech_forge:getCustomMechUpgradeConfig(mechType, slot) return mech_upgrade_registry:getCustomMechUpgradeConfig(mechType, slot) end
	function mech_forge:hasCustomMechUpgrades(mechType) return mech_upgrade_registry:hasCustomMechUpgrades(mechType) end
	function mech_forge:hasCustomMechUpgrade(mechType, slot) return mech_upgrade_registry:hasCustomMechUpgrade(mechType, slot) end
	function mech_forge:listMechsWithCustomUpgrades() return mech_upgrade_registry:listMechsWithCustomUpgrades() end
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

		mech_upgrade_state_tracker:_resetAllTrackers()

		logger.logDebug(TRIGGER_EVENTS, "===== onModsLoaded processing complete =====")
	end)

	modApi.events.onGameExited:subscribe(function()
		logger.logDebug(TRIGGER_EVENTS, "onGameExited")
		mech_upgrade_state_tracker:_resetAllTrackers()
	end)

	modApi.events.onGameVictory:subscribe(function()
		logger.logDebug(TRIGGER_EVENTS, "onGameVictory")
		mech_upgrade_state_tracker:_resetAllTrackers()
	end)

	modApi.events.onFrameDrawStart:subscribe(function()
		mech_upgrade_state_tracker:_updateAllStates()
	end)
end
