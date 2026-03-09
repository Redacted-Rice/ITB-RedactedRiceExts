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

-- Local references to other submodules (set during init)
local utils = nil
local skill_selection = nil

-- Initialize the module
function time_traveler:init()
	utils = cplus_plus_ex._subobjects.utils
	skill_selection = cplus_plus_ex._subobjects.skill_selection
	return self
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

-- Refresh last saved persistent data with current pilot state
function time_traveler:_refreshLastSavedPersistentData()
	local pilots = Game and Game:GetAvailablePilots() or nil
	if not pilots then
		return false
	end

	local changed = false
	time_traveler.lastSavedPersistentData = time_traveler.lastSavedPersistentData or {}
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
					-- Validate just in case. Really should be fine
					local traveler = memhack.structs.Pilot.new(baseAddr, true)
					if traveler then
						table.insert(time_traveler.potentialTimeTravelers, traveler)
						logger.logDebug(SUBMODULE, "found potential time traveler pilot %s at 0x%X, setting skills to %s and %s", id, baseAddr, data.skill1, data.skill2)
						skill_selection:applySkillIdsToPilot(traveler, {data.skill1, data.skill2}, false)
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
			local pilotData = time_traveler.lastSavedPersistentData[pilot:getIdStr()]
			if pilotData then
				logger.logDebug(SUBMODULE, "Checking pilot timelines: %d vs expected %d",
						pilot:getPrevTimelines(), pilotData.prevTimelines + 1)
				if pilot:getPrevTimelines() == pilotData.prevTimelines + 1 then
					time_traveler.potentialTimeTravelers = {pilot}
					skill_selection:applySkillIdsToPilot(pilot, {pilotData.skill1, pilotData.skill2}, false)
					logger.logInfo(SUBMODULE, "Found time traveler: " .. pilot:getIdStr())
				end
			else
				logger.logWarn(SUBMODULE, "pilotData %s is nil in searchForTimeTraveler - skipping", idx)
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

return time_traveler
