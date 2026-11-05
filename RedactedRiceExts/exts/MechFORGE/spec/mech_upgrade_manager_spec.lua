local helper = require("helpers/forge_helper")
local forge = helper.forge
local manager = forge._subobjects.manager
local V = forge.VANILLA_UPGRADES

describe("MechFORGE upgrade manager", function()
	before_each(function()
		helper.resetState()
	end)

	describe("vanilla bonus compensation", function()
		it("subtracts and restores max health for custom upgrades at full HP", function()
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
			assert.are.equal(3, pawn:GetHealth())
		end)

		it("only clamps current HP when it exceeds the new max", function()
			local config = { label = "Custom HP" }

			local damaged = helper.createMockPawn({
				maxBaseHealth = 5,
				maxHealth = 5,
				health = 2,
			})
			manager:_adjustVanillaHealthBonus(damaged, config, false)
			assert.are.equal(3, damaged:GetMaxHealth())
			assert.are.equal(2, damaged:GetHealth())

			local overMax = helper.createMockPawn({
				maxBaseHealth = 5,
				maxHealth = 5,
				health = 4,
			})
			manager:_adjustVanillaHealthBonus(overMax, config, false)
			assert.are.equal(3, overMax:GetMaxHealth())
			assert.are.equal(3, overMax:GetHealth())
		end)

		it("does not heal current HP when restoring max health", function()
			local pawn = helper.createMockPawn({
				maxBaseHealth = 3,
				maxHealth = 3,
				health = 2,
			})
			manager:_adjustVanillaHealthBonus(pawn, { label = "Custom HP" }, true)
			assert.are.equal(5, pawn:GetMaxHealth())
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

			forge.hooks.fireMechUpgradePoweredHooks(V.HEALTH, pawn, 0, "MgrMech", memhack.CORE_TYPE_NORMAL)

			assert.are.equal(1, poweredCount)
			assert.are.equal(3, pawn:GetMaxBaseHealth())
		end)
	end)

	describe("GetText label override", function()
		before_each(function()
			helper.initTexts()
		end)

		it("returns custom label for strategy-selected mech", function()
			local pawn = helper.createMockPawn({ mechType = "LabelMech" })
			helper.setupSquadPawns({ [0] = pawn })
			_G.Game.GetStrategySelectedPawn = function(self)
				return 0
			end

			forge:registerMechUpgrade("LabelMech", V.HEALTH, "MyLabelKey")

			-- label strings go through GetText once more (text id or passthrough)
			assert.are.equal("TEXT:MyLabelKey", GetText("Upgrade_HealthLabel"))
		end)

		it("falls through to original GetText for unrelated ids", function()
			assert.are.equal("TEXT:SomeOtherKey", GetText("SomeOtherKey"))
		end)
	end)
end)
