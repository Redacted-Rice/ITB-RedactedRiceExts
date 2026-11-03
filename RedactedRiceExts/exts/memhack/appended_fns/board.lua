local logger = memhack.logger
local SUBMODULE = logger.register("Memhack", "Board", memhack.DEBUG.ENABLED)

local function onBoardClassInitialized(BoardClass)
	BoardClass.GetMemhackObj = function(self)
		if not self.memhackObj or memhack.dll.memory.getUserdataAddr(self) ~= self.memhackObj._address then
			self.memhackObj = memhack.structs.Board.new(memhack.dll.memory.getUserdataAddr(self), true)
		end
		return self.memhackObj
	end

	-- Upper case to align with BoardPawn conventions
	BoardClass.GetPodLandingPoint = function(self)
		local point = self:GetMemhackObj():getPodLandingAsPoint()
		return point
	end

	BoardClass.SetPodLandingPoint = function(self, point)
		if type(point) ~= "userdata" and getmetatable(point) ~= Point then
			logger.logError(SUBMODULE, "Point must be... a point. Got type %s", type(point))
			return
		end
		 self:GetMemhackObj():setPodLandingLoc(point)
	end

	-- Override the modloader version with this which will be more accurate
	-- Keep the original on BoardClass so Game:GetSelectedPawn can fall back to it
	BoardClass._origGetSelectedPawn = BoardClass.GetSelectedPawn
	BoardClass.GetSelectedPawn = function(self)
		if Game then
			return Game:GetSelectedPawn()
		end
		return BoardClass._origGetSelectedPawn(self)
	end

	-- Also add an alias in Board class for api symmetry
	BoardClass.SetSelectedPawn = function(self, pawn)
		if Game then
			Game:SetSelectedPawn(pawn)
			return
		end
		logger.logError(SUBMODULE, "SetSelectedPawn: Game is not available")
	end
end

modApi.events.onBoardClassInitialized:subscribe(onBoardClassInitialized)