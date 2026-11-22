-- Manages and handles the custom mech upgrades

local mf_manager = {}

local logger = memhack.logger
local SUBMODULE = logger.register("MechFORGE", "UpgradeManager", mech_forge.DEBUG.MANAGER and mech_forge.DEBUG.ENABLED)

local hooks = nil
local mf_registry = nil
local utils = nil

function mf_manager:_adjustVanillaHealthBonus(vPawn, config, restore)
	local bonus = mech_forge.VANILLA_BONUSES.HEALTH
	local delta = restore and bonus or -bonus
	-- Max base health affects outside of mission. MaxHealth and Health is inside mission. Set both in case
	-- someone wants to edit this in the middle of a mission maybe. It shouldn't hurt to do both
	local maxBase = vPawn:GetMaxBaseHealth()
	local maxHealth = vPawn:GetMaxHealth()
	vPawn:SetMaxBaseHealth(maxBase + delta)

	-- If we are not in the upgrade menu, setting max health and set health causes a divide by 0 error...
	-- However, if we are NOT, NOT setting them causes a divide by 0 error...
	-- So here we are
	if Game:IsUpgradeMenuOpen() then
		vPawn:SetMaxHealth(maxHealth + delta)
		vPawn:SetHealth(maxHealth + delta)
	end
	logger.logDebug(SUBMODULE, "vanilla health %s %s delta %d maxBase %d->%d",
			restore and "restore" or "revert", config.label, delta, maxBase, maxBase + delta)
end

function mf_manager:_adjustVanillaMoveBonus(vPawn, config, restore)
	local bonus = mech_forge.VANILLA_BONUSES.MOVE
	-- GetMoveSpeed will return 0 if its <= 0 but we need to handle negative values for 0
	-- base move pawns so we use the raw getters and setters. These are base move speeds
	-- and do not include the bonus from the upgrade itself
	local delta = restore and bonus or -bonus
	local moveSpeed = vPawn:GetRawMoveSpeed()
	vPawn:SetRawMoveSpeed(moveSpeed + delta)
	logger.logDebug(SUBMODULE, "vanilla move %s %s delta %d move %d->%d",
			restore and "restore" or "revert", config.label, delta, moveSpeed, moveSpeed + delta)
end

function mf_manager:_handleVanillaBonusChange(vPawn, slot, config, restore)
	if slot == mech_forge.VANILLA_UPGRADES.HEALTH then
		self:_adjustVanillaHealthBonus(vPawn, config, restore)
	elseif slot == mech_forge.VANILLA_UPGRADES.MOVE then
		self:_adjustVanillaMoveBonus(vPawn, config, restore)
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
function mf_manager:_reconcilePartialMultiCoreUpgrade(vPawn, slot, requiredSlotCount)
	local mhCores = utils.getMechUpgradeMemhackCores(vPawn, slot)
	-- If its not partially powered, we don't need to do anything
	local count = mhCores:getIntSize()
	if not mhCores or
			(count == requiredSlotCount and not mhCores:isPartiallyPowered()) then
		return false
	end

	-- If it is partially powered, we need to fill empty slots or unpower the upgrade
	local vNewCores = {}
	local fullyPowered = true
	for i = 1, requiredSlotCount do
		vNewCores[i] = mhCores:getIntAt(i)
		if not utils.isCorePowered(vNewCores[i]) then
			local coreType = vPawn:GetMemhackObj():assignMechCore()
			if coreType ~= memhack.CORE_TYPE_NONE then
				vNewCores[i] = coreType
			else
				fullyPowered = false
				break
			end
		end
	end

	-- If it is not fully powered, unpower the upgrade (including any cores assigned so far).
	if not fullyPowered then
		for i = 1, requiredSlotCount do
			if utils.isCorePowered(vNewCores[i]) then
				vPawn:GetMemhackObj():unassignMechCore(vNewCores[i])
			end
			vNewCores[i] = memhack.CORE_TYPE_NONE
		end
	end
	mhCores:setIntListResizingIfNeeded(vNewCores)
	return true
end

-- Reconcile partial multicore upgrades by either powering them fully
-- or unpowering them
function mf_manager:reconcilePartialMultiCoreUpgrade(vPawn, slot)
	local mechType = utils.getMechType(vPawn)
	if not mechType then
		return
	end
	local config = mf_registry:getCustomMechUpgradeConfig(mechType, slot)
	if not config then
		return
	end
	self:_reconcilePartialMultiCoreUpgrade(vPawn, slot, config.coreSlots)
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