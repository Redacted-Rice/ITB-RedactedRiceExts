-- Tests for upgrade_menu_tracker.lua

local specHelper = require("helpers/spec_helper")

local memhack = specHelper.initMemhack()
local tracker = memhack._subobjects.upgradeMenuTracker

describe("UpgradeMenuTracker", function()
	local pawnCalls
	local pilotCalls
	local missionActive

	local function makePawn(pilot)
		return {
			GetPilot = function()
				return pilot
			end,
		}
	end

	before_each(function()
		tracker._lastPawnId = nil
		tracker._lastPawn = nil
		tracker._lastPilot = nil

		pawnCalls = {}
		pilotCalls = {}
		missionActive = false

		_G.GetCurrentMission = function()
			if missionActive then
				return {}
			end
			return nil
		end

		memhack.hooks.fireUpgradeSelectedPawnChangedHooks = function(pawn, oldPawn)
			table.insert(pawnCalls, { pawn = pawn, oldPawn = oldPawn })
		end
		memhack.hooks.fireUpgradeSelectedPilotChangedHooks = function(pawn, pilot, oldPilot)
			table.insert(pilotCalls, { pawn = pawn, pilot = pilot, oldPilot = oldPilot })
		end
	end)

	it("fires both hooks on first selection with nil old values", function()
		local pilot = { id = "PilotA" }
		local pawn = makePawn(pilot)

		_G.Game = {
			GetUpgradeSelectedPawnId = function()
				return 0
			end,
			GetUpgradeSelectedPawn = function()
				return pawn
			end,
		}

		tracker:_checkForChanges()

		assert.are.equal(1, #pawnCalls)
		assert.are.same(pawn, pawnCalls[1].pawn)
		assert.is_nil(pawnCalls[1].oldPawn)

		assert.are.equal(1, #pilotCalls)
		assert.are.same(pawn, pilotCalls[1].pawn)
		assert.are.same(pilot, pilotCalls[1].pilot)
		assert.is_nil(pilotCalls[1].oldPilot)
	end)

	it("fires pawn and pilot hooks when pawn id changes", function()
		local pilot0 = { id = "P0" }
		local pilot1 = { id = "P1" }
		local pawn0 = makePawn(pilot0)
		local pawn1 = makePawn(pilot1)
		local selectedId = 0

		_G.Game = {
			GetUpgradeSelectedPawnId = function()
				return selectedId
			end,
			GetUpgradeSelectedPawn = function()
				return selectedId == 0 and pawn0 or pawn1
			end,
		}

		tracker:_checkForChanges()
		selectedId = 1
		tracker:_checkForChanges()

		assert.are.equal(2, #pawnCalls)
		assert.are.same(pawn1, pawnCalls[2].pawn)
		assert.are.same(pawn0, pawnCalls[2].oldPawn)

		assert.are.equal(2, #pilotCalls)
		assert.are.same(pilot1, pilotCalls[2].pilot)
		assert.are.same(pilot0, pilotCalls[2].oldPilot)
	end)

	it("fires only pilot hook when pilot changes on the same pawn id", function()
		local pilotA = { id = "A" }
		local pilotB = { id = "B" }
		local currentPilot = pilotA
		local pawn = {
			GetPilot = function()
				return currentPilot
			end,
		}

		_G.Game = {
			GetUpgradeSelectedPawnId = function()
				return 1
			end,
			GetUpgradeSelectedPawn = function()
				return pawn
			end,
		}

		tracker:_checkForChanges()
		currentPilot = pilotB
		tracker:_checkForChanges()

		assert.are.equal(1, #pawnCalls)
		assert.are.equal(2, #pilotCalls)
		assert.are.same(pilotB, pilotCalls[2].pilot)
		assert.are.same(pilotA, pilotCalls[2].oldPilot)
	end)

	it("resets and clears selection when entering a mission", function()
		local pilot = { id = "PilotA" }
		local pawn = makePawn(pilot)

		_G.Game = {
			GetUpgradeSelectedPawnId = function()
				return 0
			end,
			GetUpgradeSelectedPawn = function()
				return pawn
			end,
		}

		tracker:_checkForChanges()
		pawnCalls = {}
		pilotCalls = {}
		missionActive = true

		tracker:_checkForChanges()

		assert.are.equal(1, #pawnCalls)
		assert.is_nil(pawnCalls[1].pawn)
		assert.are.same(pawn, pawnCalls[1].oldPawn)

		assert.are.equal(1, #pilotCalls)
		assert.is_nil(pilotCalls[1].pawn)
		assert.is_nil(pilotCalls[1].pilot)
		assert.are.same(pilot, pilotCalls[1].oldPilot)
	end)

	it("resets when upgrade selection is cleared", function()
		local pilot = { id = "PilotA" }
		local pawn = makePawn(pilot)
		local selectedId = 0

		_G.Game = {
			GetUpgradeSelectedPawnId = function()
				return selectedId
			end,
			GetUpgradeSelectedPawn = function()
				return selectedId ~= nil and pawn or nil
			end,
		}

		tracker:_checkForChanges()
		selectedId = nil
		pawnCalls = {}
		pilotCalls = {}

		tracker:_checkForChanges()

		assert.are.equal(1, #pawnCalls)
		assert.is_nil(pawnCalls[1].pawn)
		assert.are.same(pawn, pawnCalls[1].oldPawn)
	end)
end)
