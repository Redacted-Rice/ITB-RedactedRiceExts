-- Tests for skill_core_sync.lua (no memedit I/O)

local specHelper = require("helpers/spec_helper")
local testUtil = require("helpers/test_util")
local gameMocks = require("helpers/game_mocks")

local memhack = specHelper.initMemhack()
local skillCoreSync = memhack.skillCoreSync

local saveGlobal = testUtil.saveGlobal
local restoreGlobals = testUtil.restoreGlobals
local saveFn = testUtil.saveFn
local restoreFns = testUtil.restoreFns
local makeMockPawn = gameMocks.makeMockPawn
local makeSavePtable = gameMocks.makeSavePtable
local installModApiExt = gameMocks.installModApiExt
local installGameGetPawn = gameMocks.installGameGetPawn

local function weaponGlobals(prefix)
	_G[prefix] = { id = prefix }
	_G[prefix .. "_A"] = { id = prefix .. "_A" }
	_G[prefix .. "_B"] = { id = prefix .. "_B" }
	_G[prefix .. "_AB"] = { id = prefix .. "_AB" }
end

local function clearWeaponGlobals(prefix)
	_G[prefix] = nil
	_G[prefix .. "_A"] = nil
	_G[prefix .. "_B"] = nil
	_G[prefix .. "_AB"] = nil
end

local function sampleCores(power, upgrade1, upgrade2)
	return {
		power = power,
		upgrade1 = upgrade1,
		upgrade2 = upgrade2,
	}
