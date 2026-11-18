local utils = {}

function utils.isValidUpgradeSlot(slot)
	return slot == mech_forge.VANILLA_UPGRADES.HEALTH
		or slot == mech_forge.VANILLA_UPGRADES.MOVE
end

function utils.isCorePowered(core)
	return core ~= nil and core ~= memhack.CORE_TYPE_NONE
end

-- Single-slot mechs: one powered core in the list means the upgrade is powered.
function utils.isMechUpgradePowerListPowered(list)
	if type(list) ~= "table" or #list < 1 then
		return false
	end
	for i = 1, #list do
		if not utils.isCorePowered(list[i]) then
			return false
		end
	end
	return true
end

function utils.getMechUpgradePowerList(pawn, slot)
	if not pawn then
		return nil
	end
	if slot == mech_forge.VANILLA_UPGRADES.HEALTH then
		return pawn:GetHpCorePowerList()
	end
	if slot == mech_forge.VANILLA_UPGRADES.MOVE then
		return pawn:GetMoveCorePowerList()
	end
	return nil
end

function utils.isMechUpgradePowered(pawn, slot)
	if not utils.isValidUpgradeSlot(slot) then
		return false
	end
	if slot == mech_forge.VANILLA_UPGRADES.HEALTH then
		return pawn:IsHpPowered()
	end
	if slot == mech_forge.VANILLA_UPGRADES.MOVE then
		return pawn:IsMovePowered()
	end
	return false
end

function utils.getMechType(pawn)
	if not pawn then
		return nil
	end
	local mechType = pawn:GetType()
	if mechType and mechType ~= "" then
		return mechType
	end
	return nil
end

function utils.resolveText(value, pawn)
	if value == nil then
		return nil
	end

	-- If we have a function call it and use the result or the passed label if its not fn
	local resolved = type(value) == "function" and value(pawn) or value

	-- call get text which will be overridden to handle custom lables
	return GetText(resolved)
end

return utils