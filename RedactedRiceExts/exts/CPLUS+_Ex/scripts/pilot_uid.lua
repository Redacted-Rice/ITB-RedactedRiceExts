-- Pilot instance unique ID separate from Pilot ID to allow for
-- multiple pilots with the same Pilot ID. This is per instance
-- of a pilot.
--
-- Identity is the saveVal pair on lvl-up skills (vanilla save/load),
-- expressed as pilotId:sv1:sv2. Same UID = same pilot (including when
-- the game recreates wrappers on turn reset)

local pilot_uid = {}

local logger = memhack.logger
local SUBMODULE = logger.register("CPLUS+", "PilotUid", cplus_plus_ex.DEBUG.PILOT_UID and cplus_plus_ex.DEBUG.ENABLED)

function pilot_uid:init()
	local Pilot = memhack.structs.Pilot
	Pilot.getUidStr = function(pilot)
		return pilot_uid:_ensurePilotUid(pilot)
	end

	return self
end

function pilot_uid:_makePilotUid(pilotId, sv1, sv2)
	return string.format("%s:%d:%d", pilotId, sv1, sv2)
end

function pilot_uid:_readSaveValPair(pilot)
	return pilot:getLvlUpSkill(1):getSaveVal(), pilot:getLvlUpSkill(2):getSaveVal()
enabled

-- Return saveVal UID on pilot
function pilot_uid:_ensurePilotUid(pilot)
	if type(pilot) ~= "table" or getmetatable(pilot) ~= memhack.structs.Pilot then
		logger.logError(SUBMODULE, "_ensurePilotUid: expected Pilot struct, got %s", type(pilot))
		return nil
	end

	local pilotId = pilot:getIdStr()
	local sv1, sv2 = self:_readSaveValPair(pilot)
	local uid = self:_makePilotUid(pilotId, sv1, sv2)
	logger.logDebug(SUBMODULE, "uid %s @%s", uid, tostring(addr))
	return uid
end

return pilot_uid
