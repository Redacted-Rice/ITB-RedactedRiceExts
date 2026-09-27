-- Pilot instance unique ID separate from Pilot ID to allow for
-- multiple pilots with the same Pilot ID. This is per instance
-- of a pilot.
--
-- Identity is the saveVal pair on lvl-up skills (vanilla save/load),
-- expressed as pilotId:sv1:sv2. Same UID = same pilot (including when
-- the game recreates wrappers on turn reset).
--
-- External API (safe to call from anywhere):
--   Pilot.getUidStr()              — read only. Never mints or walks pilots
--   getAvailablePilotsWithUids()   — walk pilots and remint duplicate UIDs
--   ensureUniqueAmongAvailable(p)  — remint pilot if it collides with available pilots
--
-- Internal helpers must not call external resolve APIs to avoid infinite loops.
-- Re-entrant resolve returns the in progress entries/claimed snapshot.

local pilot_uid = {}

local logger = memhack.logger
local SUBMODULE = logger.register("CPLUS+", "PilotUid", cplus_plus_ex.DEBUG.PILOT_UID and cplus_plus_ex.DEBUG.ENABLED)

local SAVE_VAL_MIN = 0
local SAVE_VAL_MAX = 13
local MINT_MAX_ATTEMPTS = 1000

-- In progress resolve snapshot (nil when not resolving)
local _resolvingAvailable = false
local _resolveEntries = nil
local _resolveClaimed = nil

function pilot_uid:init()
	local Pilot = memhack.structs.Pilot
	Pilot.getUidStr = function(pilot)
		return pilot_uid:_readUid(pilot)
	end

	return self
end

------------------------------------------------------------------------
-- Internal helpers
------------------------------------------------------------------------

function pilot_uid:_makePilotUid(pilotId, sv1, sv2)
	return string.format("%s:%d:%d", pilotId, sv1, sv2)
end

function pilot_uid:_readSaveValPair(pilot)
	return pilot:getLvlUpSkill(1):getSaveVal(), pilot:getLvlUpSkill(2):getSaveVal()
end

-- Read only UID from saveVals
function pilot_uid:_readUid(pilot)
	if type(pilot) ~= "table" or getmetatable(pilot) ~= memhack.structs.Pilot then
		logger.logError(SUBMODULE, "_readUid: expected Pilot struct, got %s", type(pilot))
		return nil
	end

	local pilotId = pilot:getIdStr()
	local sv1, sv2 = self:_readSaveValPair(pilot)
	return self:_makePilotUid(pilotId, sv1, sv2)
end

-- Mint random unused saveVals against the passed claimed set.
function pilot_uid:_mintUniqueUid(pilot, claimedUids)
	local pilotId = pilot:getIdStr()

	for _ = 1, MINT_MAX_ATTEMPTS do
		local sv1 = math.random(SAVE_VAL_MAX - SAVE_VAL_MIN + 1) - 1 + SAVE_VAL_MIN
		local sv2 = math.random(SAVE_VAL_MAX - SAVE_VAL_MIN + 1) - 1 + SAVE_VAL_MIN
		local uid = self:_makePilotUid(pilotId, sv1, sv2)
		if not claimedUids[uid] then
			pilot:getLvlUpSkill(1):_setSaveVal_noFire(sv1)
			pilot:getLvlUpSkill(2):_setSaveVal_noFire(sv2)
			claimedUids[uid] = true
			logger.logInfo(SUBMODULE, "minted UID %s", uid)
			return uid
		end
	end

	logger.logError(SUBMODULE, "_mintUniqueUid: failed to find free UID for %s after %d attempts",
			pilotId, MINT_MAX_ATTEMPTS)
	return nil
end

-- Claim current UID or mint on conflict
function pilot_uid:_claimOrMintUid(pilot, claimedUids)
	local uid = self:_readUid(pilot)
	if claimedUids[uid] then
		logger.logInfo(SUBMODULE, "UID conflict %s for %s; minting", uid, pilot:getIdStr())
		return self:_mintUniqueUid(pilot, claimedUids)
	end
	claimedUids[uid] = true
	return uid
end

-- Walk available pilots building claimed set.
-- Re-entrant calls return the in progress snapshot to avoid infinite loops
function pilot_uid:_resolveAvailablePilots()
	if _resolvingAvailable then
		logger.logWarn(SUBMODULE, "_resolveAvailablePilots re-entered. Returning in progress snapshot")
		return _resolveEntries, _resolveClaimed
	end

	local pilots = (Game and Game:GetAvailablePilots()) or {}
	_resolvingAvailable = true
	_resolveClaimed = {}
	_resolveEntries = {}

	for _, pilot in pairs(pilots) do
		local uid = self:_claimOrMintUid(pilot, _resolveClaimed)
		table.insert(_resolveEntries, {pilot = pilot, uid = uid})
	end

	local entries, claimedUids = _resolveEntries, _resolveClaimed
	_resolvingAvailable = false
	_resolveEntries = nil
	_resolveClaimed = nil

	return entries, claimedUids
end

------------------------------------------------------------------------
-- External API
------------------------------------------------------------------------

-- Returns array of {pilot=, uid=} with UID conflicts already reminted
function pilot_uid:getAvailablePilotsWithUids()
	local entries, _ = self:_resolveAvailablePilots()
	logger.logDebug(SUBMODULE, "getAvailablePilotsWithUids: %d pilots", #entries)
	return entries
end

-- Remint pilot if its UID collides with any currently available pilot.
-- Used for pod/perfect island rewards not in the available list yet.
function pilot_uid:ensureUniqueAmongAvailable(pilot)
	if type(pilot) ~= "table" or getmetatable(pilot) ~= memhack.structs.Pilot then
		logger.logError(SUBMODULE, "ensureUniqueAmongAvailable: expected Pilot struct, got %s", type(pilot))
		return nil
	end

	local _, claimedUids = self:_resolveAvailablePilots()
	return self:_claimOrMintUid(pilot, claimedUids)
end

return pilot_uid
