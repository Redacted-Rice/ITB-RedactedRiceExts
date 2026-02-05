local function onGameClassInitialized(GameClass)
	-- persistent pointer. This won't change and stays even between runs
	-- and going to the main menu

	GameClass.GetMemhackObj = function(self)
		if not self.memhackObj or memhack.dll.memory.getUserdataAddr(self) ~= self.memhackObj._address then
			self.memhackObj = memhack.structs.GameMap.new(memhack.dll.memory.getUserdataAddr(self), true)
		end
		return self.memhackObj
	end

	-- Upper case to align with BoardPawn conventions
	GameClass.GetReputation = function(self)
		local reputation = self:GetMemhackObj():getReputation()
		return reputation
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
		local score = memhack.dll.memory.readInt(getScoreAddr())
		return score
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

	-- Gets the memhack storage struct which can be used to read the
	-- current pilots and weapons in storage. Write is not currently
	-- supported due to complexity required and lack of need for it
	GameClass.GetStorage = function(self)
		local storage = self:GetMemhackObj():getResearchControl():getStorage()
		return storage
	end

	-- Get all memhack pilot structs for pilots currently in the squad
	-- Returns array of Pilot structs (up to 3, some mechs may not have pilots)
	-- Order/alignment to pawnId is not guaranteed
	-- All returned pilots will be non-nil
	GameClass.GetSquadPilots = function(self)
		local pilots = {}
		for i = 0, 2 do
			local pawn = self:GetPawn(i)
			if pawn then
				local pilot = pawn:GetPilot()
				if pilot then
					table.insert(pilots, pilot)
				end
			end
		end
		return pilots
	end

	-- Gets all memhack pilot structs for pilots currently in storage
	-- All returned pilots will be non-nil
	GameClass.GetStoragePilots = function(self)
		local allPilots = self:GetStorage():getAllOfType(memhack.structs.StorageObject.TYPE_PILOT)
		-- Filter out any nil pilots. I don't think this should happen but just in case
		local pilots = {}
		for _, pilot in ipairs(allPilots) do
			if pilot then
				table.insert(pilots, pilot)
			end
		end
		return pilots
	end

	-- Gets all memhack pilot structs for pilots that are available currently
	-- This is the squad pilots and storage pilots. This does not include pod
	-- rewards or perfect island rewards that are displayed and have not been
	-- claimed yet
	-- All returned pilots will be non-nil
	GameClass.GetAvailablePilots = function(self)
		-- Both of this already handle/remove nil pilots so we don't need to do that here
		local pilots = self:GetSquadPilots()
		for _, pilot in ipairs(self:GetStoragePilots()) do
			table.insert(pilots, pilot)
		end
		return pilots
	end

	-- Returns the pilot for time pod rewards before they are claimed to
	-- your storage. If there is no pilot or the pod UI is not open, will
	-- return nil
	GameClass.GetPodRewardPilot = function(self)
		local pilot = self:GetMemhackObj():getVictoryScreen():getPodRewardPilot()
		return pilot
	end

	-- Returns the pilot for perfect island rewards before they are claimed to
	-- your storage. If there is no pilot or the perfect reward UI is not open, will
	-- return nil
	-- Actually not sure if this will still work if the reward UI is "minimized" or not
	GameClass.GetPerfectIslandRewardPilot = function(self)
		local pilot = self:GetMemhackObj():getUnknownObj1():getPerfectIslandRewardPilot()
		return pilot
	end
end

modApi.events.onGameClassInitialized:subscribe(onGameClassInitialized)