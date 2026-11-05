-- Manages and handles the custom mech upgrades

local mf_manager = {}

local logger = memhack.logger
local SUBMODULE = logger.register("MechFORGE", "UpgradeManager", mech_forge.DEBUG.MANAGER and mech_forge.DEBUG.ENABLED)

local hooks = nil
local mf_registry = nil
local utils = nil

function mf_manager:_adjustVanillaHealthBonus(pawn, config, restore)
	local bonus = mech_forge.VANILLA_BONUSES.HEALTH
	local delta = restore and bonus or -bonus
	-- Max base health affects outside of mission. MaxHealth and Health is inside mission. Set both in case
	-- someone wants to edit this in the middle of a mission maybe. It shouldn't hurt to do both
	local maxBase = pawn:GetMaxBaseHealth()
	local maxHealth = pawn:GetMaxHealth()
	pawn:SetMaxBaseHealth(maxBase + delta)
	pawn:SetMaxHealth(maxHealth + delta)
	local health = pawn:GetHealth()
	local newMaxHealth = maxHealth + delta
	if health > newMaxHealth then
		pawn:SetHealth(newMaxHealth)
	end
	logger.logDebug(SUBMODULE,
		"vanilla health %s %s delta %d maxBase %d->%d",
		restore and "restore" or "revert", config.label, delta, maxBase, maxBase + delta)
end

function mf_manager:_adjustVanillaMoveBonus(pawn, config, restore)
	local bonus = mech_forge.VANILLA_BONUSES.MOVE
	-- GetMoveSpeed will return 0 if its <= 0 but we need to handle negative values for 0
	-- base move pawns so we use the raw getters and setters. These are base move speeds
	-- and do not include the bonus from the upgrade itself
	local delta = restore and bonus or -bonus
	local moveSpeed = pawn:GetRawMoveSpeed()
	pawn:SetRawMoveSpeed(moveSpeed + delta)
	logger.logDebug(SUBMODULE,
		"vanilla move %s %s delta %d move %d->%d",
		restore and "restore" or "revert", config.label, delta, moveSpeed, moveSpeed + delta)
end

function mf_manager:_handleVanillaBonusChange(pawn, slot, config, restore)
	if slot == mech_forge.VANILLA_UPGRADES.HEALTH then
		self:_adjustVanillaHealthBonus(pawn, config, restore)
	elseif slot == mech_forge.VANILLA_UPGRADES.MOVE then
		self:_adjustVanillaMoveBonus(pawn, config, restore)
	end
end

function mf_manager:_invokeRegisteredCallback(config, field, ...)
	if not config then
		return
	end
	local fn = config[field]
	if fn then
		fn(...)
	end
end

function mf_manager:_subscribeUpgradeCallbackEvents()
	-- Use internal priority so others can run first if needed for some reason
	local priority = hooks.INTERNAL_PRIORITY

	hooks.events.onMechUpgradeCoreChanged:subscribe(function(slot, pawn, pawnId, mechType, oldCore, newCore)
		local config = mf_registry:getCustomMechUpgradeConfig(mechType, slot)
		self:_invokeRegisteredCallback(config, "onCoreChanged", slot, pawn, pawnId, mechType, oldCore, newCore)
	end, priority)

	hooks.events.onMechUpgradePowered:subscribe(function(slot, pawn, pawnId, mechType, newCore)
		local config = mf_registry:getCustomMechUpgradeConfig(mechType, slot)
		if config then
			self:_handleVanillaBonusChange(pawn, slot, config, false)
			self:_invokeRegisteredCallback(config, "onPowered", slot, pawn, pawnId, mechType, newCore)
		end
	end, priority)

	hooks.events.onMechUpgradeUnpowered:subscribe(function(slot, pawn, pawnId, mechType, oldCore)
		local config = mf_registry:getCustomMechUpgradeConfig(mechType, slot)
		if config then
			self:_handleVanillaBonusChange(pawn, slot, config, true)
			self:_invokeRegisteredCallback(config, "onUnpowered", slot, pawn, pawnId, mechType, oldCore)
		end
	end, priority)

	logger.logDebug(SUBMODULE, "Subscribed upgrade callback events")
end

function mf_manager:init()
	hooks = mech_forge._subobjects.hooks
	mf_registry = mech_forge._subobjects.registry
	utils = mech_forge._subobjects.utils
	self:_subscribeUpgradeCallbackEvents()
	return self
end

return mf_manager
