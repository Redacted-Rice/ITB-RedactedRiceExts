local helper = require("helpers/forge_helper")
local forge = helper.forge
local V = forge.VANILLA_UPGRADES

describe("MechFORGE registry", function()
	before_each(function()
		helper.resetState()
	end)

	it("registers a custom upgrade with table config", function()
		local ok = forge:registerMechUpgrade("StarMech", V.HEALTH, {
			label = "Custom Reactor",
			onPowered = function() end,
			onUnpowered = function() end,
		})
		assert.is_true(ok)

		local config = forge:getCustomMechUpgradeConfig("StarMech", V.HEALTH)
		assert.is_not_nil(config)
		assert.are.equal("Custom Reactor", config.label)
	end)

	it("rejects mismatched onPowered/onUnpowered pairs", function()
		local ok = forge:registerMechUpgrade("StarMech", V.MOVE, "Label", function() end, nil)
		assert.is_false(ok)
		assert.is_nil(forge:getCustomMechUpgradeConfig("StarMech", V.MOVE))
	end)

	it("rejects invalid slots and empty mech types", function()
		assert.is_false(forge:registerMechUpgrade("", V.HEALTH, "Label"))
		assert.is_false(forge:registerMechUpgrade("Mech", "bad-slot", "Label"))
	end)

	it("lists mechs with custom upgrades", function()
		forge:registerMechUpgrade("MechA", V.HEALTH, "A")
		forge:registerMechUpgrade("MechB", V.MOVE, "B")

		local mechs = forge:listMechsWithCustomUpgrades()
		table.sort(mechs)
		assert.are.same({ "MechA", "MechB" }, mechs)
	end)

	it("accepts label-only registration and optional tooltip", function()
		assert.is_true(forge:registerMechUpgrade("LabelOnly", V.HEALTH, "Reactor"))
		local config = forge:getCustomMechUpgradeConfig("LabelOnly", V.HEALTH)
		assert.is_nil(config.onPowered)
		assert.is_nil(config.tooltip)

		assert.is_true(forge:registerMechUpgrade("WithTip", V.MOVE, {
			label = "MoveX",
			tooltip = "TipKey",
		}))
		config = forge:getCustomMechUpgradeConfig("WithTip", V.MOVE)
		assert.are.equal("TipKey", config.tooltip)
	end)

	it("rejects empty tooltip strings", function()
		assert.is_false(forge:registerMechUpgrade("BadTip", V.HEALTH, {
			label = "L",
			tooltip = "",
		}))
	end)
end)
