-- Manages and handles the custom mech upgrades

local mech_upgrade_manager = {}

local logger = memhack.logger
local SUBMODULE = logger.register("MechFORGE", "UpgradeManager", mech_forge.DEBUG.EFFECTS and mech_forge.DEBUG.ENABLED)

local hooks = nil
local mech_upgrade_registry = nil

function mech_upgrade_manager:_invokeRegisteredCallback(config, field, ...)
	if not config then
		return
	end
	local fn = config[field]
	if fn then
		fn(...)
	end
end

function mech_upgrade_manager:_subscribeUpgradeCallbackEvents()
	-- Use internal priority so others can run first if needed for some reason
	local priority = hooks.INTERNAL_PRIORITY

	hooks.events.onReactorCoreChanged:subscribe(function(slot, pawnId, pawn, mechType, oldCore, newCore)
		local config = mech_upgrade_registry:getCustomMechUpgradeConfig(mechType, slot)
		self:_invokeRegisteredCallback(config, "onCoreChange", pawn, pawnId, slot, oldCore, newCore)
	end, priority)

	hooks.events.onUpgradePowered:subscribe(function(slot, pawnId, pawn, mechType, newCore)
		local config = mech_upgrade_registry:getCustomMechUpgradeConfig(mechType, slot)
		self:_invokeRegisteredCallback(config, "onApply", pawn, pawnId, newCore)
	end, priority)

	hooks.events.onUpgradeUnpowered:subscribe(function(slot, pawnId, pawn, mechType, oldCore)
		local config = mech_upgrade_registry:getCustomMechUpgradeConfig(mechType, slot)
		self:_invokeRegisteredCallback(config, "onRemove", pawn, pawnId, oldCore)
	end, priority)

	logger.logDebug(SUBMODULE, "Subscribed upgrade callback events")
end

function mech_upgrade_manager:init()
	hooks = mech_forge._subobjects.hooks
	mech_upgrade_registry = mech_forge._subobjects.mech_upgrade_registry
	self:_subscribeUpgradeCallbackEvents()
	return self
end

return mech_upgrade_manager
