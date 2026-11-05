local helper = require("helpers/forge_helper")
local forge = helper.forge
local stateTracker = forge._subobjects.state_tracker
local V = forge.VANILLA_UPGRADES

describe("MechFORGE state tracker", function()
	before_each(function()
		helper.resetState()
	end)

	it("initializes tracked squad slots at module load", function()
		assert.is_not_nil(stateTracker._tracked)
		assert.is_not_nil(stateTracker._tracked[0])
		assert.is_not_nil(stateTracker._tracked[1])
		assert.is_not_nil(stateTracker._tracked[2])
	end)

	it("fires core and powered hooks on first observed core value", function()
		local coreChanges = 0
		local poweredChanges = 0

		forge:addMechUpgradeCoreChangedHook(function()
			coreChanges = coreChanges + 1
		end)
		forge:addMechUpgradePoweredHook(function()
			poweredChanges = poweredChanges + 1
		end)

		local pawn = helper.createMockPawn({
			mechType = "TrackMech",
			hpCore = memhack.CORE_TYPE_NORMAL,
			moveCore = memhack.CORE_TYPE_NONE,
		})
		helper.setupSquadPawns({ [0] = pawn })

		stateTracker:_updateAllStates()

		-- health and move slots both transition from nil on first poll
		assert.are.equal(2, coreChanges)
		assert.are.equal(1, poweredChanges)
		assert.are.equal(memhack.CORE_TYPE_NORMAL, stateTracker:_getTrackedCore(0, V.HEALTH))
	end)

	it("does not refire hooks when cores are unchanged", function()
		local coreChanges = 0
		forge:addMechUpgradeCoreChangedHook(function()
			coreChanges = coreChanges + 1
		end)

		local pawn = helper.createMockPawn({
			hpCore = memhack.CORE_TYPE_NORMAL,
			moveCore = memhack.CORE_TYPE_NONE,
		})
		helper.setupSquadPawns({ [0] = pawn })

		stateTracker:_updateAllStates()
		stateTracker:_updateAllStates()

		assert.are.equal(2, coreChanges)
	end)

	it("detects powered to unpowered transitions", function()
		local unpoweredCount = 0
		forge:addMechUpgradeUnpoweredHook(function()
			unpoweredCount = unpoweredCount + 1
		end)

		local pawn = helper.createMockPawn({
			hpCore = memhack.CORE_TYPE_NORMAL,
		})
		helper.setupSquadPawns({ [0] = pawn })

		stateTracker:_updateAllStates()
		pawn:SetHpCore(memhack.CORE_TYPE_NONE)
		stateTracker:_updateAllStates()

		assert.are.equal(1, unpoweredCount)
	end)

	-- documents current behavior: reset clears history so the next poll looks like a fresh load
	it("refires powered hooks after tracker reset while cores stay powered", function()
		local poweredCount = 0
		forge:addMechUpgradePoweredHook(function()
			poweredCount = poweredCount + 1
		end)

		local pawn = helper.createMockPawn({
			hpCore = memhack.CORE_TYPE_NORMAL,
			moveCore = memhack.CORE_TYPE_NONE,
		})
		helper.setupSquadPawns({ [0] = pawn })

		stateTracker:_updateAllStates()
		stateTracker:_resetAllTrackers()
		stateTracker:_updateAllStates()

		assert.are.equal(2, poweredCount)
	end)
end)
