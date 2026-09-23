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
--       save = function(pilot) -> value,  -- Function to get value to save
--       restore = function(pilot, value),  -- Function to restore value
--     }
--   }
-- }
time_traveler.registeredFields = {}

-- Local references to other submodules (set during init)
local utils = nil
local skill_selection = nil
local pilot_uid = nil

-- Build a struct scan definition for locating a pilot in memory.
-- Anchors on ItBString strLen (same offset for local and remote id storage).
-- Id text is verified via itb_string, which reads unionType and compares inline or through the heap pointer.
local function buildPilotScanStruct(id, data)
	local PilotLayout = memhack.structs.Pilot._layout
	local ItBStringLayout = memhack.structs.ItBString._layout
	local idLen = #id
	local strLenOffset = PilotLayout.id.offset + ItBStringLayout.strLen.offset

	-- memchr key: low byte of expected strLen at the strLen field offset. Not as good a
	-- candidate as 'P' was but this makes the scan much simpler as we can always check
	-- for the struct in a single search. idLen % 256 is only the memchr hint; for ids
	-- longer than 255 the exact int field below still filters false key hits.
	local structDef = memhack.dll.scanner.StructSearch.new(idLen % 256, strLenOffset)
	structDef:addField(PilotLayout.xp.offset, "int", data.xp)
	structDef:addField(PilotLayout.level.offset, "int", data.level)
	structDef:addField(PilotLayout.prevTimelines.offset, "int", data.prevTimelines + 1)
	-- Exact strLen int (filters key hits where only the low byte matched)
	structDef:addField(strLenOffset, "int", idLen)
	-- Will handle local and remote ITB strings
	structDef:addField(PilotLayout.id.offset, "itb_string", id)

	return structDef
end

-- Validate a scan hit and return the pilot struct, or nil if id/validation fails.
local function acceptScannedPilot(baseAddr, id)
	local traveler = memhack.structs.Pilot.new(baseAddr, true)
	if not traveler then
		return nil
	end

	local scannedId = traveler:getIdStr()
	if scannedId ~= id then
		logger.logDebug(SUBMODULE, "Scan candidate at 0x%X rejected: expected id %s, got %s",
			baseAddr, id, tostring(scannedId))
		return nil
	end

	return traveler
end

-- Initialize the module
function time_traveler:init()
	utils = cplus_plus_ex._subobjects.utils
	skill_selection = cplus_plus_ex._subobjects.skill_selection
	pilot_uid = cplus_plus_ex._subobjects.pilot_uid
	return self
end

-- Memory scan matches on pilot type id, not UID.
function time_traveler:_getScanIdFromPersistentEntry(storageKey, data)
	if data and data.pilotId then
		return data.pilotId
	end
	-- legacy - storage key is the pilot type id
	return storageKey
end

function time_traveler:_lookupPersistentData(pilot)
	if type(pilot) ~= "table" or getmetatable(pilot) ~= memhack.structs.Pilot then
		return nil, nil
	end

	self:_loadPersistentDataIfNeeded()

	if not self.lastSavedPersistentData then
		return nil, nil
	end

	-- Try lookup by UID
	local uid = pilot:getUidStr()
	if self.lastSavedPersistentData[uid] then
		return self.lastSavedPersistentData[uid], uid
	end

	-- If that doesn't work, try legacy lookup (by pilot ID)
	local legacyKey = pilot:getIdStr()
	if self.lastSavedPersistentData[legacyKey] then
		return self.lastSavedPersistentData[legacyKey], legacyKey
	end
	return nil, legacyKey
end

