local helper = require("helpers/forge_helper")
local utils = helper.forge._subobjects.utils
local V = helper.forge.VANILLA_UPGRADES

describe("MechFORGE utils", function()
	before_each(function()
		helper.resetState()
	end)

	describe("isValidUpgradeSlot", function()
		it("accepts health and move slots", function()
			assert.is_true(utils.isValidUpgradeSlot(V.HEALTH))
			assert.is_true(utils.isValidUpgradeSlot(V.MOVE))
		end)

		it("rejects unknown slots", function()
			assert.is_false(utils.isValidUpgradeSlot("weapon"))
			assert.is_false(utils.isValidUpgradeSlot(nil))
		end)
	end)

	describe("isCorePowered", function()
		it("treats CORE_TYPE_NONE and nil as unpowered", function()
			assert.is_false(utils.isCorePowered(nil))
			assert.is_false(utils.isCorePowered(memhack.CORE_TYPE_NONE))
		end)

		it("treats other core values as powered", function()
			assert.is_true(utils.isCorePowered(memhack.CORE_TYPE_NORMAL))
			assert.is_true(utils.isCorePowered(memhack.CORE_TYPE_SKILL_BONUS))
		end)
	end)

	describe("getMechUpgradeCore", function()
		it("reads hp and move cores from pawn", function()
			local pawn = helper.createMockPawn({
				hpCore = memhack.CORE_TYPE_NORMAL,
				moveCore = memhack.CORE_TYPE_NONE,
			})

			assert.are.equal(memhack.CORE_TYPE_NORMAL, utils.getMechUpgradeCore(pawn, V.HEALTH))
			assert.are.equal(memhack.CORE_TYPE_NONE, utils.getMechUpgradeCore(pawn, V.MOVE))
		end)

		it("returns nil for missing pawn or unsupported slot", function()
			assert.is_nil(utils.getMechUpgradeCore(nil, V.HEALTH))
			assert.is_nil(utils.getMechUpgradeCore(helper.createMockPawn(), "bad"))
		end)
	end)

	describe("getMechType", function()
		it("returns non-empty pawn type strings", function()
			local pawn = helper.createMockPawn({ mechType = "PrimeMech" })
			assert.are.equal("PrimeMech", utils.getMechType(pawn))
		end)

		it("returns nil for empty type", function()
			local pawn = helper.createMockPawn({ mechType = "" })
			assert.is_nil(utils.getMechType(pawn))
		end)
	end)

	describe("isMechUpgradePowered", function()
		it("reflects live core values on the pawn", function()
			local pawn = helper.createMockPawn({
				hpCore = memhack.CORE_TYPE_NORMAL,
				moveCore = memhack.CORE_TYPE_NONE,
			})
			assert.is_true(utils.isMechUpgradePowered(pawn, V.HEALTH))
			assert.is_false(utils.isMechUpgradePowered(pawn, V.MOVE))
		end)
	end)

	describe("resolveText", function()
		before_each(function()
			_G.GetText = function(id)
				return id
			end
		end)

		it("resolves function labels with the pawn before lookup", function()
			local pawn = helper.createMockPawn({ mechType = "FnMech" })
			local label = utils.resolveText(function(p)
				return p:GetType() .. "_Label"
			end, pawn)
			assert.are.equal("FnMech_Label", label)
		end)

		it("returns nil for nil label", function()
			assert.is_nil(utils.resolveText(nil, helper.createMockPawn()))
		end)
	end)
end)
