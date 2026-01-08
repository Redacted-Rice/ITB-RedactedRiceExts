-- Time Traveler Module
-- Handles time traveler detection and persistent data management

-- TODO: Later: Does this correctly assign skills to time traveler on start up in hangar or just when
-- actually starting the game?

local time_traveler = {}

-- Module state
time_traveler.pilotStructs = nil
time_traveler.lastSavedPersistentData = nil
time_traveler.timeTraveler = nil  -- The actual time traveler pilot struct

-- Reference to owner (set during init)
local owner = nil
local utils = nil

-- Initialize the module with reference to owner
function time_traveler.init(ownerRef)
	owner = ownerRef
	utils = ownerRef._modules.utils
end

-- Refresh game data (get all pilots)
function time_traveler.refreshGameData()
	if Game then
		time_traveler.pilotStructs = utils.getAllSquadPilots()
		if owner.PLUS_DEBUG then LOG("refreshGameData") end
	end
end

-- Clear game data
function time_traveler.clearGameData()
	time_traveler.pilotStructs = nil
	if owner.PLUS_DEBUG then LOG("clearGameData") end
end

-- Load persistent data if not already loaded
function time_traveler.loadPersistentDataIfNeeded()
	if not time_traveler.lastSavedPersistentData then
		if not modApi:isProfilePath() then return end
		if owner.PLUS_DEBUG then LOG("Loading persistent data!") end
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
function time_traveler.refreshLastSavedPersistentData()
	local pilots = utils.getAllSquadPilots()
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
	if owner.PLUS_DEBUG then LOG("refreshLastSavedPersistentData: "..(changed and "true" or "false")) end
	return changed
end

-- Check if persistent data has changed
function time_traveler.persistentDataChanged()
	local changed = false
	if not time_traveler.lastSavedPersistentData then
		local loaded = time_traveler.loadPersistentDataIfNeeded()
		if not loaded then
			time_traveler.refreshLastSavedPersistentData()
		end
		changed = true
	else
		changed = time_traveler.refreshLastSavedPersistentData()
	end

	if owner.PLUS_DEBUG then LOG("persistentDataChanged: "..(changed and "true" or "false")) end
	return changed
end

-- Save persistent data if it has changed
function time_traveler.savePersistentDataIfChanged()
	if time_traveler.persistentDataChanged() then
		if not modApi:isProfilePath() then return end

		-- TODO: Make sure to clear out old data
		if owner.PLUS_DEBUG then LOG("Saving persistent data!") end
		sdlext.config(
			modApi:getCurrentProfilePath().."modcontent.lua",
			function(readObj)
				readObj.cplus_plus_ex = {}
				readObj.cplus_plus_ex.last_run_pilots = {}
				for _, pilot in pairs(utils.getAllSquadPilots()) do
					local id = pilot:getIdStr()
					readObj.cplus_plus_ex.last_run_pilots[id] = time_traveler.lastSavedPersistentData[id]
				end
			end
		)
	end
end

-- Scan for time traveler pilot using memory scanning
function time_traveler.scanForTimeTraveler()
	time_traveler.loadPersistentDataIfNeeded()

	local PilotLayout = memhack.structs.Pilot._layout
	local scanner = memhack.dll.scanner.new("struct", {checkTiming=true})

	for id, data in pairs(time_traveler.lastSavedPersistentData) do
		if owner.PLUS_DEBUG then
			LOG("traveler search: scanning for pilot "..id..
				" with timelines == " .. (data.prevTimelines + 1) ..
				", xp == " .. data.xp .. ", level == " .. data.level)
		end

		local structDef = memhack.dll.scanner.StructSearch.new(string.byte(id:sub(1,1)), PilotLayout.id.offset)
		structDef:addField(PilotLayout.xp.offset, "int", data.xp)
		structDef:addField(PilotLayout.level.offset, "int", data.level)
		structDef:addField(PilotLayout.prevTimelines.offset, "int", data.prevTimelines + 1)
		structDef:addField(PilotLayout.id.offset, "string", id)

		local results = scanner:firstScan("exact", structDef)

		if owner.PLUS_DEBUG then
			LOG("traveler search: found " .. results.resultCount .. " matches")
		end

		if results.resultCount > 0 then
			local matches = scanner:getResults({limit = 1})
			local baseAddr = matches.results[1].address
			if owner.PLUS_DEBUG then LOG("traveler search: setting to found pilot at " .. string.format("0x%X", baseAddr)) end
			-- TODO: store time treaveler here
			time_traveler.timeTraveler = memhack.structs.Pilot.new(baseAddr)
			break
		end

		scanner:reset()
	end
end

-- Search for time traveler in current pilot structs
function time_traveler.searchForTimeTraveler()
	if time_traveler.pilotStructs then
		if owner.PLUS_DEBUG then LOG("traveler search: Checking cached pilots") end
		for _, pilot in pairs(time_traveler.pilotStructs) do
			local pilotData = time_traveler.lastSavedPersistentData[pilot:getIdStr()]
			if owner.PLUS_DEBUG then LOG("traveler search: ".. pilot:getPrevTimelines() .. " - " .. pilotData.prevTimelines + 1) end
			if pilot:getPrevTimelines() == pilotData.prevTimelines + 1 then
				time_traveler.timeTraveler = pilot
				if owner.PLUS_DEBUG then LOG("PLUS Ext: Found time traveler! ".. pilot:getIdStr()) end
			end
		end
	else
		if owner.PLUS_DEBUG then LOG("traveler search: No cached pilots; Scanning for pilot") end
		time_traveler.scanForTimeTraveler()
	end
end

return time_traveler
