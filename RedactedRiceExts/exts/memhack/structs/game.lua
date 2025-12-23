local REPUTATION_OFFSET = 0x848C

local function onGameClassInitialized(GameClass, game)
	-- Upper case to align with BoardPawn conventions
	GameClass.GetReputation = function(self)
		local gamePtr = memhack.dll.memory.getUserdataAddr(self)
		return memhack.dll.memory.readInt(gamePtr + REPUTATION_OFFSET)
	end

	GameClass.SetReputation = function(self, reputation)
		if type(reputation) ~= "number" then
			error(string.format("Reputation must be a number, got %s", type(reputation)))
		end
		local gamePtr = memhack.dll.memory.getUserdataAddr(self)
		memhack.dll.memory.writeInt(gamePtr + REPUTATION_OFFSET, reputation)
	end

	-- Convenience function to add/subtract reputation
	GameClass.AddReputation = function(self, amount)
		if type(amount) ~= "number" then
			error(string.format("Amount must be a number, got %s", type(amount)))
		end
		local current = self:GetReputation()
		self:SetReputation(current + amount)
	end
end

modApi.events.onGameClassInitialized:subscribe(onGameClassInitialized)