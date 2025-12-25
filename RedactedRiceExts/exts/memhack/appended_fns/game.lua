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
	
	-- This was found by identifying the memory using cheat engine the searching
	-- backwards a couple jumps until I found a stable exe offset & chain
	-- There may be some other interesting pointers or values stored here as well
	local function getScoreAddr()
		local exeBase = memhack.dll.process.getExeBase()
		local intermediateAddr = memhack.dll.memory.readPointer(exeBase + 0x4D19E0)
		local gameStateStructAddr = memhack.dll.memory.readPointer(intermediateAddr + 0x10)
		return gameStateStructAddr + 0x148
	end
	
	-- Doesn't need to be a part of game but it fits logically there
	GameClass.GetScore = function(self)
		return memhack.dll.memory.readInt(getScoreAddr())
	end

	GameClass.SetScore = function(self, score)
		if type(score) ~= "number" then
			error(string.format("score must be a number, got %s", type(score)))
		end
		memhack.dll.memory.writeInt(getScoreAddr(), score)
	end

	-- Convenience function to add/subtract score
	GameClass.AddScore = function(self, amount)
		if type(amount) ~= "number" then
			error(string.format("Amount must be a number, got %s", type(amount)))
		end
		local current = self:GetScore()
		self:SetScore(current + amount)
	end
end

modApi.events.onGameClassInitialized:subscribe(onGameClassInitialized)