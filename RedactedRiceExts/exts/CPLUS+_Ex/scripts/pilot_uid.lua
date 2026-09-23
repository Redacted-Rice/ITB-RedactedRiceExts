-- Pilot instance unique ID separate from Pilot ID to allow for
-- multiple pilots with the same Pilot ID. This is per instance
-- of a pilot.
--
-- Identity is always the saveVal pair on lvl-up skills (vanilla save/load).
-- On load: match saveVals to GAME.cplus_plus_ex data, or mint if missing.
-- New pilot during run: mint unused saveVal pair via skill_selection.

local pilot_uid = {}

local logger = memhack.logger
local SUBMODULE = logger.register("CPLUS+", "PilotUid", cplus_plus_ex.DEBUG.SELECTION and cplus_plus_ex.DEBUG.ENABLED)

local SAVE_VAL_MIN = 0
local SAVE_VAL_MAX = 13
local SAVE_VAL_SPAN = SAVE_VAL_MAX - SAVE_VAL_MIN + 1
local SAVE_VAL_KEY_MAX = SAVE_VAL_MAX + SAVE_VAL_MAX * SAVE_VAL_SPAN
local SAVE_VAL_KEY_COUNT = SAVE_VAL_KEY_MAX + 1

-- sv1 + sv2*14 -> pilot that owns it (cleared on game load)
pilot_uid._usedSaveValKeys = {}
pilot_uid._usedSaveValKeyList = {}
pilot_uid._usedSaveValKeyCount = 0

function pilot_uid:init()
	self:resetTracking()

	local Pilot = memhack.structs.Pilot
	Pilot.getUidStr = function(pilot)
		return pilot_uid:_ensurePilotUid(pilot)
	end

	return self
end

function pilot_uid:resetTracking()
	self._usedSaveValKeys = {}
	self._usedSaveValKeyList = {}
	self._usedSaveValKeyCount = 0
end

function pilot_uid:_saveValPairToKey(sv1, sv2)
	return sv1 + sv2 * SAVE_VAL_SPAN
end

function pilot_uid:_keyToSaveValPair(key)
	local sv2 = math.floor(key / SAVE_VAL_SPAN)
	local sv1 = key % SAVE_VAL_SPAN
	return sv1, sv2
end

-- Map a draw in the compressed range back to an unused saveVal key.
function pilot_uid:_mapDrawToKey(draw)
	local index = draw
	for i = 1, self._usedSaveValKeyCount do
		if index >= self._usedSaveValKeyList[i] then
			index = index + 1
		end
	end
	return index
end

function pilot_uid:_registerPilotUid(pilot)
	local sv1, sv2 = self:_readSaveValPair(pilot)
	local key = self:_saveValPairToKey(sv1, sv2)
	if self._usedSaveValKeys[key] ~= nil then
		logger.logError(SUBMODULE, "_registerUid: key %d already registered to pilot %s - overwritting to pilot %s",
				key, self._usedSaveValKeys[key]:getUidStr(), pilot:getUidStr())
		self._usedSaveValKeys[key] = pilot
		return
	end

	-- Insert it in our lookup table
	self._usedSaveValKeys[key] = pilot

	-- And out minting list
	local list = self._usedSaveValKeyList
	for i = 1, #list do
		if list[i] > key then
			table.insert(list, i, key)
			self._usedSaveValKeyCount = self._usedSaveValKeyCount + 1
			return
		end
	end
	list[#list + 1] = key
	-- And our count
	self._usedSaveValKeyCount = self._usedSaveValKeyCount + 1
end

function pilot_uid:_getPilotUidOwner(pilot)
	local sv1, sv2 = self:_readSaveValPair(pilot)
	return self._usedSaveValKeys[self:_saveValPairToKey(sv1, sv2)]
end

function pilot_uid:_isPilotRegistered(pilot)
	local owner = self:_getPilotUidOwner(pilot)
	return owner ~= nil and owner == pilot
end

function pilot_uid:_isPilotUinque(pilot)
	local owner = self:_getPilotUidOwner(pilot)
	return owner == nil or owner == pilot
end

function pilot_uid:_makePilotUid(pilotId, sv1, sv2)
	return string.format("%s:%d:%d", pilotId, sv1, sv2)
end

function pilot_uid:_readSaveValPair(pilot)
	return pilot:getLvlUpSkill(1):getSaveVal(), pilot:getLvlUpSkill(2):getSaveVal()
end

-- TODO: See about removing
function pilot_uid:_ensureGameTables()
	if GAME == nil then
		GAME = {}
	end
	if GAME.cplus_plus_ex == nil then
		GAME.cplus_plus_ex = {}
	end
	GAME.cplus_plus_ex.pilotSkills = GAME.cplus_plus_ex.pilotSkills or {}
	GAME.cplus_plus_ex.pilotVirtualSkills = GAME.cplus_plus_ex.pilotVirtualSkills or {}
end

function pilot_uid:_mintAndBind(pilot)
	local pilotId = pilot:getIdStr()
	local range = SAVE_VAL_KEY_COUNT - self._usedSaveValKeyCount

	if range <= 0 then
		logger.logError(SUBMODULE, "_mintAndBind: exhausted all saveVal keys")
		return 0, 1, self:_makePilotUid(pilotId, 0, 1)
	end

	local draw = math.random(range) - 1
	local key = self:_mapDrawToKey(draw)
	local sv1, sv2 = self:_keyToSaveValPair(key)

	-- Use noFire so UID minting does not look like a skill change.
	pilot:getLvlUpSkill(1):_setSaveVal_noFire(sv1)
	pilot:getLvlUpSkill(2):_setSaveVal_noFire(sv2)

	self:_registerPilotUid(pilot)
	local uid = self:_makePilotUid(pilotId, sv1, sv2)
	logger.logInfo(SUBMODULE, "minted, registered, and bound UID %s", uid)
	return uid
end

-- Return saveVal UID on pilot, or mint a new one for a new pilot.
function pilot_uid:_ensurePilotUid(pilot)
	if type(pilot) ~= "table" or getmetatable(pilot) ~= memhack.structs.Pilot then
		logger.logError(SUBMODULE, "_ensurePilotUid: expected Pilot struct, got %s", type(pilot))
		return nil
	end

	local sv1, sv2 = self:_readSaveValPair(pilot)
	local currUid = self:_makePilotUid(pilot:getIdStr(), sv1, sv2)

	-- If its already registered, return the UID.
	if self:_isPilotRegistered(pilot) then
		return currUid
	elseif self:_isPilotUinque(pilot) then
		-- If its unique, register it and return the UID.
		self:_registerPilotUid(pilot)
		logger.logDebug(SUBMODULE, "_ensurePilotUid registering UID %s", currUid)
		return currUid
	else
		-- If its not unique, mint a new one and return it.
		return self:_mintAndBind(pilot)
	end
end

return pilot_uid
