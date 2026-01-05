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

	-- Use struct scanner to find pilot by matching multiple fields at once
	-- Get field definitions from Pilot struct
	local PilotLayout = memhack.structs.Pilot._layout

	-- We use the first byte of the ID string as the search key
	local scanner = memhack.dll.scanner.new("struct", {checkTiming=true})
	for id, data in pairs(self._lastSavedPersistentData) do
		if self.PLUS_DEBUG then
			LOG("traveler search: scanning for pilot "..id..
				" with timelines == " .. (data.prevTimelines + 1) ..
				", xp == " .. data.xp .. ", level == " .. data.level)
		end

		-- Create struct definition with first byte of ID as key passing the offset
		-- from the base of the pilot struct so we can use our defined offsets as is
		local structDef = memhack.dll.scanner.StructSearch.new(string.byte(id:sub(1,1)), PilotLayout.id.offset)

		-- Add fields using struct-relative offsets. We created the key with the offset
		-- from the pilot base struct so we don't need to compute them relative to the
		-- key but instead use directly from the pilot base address
		structDef:addField(PilotLayout.xp.offset, "int", data.xp)
		structDef:addField(PilotLayout.level.offset, "int", data.level)
		structDef:addField(PilotLayout.prevTimelines.offset, "int", data.prevTimelines + 1)
		structDef:addField(PilotLayout.id.offset, "string", id)

		-- perform the scan
		local results = scanner:firstScan("exact", structDef)

		if self.PLUS_DEBUG then
			LOG("traveler search: found " .. results.resultCount .. " matches")
		end

		if results.resultCount > 0 then
			local matches = scanner:getResults({limit = 1})
			-- Since we passed keyOffset, the address is already the struct base
			local baseAddr = matches.results[1].address
			if self.PLUS_DEBUG then LOG("traveler search: setting to found pilot at " .. string.format("0x%X", baseAddr)) end
			self.timeTraveler = memhack.structs.Pilot.new(baseAddr)
			break  -- Found the time traveler, no need to continue
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