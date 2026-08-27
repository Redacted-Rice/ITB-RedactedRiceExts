--[[
	Apply skill bonus cores to weapon power/upgrade lists.
	The base game seems to guard against multiple bonus cores on loading
	and because skills are reapplied on load we need special handling
	to get them to work right on loading.
	
	This does the following:
		PostLoadGame (not in mission): apply cores from save.
		MissionStart: snapshot live cores.
		MissionEnd: reapply from snapshot.
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

skillCoreSync.WEAPON_SLOTS = {
	{ field = "primary", index = 1 },
	{ field = "secondary", index = 2 },
}

function skillCoreSync.initGameSaveData()
	if GAME == nil then
		GAME = {}
	end
	if GAME.memhack == nil then
		GAME.memhack = {}
	end
end

function skillCoreSync.getMissionSnapshot()
	skillCoreSync.initGameSaveData()
	return GAME.memhack.mission_core_snapshot
end

function skillCoreSync.setMissionSnapshot(snap)
	skillCoreSync.initGameSaveData()
	GAME.memhack.mission_core_snapshot = snap
end

function skillCoreSync.clearMissionSnapshot()
	skillCoreSync.initGameSaveData()
	GAME.memhack.mission_core_snapshot = nil
end

function skillCoreSync.listToString(list)
	if type(list) ~= "table" then
		return tostring(list)
	end
	if #list == 0 then
		return "{}"
	end
	return "{" .. table.concat(list, ",") .. "}"
end

function skillCoreSync.copyList(list)
	if type(list) ~= "table" then
		return nil
	end
	local out = {}
	for i, v in ipairs(list) do
		out[i] = v
	end
	return out
end

function skillCoreSync.logCores(tag, pawnId, hpCore, moveCore, weapons)
	local w1 = weapons and weapons[1]
	local w2 = weapons and weapons[2]
	logger.logInfo(SUBMODULE,
			"[Memhack:CoreSync] %s pawn %d hp=%s move=%s w1={power=%s mod1=%s mod2=%s} w2={power=%s mod1=%s mod2=%s}",
			tag, pawnId, tostring(hpCore), tostring(moveCore),
			skillCoreSync.listToString(w1 and w1.power),
			skillCoreSync.listToString(w1 and w1.upgrade1),
			skillCoreSync.listToString(w1 and w1.upgrade2),
			skillCoreSync.listToString(w2 and w2.power),
			skillCoreSync.listToString(w2 and w2.upgrade1),
			skillCoreSync.listToString(w2 and w2.upgrade2)
	)
end

function skillCoreSync.readWeaponIntList(getter, pawn, weaponIndex)
	local memedit = memedit:get()
	if not memedit.weapon[getter] then
		return nil
	end
	local list = memedit.weapon[getter](pawn, weaponIndex)
	if not list then
		return nil
	end
	local values = {}
	for i = 0, list:size() - 1 do
		values[i + 1] = list:at(i)
	end
	return values
end

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

-- Tries first to get from Squad data then will fallback to region data 
function skillCoreSync.getSavePawnTable(pawnId)
	if SquadData then
		local ptable = modapiext.pawn:getSavedataTable(pawnId, SquadData)
		if ptable then
			return ptable
		end
	end

	local region = modapiext.board:getCurrentRegion()
	if region and region.player and region.player.map_data then
		return modapiext.pawn:getSavedataTable(pawnId, region.player.map_data)
	end
	return nil
end

-- Applies a core list to the weapon checking the current data to ensure
-- no memory overflows
function skillCoreSync.applyCoreList(pawn, weaponIndex, spec, sourceList)
	if type(sourceList) ~= "table" then
		return
	end

	local live = skillCoreSync.readWeaponIntList(spec.get, pawn, weaponIndex)
	local maxSlots = live and #live or #sourceList

	for slotIndex, sourceVal in ipairs(sourceList) do
		if slotIndex > maxSlots then
			break
		end
		skillCoreSync.writeWeaponIntListSlot(pawn, weaponIndex, spec.field, slotIndex, sourceVal)
	end
end

-- Applies the weapon data to the pawn at the given index. This will
-- set for the base core cost and the upgrades safely ensuring no
-- memory overflows but the expectation is that the weapon type has
-- already be validated and should match the wdata
function skillCoreSync.applyWeaponCores(pawn, weaponIndex, wdata)
	for _, spec in ipairs(skillCoreSync.LIST_SPECS) do
		skillCoreSync.applyCoreList(pawn, weaponIndex, spec, wdata[spec.key])
	end
end

function skillCoreSync.applyMechCores(pawn, hpCore, moveCore)
	pawn:SetHpCore(hpCore)
	pawn:SetMoveCore(moveCore)
end

function skillCoreSync.readLiveWeaponCores(pawn, weaponIndex)
	local cores = {}
	for _, spec in ipairs(skillCoreSync.LIST_SPECS) do
		cores[spec.key] = skillCoreSync.copyList(skillCoreSync.readWeaponIntList(spec.get, pawn, weaponIndex))
	end
	return cores
end

function skillCoreSync.readLiveWeapons(pawn)
	local weapons = {}
	local weaponCount = pawn:GetWeaponCount()
	for _, slot in ipairs(skillCoreSync.WEAPON_SLOTS) do
		if slot.index <= weaponCount then
			weapons[slot.index] = skillCoreSync.readLiveWeaponCores(pawn, slot.index)
		end
	end
	return weapons
end

function skillCoreSync.weaponCoresFromSave(wdata)
	local cores = {}
	for _, spec in ipairs(skillCoreSync.LIST_SPECS) do
		cores[spec.key] = skillCoreSync.copyList(wdata[spec.key])
	end
	return cores
end

function skillCoreSync.weaponsFromSave(ptable)
	local weapons = {}
	for _, slot in ipairs(skillCoreSync.WEAPON_SLOTS) do
		local wdata = modapiext.pawn:getWeaponData(ptable, slot.field)
		if wdata then
			weapons[slot.index] = skillCoreSync.weaponCoresFromSave(wdata)
		end
	end
	return weapons
end

function skillCoreSync.applyPawnCores(pawn, hpCore, moveCore, weapons)
	skillCoreSync.applyMechCores(pawn, hpCore, moveCore)
	if type(weapons) == "table" then
		for weaponIndex, wdata in pairs(weapons) do
			if weaponIndex <= pawn:GetWeaponCount() then
				skillCoreSync.applyWeaponCores(pawn, weaponIndex, wdata)
			end
		end
	end
end

function skillCoreSync.syncPawnFromSave(pawnId)
	local pawn = Game:GetPawn(pawnId)
	local ptable = skillCoreSync.getSavePawnTable(pawnId)
	if not pawn or not ptable then
		return
	end

	-- Get the target weapon data and mech cores from the save data
	local weapons = skillCoreSync.weaponsFromSave(ptable)
	local hpCore = ptable.healthPower[1]
	local moveCore = ptable.movePower[1]

	skillCoreSync.logCores("load", pawnId, hpCore, moveCore, weapons)
	skillCoreSync.applyPawnCores(pawn, hpCore, moveCore, weapons)
end

function skillCoreSync.syncAllFromSave()
	for pawnId = 0, 2 do
		skillCoreSync.syncPawnFromSave(pawnId)
	end
end

function skillCoreSync.snapshotPawnCores(pawnId)
	local pawn = Game:GetPawn(pawnId)
	if not pawn then
		return nil
	end
	return {
		hpCore = pawn:GetHpCore(),
		moveCore = pawn:GetMoveCore(),
		weapons = skillCoreSync.readLiveWeapons(pawn),
	}
end

function skillCoreSync.snapshotAllPawnCores()
	local snap = {}
	for pawnId = 0, 2 do
		local pawnSnap = skillCoreSync.snapshotPawnCores(pawnId)
		if pawnSnap then
			snap[pawnId] = pawnSnap
			skillCoreSync.logCores("missionStart", pawnId, pawnSnap.hpCore, pawnSnap.moveCore, pawnSnap.weapons)
		end
	end
	return snap
end

function skillCoreSync.applyPawnSnapshot(pawnId, snap)
	local pawn = Game:GetPawn(pawnId)
	if not pawn or not snap then
		return
	end

	skillCoreSync.logCores("missionEnd", pawnId, snap.hpCore, snap.moveCore, snap.weapons)
	skillCoreSync.applyPawnCores(pawn, snap.hpCore, snap.moveCore, snap.weapons)
end

function skillCoreSync.applyAllFromSnapshot(snap)
	for pawnId = 0, 2 do
		if snap[pawnId] then
			skillCoreSync.applyPawnSnapshot(pawnId, snap[pawnId])
		end
	end
end

function skillCoreSync.onPostLoadGame()
	skillCoreSync.syncAllFromSave()
end

function skillCoreSync.onMissionStart()
	skillCoreSync.setMissionSnapshot(skillCoreSync.snapshotAllPawnCores())
end

function skillCoreSync.onMissionEnd()
	local snap = skillCoreSync.getMissionSnapshot()
	if not snap then
		return
	end
	skillCoreSync.applyAllFromSnapshot(snap)
	skillCoreSync.clearMissionSnapshot()
end

function skillCoreSync.init()
	modApi.events.onPostLoadGame:subscribe(skillCoreSync.onPostLoadGame)
	modApi.events.onMissionStart:subscribe(skillCoreSync.onMissionStart)
	modApi.events.onMissionEnd:subscribe(skillCoreSync.onMissionEnd)
end

return skillCoreSync
