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
			hpCores = { memhack.CORE_TYPE_NORMAL },
			moveCores = { memhack.CORE_TYPE_NONE },
		})
		helper.setupSquadPawns({ [0] = pawn })

		stateTracker:_updateAllStates()

		-- health and move slots both transition from nil on first poll
		assert.are.equal(2, coreChanges)
		assert.are.equal(1, poweredChanges)
		assert.are.same({ memhack.CORE_TYPE_NORMAL }, stateTracker:_getTrackedCores(0, V.HEALTH))
	end)

	it("does not refire hooks when cores are unchanged", function()
		local coreChanges = 0
		forge:addMechUpgradeCoreChangedHook(function()
			coreChanges = coreChanges + 1
		end)

		local pawn = helper.createMockPawn({
			hpCores = { memhack.CORE_TYPE_NORMAL },
			moveCores = { memhack.CORE_TYPE_NONE },
		})
		helper.setupSquadPawns({ [0] = pawn })

		stateTracker:_updateAllStates()
		stateTracker:_updateAllStates()

		assert.are.equal(2, coreChanges)
	end)

	it("does not treat a still-powered core swap as unpowered", function()
		local poweredCount = 0
		local unpoweredCount = 0
		forge:addMechUpgradePoweredHook(function()
			poweredCount = poweredCount + 1
		end)
		forge:addMechUpgradeUnpoweredHook(function()
			unpoweredCount = unpoweredCount + 1
		end)

		local pawn = helper.createMockPawn({
			hpCores = { memhack.CORE_TYPE_NORMAL },
		})
		helper.setupSquadPawns({ [0] = pawn })

		-- Baseline tracked state without counting initial load as a transition.
		stateTracker:_updateAllStates()
		poweredCount = 0
		unpoweredCount = 0

		pawn:SetHpCores({ memhack.CORE_TYPE_SKILL_BONUS })
		stateTracker:_updateAllStates()

		assert.are.equal(0, unpoweredCount)
		assert.are.equal(0, poweredCount)
	end)

	it("fires core changed when slot count grows", function()
		local coreChanges = 0
		forge:addMechUpgradeCoreChangedHook(function()
			coreChanges = coreChanges + 1
		end)

		local pawn = helper.createMockPawn({
			hpCores = { memhack.CORE_TYPE_NORMAL },
			moveCores = { memhack.CORE_TYPE_NONE },
		})
		helper.setupSquadPawns({ [0] = pawn })

		stateTracker:_updateAllStates()
		coreChanges = 0
		pawn:SetHpCores({
			memhack.CORE_TYPE_NORMAL,
			memhack.CORE_TYPE_NONE,
		})
		stateTracker:_updateAllStates()

		assert.are.equal(1, coreChanges)
		assert.are.same({
			memhack.CORE_TYPE_NORMAL,
			memhack.CORE_TYPE_NONE,
		}, stateTracker:_getTrackedCores(0, V.HEALTH))
	end)

	it("fires powered when all slots in a multi-core list become powered", function()
		local poweredCount = 0
		forge:addMechUpgradePoweredHook(function(slot, _, _, _, newList)
			if slot == V.HEALTH then
				poweredCount = poweredCount + 1
				assert.are.same({
					memhack.CORE_TYPE_NORMAL,
					memhack.CORE_TYPE_NORMAL,
				}, newList)
			end
		end)

		local pawn = helper.createMockPawn({
			hpCores = { memhack.CORE_TYPE_NORMAL, memhack.CORE_TYPE_NONE },
		})
		helper.setupSquadPawns({ [0] = pawn })

		stateTracker:_updateAllStates()
		poweredCount = 0

		pawn:SetHpCores({
			memhack.CORE_TYPE_NORMAL,
			memhack.CORE_TYPE_NORMAL,
		})
		stateTracker:_updateAllStates()

		assert.are.equal(1, poweredCount)
	end)

	it("fires unpowered when a multi-core list loses a powered slot", function()
		local unpoweredCount = 0
		forge:addMechUpgradeUnpoweredHook(function(slot, _, _, _, oldList)
			if slot == V.HEALTH then
				unpoweredCount = unpoweredCount + 1
				assert.are.same({
					memhack.CORE_TYPE_NORMAL,
					memhack.CORE_TYPE_NORMAL,
				}, oldList)
			end
		end)

		local pawn = helper.createMockPawn({
			hpCores = {
				memhack.CORE_TYPE_NORMAL,
				memhack.CORE_TYPE_NORMAL,
			},
		})
		helper.setupSquadPawns({ [0] = pawn })

		stateTracker:_updateAllStates()
		unpoweredCount = 0

		pawn:SetHpCores({
			memhack.CORE_TYPE_NORMAL,
			memhack.CORE_TYPE_NONE,
		})
		stateTracker:_updateAllStates()

		assert.are.equal(1, unpoweredCount)
	end)

	it("detects powered to unpowered transitions", function()
		local unpoweredCount = 0
		forge:addMechUpgradeUnpoweredHook(function()
			unpoweredCount = unpoweredCount + 1
		end)

		local pawn = helper.createMockPawn({
			hpCores = { memhack.CORE_TYPE_NORMAL },
		})
		helper.setupSquadPawns({ [0] = pawn })

		stateTracker:_updateAllStates()
		pawn:SetHpCores({ memhack.CORE_TYPE_NONE })
		stateTracker:_updateAllStates()

		assert.are.equal(1, unpoweredCount)
	end)

	-- documents current behavior: reset clears history so the next poll looks like a fresh load
	it("runs reconcile before hooks when a registered multi-core layout is partial", function()
		forge:registerMechUpgrade("TrackMulti", V.HEALTH, {
			label = "Heavy Plating",
			coreSlots = 2,
		})
		local pawn = helper.createMockPawn({
			mechType = "TrackMulti",
			hpCores = {
				memhack.CORE_TYPE_NORMAL,
				memhack.CORE_TYPE_NONE,
			},
			moveCores = { memhack.CORE_TYPE_NONE },
		})
		helper.setupSquadPawns({ [0] = pawn })

		stateTracker:_updateAllStates()

		assert.are.same({
			memhack.CORE_TYPE_NORMAL,
			memhack.CORE_TYPE_NORMAL,
		}, stateTracker:_getTrackedCores(0, V.HEALTH))
	end)

	it("refires powered hooks after tracker reset while cores stay powered", function()
		local poweredCount = 0
		forge:addMechUpgradePoweredHook(function()
			poweredCount = poweredCount + 1
		end)

		local pawn = helper.createMockPawn({
			hpCores = { memhack.CORE_TYPE_NORMAL },
			moveCores = { memhack.CORE_TYPE_NONE },
		})
		helper.setupSquadPawns({ [0] = pawn })

		stateTracker:_updateAllStates()
		stateTracker:_resetAllTrackers()
		stateTracker:_updateAllStates()

		assert.are.equal(2, poweredCount)
	end)
end)