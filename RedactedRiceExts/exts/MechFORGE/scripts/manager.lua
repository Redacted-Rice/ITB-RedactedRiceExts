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

	-- If we are not in the upgrade menu, setting max health and set health causes a divide by 0 error...
	-- However, if we are NOT, NOT setting them causes a divide by 0 error...
	-- So here we are
	if Game:IsUpgradeMenuOpen() then
		pawn:SetMaxHealth(maxHealth + delta)
		pawn:SetHealth(maxHealth + delta)
	end
	logger.logDebug(SUBMODULE, "vanilla health %s %s delta %d maxBase %d->%d",
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
	logger.logDebug(SUBMODULE, "vanilla move %s %s delta %d move %d->%d",
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

-- Fills empty sockets from the pawn core pool or clears the upgrade if not enough cores.
function mf_manager:_reconcilePartialMultiCoreUpgrade(pawn, slot, requiredSlotCount)
	local cores = utils.getMechUpgradeMemhackCores(pawn, slot)
	-- If its not partially powered, we don't need to do anything
	if not cores or not cores:isPartiallyPoweredForSlotCount(requiredSlotCount) then
		return false
	end

	-- If it is partially powered, we need to fill empty slots or unpower the upgrade
	local newCores = {}
	local fullyPowered = true
	for i = 1, requiredSlotCount do
		newCores[i] = cores:getIntAt(i)
		if not utils.isCorePowered(newCores[i]) then
			local coreType = pawn:GetMemhackObj():assignMechReactorCore()
			if coreType ~= memhack.CORE_TYPE_NONE then
				newCores[i] = coreType
			else
				fullyPowered = false
				break
			end
		end
	end

	-- If it is not fully powered, we need to unpower the upgrade (inlcuding
	-- any we've assigned so far)
	if not fullyPowered then
		for i = 1, requiredSlotCount do
			if utils.isCorePowered(newCores[i]) then
				pawn:GetMemhackObj():unassignMechReactorCore(newCores[i])
			end
			newCores[i] = memhack.CORE_TYPE_NONE
		end
	end
	cores:setIntListResizingIfNeeded(newCores)
	return true
end

-- Reconcile partial multicore upgrades by either powering them fully
-- or unpowering them
function mf_manager:reconcilePartialMultiCoreUpgrade(pawn, slot)
	local mechType = utils.getMechType(pawn)
	if not mechType then
		return
	end
	local config = mf_registry:getCustomMechUpgradeConfig(mechType, slot)
	if not config then
		return
	end
	self:_reconcilePartialMultiCoreUpgrade(pawn, slot, config.coreSlots)
end

-- Ensures the upgrade cores list is the correct size
function mf_manager:ensureCoreListSize(pawn, slot)
	local mechType = utils.getMechType(pawn)
	if not mechType then
		return
	end
	local config = mf_registry:getCustomMechUpgradeConfig(mechType, slot)
	if not config then
		return
	end

	local targetSize = config.coreSlots or 1
	local cores = utils.getMechUpgradeMemhackCores(pawn, slot)
	if not cores or cores:getIntSize() ~= targetSize then
		return
	end

	local values = {}
	for i = 1, targetSize do
		if i <= cores:getIntSize() then
			values[i] = cores:_uncheckedGetIntAt(i)
		else
			values[i] = memhack.CORE_TYPE_NONE
		end
	end
	cores:setIntListResizingIfNeeded(values)
	logger.logDebug(SUBMODULE, "grew %s cores to %d slots", slot, targetSize)
end

function mf_manager:_subscribeUpgradeCallbackEvents()
	-- Use internal priority so others can run first if needed for some reason
	local priority = hooks.INTERNAL_PRIORITY

	hooks.events.onMechUpgradeCoreChanged:subscribe(function(slot, pawn, pawnId, mechType, oldList, newList)
		local config = mf_registry:getCustomMechUpgradeConfig(mechType, slot)
		if config then
			self:_invokeRegisteredCallback(config, "onCoreChanged", slot, pawn, pawnId, mechType, oldList, newList)
		end
	end, priority)

	hooks.events.onMechUpgradePowered:subscribe(function(slot, pawn, pawnId, mechType, newList)
		local config = mf_registry:getCustomMechUpgradeConfig(mechType, slot)
		if config then
			self:_handleVanillaBonusChange(pawn, slot, config, false)
			self:_invokeRegisteredCallback(config, "onPowered", slot, pawn, pawnId, mechType, newList)
		end
	end, priority)

	hooks.events.onMechUpgradeUnpowered:subscribe(function(slot, pawn, pawnId, mechType, oldList)
		local config = mf_registry:getCustomMechUpgradeConfig(mechType, slot)
		if config then
			self:_handleVanillaBonusChange(pawn, slot, config, true)
			self:_invokeRegisteredCallback(config, "onUnpowered", slot, pawn, pawnId, mechType, oldList)
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
