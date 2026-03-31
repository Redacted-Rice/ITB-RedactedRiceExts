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
		if type(point) ~= "userdata"  and getmetatable(v) == Point then
			logger.logError(SUBMODULE, string.format("Point must be... a point. Got type %s", type(point)))
			return
		end
		 self:GetMemhackObj():setPodLandingLoc(point)
	end
end

modApi.events.onBoardClassInitialized:subscribe(onBoardClassInitialized)