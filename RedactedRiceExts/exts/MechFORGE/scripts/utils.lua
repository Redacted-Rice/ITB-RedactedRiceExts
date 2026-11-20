local utils = {}

function utils.isValidUpgradeSlot(slot)
	return slot == mech_forge.VANILLA_UPGRADES.HEALTH
		or slot == mech_forge.VANILLA_UPGRADES.MOVE
end

function utils.isCorePowered(core)
	return memhack.structs.CoreList.isCorePowered(core)
end

-- Upgrade is powered when every core in the first slotCount entries is powered.
function utils.isMechUpgradeCoresPowered(cores)
	if not type(cores) ~= "table" then
		return false
	end
	for i = 1, #cores do
		if not utils.isCorePowered(cores[i]) then
			return false
		end
	end
	return true
end

-- Get memhack hp/move CoreList on the vanilla pawn
function utils.getMechUpgradeMemhackCores(pawn, slot)
	if not pawn then
		return nil
	end
	-- We use the direct ones that return memhack CoreLists
	-- instead of the ones on pawn that return lua tables
	if slot == mech_forge.VANILLA_UPGRADES.HEALTH then
		return pawn:GetMemhackObj():getHpCores()
	end
	if slot == mech_forge.VANILLA_UPGRADES.MOVE then
		return pawn:GetMemhackObj():getMoveCores()
	end
	return nil
end

function utils.isMechUpgradePowered(pawn, slot)
	if not utils.isValidUpgradeSlot(slot) then
		return false
	end
	-- This is just a bool so we can call the ones direclty
	-- on pawn
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
