--[[
	Apply skill bonus cores to weapon power/upgrade lists.
	The base game seems to guard against multiple bonus cores on loading
	and because skills are reapplied on load we need special handling
	to get them to work right on loading.

	This does the following:
		PostLoadGame (not in mission): apply cores from save.
		PostLoadGame (in mission): ensure double suffixed _G copies so vanilla
			load of saved suffixed weapons does not error, then delayed rebuild.
		MissionStart: snapshot live cores.
		MissionEnd: strip suffixed weapons to base, then reapply snapshot.
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

skillCoreSync.WEAPON_SUFFIX_VARIANTS = { "_A", "_B", "_AB" }

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

-- Board is not set until the frame after PostLoadGame when continuing a game
-- (see mod_loader altered/misc.lua) for the snapshot
function skillCoreSync.isMissionSaveLoaded()
	return skillCoreSync.getMissionSnapshot() ~= nil
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
	logger.logDebug(SUBMODULE, 
			"%s pawn %d hp=%s move=%s w1={power=%s mod1=%s mod2=%s} w2={power=%s mod1=%s mod2=%s}",
			tag, pawnId, tostring(hpCore), tostring(moveCore),
			skillCoreSync.listToString(w1 and w1.power),
			skillCoreSync.listToString(w1 and w1.upgrade1),
			skillCoreSync.listToString(w1 and w1.upgrade2),
			skillCoreSync.listToString(w2 and w2.power),
			skillCoreSync.listToString(w2 and w2.upgrade1),
			skillCoreSync.listToString(w2 and w2.upgrade2)
		)
end

function skillCoreSync.stripWeaponSuffix(weaponId)
	if weaponId:sub(-3) == "_AB" then
		return weaponId:sub(1, -4)
	end
	if weaponId:sub(-2) == "_A" or weaponId:sub(-2) == "_B" then
		return weaponId:sub(1, -3)
	end
	return weaponId
end

function skillCoreSync.getWeaponSuffix(weaponId)
	if weaponId:sub(-3) == "_AB" then
		return "_AB"
	end
	if weaponId:sub(-2) == "_A" then
		return "_A"
	end
	if weaponId:sub(-2) == "_B" then
		return "_B"
	end
	return ""
end

function skillCoreSync.hasWeaponSuffix(weaponId)
	return skillCoreSync.getWeaponSuffix(weaponId) ~= ""
end

function skillCoreSync.isUpgradePowered(upgrade)
	-- Same rule as modapiext pawn isPowered where an empty list means the 
	-- upgrade slot is active with no core costs. non-empty requires upgrade[1] > 0.
	return upgrade and (#upgrade == 0 or (upgrade[1] and upgrade[1] > 0))
end

function skillCoreSync.getUpgradeSuffixFromCores(wdata)
	if not wdata then
		return ""
	end
	local hasA = skillCoreSync.isUpgradePowered(wdata.upgrade1)
	local hasB = skillCoreSync.isUpgradePowered(wdata.upgrade2)
	if hasA and hasB then
		return "_AB"
	elseif hasA then
		return "_A"
	elseif hasB then
		return "_B"
	end
	return ""
end

function skillCoreSync.resolveWeaponId(baseId, wdata)
	local suffix = skillCoreSync.getUpgradeSuffixFromCores(wdata)
	-- Rebuild uses stripped baseId + single suffix (e.g. Weapon_Cannon_AB).
	-- Falls back to baseId if that variant is not in _G (which it really 
	-- should be unless something odd is happening)
	if suffix ~= "" and _G[baseId .. suffix] ~= nil then
		return baseId .. suffix
	end
	return baseId
end

function skillCoreSync.logWeaponCoreDiffs(tag, pawnId, slotField, liveCores, snapCores)
	logger.logDebug(SUBMODULE, "%s pawn %d %s live={power=%s mod1=%s mod2=%s} snap={power=%s mod1=%s mod2=%s}",
			tag, pawnId, slotField,
			skillCoreSync.listToString(liveCores and liveCores.power),
			skillCoreSync.listToString(liveCores and liveCores.upgrade1),
			skillCoreSync.listToString(liveCores and liveCores.upgrade2),
			skillCoreSync.listToString(snapCores and snapCores.power),
			skillCoreSync.listToString(snapCores and snapCores.upgrade1),
			skillCoreSync.listToString(snapCores and snapCores.upgrade2))
end

function skillCoreSync.readWeaponIntList(getter, pawn, weaponIndex)
	local meInst = memedit:get()
	if not meInst.weapon[getter] then
		return nil
	end
	local list = meInst.weapon[getter](pawn, weaponIndex)
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
	-- weaponIndex is 1 based which matches memedit/BoardPawn. Slot 0 is unused, so
	-- index 1 is at begin + 0x8. Each entry is 8 bytes (smart pointer). This ends up
	-- effectively adding 1 to the index making it look like we are treating it as
	-- 0 based instead of 1 based but this is correct
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

function skillCoreSync.getSaveNonEmptyWeaponData(pawnId, slotField)
	local ptable = skillCoreSync.getSavePawnTable(pawnId)
	if not ptable then
		return nil
	end
	-- Empty slots still seem to return weapon data so ensure its actually
	-- a weapon before returning
	local wdata = modapiext.pawn:getWeaponData(ptable, slotField)
	if not wdata or type(wdata.id) ~= "string" or wdata.id == "" then
		return nil
	end
	return wdata
end

function skillCoreSync.copyInG(sourceId, destId)
	local source = _G[sourceId]
	local copy = {}
	for k, v in pairs(source) do
		copy[k] = v
	end
	setmetatable(copy, getmetatable(source))
	_G[destId] = copy
end

function skillCoreSync.addWeaponSuffixInG(sourceId)
	if not skillCoreSync.hasWeaponSuffix(sourceId) then
		return
	end

	-- Save stores a suffixed id (e.g. Weapon_Cannon_A). if we have manually applied 
	-- the fix in mission. During vanilla load the game may look up sourceId .. suffix
	-- now a double suffixed version based on what it thinks should be powered. To 
	-- to prevent the lookup from erroring, copy to the weapon to all double-suffixed 
	-- _G entries (Weapon_Cannon_A_AB, etc.) so the lookup succeeds. Not used
	-- by resolveWeaponId / AddWeapon rebuild - those use stripped base + suffix (
	-- single suffixed versions).
	for _, suffix in ipairs(skillCoreSync.WEAPON_SUFFIX_VARIANTS) do
		local variantId = sourceId .. suffix
		if _G[variantId] == nil then
			skillCoreSync.copyInG(sourceId, variantId)
			logger.logDebug(SUBMODULE, "Added _G[%s] copy from _G[%s]", variantId, sourceId)
		end
	end
end

function skillCoreSync.addAllWeaponSuffixesInGFromSave()
	for pawnId = 0, 2 do
		for _, slot in ipairs(skillCoreSync.WEAPON_SLOTS) do
			local wdata = skillCoreSync.getSaveNonEmptyWeaponData(pawnId, slot.field)
			if wdata and skillCoreSync.hasWeaponSuffix(wdata.id) then
				skillCoreSync.addWeaponSuffixInG(wdata.id)
			end
		end
	end
end

function skillCoreSync.listsEqual(a, b)
	if a == nil and b == nil then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

function skillCoreSync.weaponCoresMatch(live, snap)
	if not live or not snap then
		return live == snap
	end
	for _, spec in ipairs(skillCoreSync.LIST_SPECS) do
		if not skillCoreSync.listsEqual(live[spec.key], snap[spec.key]) then
			return false
		end
	end
	return true
end

-- Applies a core list to the weapon checking the current data to ensure
-- no memory overflows
function skillCoreSync.applyCoreList(pawn, weaponIndex, spec, sourceList)
	if type(sourceList) ~= "table" then
		return
	end

	local live = skillCoreSync.readWeaponIntList(spec.get, pawn, weaponIndex)
	if not live then
		return
	end
	local maxSlots = #live

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

-- Applies mech cores when they differ from live. Info when changing, debug when unchanged.
function skillCoreSync.applyPawnMechCores(tag, pawnId, pawn, hpCore, moveCore)
	local liveHp = pawn:GetHpCore()
	local liveMove = pawn:GetMoveCore()
	if liveHp == hpCore and liveMove == moveCore then
		logger.logDebug(SUBMODULE, "%s pawn %d mechCores unchanged hpCore=%s moveCore=%s",
				tag, pawnId, tostring(liveHp), tostring(liveMove))
		return false
	end

	logger.logInfo(SUBMODULE, "%s pawn %d mechCores %s/%s -> %s/%s",
			tag, pawnId, tostring(liveHp), tostring(liveMove),
			tostring(hpCore), tostring(moveCore))
	skillCoreSync.applyMechCores(pawn, hpCore, moveCore)
	return true
end

function skillCoreSync.readLivePilotPower(pawn)
	local pilot = pawn:GetPilot()
	if not pilot then
		return nil
	end
	return skillCoreSync.copyList(pilot:getPowerList())
end

function skillCoreSync.pilotPowerFromSave(ptable)
	if not ptable or not ptable.pilot then
		return nil
	end
	return skillCoreSync.copyList(ptable.pilot.power)
end

-- Write pilot innate skill power cores without growing the live vector.
function skillCoreSync.applyPilotPowerList(pawn, sourceList)
	if type(sourceList) ~= "table" then
		return false
	end
	local pilot = pawn:GetPilot()
	if not pilot then
		return false
	end
	return pilot:setPowerList(sourceList)
end

-- Applies pilot power cores when they differ from live. Info when changing, debug when unchanged.
function skillCoreSync.applyPawnPilotCores(tag, pawnId, pawn, powerList)
	if type(powerList) ~= "table" then
		return false
	end
	local live = skillCoreSync.readLivePilotPower(pawn)
	if live == nil then
		return false
	end
	if skillCoreSync.listsEqual(live, powerList) then
		logger.logDebug(SUBMODULE, "%s pawn %d pilotCores unchanged power=%s",
				tag, pawnId, skillCoreSync.listToString(live))
		return false
	end

	logger.logInfo(SUBMODULE, "%s pawn %d pilotCores %s -> %s",
			tag, pawnId, skillCoreSync.listToString(live), skillCoreSync.listToString(powerList))
	skillCoreSync.applyPilotPowerList(pawn, powerList)
	return true
end

function skillCoreSync.applyPawnWeaponCores(pawn, weapons)
	for weaponIndex, wdata in pairs(weapons) do
		if weaponIndex <= pawn:GetWeaponCount() then
			skillCoreSync.applyWeaponCores(pawn, weaponIndex, wdata)
		end
	end
end

function skillCoreSync.applyPawnMechCoresFromSnapshot(pawnId, snap)
	local pawn = Game:GetPawn(pawnId)
	local pawnSnap = snap and snap[pawnId]
	if not pawn or not pawnSnap then
		return
	end

	skillCoreSync.applyPawnMechCores("inMission", pawnId, pawn, pawnSnap.hpCore, pawnSnap.moveCore)
	skillCoreSync.applyPawnPilotCores("inMission", pawnId, pawn, pawnSnap.pilotPower)
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

function skillCoreSync.sanitizeSaveWeaponId(ptable, field, baseId)
	if ptable and type(baseId) == "string" then
		ptable[field] = baseId
	end
end

-- Remove and re-add weapons from the first entry marked replace onward.
-- Earlier slots are left untouched and later slots are always re-added 
-- (even if unchanged) to preserve order when a prior slot changed. No op 
-- if nothing is marked replace.
-- forceEnable: passed to AddWeapon. In mission use true so PowerCost is
-- zeroed for combat and on mission end use false and reapply cores after
function skillCoreSync.replaceAllWeapons(pawn, entries, forceEnable)
	local firstReplaceIdx = nil
	for i, entry in ipairs(entries) do
		if entry.replace then
			firstReplaceIdx = i
			break
		end
	end
	if not firstReplaceIdx then
		return
	end

	local removedTypes = {}
	for i = pawn:GetWeaponCount(), firstReplaceIdx, -1 do
		removedTypes[i] = pawn:GetWeaponType(i)
		pawn:RemoveWeapon(i)
	end

	for i = firstReplaceIdx, #entries do
		local entry = entries[i]
		if entry.typeId then
			pawn:AddWeapon(entry.typeId, forceEnable)
			local newIndex = pawn:GetWeaponCount()
			if entry.cores then
				skillCoreSync.applyWeaponCores(pawn, newIndex, entry.cores)
			end
			entry._removedType = removedTypes[i]
			entry._newIndex = newIndex
		end
	end
	return removedTypes
end

function skillCoreSync.rebuildPawnWeaponsInMission(pawnId, snap)
	local pawn = Game:GetPawn(pawnId)
	local ptable = skillCoreSync.getSavePawnTable(pawnId)
	local pawnSnap = snap and snap[pawnId]
	if not pawn or not ptable or not pawnSnap or not pawn.RemoveWeapon or not pawn.AddWeapon then
		return
	end

	local toAdd = {}
	local needsRebuild = false
	local weaponCount = pawn:GetWeaponCount()

	for _, slot in ipairs(skillCoreSync.WEAPON_SLOTS) do
		local saveWdata = skillCoreSync.getSaveNonEmptyWeaponData(pawnId, slot.field)
		local liveType = nil
		local liveCores = nil
		if slot.index <= weaponCount then
			liveType = pawn:GetWeaponType(slot.index)
			liveCores = skillCoreSync.readLiveWeaponCores(pawn, slot.index)
		end

		if saveWdata or liveType then
			local snapCores = pawnSnap.weapons and pawnSnap.weapons[slot.index]
			local slotNeedsRebuild = false

			if saveWdata and skillCoreSync.hasWeaponSuffix(saveWdata.id) then
				slotNeedsRebuild = true
				logger.logDebug(SUBMODULE, "load suffix pawn %d %s saveId=%s liveType=%s",
						pawnId, slot.field, saveWdata.id, tostring(liveType))
			elseif saveWdata and liveCores and snapCores
					and not skillCoreSync.weaponCoresMatch(liveCores, snapCores) then
				slotNeedsRebuild = true
				skillCoreSync.logWeaponCoreDiffs("load coreDiff", pawnId, slot.field, liveCores, snapCores)
			end

			local typeId
			local cores
			if slotNeedsRebuild then
				-- Strip save id to base, then resolve single-suffixed typeId from
				-- powered cores for AddWeapon (see resolveWeaponId).
				local baseId = skillCoreSync.stripWeaponSuffix(saveWdata.id)
				cores = snapCores or skillCoreSync.weaponCoresFromSave(saveWdata)
				typeId = skillCoreSync.resolveWeaponId(baseId, cores)
			else
				-- Keep live weapon when this slot does not need rebuild so
				-- replacing the other slot does not drop it.
				typeId = liveType
				cores = liveCores
				if not typeId and saveWdata then
					local baseId = skillCoreSync.stripWeaponSuffix(saveWdata.id)
					cores = snapCores or skillCoreSync.weaponCoresFromSave(saveWdata)
					typeId = skillCoreSync.resolveWeaponId(baseId, cores)
				end
			end

			if slotNeedsRebuild then
				needsRebuild = true
			end
			table.insert(toAdd, {
				field = slot.field,
				typeId = typeId,
				cores = cores,
				replace = slotNeedsRebuild,
			})
		end
	end

	if not needsRebuild then
		logger.logDebug(SUBMODULE, "load weapons unchanged pawn %d", pawnId)
		return
	end

	skillCoreSync.replaceAllWeapons(pawn, toAdd, true)
	for _, entry in ipairs(toAdd) do
		if entry._newIndex then
			logger.logInfo(SUBMODULE, "load replace pawn %d %s %s -> typeId=%s liveType=%s",
					pawnId, entry.field, tostring(entry._removedType), tostring(entry.typeId),
					tostring(pawn:GetWeaponType(entry._newIndex)))
		end
	end
end

function skillCoreSync.rebuildAllPawnWeaponsInMission(snap)
	if not snap then
		return
	end
	for pawnId = 0, 2 do
		-- Always reapply mech cores on in mission load and potential rebuild the weapons
		skillCoreSync.applyPawnMechCoresFromSnapshot(pawnId, snap)
		skillCoreSync.rebuildPawnWeaponsInMission(pawnId, snap)
	end
end

function skillCoreSync.stripSuffixedWeaponsForPawn(pawnId)
	local pawn = Game:GetPawn(pawnId)
	local ptable = skillCoreSync.getSavePawnTable(pawnId)
	if not pawn then
		return
	end

	local toAdd = {}
	local anySuffixed = false

	for _, slot in ipairs(skillCoreSync.WEAPON_SLOTS) do
		if slot.index <= pawn:GetWeaponCount() then
			local liveType = pawn:GetWeaponType(slot.index)
			if liveType and skillCoreSync.hasWeaponSuffix(liveType) then
				anySuffixed = true
				local baseId = skillCoreSync.stripWeaponSuffix(liveType)
				logger.logDebug(SUBMODULE, "missionEnd suffix pawn %d %s liveType=%s baseId=%s",
						pawnId, slot.field, liveType, baseId)
				table.insert(toAdd, {
					field = slot.field,
					typeId = baseId,
					baseId = baseId,
					replace = true,
				})
			elseif liveType then
				-- Preserve non-suffixed weapons when only the other slot is stripped
				table.insert(toAdd, {
					field = slot.field,
					typeId = liveType,
					replace = false,
				})
			end
		end
	end

	if not anySuffixed then
		logger.logDebug(SUBMODULE, "missionEnd weapons unchanged pawn %d", pawnId)
		return
	end

	-- Do not force enable then onMissionEnd reapplies
	skillCoreSync.replaceAllWeapons(pawn, toAdd, false)
	for _, entry in ipairs(toAdd) do
		if entry._newIndex then
			logger.logInfo(SUBMODULE, "missionEnd replace pawn %d %s %s -> %s",
					pawnId, entry.field, tostring(entry._removedType), tostring(entry.typeId))
			if entry.baseId then
				skillCoreSync.sanitizeSaveWeaponId(ptable, entry.field, entry.baseId)
			end
		end
	end
end

function skillCoreSync.stripAllSuffixedWeapons()
	for pawnId = 0, 2 do
		skillCoreSync.stripSuffixedWeaponsForPawn(pawnId)
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
	skillCoreSync.applyPawnMechCores("load", pawnId, pawn, hpCore, moveCore)
	skillCoreSync.applyPawnPilotCores("load", pawnId, pawn, skillCoreSync.pilotPowerFromSave(ptable))
	skillCoreSync.applyPawnWeaponCores(pawn, weapons)
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
		pilotPower = skillCoreSync.readLivePilotPower(pawn),
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
	skillCoreSync.applyPawnMechCores("missionEnd", pawnId, pawn, snap.hpCore, snap.moveCore)
	skillCoreSync.applyPawnPilotCores("missionEnd", pawnId, pawn, snap.pilotPower)
	skillCoreSync.applyPawnWeaponCores(pawn, snap.weapons)
end

function skillCoreSync.applyAllFromSnapshot(snap)
	for pawnId = 0, 2 do
		if snap[pawnId] then
			skillCoreSync.applyPawnSnapshot(pawnId, snap[pawnId])
		end
	end
end

function skillCoreSync.runLaterWeaponRebuildInMission()
	modApi:runLater(function()
		logger.logDebug(SUBMODULE, "onPostLoadGame run later rebuild")
		skillCoreSync.rebuildAllPawnWeaponsInMission(skillCoreSync.getMissionSnapshot())
	end)
end

function skillCoreSync.onPostLoadGame()
	if skillCoreSync.isMissionSaveLoaded() then
		logger.logDebug(SUBMODULE, "onPostLoadGame inMission")
		skillCoreSync.addAllWeaponSuffixesInGFromSave()
		skillCoreSync.runLaterWeaponRebuildInMission()
		return
	end
	logger.logDebug(SUBMODULE, "onPostLoadGame notInMission")
	skillCoreSync.syncAllFromSave()
end

function skillCoreSync.onMissionStart()
	logger.logDebug(SUBMODULE, "onMissionStart")
	skillCoreSync.setMissionSnapshot(skillCoreSync.snapshotAllPawnCores())
end

function skillCoreSync.onMissionEnd()
	logger.logDebug(SUBMODULE, "onMissionEnd")
	local snap = skillCoreSync.getMissionSnapshot()
	if not snap then
		logger.logDebug(SUBMODULE, "onMissionEnd abort: no snapshot")
		return
	end
	logger.logDebug(SUBMODULE, "onMissionEnd part 1 stripSuffixed")
	skillCoreSync.stripAllSuffixedWeapons()
	logger.logDebug(SUBMODULE, "onMissionEnd part 2 applySnapshot")
	skillCoreSync.applyAllFromSnapshot(snap)
	skillCoreSync.clearMissionSnapshot()
end

function skillCoreSync.init()
	modApi.events.onPostLoadGame:subscribe(skillCoreSync.onPostLoadGame)
	modApi.events.onMissionStart:subscribe(skillCoreSync.onMissionStart)
	modApi.events.onMissionEnd:subscribe(skillCoreSync.onMissionEnd)
end

return skillCoreSync