end
describe("Skill Core Sync", function()
	after_each(function()
		restoreFns()
		restoreGlobals()
		gameMocks.pawns = {}
		skillCoreSync.clearMissionSnapshot()
	end)

	describe("list helpers", function()
		it("copyList and listToString round-trip table lists", function()
			local src = { 1, 2, 3 }
			local copy = skillCoreSync.copyList(src)
			assert.is_true(src ~= copy)
			assert.are.same(src, copy)
			assert.are.equal("{1,2,3}", skillCoreSync.listToString(copy))
		end)

		it("handles non-table inputs", function()
			assert.is_nil(skillCoreSync.copyList("nope"))
			assert.are.equal("{}", skillCoreSync.listToString({}))
			assert.are.equal("123", skillCoreSync.listToString(123))
		end)

		it("listsEqual compares array contents", function()
			assert.is_true(skillCoreSync.listsEqual({ 1, 2 }, { 1, 2 }))
			assert.is_true(skillCoreSync.listsEqual(nil, nil))
			assert.is_false(skillCoreSync.listsEqual({ 1 }, { 2 }))
			assert.is_false(skillCoreSync.listsEqual({ 1 }, nil))
			assert.is_false(skillCoreSync.listsEqual("a", "a"))
		end)
	end)

	describe("stripWeaponSuffix", function()
		it("leaves unsuffixed ids unchanged", function()
			assert.are.equal("DeploySkill_Tank", skillCoreSync.stripWeaponSuffix("DeploySkill_Tank"))
		end)

		it("strips single _A and _B suffixes", function()
			assert.are.equal("Brute_Punchmech", skillCoreSync.stripWeaponSuffix("Brute_Punchmech_A"))
			assert.are.equal("Brute_Punchmech", skillCoreSync.stripWeaponSuffix("Brute_Punchmech_B"))
		end)

		it("strips _AB before treating _A as a suffix", function()
			assert.are.equal("Brute_Punchmech", skillCoreSync.stripWeaponSuffix("Brute_Punchmech_AB"))
		end)
	end)

	describe("getWeaponSuffix and hasWeaponSuffix", function()
		it("detects _A, _B, and _AB suffixes", function()
			assert.are.equal("_A", skillCoreSync.getWeaponSuffix("Weapon_A"))
			assert.are.equal("_B", skillCoreSync.getWeaponSuffix("Weapon_B"))
			assert.are.equal("_AB", skillCoreSync.getWeaponSuffix("Weapon_AB"))
			assert.are.equal("", skillCoreSync.getWeaponSuffix("Weapon"))
		end)

		it("hasWeaponSuffix reflects getWeaponSuffix", function()
			assert.is_true(skillCoreSync.hasWeaponSuffix("Weapon_A"))
			assert.is_false(skillCoreSync.hasWeaponSuffix("Weapon"))
		end)
	end)

	describe("getUpgradeSuffixFromCores", function()
		it("returns empty when neither upgrade is powered", function()
			local wdata = { upgrade1 = { 0 }, upgrade2 = { 0 } }
			assert.are.equal("", skillCoreSync.getUpgradeSuffixFromCores(wdata))
		end)

		it("treats empty upgrade lists as powered", function()
			local wdata = { upgrade1 = {}, upgrade2 = { 0 } }
			assert.are.equal("_A", skillCoreSync.getUpgradeSuffixFromCores(wdata))
		end)

		it("returns _A, _B, or _AB from powered upgrades", function()
			assert.are.equal("_A", skillCoreSync.getUpgradeSuffixFromCores({
				upgrade1 = { 1 }, upgrade2 = { 0 },
			}))
			assert.are.equal("_B", skillCoreSync.getUpgradeSuffixFromCores({
				upgrade1 = { 0 }, upgrade2 = { 2 },
			}))
			assert.are.equal("_AB", skillCoreSync.getUpgradeSuffixFromCores({
				upgrade1 = { 1 }, upgrade2 = { 2 },
			}))
		end)

		it("returns empty for nil weapon data", function()
			assert.are.equal("", skillCoreSync.getUpgradeSuffixFromCores(nil))
		end)
	end)

	describe("resolveWeaponId", function()
		local prefix = "SkillCoreSyncSpecWeapon"

		before_each(function()
			weaponGlobals(prefix)
		end)

		after_each(function()
			clearWeaponGlobals(prefix)
		end)

		it("returns base id when no upgrades are powered", function()
			local wdata = { upgrade1 = { 0 }, upgrade2 = { 0 } }
			assert.are.equal(prefix, skillCoreSync.resolveWeaponId(prefix, wdata))
		end)

		it("returns suffixed id when variant exists in _G", function()
			local wdata = { upgrade1 = { 1 }, upgrade2 = { 2 } }
			assert.are.equal(prefix .. "_AB", skillCoreSync.resolveWeaponId(prefix, wdata))
		end)
	end)

	describe("weaponCoresMatch", function()
		it("matches when all core lists are equal", function()
			local live = sampleCores({ 1 }, { 2 }, { 0 })
			local snap = sampleCores({ 1 }, { 2 }, { 0 })
			assert.is_true(skillCoreSync.weaponCoresMatch(live, snap))
		end)

		it("rejects when any core list differs", function()
			local live = sampleCores({ 1 }, { 2 }, { 0 })
			local snapPower = sampleCores({ 2 }, { 2 }, { 0 })
			local snapUpgrade = sampleCores({ 1 }, { 3 }, { 0 })

			assert.is_false(skillCoreSync.weaponCoresMatch(live, snapPower))
			assert.is_false(skillCoreSync.weaponCoresMatch(live, snapUpgrade))
		end)

		it("handles nil live or snap consistently", function()
			local cores = sampleCores({ 1 }, {}, {})
			assert.is_true(skillCoreSync.weaponCoresMatch(nil, nil))
			assert.is_false(skillCoreSync.weaponCoresMatch(cores, nil))
			assert.is_false(skillCoreSync.weaponCoresMatch(nil, cores))
		end)
	end)

	describe("weaponCoresFromSave and pilotPowerFromSave", function()
		it("copies weapon core lists from save weapon data", function()
			local wdata = {
				power = { 9 },
				upgrade1 = { 1 },
				upgrade2 = { 2 },
			}
			local cores = skillCoreSync.weaponCoresFromSave(wdata)
			assert.are.same({ 9 }, cores.power)
			assert.are.same({ 1 }, cores.upgrade1)
			assert.are.same({ 2 }, cores.upgrade2)
			wdata.power[1] = 0
			assert.are.equal(9, cores.power[1])
		end)

		it("copies pilot power from save ptable", function()
			local ptable = makeSavePtable({ pilotPower = { 4, 5 } })
			local power = skillCoreSync.pilotPowerFromSave(ptable)
			assert.are.same({ 4, 5 }, power)
			ptable.pilot.power[1] = 99
			assert.are.equal(4, power[1])
		end)
	end)

	describe("replaceAllWeapons", function()
		it("is a no op when no entry is marked replace", function()
			local pawn = makeMockPawn({ "Primary", "Secondary" })
			skillCoreSync.replaceAllWeapons(pawn, {
				{ typeId = "Primary", replace = false },
				{ typeId = "Secondary", replace = false },
			})

			assert.are.equal(2, pawn:GetWeaponCount())
			assert.are.equal("Primary", pawn:GetWeaponType(1))
			assert.are.equal("Secondary", pawn:GetWeaponType(2))
			assert.are.same({}, pawn._removeLog)
			assert.are.same({}, pawn._addLog)
		end)

		it("only rebuilds the secondary slot when it alone changed", function()
			local pawn = makeMockPawn({ "Primary", "Secondary_A" })
			skillCoreSync.replaceAllWeapons(pawn, {
				{ typeId = "Primary", replace = false },
				{ typeId = "Secondary", replace = true },
			})

			assert.are.equal(2, pawn:GetWeaponCount())
			assert.are.equal("Primary", pawn:GetWeaponType(1))
			assert.are.equal("Secondary", pawn:GetWeaponType(2))
			assert.are.same({ 2 }, pawn._removeLog)
			assert.are.same({ "Secondary" }, pawn._addLog)
		end)

		it("rebuilds from the primary slot onward to preserve order", function()
			local pawn = makeMockPawn({ "Primary_A", "Secondary" })
			skillCoreSync.replaceAllWeapons(pawn, {
				{ typeId = "Primary", replace = true },
				{ typeId = "Secondary", replace = false },
			})

			assert.are.equal(2, pawn:GetWeaponCount())
			assert.are.equal("Primary", pawn:GetWeaponType(1))
			assert.are.equal("Secondary", pawn:GetWeaponType(2))
			assert.are.same({ 2, 1 }, pawn._removeLog)
			assert.are.same({ "Primary", "Secondary" }, pawn._addLog)
		end)

		it("applies cores after replace when stubbing applyWeaponCores", function()
			local pawn = makeMockPawn({ "OldPrimary", "OldSecondary" })
			local applied = {}
			saveFn(skillCoreSync, "applyWeaponCores")
			skillCoreSync.applyWeaponCores = function(_, weaponIndex, cores)
				applied[#applied + 1] = { weaponIndex = weaponIndex, cores = cores }
			end

			local cores = sampleCores({ 7 }, { 0 }, { 0 })
			skillCoreSync.replaceAllWeapons(pawn, {
				{ typeId = "NewPrimary", replace = true, cores = cores },
				{ typeId = "NewSecondary", replace = true, cores = cores },
			})

			assert.are.equal(2, #applied)
			assert.are.equal(1, applied[1].weaponIndex)
			assert.are.equal(2, applied[2].weaponIndex)
			assert.are.same(cores, applied[1].cores)
		end)
	end)

	describe("sanitizeSaveWeaponId", function()
		it("writes stripped base id into save ptable field", function()
			local ptable = makeSavePtable({ primaryId = "Weapon_A" })
			skillCoreSync.sanitizeSaveWeaponId(ptable, "primary", "Weapon")
			assert.are.equal("Weapon", ptable.primary)
		end)

		it("ignores nil ptable or non string base id", function()
			skillCoreSync.sanitizeSaveWeaponId(nil, "primary", "Weapon")
			local ptable = {}
			skillCoreSync.sanitizeSaveWeaponId(ptable, "primary", 123)
			assert.is_nil(ptable.primary)
		end)
	end)

	describe("mission snapshot helpers", function()
		it("initializes GAME.memhack and stores snapshot", function()
			saveGlobal("GAME")
			_G.GAME = nil
			assert.is_nil(skillCoreSync.getMissionSnapshot())
			local snap = { [0] = { hpCore = 1 } }
			skillCoreSync.setMissionSnapshot(snap)
			assert.are.same(snap, skillCoreSync.getMissionSnapshot())
			assert.is_true(skillCoreSync.isMissionSaveLoaded())
			skillCoreSync.clearMissionSnapshot()
			assert.is_nil(skillCoreSync.getMissionSnapshot())
			assert.is_false(skillCoreSync.isMissionSaveLoaded())
		end)
	end)

	describe("addWeaponSuffixInG", function()
		local sourceId = "SkillCoreSyncDoubleSuffix_A"

		before_each(function()
			_G[sourceId] = { id = sourceId, marker = "src" }
		end)

		after_each(function()
			_G[sourceId] = nil
			for _, suffix in ipairs(skillCoreSync.WEAPON_SUFFIX_VARIANTS) do
				_G[sourceId .. suffix] = nil
			end
		end)

		it("is a no op for unsuffixed weapon ids", function()
			local unsuffixed = "SkillCoreSyncPlain"
			_G[unsuffixed] = { id = unsuffixed }
			skillCoreSync.addWeaponSuffixInG(unsuffixed)
			assert.is_nil(_G[unsuffixed .. "_A"])
			_G[unsuffixed] = nil
		end)

		it("creates all three double suffixed _G variants", function()
			skillCoreSync.addWeaponSuffixInG(sourceId)
			for _, suffix in ipairs(skillCoreSync.WEAPON_SUFFIX_VARIANTS) do
				local variantId = sourceId .. suffix
				assert.is_not_nil(_G[variantId])
				assert.are.equal("src", _G[variantId].marker)
			end
		end)
	end)

	describe("orchestration integration", function()
		local prefix = "SkillCoreSyncOrchWeapon"
		local squadSource = {}

		before_each(function()
			saveGlobal("SquadData")
			weaponGlobals(prefix)
			installGameGetPawn()

			local ptable = makeSavePtable({
				primaryId = prefix,
				secondary = false,
			})
			squadSource = { [1] = ptable }
			_G.SquadData = squadSource
			installModApiExt({
				bySource = { [squadSource] = { [1] = ptable } },
			})

			gameMocks.pawns[1] = makeMockPawn({ prefix .. "_A" }, { hpCore = 5, moveCore = 6, pilotPower = { 1 } })

			saveFn(skillCoreSync, "readLiveWeaponCores")
			skillCoreSync.readLiveWeaponCores = function()
				return sampleCores({ 1 }, { 0 }, { 0 })
			end

			saveFn(skillCoreSync, "applyWeaponCores")
			skillCoreSync.applyWeaponCores = function() end

			saveFn(skillCoreSync, "applyPawnMechCores")
			skillCoreSync.applyPawnMechCores = function() end

			saveFn(skillCoreSync, "applyPawnPilotCores")
			skillCoreSync.applyPawnPilotCores = function() end

			saveFn(skillCoreSync, "rebuildPawnWeaponsInMission")
			skillCoreSync.rebuildPawnWeaponsInMission = function() end
		end)

		after_each(function()
			clearWeaponGlobals(prefix)
		end)

		it("rebuilds suffixed save weapons", function()
			restoreFns()
			saveFn(skillCoreSync, "readLiveWeaponCores")
			skillCoreSync.readLiveWeaponCores = function()
				return sampleCores({ 1 }, { 0 }, { 0 })
			end
			saveFn(skillCoreSync, "applyWeaponCores")
			skillCoreSync.applyWeaponCores = function() end

			local ptable = makeSavePtable({ primaryId = prefix .. "_A", secondary = false })
			installModApiExt({ bySource = { [squadSource] = { [1] = ptable } } })
			local pawn = makeMockPawn({ prefix .. "_A" })
			gameMocks.pawns[1] = pawn

			local snap = { [1] = { weapons = { [1] = sampleCores({ 1 }, { 0 }, { 0 }) } } }
			skillCoreSync.rebuildPawnWeaponsInMission(1, snap)

			assert.are.equal(prefix, pawn:GetWeaponType(1))
			assert.are.same({ 1 }, pawn._removeLog)
		end)

		it("no ops rebuild when live cores match snapshot", function()
			restoreFns()
			local liveCores = sampleCores({ 1 }, { 0 }, { 0 })
			saveFn(skillCoreSync, "readLiveWeaponCores")
			skillCoreSync.readLiveWeaponCores = function()
				return liveCores
			end
			saveFn(skillCoreSync, "applyWeaponCores")
			skillCoreSync.applyWeaponCores = function() end

			local ptable = makeSavePtable({ primaryId = prefix, secondary = false })
			installModApiExt({ bySource = { [squadSource] = { [1] = ptable } } })
			local pawn = makeMockPawn({ prefix })
			gameMocks.pawns[1] = pawn

			local snap = { [1] = { weapons = { [1] = sampleCores({ 1 }, { 0 }, { 0 }) } } }
			skillCoreSync.rebuildPawnWeaponsInMission(1, snap)

			assert.are.equal(prefix, pawn:GetWeaponType(1))
			assert.are.same({}, pawn._removeLog)
		end)

		it("applies core diffs in place without Remove/Add when save id is unsuffixed", function()
			restoreFns()
			saveFn(skillCoreSync, "readLiveWeaponCores")
			skillCoreSync.readLiveWeaponCores = function()
				return sampleCores({ 1 }, { 0 }, { 0 })
			end
			local applied = {}
			saveFn(skillCoreSync, "applyWeaponCores")
			skillCoreSync.applyWeaponCores = function(_, weaponIndex, cores)
				applied[#applied + 1] = { weaponIndex = weaponIndex, cores = cores }
			end

			local ptable = makeSavePtable({ primaryId = prefix, secondary = false })
			installModApiExt({ bySource = { [squadSource] = { [1] = ptable } } })
			local pawn = makeMockPawn({ prefix })
			gameMocks.pawns[1] = pawn

			local snapCores = sampleCores({ 1 }, { 0 }, { 2 })
			local snap = { [1] = { weapons = { [1] = snapCores } } }
			skillCoreSync.rebuildPawnWeaponsInMission(1, snap)

			assert.are.equal(prefix, pawn:GetWeaponType(1))
			assert.are.same({}, pawn._removeLog)
			assert.are.equal(1, #applied)
			assert.are.equal(1, applied[1].weaponIndex)
			assert.are.same(snapCores, applied[1].cores)
		end)

		it("reverts secondary snapshot cores when primary suffix rebuild forces replace", function()
			restoreFns()
			local driftedSecondary = sampleCores({ 9 }, { 0 }, { 0 })
			local snapSecondary = sampleCores({ 2 }, { 0 }, { 0 })
			saveFn(skillCoreSync, "readLiveWeaponCores")
			skillCoreSync.readLiveWeaponCores = function(_, weaponIndex)
				if weaponIndex == 1 then
					return sampleCores({ 1 }, { 0 }, { 0 })
				end
				return driftedSecondary
			end
			local applied = {}
			saveFn(skillCoreSync, "applyWeaponCores")
			skillCoreSync.applyWeaponCores = function(_, weaponIndex, cores)
				applied[#applied + 1] = { weaponIndex = weaponIndex, cores = cores }
			end

			local ptable = makeSavePtable({ primaryId = prefix .. "_A" })
			installModApiExt({ bySource = { [squadSource] = { [1] = ptable } } })
			local pawn = makeMockPawn({ prefix .. "_A", prefix })
			gameMocks.pawns[1] = pawn

			local snap = {
				[1] = {
					weapons = {
						[1] = sampleCores({ 1 }, { 0 }, { 0 }),
						[2] = snapSecondary,
					},
				},
			}
			skillCoreSync.rebuildPawnWeaponsInMission(1, snap)

			assert.are.equal(prefix, pawn:GetWeaponType(1))
			assert.are.equal(prefix, pawn:GetWeaponType(2))
			assert.are.same({ 2, 1 }, pawn._removeLog)
			local secondaryApplies = {}
			for _, call in ipairs(applied) do
				if call.weaponIndex == 2 then
					secondaryApplies[#secondaryApplies + 1] = call
				end
			end
			assert.is_true(#secondaryApplies >= 1)
			assert.are.same(snapSecondary, secondaryApplies[#secondaryApplies].cores)
			assert.are_not.same(driftedSecondary, secondaryApplies[#secondaryApplies].cores)
		end)

		it("stripSuffixedWeaponsForPawn replaces suffixed live weapons with base ids", function()
			restoreFns()
			saveFn(skillCoreSync, "applyWeaponCores")
			skillCoreSync.applyWeaponCores = function() end

			local ptable = makeSavePtable({ primaryId = prefix .. "_A", secondary = false })
			installModApiExt({ bySource = { [squadSource] = { [1] = ptable } } })
			local pawn = makeMockPawn({ prefix .. "_A", prefix .. "_B" })
			gameMocks.pawns[1] = pawn

			skillCoreSync.stripSuffixedWeaponsForPawn(1)

			assert.are.equal(prefix, pawn:GetWeaponType(1))
			assert.are.equal(prefix, pawn:GetWeaponType(2))
			assert.are.equal(prefix, ptable.primary)
		end)

		it("syncPawnFromSave applies save cores to pawn", function()
			restoreFns()
			local mechCalls = 0
			local pilotCalls = 0
			local weaponCalls = 0
			saveFn(skillCoreSync, "applyPawnMechCores")
			skillCoreSync.applyPawnMechCores = function()
				mechCalls = mechCalls + 1
			end
			saveFn(skillCoreSync, "applyPawnPilotCores")
			skillCoreSync.applyPawnPilotCores = function()
				pilotCalls = pilotCalls + 1
			end
			saveFn(skillCoreSync, "applyPawnWeaponCores")
			skillCoreSync.applyPawnWeaponCores = function()
				weaponCalls = weaponCalls + 1
			end

			gameMocks.pawns[1] = makeMockPawn({ prefix })
			skillCoreSync.syncPawnFromSave(1)

			assert.are.equal(1, mechCalls)
			assert.are.equal(1, pilotCalls)
			assert.are.equal(1, weaponCalls)
		end)

		it("snapshotPawnCores captures live mech, pilot, and weapon cores", function()
			restoreFns()
			saveFn(skillCoreSync, "readLiveWeaponCores")
			skillCoreSync.readLiveWeaponCores = function()
				return sampleCores({ 8 }, { 0 }, { 0 })
			end

			local pawn = makeMockPawn({ prefix }, { hpCore = 11, moveCore = 12, pilotPower = { 13 } })
			gameMocks.pawns[1] = pawn

			local snap = skillCoreSync.snapshotPawnCores(1)
			assert.are.equal(11, snap.hpCore)
			assert.are.equal(12, snap.moveCore)
			assert.are.same({ 13 }, snap.pilotPower)
			assert.are.same({ 8 }, snap.weapons[1].power)
		end)

		it("applyPawnSnapshot restores mech and pilot cores using real apply functions", function()
			restoreFns()

			local pawn = makeMockPawn({ prefix }, { hpCore = 1, moveCore = 2, pilotPower = { 3 } })
			gameMocks.pawns[1] = pawn

			saveFn(skillCoreSync, "applyPawnWeaponCores")
			skillCoreSync.applyPawnWeaponCores = function() end

			local snap = {
				hpCore = 9,
				moveCore = 10,
				pilotPower = { 4, 5 },
				weapons = {},
			}
			skillCoreSync.applyPawnSnapshot(1, snap)

			assert.are.equal(9, pawn:GetHpCore())
			assert.are.equal(10, pawn:GetMoveCore())
			assert.are.same({ 4, 5 }, pawn:GetPilot():getPowerList())
		end)

		it("onMissionStart stores snapshot from all pawns", function()
			saveFn(skillCoreSync, "snapshotAllPawnCores")
			local expected = { [0] = { hpCore = 1 } }
			skillCoreSync.snapshotAllPawnCores = function()
				return expected
			end

			skillCoreSync.onMissionStart()
			assert.are.same(expected, skillCoreSync.getMissionSnapshot())
		end)

		it("onMissionEnd clears snapshot after strip and restore", function()
			local snap = { [0] = { hpCore = 1 } }
			skillCoreSync.setMissionSnapshot(snap)
			local order = {}

			saveFn(skillCoreSync, "stripAllSuffixedWeapons")
			skillCoreSync.stripAllSuffixedWeapons = function()
				table.insert(order, "strip")
			end
			saveFn(skillCoreSync, "applyAllFromSnapshot")
			skillCoreSync.applyAllFromSnapshot = function()
				table.insert(order, "apply")
			end

			skillCoreSync.onMissionEnd()
			assert.are.same({ "strip", "apply" }, order)
			assert.is_nil(skillCoreSync.getMissionSnapshot())
		end)

		it("onPostLoadGame syncs from save when not in mission", function()
			local syncCalls = 0
			saveFn(skillCoreSync, "syncAllFromSave")
			skillCoreSync.syncAllFromSave = function()
				syncCalls = syncCalls + 1
			end
			saveFn(skillCoreSync, "addAllWeaponSuffixesInGFromSave")
			skillCoreSync.addAllWeaponSuffixesInGFromSave = function() error("should not run") end

			skillCoreSync.onPostLoadGame()
			assert.are.equal(1, syncCalls)
		end)

		it("onPostLoadGame rebuilds in mission when snapshot exists", function()
			skillCoreSync.setMissionSnapshot({ [0] = {} })
			local suffixCalls = 0
			local rebuildCallsLocal = 0

			saveFn(skillCoreSync, "addAllWeaponSuffixesInGFromSave")
			skillCoreSync.addAllWeaponSuffixesInGFromSave = function()
				suffixCalls = suffixCalls + 1
			end
			saveFn(skillCoreSync, "rebuildAllPawnWeaponsInMission")
			skillCoreSync.rebuildAllPawnWeaponsInMission = function()
				rebuildCallsLocal = rebuildCallsLocal + 1
			end
			saveFn(skillCoreSync, "syncAllFromSave")
			skillCoreSync.syncAllFromSave = function() error("should not run") end

			skillCoreSync.onPostLoadGame()
			assert.are.equal(1, suffixCalls)
			assert.are.equal(1, rebuildCallsLocal)
		end)
	end)

	describe("save data access", function()
		before_each(function()
			saveGlobal("SquadData")
			installModApiExt({ region = nil, bySource = {}, byPawnId = {} })
		end)

		it("falls back to region map_data when SquadData has no pawn", function()
			local regionPtable = makeSavePtable({ primaryId = "RegionWeapon" })
			local region = {
				player = {
					map_data = { map = true },
				},
			}
			installModApiExt({
				region = region,
				bySource = {
					[region.player.map_data] = { [2] = regionPtable },
				},
			})
			_G.SquadData = nil

			assert.are.same(regionPtable, skillCoreSync.getSavePawnTable(2))
		end)

		it("getSaveNonEmptyWeaponData rejects empty weapon ids", function()
			local ptable = makeSavePtable({ primary = { id = "", power = { 1 } } })
			installModApiExt({
				bySource = { [_G.SquadData or {}] = { [0] = ptable } },
			})
			_G.SquadData = {}
			installModApiExt({
				byPawnId = { [0] = ptable },
			})

			assert.is_nil(skillCoreSync.getSaveNonEmptyWeaponData(0, "primary"))
		end)

		it("weaponsFromSave includes both primary and secondary slots", function()
			local ptable = makeSavePtable({
				primary = { id = "P", power = { 1 }, upgrade1 = { 0 }, upgrade2 = { 0 } },
				secondary = { id = "S", power = { 2 }, upgrade1 = { 1 }, upgrade2 = { 0 } },
			})
			local weapons = skillCoreSync.weaponsFromSave(ptable)
			assert.are.same({ 1 }, weapons[1].power)
			assert.are.same({ 2 }, weapons[2].power)
		end)
	end)

	describe("apply pawn cores", function()
		it("skips mech cores when unchanged", function()
			local pawn = makeMockPawn({}, { hpCore = 3, moveCore = 4 })
			local changed = skillCoreSync.applyPawnMechCores("tag", 0, pawn, 3, 4)
			assert.is_false(changed)
			assert.are.equal(3, pawn:GetHpCore())
		end)

		it("skips pilot cores when unchanged", function()
			local pawn = makeMockPawn({}, { pilotPower = { 1, 2 } })
			local changed = skillCoreSync.applyPawnPilotCores("tag", 0, pawn, { 1, 2 })
			assert.is_false(changed)
		end)

		it("applyPawnMechCoresFromSnapshot applies in mission mech and pilot cores", function()
			installGameGetPawn()
			local pawn = makeMockPawn({}, { hpCore = 1, moveCore = 2, pilotPower = { 3 } })
			gameMocks.pawns[1] = pawn
			local snap = {
				[1] = {
					hpCore = 7,
					moveCore = 8,
					pilotPower = { 9 },
				},
			}

			skillCoreSync.applyPawnMechCoresFromSnapshot(1, snap)
			assert.are.equal(7, pawn:GetHpCore())
			assert.are.equal(8, pawn:GetMoveCore())
			assert.are.same({ 9 }, pawn:GetPilot():getPowerList())
		end)
	end)

	describe("addAllWeaponSuffixesInGFromSave", function()
		local prefix = "SkillCoreSyncSaveSuffix"

		before_each(function()
			saveGlobal("SquadData")
			weaponGlobals(prefix)
		end)

		after_each(function()
			clearWeaponGlobals(prefix)
			for _, suffix in ipairs(skillCoreSync.WEAPON_SUFFIX_VARIANTS) do
				_G[prefix .. "_A" .. suffix] = nil
			end
		end)

		it("adds double suffix globals for suffixed weapons in save", function()
			local ptable = makeSavePtable({
				primaryId = prefix .. "_A",
				secondary = false,
			})
			_G.SquadData = {}
			installModApiExt({ byPawnId = { [0] = ptable } })

			skillCoreSync.addAllWeaponSuffixesInGFromSave()

			for _, suffix in ipairs(skillCoreSync.WEAPON_SUFFIX_VARIANTS) do
				assert.is_not_nil(_G[prefix .. "_A" .. suffix], "missing " .. prefix .. "_A" .. suffix)
			end
		end)
	end)
end)