-- Time Traveler Module
-- Handles time traveler detection and persistent data management

local time_traveler = {}

-- Register with logging system
local logger = memhack.logger
local SUBMODULE = logger.register("CPLUS+", "TimeTraveler", cplus_plus_ex.DEBUG.TIME_TRAVELER and cplus_plus_ex.DEBUG.ENABLED)

-- Module state
time_traveler.pilotStructs = nil
time_traveler.lastSavedPersistentData = nil
time_traveler.timeTraveler = nil  -- The actual time traveler pilot struct

-- Local references to other submodules (set during init)
local utils = nil

-- Initialize the module
function time_traveler:init()
	utils = cplus_plus_ex._subobjects.utils

	-- Subscribe to events
	modApi.events.onMainMenuEntered:subscribe(function()
		self:clearGameData()
	end)
	modApi.events.onHangarEntered:subscribe(function()
		self:searchForTimeTraveler()
	end)

	return self
end

function time_traveler:load()
	modApi:addSaveGameHook(function()
		self:updateAndSaveSkills()
	end)

	-- Temporary for testing memhack. Will remove later
	memhack.hooks:addPilotChangedHook(function(pilot)
		logger.logDebug(SUBMODULE, "Hook: Pilot changed")
	end)
	memhack.hooks:addPilotLvlUpSkillChangedHook(function(pilot, skill)
		logger.logDebug(SUBMODULE, "Hook: Pilot lvl up skill changed")
	end)

	logger.logDebug(SUBMODULE, "Initialized and subscribed to game hooks")
end

-- Do all time_traveler operations (refresh, load, apply, save)
function time_traveler:updateAndSaveSkills()
	self:refreshGameData()
	self:loadPersistentDataIfNeeded()
	cplus_plus_ex:applySkillsToAllPilots()
	self:savePersistentDataIfChanged()
end

-- Refresh game data (get all pilots)
function time_traveler:refreshGameData()
	if Game then
		time_traveler.pilotStructs = Game:GetSquadPilots()
		logger.logDebug(SUBMODULE, "Refreshing game data")
	end
end

-- Clear game data
function time_traveler:clearGameData()
	time_traveler.pilotStructs = nil
	logger.logDebug(SUBMODULE, "Clearing game data")
end

-- Load persistent data if not already loaded
function time_traveler:loadPersistentDataIfNeeded()
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
function time_traveler:refreshLastSavedPersistentData()
	local pilots = Game and Game:GetSquadPilots() or nil
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
function time_traveler:persistentDataChanged()
	local changed = false
	if not time_traveler.lastSavedPersistentData then
		local loaded = time_traveler:loadPersistentDataIfNeeded()
		if not loaded then
			time_traveler:refreshLastSavedPersistentData()
		end
		changed = true
	else
		changed = time_traveler:refreshLastSavedPersistentData()
	end

	logger.logDebug(SUBMODULE, "Persistent data changed: %s", changed and "yes" or "no")
	return changed
end

-- Save persistent data if it has changed
function time_traveler:savePersistentDataIfChanged()
	if time_traveler:persistentDataChanged() then
		if not modApi:isProfilePath() then
			logger.logDebug(SUBMODULE, "Skipping persistent data save: not in profile path")
			return
		end

		logger.logDebug(SUBMODULE, "Saving persistent data")
		sdlext.config(
			modApi:getCurrentProfilePath().."modcontent.lua",
			function(readObj)
				readObj.cplus_plus_ex = {}
				readObj.cplus_plus_ex.last_run_pilots = {}
				for _, pilot in pairs(Game:GetSquadPilots()) do
					local id = pilot:getIdStr()
					readObj.cplus_plus_ex.last_run_pilots[id] = time_traveler.lastSavedPersistentData[id]
				end
			end
		)
	end
end

-- Scan for time traveler pilot using memory scanning
function time_traveler:scanForTimeTraveler()
	time_traveler:loadPersistentDataIfNeeded()

	local PilotLayout = memhack.structs.Pilot._layout
	local scanner = memhack.dll.scanner.new("struct", {checkTiming=true})

	for id, data in pairs(time_traveler.lastSavedPersistentData) do
		logger.logDebug(SUBMODULE, "Scanning for pilot %s with timelines == %d, xp == %d, level == %d",
			id, data.prevTimelines + 1, data.xp, data.level)

		local structDef = memhack.dll.scanner.StructSearch.new(string.byte(id:sub(1,1)), PilotLayout.id.offset)
		structDef:addField(PilotLayout.vtable.offset, "int", memhack.structs.Pilot._vtableAddr)
		structDef:addField(PilotLayout.xp.offset, "int", data.xp)
		structDef:addField(PilotLayout.level.offset, "int", data.level)
		structDef:addField(PilotLayout.prevTimelines.offset, "int", data.prevTimelines + 1)
		structDef:addField(PilotLayout.id.offset, "string", id)

		local results = scanner:firstScan("exact", structDef)

		if cplus_plus_ex.PLUS_DEBUG then
			logger.logDebug(SUBMODULE, "Found " .. results.resultCount .. " matches")
		end

		if results.resultCount > 0 then
			local matches = scanner:getResults({limit = 1})
			local baseAddr = matches.results[1].address
			-- Validate just in case. Really should be fine
			time_traveler.timeTraveler = memhack.structs.Pilot.new(baseAddr, true)
			if time_traveler.timeTraveler then
				logger.logDebug(SUBMODULE, "Setting to found pilot at 0x%X", baseAddr)
				break
			end
		end

		scanner:reset()
	end
end

-- Search for time traveler in current pilot structs
function time_traveler:searchForTimeTraveler()
	if time_traveler.pilotStructs then
		logger.logDebug(SUBMODULE, "Checking cached pilots for time traveler")
		for _, pilot in pairs(time_traveler.pilotStructs) do
			local pilotData = time_traveler.lastSavedPersistentData[pilot:getIdStr()]
			logger.logDebug(SUBMODULE, "Checking pilot timelines: %d vs expected %d",
					pilot:getPrevTimelines(), pilotData.prevTimelines + 1)
			if pilot:getPrevTimelines() == pilotData.prevTimelines + 1 then
				time_traveler.timeTraveler = pilot
				logger.logInfo(SUBMODULE, "Found time traveler: " .. pilot:getIdStr())
			end
		end
	else
		logger.logDebug(SUBMODULE, "No cached pilots; Scanning for pilot")
		time_traveler:scanForTimeTraveler()
	end
end

return time_traveler
