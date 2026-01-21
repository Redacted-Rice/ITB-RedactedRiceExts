local function onGameClassInitialized(GameClass, game)
	-- persistent pointer. This won't change and stays even between runs
	-- and going to the main menu
	
	GameClass.GetMemhackObj = function(self)
		if not self.memhackObj or memhack.dll.memory.getUserdataAddr(self) ~= self.memhackObj._address then
			self.memhackObj = memhack.structs.GameMap.new(memhack.dll.memory.getUserdataAddr(game))
		end
		return self.memhackObj
	end
	
	-- Upper case to align with BoardPawn conventions
	GameClass.GetReputation = function(self)
		return self:GetMemhackObj():getReputation()
	end

	GameClass.SetReputation = function(self, reputation)
		if type(reputation) ~= "number" then
			error(string.format("Reputation must be a number, got %s", type(reputation)))
		end
		 self:GetMemhackObj():setReputation(reputation)
	end

	-- Convenience function to add/subtract reputation
	GameClass.AddReputation = function(self, amount)
		if type(amount) ~= "number" then
			error(string.format("Amount must be a number, got %s", type(amount)))
		end
		local obj = self:GetMemhackObj()
		obj:SetReputation(obj:getReputation() + amount)
	end
	
	-- This was found by identifying the memory using cheat engine then searching
	-- (via pointer scan for this address) for stable references in Breach.exe and repeating
	-- until I found the chain that doesn't change
	-- There may be some other interesting pointers or values stored here as well
	-- but this doesn't seem to be part of GameMap interestingly and is static - 
	-- it doesn't change address per run (but obviously is cleared/reset on load/new game)
	local function getScoreAddr()
		local exeBase = memhack.dll.process.getExeBase()
		local intermediateAddr = memhack.dll.memory.readPointer(exeBase + 0x4D19E0)
		local gameStateStructAddr = memhack.dll.memory.readPointer(intermediateAddr + 0x20)
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
	
	GameClass.GetStorage = function(self)
		return self:GetMemhackObj():getResearchControl():getStorage()
	end
end

modApi.events.onGameClassInitialized:subscribe(onGameClassInitialized)