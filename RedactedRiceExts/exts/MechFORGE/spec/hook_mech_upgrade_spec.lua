local helper = require("helpers/forge_helper")
local forge = helper.forge
local hooks = forge.hooks

describe("MechFORGE upgrade hooks", function()
	local originalCoreHooks
	local originalPoweredHooks

	before_each(function()
		helper.resetState()
		originalCoreHooks = hooks.mechUpgradeCoreChangedHooks
		originalPoweredHooks = hooks.mechUpgradePoweredHooks
		hooks.mechUpgradeCoreChangedHooks = {}
		hooks.mechUpgradePoweredHooks = {}
		hooks:initBroadcastHooks()
	end)

	after_each(function()
		hooks.mechUpgradeCoreChangedHooks = originalCoreHooks
		hooks.mechUpgradePoweredHooks = originalPoweredHooks
		hooks:initBroadcastHooks()
	end)

	it("fires registered mechUpgradeCoreChanged hooks", function()
		local seen = {}

		forge:addMechUpgradeCoreChangedHook(function(slot, pawn, pawnId, mechType, oldCore, newCore)
			table.insert(seen, { slot, pawnId, mechType, oldCore, newCore })
		end)

		local pawn = helper.createMockPawn({ mechType = "HookMech" })
		hooks.fireMechUpgradeCoreChangedHooks(
			forge.VANILLA_UPGRADES.HEALTH, pawn, 1, "HookMech", nil, memhack.CORE_TYPE_NORMAL)

		assert.are.equal(1, #seen)
		assert.are.equal(forge.VANILLA_UPGRADES.HEALTH, seen[1][1])
		assert.are.equal(1, seen[1][2])
		assert.are.equal("HookMech", seen[1][3])
		assert.is_nil(seen[1][4])
		assert.are.equal(memhack.CORE_TYPE_NORMAL, seen[1][5])
	end)

	it("fires mechUpgradePowered hooks with arguments", function()
		local slotSeen
		local coreSeen

		forge:addMechUpgradePoweredHook(function(slot, pawn, pawnId, mechType, newCore)
			slotSeen = slot
			coreSeen = newCore
		end)

		hooks.fireMechUpgradePoweredHooks(
			forge.VANILLA_UPGRADES.MOVE, {}, 2, "HookMech", memhack.CORE_TYPE_SKILL_BONUS)

		assert.are.equal(forge.VANILLA_UPGRADES.MOVE, slotSeen)
		assert.are.equal(memhack.CORE_TYPE_SKILL_BONUS, coreSeen)
	end)
end)
