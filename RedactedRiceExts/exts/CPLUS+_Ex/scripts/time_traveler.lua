-- Time Traveler Module
-- Handles time traveler detection and persistent data management
-- This will update and save the current run pilot data in the modcontent.lua file
-- so that we have the info to use for the potential time travelers to search for
-- and apply as appropriate.
-- I ended up needing to track all pilots because any could be a time traveler. This is now
-- redundant with the data saved in saveData but it seems more intuitive to use that data
-- primarily so I will keep it as is.

local time_traveler = {}

-- Register with logging system
local logger = memhack.logger
local SUBMODULE = logger.register("CPLUS+", "TimeTraveler", cplus_plus_ex.DEBUG.TIME_TRAVELER and cplus_plus_ex.DEBUG.ENABLED)

-- Module state
-- Store per profile. These from what I can tell stay valid the whole life of the game
-- even when switching profiles
time_traveler.allPilots = {}
time_traveler.lastSavedPersistentData = nil
-- There may be times where there is more than one... In testing we saw cases
-- were a quick close & reopen of the game *can* end up finding more than one or
-- unexpected pilots. As such we keep track of all potential travelers. Typically
-- there will be just one
time_traveler.potentialTimeTravelers = {}

-- Persistent data registry for custom mod data
-- Format: {
--   [modId] = {
--     [fieldName] = {
--       save = function(pilotId) -> value,  -- Function to get value to save
--       restore = function(pilotId, value),  -- Function to restore value
--     }
--   }
-- }
time_traveler.registeredFields = {}

-- Local references to other submodules (set during init)
local utils = nil
local skill_selection = nil

-- Initialize the module
function time_traveler:init()
	utils = cplus_plus_ex._subobjects.utils
	skill_selection = cplus_plus_ex._subobjects.skill_selection
	return self
end

-- Register a field to persist across time travel
-- modId: unique identifier for the mod (e.g., "pilots_plus")
-- fieldName: name of the field to persist (e.g., "warbot_added_count")
-- saveFn: function(pilotId) -> value to save
-- restoreFn: function(pilotId, value) to restore the value
function time_traveler:registerTimeTravelerData(modId, fieldName, saveFn, restoreFn)
	if type(modId) ~= "string" or modId == "" then
		logger.logError(SUBMODULE, "registerTimeTravelerData: modId must be a non-empty string")
		return false
	end
	if type(fieldName) ~= "string" or fieldName == "" then
		logger.logError(SUBMODULE, "registerTimeTravelerData: fieldName must be a non-empty string")
		return false
	end
	if type(saveFn) ~= "function" then
		logger.logError(SUBMODULE, "registerTimeTravelerData: saveFn must be a function")
		return false
	end
	if type(restoreFn) ~= "function" then
		logger.logError(SUBMODULE, "registerTimeTravelerData: restoreFn must be a function")
		return false
	end
	if not self.registeredFields[modId] then
		self.registeredFields[modId] = {}
	end

	self.registeredFields[modId][fieldName] = {
		save = saveFn,
		restore = restoreFn,
	}
	return true
end

function time_traveler:load()
	-- Temporary for testing memhack. Will remove later
	memhack.hooks:addPilotChangedHook(function(pilot)
		logger.logDebug(SUBMODULE, "Hook: Pilot changed")
	end)
	memhack.hooks:addPilotLvlUpSkillChangedHook(function(pilot, skill)
		logger.logDebug(SUBMODULE, "Hook: Pilot lvl up skill changed")
	end)

	logger.logDebug(SUBMODULE, "Initialized and subscribed to game hooks")
end

-- Refresh cached squad pilot data
function time_traveler:_refreshGameData()
	if Game and Profile then
		time_traveler.allPilots[Profile.visible_name] = Game:GetAvailablePilots()
		logger.logDebug(SUBMODULE, "Refreshing game data")
	end
end

