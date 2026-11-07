-- Logging utility for Extensions
-- Shared by both CPLUS+ and Memhack extensions

local get_text = {}

function get_text.basedOnSelectedPawn(fn)
	assert(type(fn) == "function", "fn must be... a function")
	return function(r1, r2, r3)
		local pawn
		if Game then
			pawn = Game:GetUpgradeSelectedPawn()
			if not pawn then
				pawn = Game:GetSelectedPawn()
			end
		end
		return fn(pawn, r1, r2, r3)
	end
end

return get_text
