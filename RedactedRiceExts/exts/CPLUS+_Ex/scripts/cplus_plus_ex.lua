cplus_plus_ex = {
	PLUS_DEBUG = true, -- eventually default to false
	PLUS_EXTRA_DEBUG = false,
	_pilotStructs = nil,
	
	_lastSavedPersistentData = nil,
	plus_manager = nil,
	timeTraveler = nil,
}

function cplus_plus_ex:refreshGameData()
	if Game then
		self._pilotStructs = self:getAllPilots()
		if self.PLUS_DEBUG then LOG("refreshGameData") end
	end
end

function cplus_plus_ex:clearGameData()
	self._pilotStructs = nil
	if self.PLUS_DEBUG then LOG("clearGameData") end
end

function cplus_plus_ex:loadPersistentDataIfNeeded()
	if not self._lastSavedPersistentData then
		if not modApi:isProfilePath() then return end
		if self.PLUS_DEBUG then LOG("Loading persistent data!") end
		self._lastSavedPersistentData = {}

		sdlext.config(
			modApi:getCurrentProfilePath().."modcontent.lua",
			function(obj)
				if obj.cplus_plus_ex then
					for id, data in pairs(obj.cplus_plus_ex) do
						self._lastSavedPersistentData[id] = data
					end
				end
			end
		)
	end
end

function cplus_plus_ex:refreshLastSavedPersistentData()
	local pilots = self:getAllPilots()
	-- TODO what to do here
	if not pilots then
		return false
	end
	
	local changed = false
	self._lastSavedPersistentData = self._lastSavedPersistentData or {}
	for _, pilot in pairs(pilots) do
		local id = pilot:getIdStr()
		self._lastSavedPersistentData[id] = self._lastSavedPersistentData[id] or {}
		if self._lastSavedPersistentData[id].name ~= pilot:getNameStr() then 
			self._lastSavedPersistentData[id].name = pilot:getNameStr()
			changed = true
		end
		if self._lastSavedPersistentData[id].xp ~= pilot:getXp() then 
			self._lastSavedPersistentData[id].xp = pilot:getXp()
			changed = true
		end
		if self._lastSavedPersistentData[id].level ~= pilot:getLevel() then 
			self._lastSavedPersistentData[id].level = pilot:getLevel()
			changed = true
		end
		if self._lastSavedPersistentData[id].skill1 ~= pilot:getLvlUpSkills():getSkill1():getIdStr() then 
			self._lastSavedPersistentData[id].skill1 = pilot:getLvlUpSkills():getSkill1():getIdStr()
			changed = true
		end
		if self._lastSavedPersistentData[id].skill2 ~= pilot:getLvlUpSkills():getSkill2():getIdStr() then 
			self._lastSavedPersistentData[id].skill2 = pilot:getLvlUpSkills():getSkill2():getIdStr()
			changed = true
		end
		if self._lastSavedPersistentData[id].prevTimelines ~= pilot:getPrevTimelines() then 
			self._lastSavedPersistentData[id].prevTimelines = pilot:getPrevTimelines()
			changed = true
		end
	end
	if self.PLUS_DEBUG then LOG("refreshLastSavedPersistentData: "..(changed and "true" or "false")) end
	return changed
end

function cplus_plus_ex:persistentDataChanged()
	local changed = false
	if not self._lastSavedPersistentData then
		local loaded = self:loadPersistentDataIfNeeded()
		if not loaded then
			self:refreshLastSavedPersistentData()
		end
		changed = true
	else
		changed = self:refreshLastSavedPersistentData()
	end

	if self.PLUS_DEBUG then LOG("persistentDataChanged: "..(changed and "true" or "false")) end
	return changed
end

function cplus_plus_ex:savePersistentDataIfChanged()
	if self:persistentDataChanged() then
		if not modApi:isProfilePath() then return end

		if self.PLUS_DEBUG then LOG("Saving persistent data!") end
		sdlext.config(
			modApi:getCurrentProfilePath().."modcontent.lua",
			function(readObj)
				-- clear out any old data
				readObj.cplus_plus_ex = {}
				for _, pilot in pairs(self.getAllPilots()) do
				local id = pilot:getIdStr()
					readObj.cplus_plus_ex[id] = self._lastSavedPersistentData[id]
				end
			end
		)
	end
end

function cplus_plus_ex:doItAll()
	self:refreshGameData()
	self:loadPersistentDataIfNeeded()
	
	self.plus_manager:applySkillsToAllPilots()
	
	self:savePersistentDataIfChanged()
end