-- Clear cached game data
function time_traveler:_clearGameData()
	if Profile then
		time_traveler.allPilots[Profile.visible_name] = nil
		logger.logDebug(SUBMODULE, "Clearing game data")
	end
end

-- Load persistent data if not already loaded
function time_traveler:_loadPersistentDataIfNeeded()
	if not time_traveler.lastSavedPersistentData then
		if not modApi:isProfilePath() then
			logger.logDebug(SUBMODULE, "Skipping persistent data load: not in profile path")
			return
		end
		logger.logDebug(SUBMODULE, "Loading persistent data")
		time_traveler.lastSavedPersistentData = {}

		sdlext.config(
			modApi:getCurrentProfilePath().."modcontent.lua",
			function(obj)
				if obj.cplus_plus_ex and obj.cplus_plus_ex.last_run_pilots then
					for id, data in pairs(obj.cplus_plus_ex.last_run_pilots) do
						time_traveler.lastSavedPersistentData[id] = data
					end
				end
			end
		)
	end
end

function time_traveler:_refreshLastSavedPersistentData()
	local pilots = Game and Game:GetAvailablePilots() or nil
	if not pilots then
		return false
	end

	local changed = false
	time_traveler.lastSavedPersistentData = time_traveler.lastSavedPersistentData or {}
	local skill_state_tracker = cplus_plus_ex._subobjects.skill_state_tracker

	for _, pilot in pairs(pilots) do
		local id = pilot:getIdStr()
		time_traveler.lastSavedPersistentData[id] = time_traveler.lastSavedPersistentData[id] or {}
		if time_traveler.lastSavedPersistentData[id].name ~= pilot:getNameStr() then
			time_traveler.lastSavedPersistentData[id].name = pilot:getNameStr()
			changed = true
		end
		if time_traveler.lastSavedPersistentData[id].xp ~= pilot:getXp() then
			time_traveler.lastSavedPersistentData[id].xp = pilot:getXp()
			changed = true
		end
		if time_traveler.lastSavedPersistentData[id].level ~= pilot:getLevel() then
			time_traveler.lastSavedPersistentData[id].level = pilot:getLevel()
			changed = true
		end
		if time_traveler.lastSavedPersistentData[id].skill1 ~= pilot:getLvlUpSkills():getSkill1():getIdStr() then
			time_traveler.lastSavedPersistentData[id].skill1 = pilot:getLvlUpSkills():getSkill1():getIdStr()
			changed = true
		end
		if time_traveler.lastSavedPersistentData[id].skill2 ~= pilot:getLvlUpSkills():getSkill2():getIdStr() then
			time_traveler.lastSavedPersistentData[id].skill2 = pilot:getLvlUpSkills():getSkill2():getIdStr()
			changed = true
		end
		if time_traveler.lastSavedPersistentData[id].prevTimelines ~= pilot:getPrevTimelines() then
			time_traveler.lastSavedPersistentData[id].prevTimelines = pilot:getPrevTimelines()
			changed = true
		end

		local virtualSkills = {}
		local gameVirtual = GAME.cplus_plus_ex.pilotVirtualSkills[id]
		if gameVirtual then
			for _, entry in ipairs(gameVirtual) do
				table.insert(virtualSkills, { id = entry.id, source = entry.source })
			end
		end
		local currentVirtualSkills = time_traveler.lastSavedPersistentData[id].virtualSkills or {}
		local virtualSkillsChanged = #virtualSkills ~= #currentVirtualSkills
		if not virtualSkillsChanged then
			for i, entry in ipairs(virtualSkills) do
				local cur = currentVirtualSkills[i]
				if not cur or cur.id ~= entry.id or cur.source ~= entry.source then
					virtualSkillsChanged = true
					break
				end
			end
		end

		if virtualSkillsChanged then
			time_traveler.lastSavedPersistentData[id].virtualSkills = virtualSkills
			changed = true
		end

		-- Save custom registered fields for this pilot
		if not time_traveler.lastSavedPersistentData[id].customData then
			time_traveler.lastSavedPersistentData[id].customData = {}
		end

		for modId, fields in pairs(self.registeredFields) do
			if not time_traveler.lastSavedPersistentData[id].customData[modId] then
				time_traveler.lastSavedPersistentData[id].customData[modId] = {}
			end

			for fieldName, fieldDef in pairs(fields) do
				-- Call the save function to get the value
				local success, value = pcall(fieldDef.save, id)
				if success then
					-- Check if value changed
					local oldValue = time_traveler.lastSavedPersistentData[id].customData[modId][fieldName]
					if oldValue ~= value then
						time_traveler.lastSavedPersistentData[id].customData[modId][fieldName] = value
						changed = true
						logger.logDebug(SUBMODULE, "Saved custom field %s.%s for pilot %s: %s",
							modId, fieldName, id, tostring(value))
					end
				else
					logger.logError(SUBMODULE, "Failed to save custom field %s.%s for pilot %s: %s",
						modId, fieldName, id, value)
				end
			end
		end
	end
	logger.logDebug(SUBMODULE, "Refreshed last saved persistent data: %s",
			changed and "changed" or "unchanged")
	return changed
