-- Manages and handles the custom mech upgrades

local mech_upgrade_manager = {}

local logger = memhack.logger
local SUBMODULE = logger.register("MechFORGE", "UpgradeManager", mech_forge.DEBUG.MANAGER and mech_forge.DEBUG.ENABLED)

local TEXT_ID_TO_SLOT = {
	Upgrade_HealthLabel = mech_forge.VANILLA_UPGRADES.HEALTH,
	Upgrade_MoveLabel = mech_forge.VANILLA_UPGRADES.MOVE,
}

local hooks = nil
local mech_upgrade_registry = nil
local utils = nil

function mech_upgrade_manager:_adjustVanillaHealthBonus(pawn, config, restore)
	local bonus = mech_forge.VANILLA_BONUSES.HEALTH
	local delta = restore and bonus or -bonus
	-- Max base health affects outside of mission. MaxHealth and Health is inside mission. Set both in case
	-- someone wants to edit this in the middle of a mission maybe. It shouldn't hurt to do both
	local maxBase = pawn:GetMaxBaseHealth()
	local maxHealth = pawn:GetMaxHealth()
	pawn:SetMaxBaseHealth(maxBase + delta)
	pawn:SetMaxHealth(maxHealth + delta)
	pawn:SetHealth(pawn:GetHealth() + delta)
	logger.logDebug(SUBMODULE,
		"vanilla health %s %s delta %d maxBase %d->%d",
		restore and "restore" or "revert", config.label, delta, maxBase, maxBase + delta)
end

function mech_upgrade_manager:_adjustVanillaMoveBonus(pawn, config, restore)
	local bonus = mech_forge.VANILLA_BONUSES.MOVE
	local delta = restore and bonus or -bonus
	local moveSpeed = pawn:GetMoveSpeed()
	pawn:SetMoveSpeed(moveSpeed + delta)
	logger.logDebug(SUBMODULE,
		"vanilla move %s %s delta %d move %d->%d",
		restore and "restore" or "revert", config.label, delta, moveSpeed, moveSpeed + delta)
end

function mech_upgrade_manager:_handleVanillaBonusChange(pawn, slot, config, restore)
	if slot == mech_forge.VANILLA_UPGRADES.HEALTH then
		self:_adjustVanillaHealthBonus(pawn, config, restore)
	elseif slot == mech_forge.VANILLA_UPGRADES.MOVE then
		self:_adjustVanillaMoveBonus(pawn, config, restore)
	end
end

function mech_upgrade_manager:_invokeRegisteredCallback(config, field, ...)
	if not config then
		return
	end
	local fn = config[field]
	if fn then
		fn(...)
	end
end

function mech_upgrade_manager:_resolveUpgradeLabel(label, pawn)
	if label == nil then
		return nil
	end

	-- If we have a function call it and use the result or the passed label if its not fn
	local resolved = type(label) == "function" and label(pawn) or label
	if type(resolved) ~= "string" then
		return resolved ~= nil and tostring(resolved) or nil
	end
	if resolved == "" then
		return nil
	enabled

	-- call get text which will be overridden to handle custom lables
	return GetText(resolved)
end

function mech_upgrade_manager:_customUpgradeLabelForTextId(id)
	-- If its not one of the labels we override return
	local slot = TEXT_ID_TO_SLOT[id]
	if not slot then
		return nil
	end

	-- Get the currently selected pawn in the strategy menu
	local pawnId = Game:GetStrategySelectedPawn()
	if pawnId == nil then
		return nil
	end

	-- Get the mechtype of the pawn
	local pawn = Game:GetPawn(pawnId)
	local mechType = utils.getMechType(pawn)
	if not mechType then
		return nil
	end

	-- See if it has a custom upgrade config for this text
	local config = mech_upgrade_registry:getCustomMechUpgradeConfig(mechType, slot)
	if not config or not config.label then
		return nil
	end

	-- If it does, resolve the text and return it
	local text = self:_resolveUpgradeLabel(config.label, pawn)
	if not text then
		return nil
	end
	logger.logDebug(SUBMODULE, "GetText %s -> %s (%s %s)", id, text, mechType, slot)
	return text
end

function mech_upgrade_manager:_subscribeUpgradeCallbackEvents()
	-- Use internal priority so others can run first if needed for some reason
	local priority = hooks.INTERNAL_PRIORITY

	hooks.events.onMechUpgradeCoreChanged:subscribe(function(slot, pawn, pawnId, mechType, oldCore, newCore)
		local config = mech_upgrade_registry:getCustomMechUpgradeConfig(mechType, slot)
		self:_invokeRegisteredCallback(config, "onCoreChanged", slot, pawn, pawnId, mechType, oldCore, newCore)
	end, priority)

	hooks.events.onMechUpgradePowered:subscribe(function(slot, pawn, pawnId, mechType, newCore)
		local config = mech_upgrade_registry:getCustomMechUpgradeConfig(mechType, slot)
		if config then
			self:_handleVanillaBonusChange(pawn, slot, config, false)
			self:_invokeRegisteredCallback(config, "onPowered", slot, pawn, pawnId, mechType, newCore)
		end
	end, priority)

	hooks.events.onMechUpgradeUnpowered:subscribe(function(slot, pawn, pawnId, mechType, oldCore)
		local config = mech_upgrade_registry:getCustomMechUpgradeConfig(mechType, slot)
		if config then
			self:_handleVanillaBonusChange(pawn, slot, config, true)
			self:_invokeRegisteredCallback(config, "onUnpowered", slot, pawn, pawnId, mechType, oldCore)
		end
	end, priority)

	logger.logDebug(SUBMODULE, "Subscribed upgrade callback events")
end

function mech_upgrade_manager:_installOverrides()
	mech_upgrade_manager._origGetText = GetText
	function GetText(id, r1, r2, r3)
		if type(id) == "string" then
			local label = mech_upgrade_manager:_customUpgradeLabelForTextId(id)
			if label then
				return label
			end
		end
		return mech_upgrade_manager._origGetText(id, r1, r2, r3)
	end
end

function mech_upgrade_manager:init()
	hooks = mech_forge._subobjects.hooks
	mech_upgrade_registry = mech_forge._subobjects.mech_upgrade_registry
	utils = mech_forge._subobjects.utils
	self:_installOverrides()
	self:_subscribeUpgradeCallbackEvents()
	return self
end

return mech_upgrade_manager
