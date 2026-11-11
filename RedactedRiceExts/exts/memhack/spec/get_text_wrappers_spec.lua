describe("memhack getTextWrappers", function()
	local wrappers = require("../utils/get_text_wrappers")

	before_each(function()
		_G.Game = nil
	end)

	it("basedOnSelectedPawn passes text id through to GetText", function()
		local upgradePawn = { id = "upgrade" }

		_G.Game = {
			GetUpgradeSelectedPawn = function()
				return upgradePawn
			end,
			GetSelectedPawn = function()
				return nil
			end,
		}

		local seenPawn
		local textFn = wrappers.basedOnSelectedPawn(function(pawn)
			seenPawn = pawn
			return "ok"
		end)
		local result = textFn("MyTextId", "a", "b", "c")
		assert.are.equal("ok", result)
		assert.are.equal(upgradePawn, seenPawn)
	end)

	it("basedOnSelectedPawn prefers upgrade menu pawn", function()
		local upgradePawn = { id = "upgrade" }
		local missionPawn = { id = "mission" }

		_G.Game = {
			GetUpgradeSelectedPawn = function()
				return upgradePawn
			end,
			GetSelectedPawn = function()
				return missionPawn
			end,
		}

		local seen
		wrappers.basedOnSelectedPawn(function(pawn)
			seen = pawn
		end)("TextId")
		assert.are.equal(upgradePawn, seen)
	end)

	it("basedOnSelectedPawn falls back to mission selected pawn", function()
		local missionPawn = { id = "mission" }

		_G.Game = {
			GetUpgradeSelectedPawn = function()
				return nil
			end,
			GetSelectedPawn = function()
				return missionPawn
			end,
		}

		local seen
		wrappers.basedOnSelectedPawn(function(pawn)
			seen = pawn
		end)("TextId")
		assert.are.equal(missionPawn, seen)
	end)

	it("basedOnSelectedPawn passes nil pawn when none selected", function()
		_G.Game = {
			GetUpgradeSelectedPawn = function()
				return nil
			end,
			GetSelectedPawn = function()
				return nil
			end,
		}

		local seen = "unset"
		wrappers.basedOnSelectedPawn(function(pawn)
			seen = pawn
		end)("TextId")
		assert.is_nil(seen)
	end)
end)
