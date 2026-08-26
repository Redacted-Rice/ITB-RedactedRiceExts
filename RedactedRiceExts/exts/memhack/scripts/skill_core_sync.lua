--[[
	Apply skill bonus cores to weapon power/upgrade lists.
	The base game seems to guard against multiple bonus cores on loading
	and because skills are reapplied on load we need special handling
	to get them to work right on loading
]]

-- Register with logging system
local logger = memhack.logger
local SUBMODULE = logger.register("Memhack", "SkillCoreSync", memhack.DEBUG.SKILL_CORE_SYNC and memhack.DEBUG.ENABLED)

local skillCoreSync = {}

skillCoreSync.LIST_SPECS = {
	{ key = "power", get = "getPowerList", field = "PowerList" },
	{ key = "upgrade1", get = "getUpgradeListA", field = "UpgradeListA" },
	{ key = "upgrade2", get = "getUpgradeListB", field = "UpgradeListB" },
}

function skillCoreSync.writeWeaponIntListSlot(pawn, weaponIndex, fieldName, slotIndex, value)
	local addresses = memedit:loadAddressesFromFile()
	if not addresses then
		return false
	end
	local mem = memhack.dll.memory

	local pawnAddr = mem.getUserdataAddr(pawn)
	local weaponListAddr = mem.readPointer(pawnAddr + addresses.vital.delta_weapons)
	local weaponAddr = mem.readPointer(weaponListAddr + weaponIndex * 0x8)
	local fieldEntry = addresses.weapon[fieldName]
	if not fieldEntry or not weaponAddr then
		return false
	end

	local vecAddr = mem.readPointer(weaponAddr + fieldEntry[1])
	if not vecAddr or vecAddr == 0 then
		return false
	end

	mem.writeInt(vecAddr + (slotIndex - 1) * 4, value)
	return true
end

function skillCoreSync.applySkillBonusList(pawn, weaponIndex, spec, saveList)
	if type(saveList) ~= "table" then
		return
	end

	local skillBonusCore = memhack.structs.BoardPawn.CORE_TYPE_SKILL_BONUS
	local memedit = memedit:get()

	for slotIndex, saveVal in ipairs(saveList) do
		if saveVal == skillBonusCore then
			local wrote = skillCoreSync.writeWeaponIntListSlot(pawn, weaponIndex, spec.field, slotIndex, skillBonusCore)
			logger.logDebug(SUBMODULE,
				"pawn %d wpnIdx=%d %s slot=%d wrote=%s",
				pawn:GetId(), weaponIndex, spec.key, slotIndex, tostring(wrote))
		end
	end
end

function skillCoreSync.applySkillBonusWeaponCores(pawn, weaponIndex, wdata)
	if not pawn or not wdata then
		return false
	end

	for _, spec in ipairs(skillCoreSync.LIST_SPECS) do
		skillCoreSync.applySkillBonusList(pawn, weaponIndex, spec, wdata[spec.key])
	end

	return true
end

return skillCoreSync
