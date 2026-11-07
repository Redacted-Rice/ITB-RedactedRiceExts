local utils = {}

function utils.isValidUpgradeSlot(slot)
	return slot == mech_forge.VANILLA_UPGRADES.HEALTH
		or slot == mech_forge.VANILLA_UPGRADES.MOVE
end

function utils.isCorePowered(core)
	return core ~= nil and core ~= memhack.CORE_TYPE_NONE
end

function utils.getMechUpgradeCore(pawn, slot)
	if not pawn then
		return nil
	end
	if slot == mech_forge.VANILLA_UPGRADES.HEALTH and pawn.GetHpCore then
		return pawn:GetHpCore()
	end
	if slot == mech_forge.VANILLA_UPGRADES.MOVE and pawn.GetMoveCore then
		return pawn:GetMoveCore()
	end
	return nil
end

function utils.isMechUpgradePowered(pawn, slot)
	if not utils.isValidUpgradeSlot(slot) then
		return false
	end
	return utils.isCorePowered(utils.getMechUpgradeCore(pawn, slot))
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
