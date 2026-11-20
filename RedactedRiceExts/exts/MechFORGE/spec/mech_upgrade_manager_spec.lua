local helper = require("helpers/forge_helper")
local forge = helper.forge
local manager = forge._subobjects.manager
local utils = forge._subobjects.utils
local V = forge.VANILLA_UPGRADES

describe("MechFORGE upgrade manager", function()
	before_each(function()
		helper.resetState()
	end)

	describe("vanilla bonus compensation", function()
		it("subtracts and restores max health for custom upgrades at full HP", function()
			helper.setUpgradeMenuOpen(true)
			local pawn = helper.createMockPawn({
				maxBaseHealth = 5,
				maxHealth = 5,
				health = 5,
			})
			local config = { label = "Custom HP" }

			manager:_adjustVanillaHealthBonus(pawn, config, false)
			assert.are.equal(3, pawn:GetMaxBaseHealth())
			assert.are.equal(3, pawn:GetMaxHealth())
			assert.are.equal(3, pawn:GetHealth())

			manager:_adjustVanillaHealthBonus(pawn, config, true)
			assert.are.equal(5, pawn:GetMaxBaseHealth())
			assert.are.equal(5, pawn:GetMaxHealth())
			assert.are.equal(5, pawn:GetHealth())
		end)

		it("only adjusts maxBase health outside the upgrade menu", function()
			helper.setUpgradeMenuOpen(false)
			local pawn = helper.createMockPawn({
				maxBaseHealth = 5,
				maxHealth = 5,
				health = 4,
			})
			manager:_adjustVanillaHealthBonus(pawn, { label = "Custom HP" }, false)
			assert.are.equal(3, pawn:GetMaxBaseHealth())
			assert.are.equal(5, pawn:GetMaxHealth())
			assert.are.equal(4, pawn:GetHealth())
		end)

		it("sets mission max and current HP when upgrade menu is open", function()
			helper.setUpgradeMenuOpen(true)
			local config = { label = "Custom HP" }

			local damaged = helper.createMockPawn({
				maxBaseHealth = 5,
				maxHealth = 5,
				health = 2,
			})
			manager:_adjustVanillaHealthBonus(damaged, config, false)
			assert.are.equal(3, damaged:GetMaxHealth())
			assert.are.equal(3, damaged:GetHealth())

			local overMax = helper.createMockPawn({
				maxBaseHealth = 5,
				maxHealth = 5,
				health = 4,
			})
			manager:_adjustVanillaHealthBonus(overMax, config, false)
			assert.are.equal(3, overMax:GetMaxHealth())
			assert.are.equal(3, overMax:GetHealth())
		end)

		it("does not change mission HP when restoring max base health outside the upgrade menu", function()
			helper.setUpgradeMenuOpen(false)
			local pawn = helper.createMockPawn({
				maxBaseHealth = 3,
				maxHealth = 3,
				health = 2,
			})
			manager:_adjustVanillaHealthBonus(pawn, { label = "Custom HP" }, true)
			assert.are.equal(5, pawn:GetMaxBaseHealth())
			assert.are.equal(3, pawn:GetMaxHealth())
			assert.are.equal(2, pawn:GetHealth())
		end)

		it("subtracts and restores raw move speed", function()
			local pawn = helper.createMockPawn({ rawMoveSpeed = 0 })
			local config = { label = "Custom Move" }

			manager:_adjustVanillaMoveBonus(pawn, config, false)
			assert.are.equal(-1, pawn:GetRawMoveSpeed())

			manager:_adjustVanillaMoveBonus(pawn, config, true)
			assert.are.equal(0, pawn:GetRawMoveSpeed())
		end)

		it("runs registered onPowered via event wiring when core hook fires", function()
			local poweredCount = 0
			forge:registerMechUpgrade("MgrMech", V.HEALTH, {
				label = "Reactor",
				onPowered = function()
					poweredCount = poweredCount + 1
				end,
				onUnpowered = function() end,
			})

			local pawn = helper.createMockPawn({
				mechType = "MgrMech",
				maxBaseHealth = 5,
				maxHealth = 5,
				health = 5,
			})

			forge.hooks.fireMechUpgradePoweredHooks(
					V.HEALTH, pawn, 0, "MgrMech", { memhack.CORE_TYPE_NORMAL })

			assert.are.equal(1, poweredCount)
			assert.are.equal(3, pawn:GetMaxBaseHealth())
		end)
	end)

	describe("multi-core layout", function()
		it("does not resize innate lists until size already matches coreSlots", function()
			forge:registerMechUpgrade("MultiMech", V.HEALTH, {
				label = "Heavy Plating",
				coreSlots = 4,
			})
			local pawn = helper.createMockPawn({
				mechType = "MultiMech",
				hpCores = { memhack.CORE_TYPE_NORMAL },
			})

			manager:ensureCoreListSize(pawn, V.HEALTH)

			assert.are.equal(1, utils.getMechUpgradeMemhackCores(pawn, V.HEALTH):getIntSize())
			assert.are.same({ memhack.CORE_TYPE_NORMAL },
					utils.getMechUpgradeMemhackCores(pawn, V.HEALTH):getIntList())
		end)

		it("rewrites the list when size already equals coreSlots", function()
			forge:registerMechUpgrade("SizedMech", V.HEALTH, {
				label = "Heavy Plating",
				coreSlots = 3,
			})
			local pawn = helper.createMockPawn({
				mechType = "SizedMech",
				hpCores = {
					memhack.CORE_TYPE_NORMAL,
					memhack.CORE_TYPE_NONE,
					memhack.CORE_TYPE_SKILL_BONUS,
				},
			})

			manager:ensureCoreListSize(pawn, V.HEALTH)

			assert.are.same({
				memhack.CORE_TYPE_NORMAL,
				memhack.CORE_TYPE_NONE,
				memhack.CORE_TYPE_SKILL_BONUS,
			}, utils.getMechUpgradeMemhackCores(pawn, V.HEALTH):getIntList())
		end)

		it("fills partial multi-core layouts when the reactor pool has cores", function()
			forge:registerMechUpgrade("FillMech", V.HEALTH, {
				label = "Heavy Plating",
				coreSlots = 3,
			})
			local pawn = helper.createMockPawn({
				mechType = "FillMech",
				hpCores = {
					memhack.CORE_TYPE_NORMAL,
					memhack.CORE_TYPE_NONE,
					memhack.CORE_TYPE_NONE,
				},
			})

			manager:_reconcilePartialMultiCoreUpgrade(pawn, V.HEALTH, 3)

			assert.are.same({
				memhack.CORE_TYPE_NORMAL,
				memhack.CORE_TYPE_NORMAL,
				memhack.CORE_TYPE_NORMAL,
			}, utils.getMechUpgradeMemhackCores(pawn, V.HEALTH):getIntList())
		end)

		it("clears powered slots when the pool cannot fill the layout", function()
			forge:registerMechUpgrade("ClearMech", V.HEALTH, {
				label = "Heavy Plating",
				coreSlots = 3,
			})
			local unassigned = {}
			local pawn = helper.createMockPawn({
				mechType = "ClearMech",
				hpCores = {
					memhack.CORE_TYPE_NORMAL,
					memhack.CORE_TYPE_NONE,
					memhack.CORE_TYPE_NONE,
				},
				assignMechReactorCore = function()
					return memhack.CORE_TYPE_NONE
				end,
				unassignMechReactorCore = function(_, coreType)
					table.insert(unassigned, coreType)
					return coreType
				end,
			})

			manager:_reconcilePartialMultiCoreUpgrade(pawn, V.HEALTH, 3)

			assert.are.same({
				memhack.CORE_TYPE_NONE,
				memhack.CORE_TYPE_NONE,
				memhack.CORE_TYPE_NONE,
			}, utils.getMechUpgradeMemhackCores(pawn, V.HEALTH):getIntList())
			assert.are.same({ memhack.CORE_TYPE_NORMAL }, unassigned)
		end)
	end)
end)