end

-- Check if persistent data has changed
function time_traveler:_persistentDataChanged()
	local changed = false
	if not time_traveler.lastSavedPersistentData then
		local loaded = self:_loadPersistentDataIfNeeded()
		if not loaded then
			self:_refreshLastSavedPersistentData()
		end
		changed = true
	else
		changed = self:_refreshLastSavedPersistentData()
	end

	logger.logDebug(SUBMODULE, "Persistent data changed: %s", changed and "yes" or "no")
	return changed
end

-- Save persistent data if it has changed
function time_traveler:_updateDataOnSave()
	time_traveler:_refreshGameData()

	if self:_persistentDataChanged() then
		if not modApi:isProfilePath() then
			logger.logDebug(SUBMODULE, "Skipping persistent data save: not in profile path")
			return
		end

		logger.logDebug(SUBMODULE, "Saving persistent data")
		sdlext.config(modApi:getCurrentProfilePath().."modcontent.lua",
				function(readObj)
					-- Get existing cplus_plus section if it exists or create it
					readObj.cplus_plus_ex = readObj.cplus_plus_ex or {}
					-- Clear out last_run_pilots to ensure no stale data
					readObj.cplus_plus_ex.last_run_pilots = {}
					for _, pilot in pairs(Game:GetAvailablePilots()) do
						local id = pilot:getIdStr()
						readObj.cplus_plus_ex.last_run_pilots[id] = time_traveler.lastSavedPersistentData[id]
					end
				end
		)
	end
end