function cplus_plus_ex:scanForTimeTraveler()
	self:loadPersistentDataIfNeeded()
	
	-- TODO: Have a structured, dependent scan? Like string or array
	-- but with some don't care sections
	-- If kept like this, instead use offsets from pilot struct def
	-- This seems to be working well with additional fields
	local scanner = memhack.dll.scanner.new("string", {checkTiming=true})
	
	for id, data in pairs(self._lastSavedPersistentData) do 
		local results = scanner:firstScan("exact", id)
		if self.PLUS_DEBUG then 
			LOG("traveler search: found " .. results.resultCount .. " matches for pilot "..id.. 
				". Searching for timelines == " .. (data.prevTimelines + 1) ..
				", xp == " .. data.xp .. ", level == " .. data.level)
		end
		
		if results.resultCount > 0 then
			local matches = scanner:getResults({limit = 1000})
			for i = 1, results.resultCount do
				local baseAddr = matches.results[i].address - 0x84
				local xpFound = memhack.dll.memory.readInt(baseAddr + 0x3C)
				local lvlFound = memhack.dll.memory.readInt(baseAddr + 0x68)
				local prevTimelinesFound = memhack.dll.memory.readInt(baseAddr + 0x288)
				
				if prevTimelinesFound ~= data.prevTimelines + 1 then
					if self.PLUS_EXTRA_DEBUG then LOG("traveler search: checking pilot at " .. baseAddr .. " timelines mismatch: " .. prevTimelinesFound) end
				elseif xpFound ~= data.xp then
					if self.PLUS_EXTRA_DEBUG then LOG("traveler search: checking pilot at " .. baseAddr .. " xp mismatch: " .. xpFound) end
				elseif lvlFound ~= data.level then
					if self.PLUS_EXTRA_DEBUG then LOG("traveler search: checking pilot at " .. baseAddr .. " level mismatch: " .. lvlFound) end
				else
					if self.PLUS_DEBUG then LOG("traveler search: found pilot at " .. baseAddr) end
					self.timeTraveler = memhack.structs.Pilot.new(baseAddr)
				end
			end
		end
		scanner:reset()
	end
end

function cplus_plus_ex:searchForTimeTraveler()
	if self._pilotStructs then
		if self.PLUS_DEBUG then LOG("traveler search: Checking cached pilots") end
		for _, pilot in pairs(self._pilotStructs) do
			local pilotData = self._lastSavedPersistentData[pilot:getIdStr()]
			if self.PLUS_DEBUG then LOG("traveler search: ".. pilot:getPrevTimelines() .. " - " .. pilotData.prevTimelines + 1) end
			if pilot:getPrevTimelines() == pilotData.prevTimelines + 1 then
				self.timeTraveler = pilot
				if self.PLUS_DEBUG then LOG("PLUS Ext: Found time traveler! ".. pilot:getIdStr()) end
			end
		end
	else
		if self.PLUS_DEBUG then LOG("traveler search: No cached pilots; Scanning for pilot") end
		self:scanForTimeTraveler()
	end
end

function cplus_plus_ex:addHooks()
	modApi:addSaveGameHook(function()
		cplus_plus_ex:doItAll()
	end)
	if self.PLUS_DEBUG then LOG("PLUS Ext: Initialized and subscribed to game hooks") end
end

function cplus_plus_ex:addEvents()	
	-- TODO: Maybe a different event?
	modApi.events.onMainMenuEntered:subscribe(function()
		cplus_plus_ex:clearGameData()
	end)
	modApi.events.onHangarEntered:subscribe(function()
		cplus_plus_ex:searchForTimeTraveler()
	end)
	if self.PLUS_DEBUG then LOG("PLUS Ext: Initialized and subscribed to game events") end
end

function cplus_plus_ex:init(plus_manager)
	self.plus_manager = plus_manager
	self.plus_manager:init(self)
	
	-- Events are not cleared
	self:addEvents()
end

function cplus_plus_ex:load()
	self.plus_manager:load()
	
	-- Add the hooks - these are cleared each reload
	self:addHooks()
end

-- Shows an error popup to the user
function cplus_plus_ex:showErrorPopup(message)
	if modApi then
		-- Use modApi's message box for user-facing errors
		modApi:scheduleHook(50, function()
			sdlext.showDialog(
				function(dialog)
					local ui = require("ui")
					local frame = Ui()
						:widthpx(500):heightpx(200)
						:caption("PLUS Extension Error")

					frame:addSurface(Ui()
						:width(1):height(1)
						:decorate({ DecoSolid(deco.colors.buttonborder) })
					)

					local scrollarea = UiScrollArea()
						:width(1):height(1)
						:padding(10)
					frame:add(scrollarea)

					local textbox = UiTextBox(message)
						:width(1)
					scrollarea:add(textbox)

					return frame
				end
			)
		end)
	end
end

function cplus_plus_ex:logAndShowErrorPopup(message)
	LOG(message)
	self:showErrorPopup(message)
end

-- Helper function to get all pilots in the current squad
function cplus_plus_ex:getAllPilots()
	if not Game then return nil end
	
	local pilots = {}

	-- Iterate through the 3 squad positions (0, 1, 2)
	for i = 0, 2 do
		local pawnId = i  -- Pawn IDs correspond to squad positions
		local pawn = Game:GetPawn(pawnId)

		if pawn ~= nil then
			local pilot = pawn:GetPilot()
			if pilot ~= nil then
				pilots[i + 1] = pilot
			end
		end
	end
	return pilots
end