cplus_plus_ex = {
	PLUS_DEBUG = true, -- eventually default to false
	VANILLA_SKILLS = {
		{id = "Health", shortName = "Pilot_HealthShort", fullName = "Pilot_HealthName", description= "Pilot_HealthDesc", bonuses = {health = 2}, saveVal = 0 },
		{id = "Move", shortName = "Pilot_MoveShort", fullName = "Pilot_MoveName", description= "Pilot_MoveDesc", bonuses = {move = 1}, saveVal = 1 },
		{id = "Grid", shortName = "Pilot_GridShort", fullName = "Pilot_GridName", description= "Pilot_GridDesc", bonuses = {grid = 3}, saveVal = 2 },
		{id = "Reactor", shortName = "Pilot_ReactorShort", fullName = "Pilot_ReactorName", description= "Pilot_ReactorDesc", bonuses = {cores = 1}, saveVal = 3 },
		{id = "Opener", shortName = "Pilot_OpenerName", fullName = "Pilot_OpenerName", description= "Pilot_OpenerDesc", saveVal = 4 },
		{id = "Closer", shortName = "Pilot_CloserName", fullName = "Pilot_CloserName", description= "Pilot_CloserDesc", saveVal = 5 },
		{id = "Popular", shortName = "Pilot_PopularName", fullName = "Pilot_PopularName", description= "Pilot_PopularDesc", saveVal = 6 },
		{id = "Thick", shortName = "Pilot_ThickName", fullName = "Pilot_ThickName", description= "Pilot_ThickDesc", saveVal = 7 },
		{id = "Skilled", shortName = "Pilot_SkilledName", fullName = "Pilot_SkilledName", description= "Pilot_SkilledDesc", bonuses = {health = 2, move = 1}, saveVal = 8 },
		{id = "Invulnerable", shortName = "Pilot_InvulnerableName", fullName = "Pilot_InvulnerableName", description= "Pilot_InvulnerableDesc", saveVal = 9 },
		{id = "Adrenaline", shortName = "Pilot_AdrenalineName", fullName = "Pilot_AdrenalineName", description= "Pilot_AdrenalineDesc", saveVal = 10 },
		{id = "Pain", shortName = "Pilot_PainName", fullName = "Pilot_PainName", description= "Pilot_PainDesc", saveVal = 11 },
		{id = "Regen", shortName = "Pilot_RegenName", fullName = "Pilot_RegenName", description= "Pilot_RegenDesc", saveVal = 12 },
		{id = "Conservative", shortName = "Pilot_ConservativeName", fullName = "Pilot_ConservativeName", description= "Pilot_ConservativeDesc", saveVal = 13 },
	},
	_registeredSkills = {},  -- category -> skillId -> {shortName, fullName, description, bonuses, skillType}
	_registeredSkillsIds = {},  -- skillId -> category
	_enabledSkills = {},  -- skillId -> {shortName, fullName, description, bonuses, skillType}
	_enabledSkillsIds = {},  -- Array of all enabled skill IDs
	_pilotSkillExclusionsAuto = {},  -- pilotId -> excluded skill ids (set-like table) - auto-loaded from pilot Blacklists
	_pilotSkillExclusionsManual = {},  -- pilotId -> excluded skill ids (set-like table) - manually registered via API
	_pilotSkillInclusions = {},  -- pilotId -> included skill ids (set-like table)
	_constraintFunctions = {},  -- Array of function(pilot, selectedSkills, candidateSkillId) -> boolean
	_localRandomCount = nil  -- Track local random count for this session
}

function cplus_plus_ex:initGameStorage()
	if GAME == nil then
		return
	end

	if GAME.cplus_plus_ex == nil then
		GAME.cplus_plus_ex = {}
	end

	if GAME.cplus_plus_ex.pilotSkills == nil then
		GAME.cplus_plus_ex.pilotSkills = {}
	end

	if GAME.cplus_plus_ex.randomSeed == nil then
		-- Initialize with a seed based on os.time()
		GAME.cplus_plus_ex.randomSeed = os.time()
	end

	if GAME.cplus_plus_ex.randomSeedCnt == nil then
		GAME.cplus_plus_ex.randomSeedCnt = 0
	end

	-- reset our local count to force a re-roll to ensure we
	-- stay inline
	self._localRandomCount = nil