-- Register a field to persist across time travel
-- modId: unique identifier for the mod (e.g., "pilots_plus")
-- fieldName: name of the field to persist (e.g., "warbot_added_count")
-- saveFn: function(pilot) -> value to save
-- restoreFn: function(pilot, value) to restore the value
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
	--[[ Temporary for testing memhack. Will remove later
	memhack.hooks:addPilotChangedHook(function(pilot)
		logger.logDebug(SUBMODULE, "Hook: Pilot changed")
	end)
	memhack.hooks:addPilotLvlUpSkillChangedHook(function(pilot, skill)
		logger.logDebug(SUBMODULE, "Hook: Pilot lvl up skill changed")
	end)]]
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

	for _, pilot in pairs(pilots) do
		local uid = pilot:getUidStr()
		time_traveler.lastSavedPersistentData[uid] = time_traveler.lastSavedPersistentData[uid] or {}
		local entry = time_traveler.lastSavedPersistentData[uid]
		if entry.pilotId ~= pilot:getIdStr() then
			entry.pilotId = pilot:getIdStr()
			changed = true
		end
		if entry.name ~= pilot:getNameStr() then
			entry.name = pilot:getNameStr()
			changed = true
		end
		if entry.xp ~= pilot:getXp() then
			entry.xp = pilot:getXp()
			changed = true
		end
		if entry.level ~= pilot:getLevel() then
			entry.level = pilot:getLevel()
			changed = true
		end
		if entry.skill1 ~= pilot:getLvlUpSkills():getSkill1():getIdStr() then
			entry.skill1 = pilot:getLvlUpSkills():getSkill1():getIdStr()
			changed = true
		end
		if entry.skill2 ~= pilot:getLvlUpSkills():getSkill2():getIdStr() then
			entry.skill2 = pilot:getLvlUpSkills():getSkill2():getIdStr()
			changed = true
		end
		if entry.prevTimelines ~= pilot:getPrevTimelines() then
			entry.prevTimelines = pilot:getPrevTimelines()
			changed = true
		end

		local virtualSkills = {}
		local gameVirtual = GAME.cplus_plus_ex.pilotVirtualSkills[uid]
		if gameVirtual then
			for _, skillEntry in ipairs(gameVirtual) do
				table.insert(virtualSkills, { id = skillEntry.id, source = skillEntry.source })
			end
		end
		local currentVirtualSkills = entry.virtualSkills or {}
		local virtualSkillsChanged = #virtualSkills ~= #currentVirtualSkills
		if not virtualSkillsChanged then
			for i, skillEntry in ipairs(virtualSkills) do
				local cur = currentVirtualSkills[i]
				if not cur or cur.id ~= skillEntry.id or cur.source ~= skillEntry.source then
					virtualSkillsChanged = true
					break
				end
			end
		end

		if virtualSkillsChanged then
			entry.virtualSkills = virtualSkills
			changed = true
		end

		-- Save custom registered fields for this pilot
		entry.customData = entry.customData or {}

		for modId, fields in pairs(self.registeredFields) do
			entry.customData[modId] = entry.customData[modId] or {}

			for fieldName, fieldDef in pairs(fields) do
				-- Call the save function to get the value
				local success, value = pcall(fieldDef.save, pilot)
				if success then
					-- Check if value changed
					local oldValue = entry.customData[modId][fieldName]
					if oldValue ~= value then
						entry.customData[modId][fieldName] = value
						changed = true
						logger.logDebug(SUBMODULE, "Saved custom field %s.%s for pilot %s: %s",
							modId, fieldName, uid, tostring(value))
					end
				else
					logger.logError(SUBMODULE, "Failed to save custom field %s.%s for pilot %s: %s",
						modId, fieldName, uid, value)
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
						local uid = pilot:getUidStr()
						readObj.cplus_plus_ex.last_run_pilots[uid] = time_traveler.lastSavedPersistentData[uid]
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

	for storageKey, data in pairs(time_traveler.lastSavedPersistentData) do
		local scanId = self:_getScanIdFromPersistentEntry(storageKey, data)
		if pilot and scanId ~= pilot.id then
			logger.logDebug(SUBMODULE, "Skipping storage key %s (scan id %s)", storageKey, scanId)
		else
			logger.logDebug(SUBMODULE, "Scanning storage key %s (scan id %s) with timelines == %d, xp == %d, level == %d",
				storageKey, scanId, data.prevTimelines + 1, data.xp, data.level)

			local structDef = buildPilotScanStruct(scanId, data)
			local scanner = memhack.dll.scanner.new("struct", {checkTiming = cplus_plus_ex.DEBUG.TIME_TRAVELER})

			local results = scanner:firstScan("exact", structDef)

			if cplus_plus_ex.PLUS_DEBUG then
				logger.logDebug(SUBMODULE, "Found " .. results.resultCount .. " matches")
			end

			if results.resultCount > 0 then
				local matches = scanner:getResults()
				for _, result in ipairs(matches.results) do
					local baseAddr = result.address
					local traveler = acceptScannedPilot(baseAddr, scanId)
					if traveler then
						table.insert(time_traveler.potentialTimeTravelers, traveler)
						logger.logDebug(SUBMODULE, "found potential time traveler key %s at 0x%X, setting skills to %s and %s",
							storageKey, baseAddr, data.skill1, data.skill2)
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
						self:_restoreCustomData(traveler, data)
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
			local pilotData, storageKey = self:_lookupPersistentData(pilot)

			if pilotData then
				logger.logDebug(SUBMODULE, "Checking pilot %s (key %s) timelines: %d vs expected %d",
						pilot:getUidStr(), storageKey, pilot:getPrevTimelines(), pilotData.prevTimelines + 1)
				if pilot:getPrevTimelines() == pilotData.prevTimelines + 1 then
					time_traveler.potentialTimeTravelers = {pilot}
					skill_selection:applySkillIdsToPilot(pilot, {pilotData.skill1, pilotData.skill2}, false)
					logger.logInfo(SUBMODULE, "Found time traveler: %s", pilot:getUidStr())
					-- Set virtual skills too
					if pilotData.virtualSkills and type(pilotData.virtualSkills) == "table" and #pilotData.virtualSkills > 0 then
						skill_selection:applyVirtualSkillIdsToPilot(pilot, pilotData.virtualSkills)
						logger.logDebug(SUBMODULE, "restored %d virtual skills to time traveler", #pilotData.virtualSkills)
					else
						logger.logDebug(SUBMODULE, "Ensuring virtual skills from time traveler are empty")
						skill_selection:clearVirtualSkillsFromPilot(pilot)
					end

					-- Restore custom registered data
					self:_restoreCustomData(pilot, pilotData)
				end
			else
				logger.logDebug(SUBMODULE, "No saved data for pilot %s - not a time traveler", pilot:getUidStr())
			end
		end
	end
end

-- Restore custom data for a time traveler
function time_traveler:_restoreCustomData(pilot, data)
	if type(pilot) ~= "table" or getmetatable(pilot) ~= memhack.structs.Pilot then
		logger.logError(SUBMODULE, "_restoreCustomData: expected Pilot struct, got %s", type(pilot))
		return
	end
	if not data.customData then
		logger.logDebug(SUBMODULE, "No custom data to restore for pilot %s", pilot:getUidStr())
		return
	end

	logger.logInfo(SUBMODULE, "Restoring custom data for time traveler %s", pilot:getUidStr())

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
					local success, err = pcall(fieldDef.restore, pilot, savedValue)
					if success then
						logger.logInfo(SUBMODULE, "Restored custom field %s.%s for time traveler %s: %s",
							modId, fieldName, pilot:getUidStr(), tostring(savedValue))
					else
						logger.logError(SUBMODULE, "Failed to restore custom field %s.%s for time traveler %s: %s",
							modId, fieldName, pilot:getUidStr(), err)
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
-- @return table|nil Array of { id, source } entries, or nil if none found
function time_traveler:refreshTimeTravlerDataAndGetVirtSkills(pilot)
	if type(pilot) ~= "table" or getmetatable(pilot) ~= memhack.structs.Pilot then
		logger.logError(SUBMODULE, "refreshTimeTravlerDataAndGetVirtSkills: expected Pilot struct, got %s", type(pilot))
		return nil
	end

	local persistentData = self:_lookupPersistentData(pilot)
	if not persistentData then
		logger.logDebug(SUBMODULE, "No persistent data found for pilot %s", pilot:getUidStr())
		return nil
	end

	if not persistentData.virtualSkills or #persistentData.virtualSkills == 0 then
		logger.logDebug(SUBMODULE, "No virtual skills in persistent data for pilot %s", pilot:getUidStr())
		return nil
	end

	self:_restoreCustomData(pilot, persistentData)

	local ids = {}
	for _, entry in ipairs(persistentData.virtualSkills) do
		table.insert(ids, entry.id)
	end
	logger.logInfo(SUBMODULE, "Retrieved %d virtual skills for time traveler %s from persistent data: %s",
			#persistentData.virtualSkills, pilot:getUidStr(), table.concat(ids, ", "))

	return persistentData.virtualSkills
end

return time_traveler