-- Scan for time traveler pilot using memory scanning
function time_traveler:_scanForTimeTraveler()
	logger.logDebug(SUBMODULE, "Maybe scanning for time traveler")
	self:_loadPersistentDataIfNeeded()

	-- Check which pilot we are looking for
	local pilot = nil
	if Profile then
		pilot = Profile.pilot
		if not pilot then
			logger.logDebug(SUBMODULE, "No profile pilot found. This means there is no time traveler.")
			return
		end
	end

	for id, data in pairs(time_traveler.lastSavedPersistentData) do
		if pilot and id ~= pilot.id then
			logger.logDebug(SUBMODULE, "Skipping pilot Id %s", id)
		else
			logger.logDebug(SUBMODULE, "Scanning for pilot %s with timelines == %d, xp == %d, level == %d",
				id, data.prevTimelines + 1, data.xp, data.level)

			local PilotLayout = memhack.structs.Pilot._layout
			local scanner = memhack.dll.scanner.new("struct", {checkTiming = cplus_plus_ex.DEBUG.TIME_TRAVELER})
			local structDef = memhack.dll.scanner.StructSearch.new(string.byte(id:sub(1,1)), PilotLayout.id.offset)
			--structDef:addField(PilotLayout.vtable.offset, "int", memhack.structs.Pilot._vtableAddr)
			structDef:addField(PilotLayout.xp.offset, "int", data.xp)
			structDef:addField(PilotLayout.level.offset, "int", data.level)
			structDef:addField(PilotLayout.prevTimelines.offset, "int", data.prevTimelines + 1)
			structDef:addField(PilotLayout.id.offset, "string", id)

			local results = scanner:firstScan("exact", structDef)

			if cplus_plus_ex.PLUS_DEBUG then
				logger.logDebug(SUBMODULE, "Found " .. results.resultCount .. " matches")
			end

			if results.resultCount > 0 then
				local matches = scanner:getResults()
				for _, result in ipairs(matches.results) do
					local baseAddr = result.address
					local traveler = memhack.structs.Pilot.new(baseAddr, true)
					if traveler then
						table.insert(time_traveler.potentialTimeTravelers, traveler)
						logger.logDebug(SUBMODULE, "found potential time traveler pilot %s at 0x%X, setting skills to %s and %s", id, baseAddr, data.skill1, data.skill2)
						skill_selection:applySkillIdsToPilot(traveler, {data.skill1, data.skill2}, false)
						-- Set any virtual skills too
						if data.virtualSkills and type(data.virtualSkills) == "table" and #data.virtualSkills > 0 then
							skill_selection:applyVirtualSkillIdsToPilot(traveler, data.virtualSkills)
							logger.logDebug(SUBMODULE, "restored %d virtual skills to time traveler", #data.virtualSkills)
						else
							logger.logDebug(SUBMODULE, "Ensuring virtual skills from time traveler are empty")
							skill_selection:clearVirtualSkillsFromPilot(traveler)
						end

						-- Restore custom registered data
						self:_restoreCustomData(id, data)
					end
				end
			end
		end
	end
end

-- Scan for time traveler pilot using memory scanning
function time_traveler:_getTimeTravelerFromMemory()
	-- profile already ensured non-null in this path
	-- profile data will not be updated yet if we did not shut the game down. Instead
	-- we have to check the existing pilot pointers and the expected timelines to see
	-- which was taken
	logger.logDebug(SUBMODULE, "Checking squad pilots for time traveler")
	for idx, pilot in pairs(time_traveler.allPilots[Profile.visible_name]) do
		local valid, err = pilot:validate()
		if not valid then
			logger.logWarn(SUBMODULE, "Pilot at idx %s is invalid (%s) - must not be time traveler!", idx, err)
		else
			-- Look up this pilot's data from saved persistent data
			local pilotId = pilot:getIdStr()
			local pilotData = time_traveler.lastSavedPersistentData[pilotId]

			if pilotData then
				logger.logDebug(SUBMODULE, "Checking pilot %s timelines: %d vs expected %d",
						pilotId, pilot:getPrevTimelines(), pilotData.prevTimelines + 1)
				if pilot:getPrevTimelines() == pilotData.prevTimelines + 1 then
					time_traveler.potentialTimeTravelers = {pilot}
					skill_selection:applySkillIdsToPilot(pilot, {pilotData.skill1, pilotData.skill2}, false)
					logger.logInfo(SUBMODULE, "Found time traveler: " .. pilotId)
					-- Set virtual skills too
					if pilotData.virtualSkills and type(pilotData.virtualSkills) == "table" and #pilotData.virtualSkills > 0 then
						skill_selection:applyVirtualSkillIdsToPilot(pilot, pilotData.virtualSkills)
						logger.logDebug(SUBMODULE, "restored %d virtual skills to time traveler", #pilotData.virtualSkills)
					else
						logger.logDebug(SUBMODULE, "Ensuring virtual skills from time traveler are empty")
						skill_selection:clearVirtualSkillsFromPilot(pilot)
					end

					-- Restore custom registered data
					self:_restoreCustomData(pilotId, pilotData)
				end
			else
				logger.logDebug(SUBMODULE, "No saved data for pilot %s - not a time traveler", pilotId)
			end
		end
	end
end

-- Restore custom data for a time traveler
-- timeTravelerId: the pilot ID of the time traveler
-- data: the saved persistent data for this pilot
function time_traveler:_restoreCustomData(timeTravelerId, data)
	if not data.customData then
		logger.logDebug(SUBMODULE, "No custom data to restore for pilot %s", timeTravelerId)
		return
	end

	logger.logInfo(SUBMODULE, "Restoring custom data for time traveler %s", timeTravelerId)

	for modId, modData in pairs(data.customData) do
		local fields = self.registeredFields[modId]
		if not fields then
			logger.logWarn(SUBMODULE, "Mod %s is not registered, skipping restore of its data", modId)
		else
			for fieldName, savedValue in pairs(modData) do
				local fieldDef = fields[fieldName]
				if not fieldDef then
					logger.logWarn(SUBMODULE, "Field %s.%s is not registered, skipping restore", modId, fieldName)
				else
					local success, err = pcall(fieldDef.restore, timeTravelerId, savedValue)
					if success then
						logger.logInfo(SUBMODULE, "Restored custom field %s.%s for time traveler %s: %s",
							modId, fieldName, timeTravelerId, tostring(savedValue))
					else
						logger.logError(SUBMODULE, "Failed to restore custom field %s.%s for time traveler %s: %s",
							modId, fieldName, timeTravelerId, err)
					end
				end
			end
		end
	end
end

-- Search for time traveler in squad pilots
function time_traveler:_searchForTimeTraveler()
	if Profile and time_traveler.allPilots[Profile.visible_name] then
		self:_getTimeTravelerFromMemory()
	else
		self:_scanForTimeTraveler()
	end
end

--- Narrow down potential time travelers to the one matching the given address
--- @param address number The pilot address to match
--- @return boolean found Whether a matching time traveler was found and set
function time_traveler:narrowTimeTraveler(address)
	if not self.potentialTimeTravelers then
		return false
	end

	for _, ttPilot in ipairs(self.potentialTimeTravelers) do
		if ttPilot._address == address then
			-- Narrow down to just this one
			self.potentialTimeTravelers = {ttPilot}
			logger.logDebug(SUBMODULE, "Narrowed time traveler to pilot at address %d", address)
			return true
		end
	end

	return false
end

-- Get virtual skills for a time traveler from persistent data and refreshes any
-- custom/extra data from the time traveler to GAME
-- @param pilotId string The pilot ID
-- @return table|nil Array of { id, source } entries, or nil if none found
function time_traveler:refreshTimeTravlerDataAndGetVirtSkills(pilotId)
	self:_loadPersistentDataIfNeeded()

	if not self.lastSavedPersistentData then
		logger.logDebug(SUBMODULE, "No persistent data available for refreshTimeTravlerDataAndGetVirtSkills")
		return nil
	end

	local persistentData = self.lastSavedPersistentData[pilotId]
	if not persistentData then
		logger.logDebug(SUBMODULE, "No persistent data found for pilot %s", pilotId)
		return nil
	end

	if not persistentData.virtualSkills or #persistentData.virtualSkills == 0 then
		logger.logDebug(SUBMODULE, "No virtual skills in persistent data for pilot %s", pilotId)
		return nil
	end

	-- Restore custom registered data
	self:_restoreCustomData(pilotId, persistentData)

	local ids = {}
	for _, entry in ipairs(persistentData.virtualSkills) do
		table.insert(ids, entry.id)
	end
	logger.logInfo(SUBMODULE, "Retrieved %d virtual skills for time traveler %s from persistent data: %s",
			#persistentData.virtualSkills, pilotId, table.concat(ids, ", "))

	return persistentData.virtualSkills
end

return time_traveler