end

-- Registers all vanilla skills
function cplus_plus_ex:registerVanilla()
	-- Register all vanilla skills
	for _, skill in ipairs(self.VANILLA_SKILLS) do
		self:registerSkill("vanilla", skill)
	end
end

-- Scans global for all pilot definitions and registers their Blacklist exclusions
-- This maintains the vanilla method of defining pilot exclusions to be compatible
-- without any specific changes for using this extension
function cplus_plus_ex:registerPilotExclusionsFromGlobal()
	-- Clear only auto-loaded exclusions
	self._pilotSkillExclusionsAuto = {}

	if _G.Pilot == nil then
		if self.PLUS_DEBUG then
			LOG("PLUS Ext: Error: Pilot class not found, skipping exclusion registration")
		end
		return
	end

	local pilotCount = 0
	local exclusionCount = 0

	-- Scan _G for all Pilot instances using metatable check
	-- This assumes all pilots are created via Pilot:new (e.g. via CreatePilot()) which
	-- will automatically set the metatable to Pilot
	for key, value in pairs(_G) do
		if type(key) == "string" and type(value) == "table" and getmetatable(value) == _G.Pilot then
			pilotCount = pilotCount + 1

			-- Check if the pilot has a Blacklist array
			if value.Blacklist ~= nil and type(value.Blacklist) == "table" and #value.Blacklist > 0 then
				-- Register the blacklist as auto loaded exclusions
				self:registerPilotSkillExclusions(key, value.Blacklist, true)
				exclusionCount = exclusionCount + 1

				if self.PLUS_DEBUG then
					LOG("PLUS Ext: Found " .. #value.Blacklist .. " exclusion(s) for pilot " .. key)
				end
			end
		end
	end

	if self.PLUS_DEBUG then
		LOG("PLUS Ext: Scanned " .. pilotCount .. " pilot(s), registered exclusions for " .. exclusionCount .. " pilot(s)")
	end
end

-- Registers a constraint function for skill assignment
-- These functions take pilot, selectedSkills, and candidateSkillId and return true if the candidateskill can be assigned to the pilot
--   pilot - The memhack pilot struct
--   selectedSkills - Array like table of skill IDs that have already been selected for this pilot
--   candidateSkillId - The skill ID being considered for assignment
-- The default pilot inclusion/exclusion and duplicate prevention use this same function. These can be
-- used as examples for using constraint functions
function cplus_plus_ex:registerConstraintFunction(constraintFn)
	table.insert(self._constraintFunctions, constraintFn)
	if self.PLUS_DEBUG then
		LOG("PLUS Ext: Registered constraint function")
	end
end

-- Helper function to register pilot-skill relationships
-- targetTable: either _pilotSkillExclusionsAuto, _pilotSkillExclusionsManual, or _pilotSkillInclusions
-- relationshipType: "exclusion" or "inclusion" (for debug logging)
-- isAuto: true if auto-loaded, false if manual (for debug logging)
local function registerPilotSkillRelationship(self, targetTable, pilotId, skillIds, relationshipType, isAuto)
	if targetTable[pilotId] == nil then
		targetTable[pilotId] = {}
	end

	for _, skillId in ipairs(skillIds) do
		-- store with skillId as key so it acts like a set
		targetTable[pilotId][skillId] = true

		if self.PLUS_DEBUG then
			local action = relationshipType == "exclusion" and "cannot have" or "can have"
			local source = isAuto and " (auto)" or " (manual)"
			LOG("PLUS Ext: Registered " .. relationshipType .. source .. " - Pilot " .. pilotId .. " " .. action .. " skill " .. skillId)
		end
	end
end

-- Registers pilot skill exclusions
-- Takes pilot id and list of skill ids to exclude
-- isAuto true if auto-loaded from pilot Blacklist, false/nil if manually registered via API. Defaults to false
function cplus_plus_ex:registerPilotSkillExclusions(pilotId, skillIds, isAuto)
	isAuto = isAuto or false
	local targetTable = isAuto and self._pilotSkillExclusionsAuto or self._pilotSkillExclusionsManual
	registerPilotSkillRelationship(self, targetTable, pilotId, skillIds, "exclusion", isAuto)
end

-- Registers pilot skill inclusions
-- Takes pilot id and list of skill ids to include
-- This is only needed for specific inclusion skills. Any default
-- enabled, non-excluded skill will be available as well as any added here
function cplus_plus_ex:registerPilotSkillInclusions(pilotId, skillIds)
	registerPilotSkillRelationship(self, self._pilotSkillInclusions, pilotId, skillIds, "inclusion", false)
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

-- saveVal is optional and must be between 0-13 (vanilla range). This will be used so if
-- the extension fails to load or is uninstalled, a suitable vanilla skill will be used
-- instead. If not provided or out of range, a random vanilla value will be used.
-- The save data in vanilla only supports 0-13. Anything out of range is clamped to this range
function cplus_plus_ex:registerSkill(category, idOrTable, shortName, fullName, description, bonuses, skillType, saveVal)

	if self._registeredSkills[category] == nil then
		self._registeredSkills[category] = {}
	end

	local id = idOrTable
	if type(idOrTable) == "table" then
		id = idOrTable.id
		shortName = idOrTable.shortName
		fullName = idOrTable.fullName
		description = idOrTable.description
		bonuses = idOrTable.bonuses
		skillType = idOrTable.skillType
		saveVal = idOrTable.saveVal
	end

	-- Check if ID is already registered globally
	if self._registeredSkillsIds[id] ~= nil then
		self:logAndShowErrorPopup("PLUS Ext error: Skill ID '" .. id .. "' in category '" .. category .. "' conflicts with existing skill from category '" .. self._registeredSkillsIds[id] .. "'.")
		return
	end

	-- Validate and normalize saveVal
	-- Default to -1 if not provided
	local originalSaveVal = saveVal
	saveVal = saveVal or -1
	-- Convert non-numbers or values outside 0-13 range to -1 (random assignment)
	if type(saveVal) ~= "number" or saveVal < 0 or saveVal > 13 then
		if originalSaveVal ~= nil and originalSaveVal ~= -1 then
			LOG("PLUS Ext: Warning: Skill '" .. id .. "' has invalid saveVal '" .. tostring(originalSaveVal) .. "' (must be 0-13 or -1). Using random assignment (-1) instead.")
		end
		saveVal = -1
	end

	-- Register the skill with its type included in the skill data
	self._registeredSkills[category][id] = { shortName = shortName, fullName = fullName, description = description,
			bonuses = bonuses or {},
			skillType = skillType or "default",
			saveVal = saveVal,
	}
	self._registeredSkillsIds[id] = category
end

function cplus_plus_ex:enableCategory(category)
	if self._registeredSkills[category] == nil then
		LOG("PLUS Ext error: Attempted to enable unknown category ".. category)
		return
	end
	for id, skill in pairs(self._registeredSkills[category]) do
		-- Check if already enabled
		if self._enabledSkills[id] ~= nil then
			LOG("PLUS Ext warning: Skill " .. id .. " already enabled, skipping")
		else
			-- Add the skill to enabled list. We don't care at this point if its inclusion type or not
			self._enabledSkills[id] = skill
			table.insert(self._enabledSkillsIds, id)

			if self.PLUS_DEBUG then
				local skillType = skill.skillType or "default"
				LOG("PLUS Ext: Enabled skill: " .. id .. " (type: " .. skillType .. ")")
			end
		end
	end
end

-- Uses the stored seed and sequential access count to ensure deterministic random values
-- The RNG is seeded once per session, then we fast forward to the saved count
-- skillsList - array like table of skill IDs to select from
function cplus_plus_ex:getRandomSkillId(skillsList)
	if #skillsList == 0 then
		LOG("PLUS Ext error: No skills available in list")
		return nil
	end

	-- Get the stored seed and count from GAME
	local seed = GAME.cplus_plus_ex.randomSeed
	local savedCount = GAME.cplus_plus_ex.randomSeedCnt

	-- If this is the first call this session, initialize the RNG to match
	-- what is in our saved data
	if self._localRandomCount == nil then
		math.randomseed(seed)
		for i = 1, savedCount do
			math.random()
		end
		self._localRandomCount = savedCount
		if self.PLUS_DEBUG then LOG("PLUS Ext: Initialized RNG with seed " .. seed .. " and fast-forwarded " .. savedCount .. " times") end
	end

	-- Generate the next random index in the range of available skills
	local index = math.random(1, #skillsList)

	-- Increment both local and saved count
	self._localRandomCount = self._localRandomCount + 1
	GAME.cplus_plus_ex.randomSeedCnt = self._localRandomCount

	return skillsList[index]
end

-- Selects random level up skills based on count and configured constraints
-- Returns a array like table of skill IDs that satisfy the constraints
-- I pass count even though its currently only expected to be 2 just because I feel
-- like it could be interesting and possible to have pilots with more than two skills
function cplus_plus_ex:selectRandomSkills(pilot, count)
	if #self._enabledSkillsIds == 0 then
		LOG("PLUS Ext error: No enabled skills available")
		return nil
	end

	if count > #self._enabledSkillsIds then
		LOG("PLUS Ext error: Cannot select " .. count .. " skills from " .. #self._enabledSkillsIds .. " available skills")
		return nil
	end

	local selectedSkills = {}

	-- Create a copy of all available skill IDs as an array. This will be our
	-- base list and we will narrow it down as we go if we try to assign
	-- an unallowed skill
	local availableSkills = {}
	for _, skillId in ipairs(self._enabledSkillsIds) do
		table.insert(availableSkills, skillId)
	end

	-- Keep selecting until we have enough skills or run out of options
	while #selectedSkills < count and #availableSkills > 0 do
		-- Get a random skill from the available pool
		local candidateSkillId = self:getRandomSkillId(availableSkills)

		if candidateSkillId == nil then
			return nil
		end

		if self:checkSkillConstraints(pilot, selectedSkills, candidateSkillId) then
			-- If valid, add to the selected but do not remove yet
			-- ALlows for potential duplicates in the future
			table.insert(selectedSkills, candidateSkillId)
		else
			-- If the skill is invalid, remove it from the pool
			for i, skillId in ipairs(availableSkills) do
				if skillId == candidateSkillId then
					table.remove(availableSkills, i)
					break
				end
			end
		end
	end

	-- Check we assigned the expected number of skill
	if #selectedSkills ~= count then
		LOG("PLUS Ext error: Failed to select " .. count .. " skills. Selected " .. #selectedSkills .. ". Constraints may be impossible to satisfy with available skills.")
		return nil
	end
	return selectedSkills
end

-- Checks if a skill can be assigned to the given pilot
-- using all registered constraint functions
-- Returns true if all constraints pass, false otherwise
function cplus_plus_ex:checkSkillConstraints(pilot, selectedSkills, candidateSkillId)
	-- Check all constraint functions
	for _, constraintFn in ipairs(self._constraintFunctions) do
		if not constraintFn(pilot, selectedSkills, candidateSkillId) then
			return false
		end
	end
	return true
end

-- Registers a constraint fn that prevents duplicate skills
-- Ensures that the same skill is not assigned to multiple slots for a pilot
-- I making preventing duplicates a constraint because I could see a case for allowing
-- duplicates. Some vanilla skills and custom skills could certainly allow duplicates
function cplus_plus_ex:registerNoDupsConstraintFunction()
	self:registerConstraintFunction(function(pilot, selectedSkills, candidateSkillId)
		-- Check if this skill has already been selected
		for _, skillId in ipairs(selectedSkills) do
			if skillId == candidateSkillId then
				if self.PLUS_DEBUG then LOG("PLUS Ext: Prevented duplicate add of skill ".. candidateSkillId.. " on pilot "..pilot:getIdStr()) end
				return false
			end
		end
		return true
	end)
end

-- Registers the built-in exclusion and inclusion constraint function for pilot skills
-- so we can handle them easily similar to how vanilla does it
function cplus_plus_ex:registerPlusExclusionInclusionConstraintFunction()
	self:registerConstraintFunction(function(pilot, selectedSkills, candidateSkillId)
		local pilotId = pilot:getIdStr()

		-- Get the skill object to check its type
		local skill = self._enabledSkills[candidateSkillId]

		if skill == nil then
			LOG("PLUS Ext warning: Skill " .. candidateSkillId .. " not found in enabled skills")
			return false
		end

		-- For inclusion skills check if pilot is in inclusion list
		-- For default skills check if pilot is NOT in exclusion list (must be absent)
		local isInclusionSkill = skill.skillType == "inclusion"

		if isInclusionSkill then
			-- Check inclusion list
			local pilotList = self._pilotSkillInclusions[pilotId]
			local skillInList = pilotList and pilotList[candidateSkillId]
			local allowed = skillInList == true
			if not allowed and self.PLUS_DEBUG then
				LOG("PLUS Ext: Prevented inclusion skill " .. candidateSkillId .. " for pilot " .. pilotId)
			end
			return allowed
		else
			-- Check both auto and manual exclusion lists
			local autoExcluded = self._pilotSkillExclusionsAuto[pilotId] and self._pilotSkillExclusionsAuto[pilotId][candidateSkillId]
			local manualExcluded = self._pilotSkillExclusionsManual[pilotId] and self._pilotSkillExclusionsManual[pilotId][candidateSkillId]
			local excluded = autoExcluded or manualExcluded
			if excluded and self.PLUS_DEBUG then
				LOG("PLUS Ext: Prevented exclusion " .. (autoExcluded and "(auto)" or "") .. (manualExcluded and "(manual)" or "") .. " skill " .. candidateSkillId .. " for pilot " .. pilotId)
			end
			return not excluded
		end
	end)
end

-- Main function to apply level up skills to a pilot (handles both skill slots)
-- Takes a memhack pilot struct and applies both skill slots (1 and 2)
-- Checks GAME memory and either loads existing skills or creates and assigns new ones
function cplus_plus_ex:applySkillsToPilot(pilot)
	if pilot == nil then
		LOG("PLUS Ext error: Pilot is nil")
		return
	end

	-- Use pilot ID as the key for storing skills for now. Multiple pilots with same ID is
	-- technically possible but not allowed by vanilla so this may change later
	local pilotId = pilot:getIdStr()

	-- Try to get stored skills
	local storedSkills = GAME.cplus_plus_ex.pilotSkills[pilotId]

	-- If the skills are not stored, we need to assign them
	if storedSkills == nil then
		-- Select 2 random skills that satisfy all registered constraint functions
		storedSkills = self:selectRandomSkills(pilot, 2)
		if storedSkills == nil then
			return
		end

		-- Store the skills in GAME
		GAME.cplus_plus_ex.pilotSkills[pilotId] = storedSkills

		if self.PLUS_DEBUG then
			LOG("PLUS Ext: Assigning random skills to pilot " .. pilotId .. ": [" .. storedSkills[1] .. ", " .. storedSkills[2] .. "]")
		end
	else
		if self.PLUS_DEBUG then
			LOG("PLUS Ext: Applying stored skills to pilot " .. pilotId .. ": [" .. storedSkills[1] .. ", " .. storedSkills[2] .. "]")
		end
	end

	local skill1Id = storedSkills[1]
	local skill2Id = storedSkills[2]
	local skill1 = self._enabledSkills[skill1Id]
	local skill2 = self._enabledSkills[skill2Id]

	-- Determine saveVal for skill 1
	-- If skill has saveVal = -1, assign random value (0-13)
	local saveVal1 = skill1.saveVal
	if saveVal1 == -1 then
		saveVal1 = math.random(0, 13)
		if self.PLUS_DEBUG then
			LOG("PLUS Ext: Assigned random saveVal " .. saveVal1 .. " to skill " .. skill1Id .. " for pilot " .. pilotId)
		end
	end

	-- Determine saveVal for skill 2
	-- If skill has saveVal = -1, assign random value (0-13)
	local saveVal2 = skill2.saveVal
	if saveVal2 == -1 then
		saveVal2 = math.random(0, 13)
		if self.PLUS_DEBUG then
			LOG("PLUS Ext: Assigned random saveVal " .. saveVal2 .. " to skill " .. skill2Id .. " for pilot " .. pilotId)
		end
	end

	-- If both skills have the same saveVal, reassign skill2
	if saveVal1 == saveVal2 then
		-- Generate from 0-12, increment if >= saveVal1 to exclude skill1's value
		-- This guarantees a different value
		saveVal2 = math.random(0, 12)
		if saveVal2 >= saveVal1 then
			saveVal2 = saveVal2 + 1
		end
		if self.PLUS_DEBUG then
			LOG("PLUS Ext: SaveVal conflict detected for pilot " .. pilotId .. ", reassigned skill2 saveVal to " .. saveVal2)
		end
	end

	-- Apply both skills with their determined saveVal
	pilot:setLvlUpSkill(1, skill1Id, skill1.shortName, skill1.fullName, skill1.description, saveVal1, skill1.bonuses)
	pilot:setLvlUpSkill(2, skill2Id, skill2.shortName, skill2.fullName, skill2.description, saveVal2, skill2.bonuses)
end

-- Helper function to get all pilots in the current squad
function cplus_plus_ex:getAllPilots()
	local pilots = {}

	-- Iterate through the 3 squad positions (0, 1, 2)
	for i = 0, 2 do
		local pawnId = i  -- Pawn IDs correspond to squad positions
		local pawn = Game:GetPawn(pawnId)

		if pawn ~= nil then
			local pilot = pawn:GetPilot()
			if pilot ~= nil then
				table.insert(pilots, {pilot = pilot, index = i})
			end
		end
	end

	return pilots
end

-- Apply skills to all pilots in the squad
function cplus_plus_ex:applySkillsToAllPilots()
	if #self._enabledSkillsIds == 0 then
		if self.PLUS_DEBUG then LOG("PLUS Ext: No enabled skills, skipping pilot skill assignment") end
		return
	end

	-- Apply/assign skills for each pilot
	local pilots = self:getAllPilots()
	for _, pilotData in ipairs(pilots) do
		self:applySkillsToPilot(pilotData.pilot)
	end

	if self.PLUS_DEBUG then LOG("PLUS Ext: Applied skills to " .. #pilots .. " pilot(s)") end
end

-- Event handler for when the game is entered (loaded or new game)
function cplus_plus_ex:onGameEntered()
	self:initGameStorage()
	if self.PLUS_DEBUG then LOG("PLUS Ext: Game entered, storage initialized") end

	-- Regbister/refresh pilot exclusions from their global definitions
	self:registerPilotExclusionsFromGlobal()

	self:applySkillsToAllPilots()
end

function cplus_plus_ex:init()
	-- Register vanilla skills
	self:registerVanilla()

	-- Register built-in constraint functions
	self:registerNoDupsConstraintFunction()  -- Prevents same skill in multiple slots
	self:registerPlusExclusionInclusionConstraintFunction()  -- Checks pilot exclusions and inclusion-type skills

	-- TODO: Temp. Long term control via options or other configs?
	self:enableCategory("vanilla")

	-- Subscribe to game events
	modApi.events.onGameEntered:subscribe(function()
		cplus_plus_ex:onGameEntered()
	end)

	if self.PLUS_DEBUG then LOG("PLUS Ext: Initialized and subscribed to game events") end
end