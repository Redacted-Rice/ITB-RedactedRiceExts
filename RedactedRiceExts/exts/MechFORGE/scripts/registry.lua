-- Mech Upgrade Registration Module
-- For registering custom mech upgrades for specific mech types

local mf_registry = {}

local logger = memhack.logger
local SUBMODULE = logger.register("MechFORGE", "Registry", mech_forge.DEBUG.REGISTRY and mech_forge.DEBUG.ENABLED)
local utils = mech_forge._subobjects.utils

mf_registry._byMechType = {}

function mf_registry:_validateUpgradeCallbacks(mechType, slot, onPowered, onUnpowered, onCoreChanged)
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
-- label required, A non-empty string, text id, or function(pawn)
-- onPowered/onUnpowered optional but both must be set or both omitted
-- onCoreChanged optional, any core value change on this slot.
-- onXxxx Functions' args match the respective hooks in hooks.lua
-- Config args can optionally be passed as a table instead
function mf_registry:registerMechUpgrade(mechType, slot, labelOrTable, onPowered, onUnpowered, onCoreChanged)
	if type(mechType) ~= "string" or mechType == "" then
		logger.logError(SUBMODULE, "registerMechUpgrade: mechType must be a non-empty string")
		return false
	end

	-- Make input args consistent
	local label = labelOrTable
	local tooltip = nil
	if type(labelOrTable) == "table" then
		label = labelOrTable.label
		tooltip = labelOrTable.tooltip
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
	local labelType = type(label)
	if labelType == "string" then
		if label == "" then
			logger.logError(SUBMODULE, "registerMechUpgrade: label must be non-empty for %s %s", mechType, slot)
			return false
		end
	elseif labelType ~= "function" then
		logger.logError(SUBMODULE,
			"registerMechUpgrade: label must be a non-empty string or function for %s %s",
			mechType, slot)
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
	if tooltip ~= nil then
		local tooltipType = type(tooltip)
		if tooltipType ~= "string" and tooltipType ~= "function" then
			logger.logError(SUBMODULE,
				"registerMechUpgrade: tooltip must be a string, text id, or function for %s %s",
				mechType, slot)
			return false
		end
		if tooltipType == "string" and tooltip == "" then
			logger.logError(SUBMODULE,
				"registerMechUpgrade: tooltip must be non-empty when set for %s %s",
				mechType, slot)
			return false
		end
	end

	entry[slot] = {
		label = label,
		tooltip = tooltip,
		onPowered = onPowered,
		onUnpowered = onUnpowered,
		onCoreChanged = onCoreChanged,
	}
	logger.logInfo(SUBMODULE, "Registered MechFORGE %s upgrade for %s", slot, mechType)
	return true
end

-- Returns only the custom upgrade configs or nil if no custom upgrades are registered
function mf_registry:getCustomMechUpgradeConfigs(mechType)
	if type(mechType) ~= "string" then
		return nil
	end
	return self._byMechType[mechType]
end

-- Returns nil if slot does not have a custom upgrade
function mf_registry:getCustomMechUpgradeConfig(mechType, slot)
	if not utils.isValidUpgradeSlot(slot) then
		return nil
	end
	local entry = self:getCustomMechUpgradeConfigs(mechType)
	if not entry then
		return nil
	end
	return entry[slot]
end

function mf_registry:hasCustomMechUpgrades(mechType)
	return self:getCustomMechUpgradeConfigs(mechType) ~= nil
end

function mf_registry:hasCustomMechUpgrade(mechType, slot)
	return self:getCustomMechUpgradeConfig(mechType, slot) ~= nil
end

function mf_registry:listMechsWithCustomUpgrades()
	local result = {}
	for mechType, _ in pairs(self._byMechType) do
		table.insert(result, mechType)
	end
	return result
end

return mf_registry
