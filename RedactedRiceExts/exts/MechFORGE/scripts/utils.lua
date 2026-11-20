local utils = {}

function utils.isValidUpgradeSlot(slot)
	return slot == mech_forge.VANILLA_UPGRADES.HEALTH
		or slot == mech_forge.VANILLA_UPGRADES.MOVE
end

function utils.isCorePowered(coreType)
	return memhack.structs.CoreList.isCorePowered(coreType)
end

-- True when every entry in vCores is powered.
-- Takes "vanilla" core list of a lua table
function utils.isMechUpgradeCoresPowered(vCores)
	if type(vCores) ~= "table" then
		return false
	end
	for i = 1, #vCores do
		if not utils.isCorePowered(vCores[i]) then
			return false
		end
	end
	return true
end

-- Get memhack hp/move CoreList on the vanilla pawn
function utils.getMechUpgradeMemhackCores(vPawn, slot)
	if not vPawn then
		return nil
	end
	if slot == mech_forge.VANILLA_UPGRADES.HEALTH then
		return vPawn:GetMemhackObj():getHpCores()
	end
	if slot == mech_forge.VANILLA_UPGRADES.MOVE then
		return vPawn:GetMemhackObj():getMoveCores()
	end
	return nil
end

function utils.isMechUpgradePowered(vPawn, slot)
	if not utils.isValidUpgradeSlot(slot) then
		return false
	end
	if slot == mech_forge.VANILLA_UPGRADES.HEALTH then
		return vPawn:IsHpPowered()
	end
	if slot == mech_forge.VANILLA_UPGRADES.MOVE then
		return vPawn:IsMovePowered()
	end
	return false
end

function utils.getMechType(vPawn)
	if not vPawn then
		return nil
	end
	local mechType = vPawn:GetType()
	if mechType and mechType ~= "" then
		return mechType
	end
	return nil
end

function utils.resolveText(value, vPawn)
	if value == nil then
		return nil
	end

	-- If we have a function call it and use the result or the passed label if its not fn
	local resolved = type(value) == "function" and value(vPawn) or value

	-- call get text which will be overridden to handle custom lables
	return GetText(resolved)
end

return utils