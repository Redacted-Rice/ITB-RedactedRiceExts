-- Mech Upgrade Registration Module
-- For registering custom mech upgrades for specific mech types

local mech_upgrade_registry = {}

local logger = memhack.logger
local SUBMODULE = logger.register("MechFORGE", "Registry", mech_forge.DEBUG.REGISTRY and mech_forge.DEBUG.ENABLED)
local utils = mech_forge._subobjects.utils

mech_upgrade_registry._byMechType = {}

function mech_upgrade_registry:_validateUpgradeCallbacks(mechType, slot, onPowered, onUnpowered, onCoreChanged)
	local hasPowered = onPowered ~= nil
	local hasUnpowered = onUnpowered ~= nil
	if hasPowered ~= hasUnpowered then
		logger.logError(SUBMODULE,
			"registerMechUpgrade: onPowered and onUnpowered must both be set or both omitted for %s %s",
			mechType, slot)
		return false
	end

	local callbacks = {
		{ fn = onPowered, name = "onPowered" },
		{ fn = onUnpowered, name = "onUnpowered" },
		{ fn = onCoreChanged, name = "onCoreChanged" },
	}
	for _, callback in ipairs(callbacks) do
		if callback.fn ~= nil and type(callback.fn) ~= "function" then
			logger.logError(SUBMODULE,
				"registerMechUpgrade: %s must be a function for %s %s",
				callback.name, mechType, slot)
			return false
		end
	end
	return true
end

-- Adds a custom upgrade to the mech in place of the given slot.
-- slot must be mech_forge.VANILLA_UPGRADES.HEALTH or .MOVE
-- label required (positional or label field in table) to display for the upgrade
-- onPowered/onUnpowered optional but both must be set or both omitted
-- onCoreChanged optional, any core value change on this slot.
-- onXxxx Functions' args match the respective hooks in hooks.lua
-- Config args can optionally be passed as a table instead
function mech_upgrade_registry:registerMechUpgrade(mechType, slot, labelOrTable, onPowered, onUnpowered, onCoreChanged)
	if type(mechType) ~= "string" or mechType == "" then
		logger.logError(SUBMODULE, "registerMechUpgrade: mechType must be a non-empty string")
		return false
	end

	-- Make input args consistent
	local label = labelOrTable
	if type(labelOrTable) == "table" then
		label = labelOrTable.label
		onPowered = labelOrTable.onPowered
		onUnpowered = labelOrTable.onUnpowered
		onCoreChanged = labelOrTable.onCoreChanged
	end

	-- Ensure its a valid slot
	if not utils.isValidUpgradeSlot(slot) then
		logger.logError(SUBMODULE,
			"registerMechUpgrade: slot must be mech_forge.VANILLA_UPGRADES.HEALTH or .MOVE, got %s",
			tostring(slot))
		return false
	end

	-- Require a label
	if type(label) ~= "string" or label == "" then
		logger.logError(SUBMODULE, "registerMechUpgrade: label must be a non-empty string for %s %s", mechType, slot)
		return false
	end

	if not self:_validateUpgradeCallbacks(mechType, slot, onPowered, onUnpowered, onCoreChanged) then
		return false
	end

	-- Set the entry for the mech
	local entry = self._byMechType[mechType]
	if not entry then
		entry = {}
		self._byMechType[mechType] = entry
	end
	if entry[slot] ~= nil then
		logger.logWarn(SUBMODULE, "registerMechUpgrade: overwriting existing %s upgrade for %s", slot, mechType)
	end
	entry[slot] = {
		label = label,
		onPowered = onPowered,
		onUnpowered = onUnpowered,
		onCoreChanged = onCoreChanged,
	}
	logger.logInfo(SUBMODULE, "Registered MechFORGE %s upgrade for %s", slot, mechType)
	return true
end

-- Returns only the custom upgrade configs or nil if no custom upgrades are registered
function mech_upgrade_registry:getCustomMechUpgradeConfigs(mechType)
	if type(mechType) ~= "string" then
		return nil
	end
	return self._byMechType[mechType]
end

-- Returns nil if slot does not have a custom upgrade
function mech_upgrade_registry:getCustomMechUpgradeConfig(mechType, slot)
	if not utils.isValidUpgradeSlot(slot) then
		return nil
	end
	local entry = self:getCustomMechUpgradeConfigs(mechType)
	if not entry then
		return nil
	end
	return entry[slot]
end

function mech_upgrade_registry:hasCustomMechUpgrades(mechType)
	return self:getCustomMechUpgradeConfigs(mechType) ~= nil
end

function mech_upgrade_registry:hasCustomMechUpgrade(mechType, slot)
	return self:getCustomMechUpgradeConfig(mechType, slot) ~= nil
end

function mech_upgrade_registry:listMechsWithCustomUpgrades()
	local result = {}
	for mechType, _ in pairs(self._byMechType) do
		table.insert(result, mechType)
	end
	return result
end

return mech_upgrade_registry
