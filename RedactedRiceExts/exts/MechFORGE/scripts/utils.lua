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

return utils
