local plus_manager = {
	PLUS_DEBUG = nil,
	_cplus_plus_ex = nil,
	allowReusableSkills = false, -- will be set on load by options but default to vanilla
	VANILLA_SKILLS = {
		{id = "Health", shortName = "Pilot_HealthShort", fullName = "Pilot_HealthName", description= "Pilot_HealthDesc", bonuses = {health = 2}, saveVal = 0, reusability = "reusable" },
		{id = "Move", shortName = "Pilot_MoveShort", fullName = "Pilot_MoveName", description= "Pilot_MoveDesc", bonuses = {move = 1}, saveVal = 1, reusability = "reusable" },
		{id = "Grid", shortName = "Pilot_GridShort", fullName = "Pilot_GridName", description= "Pilot_GridDesc", bonuses = {grid = 3}, saveVal = 2, reusability = "reusable" },
		{id = "Reactor", shortName = "Pilot_ReactorShort", fullName = "Pilot_ReactorName", description= "Pilot_ReactorDesc", bonuses = {cores = 1}, saveVal = 3, reusability = "reusable" },
		{id = "Opener", shortName = "Pilot_OpenerName", fullName = "Pilot_OpenerName", description= "Pilot_OpenerDesc", saveVal = 4, reusability = "per_pilot" },
		{id = "Closer", shortName = "Pilot_CloserName", fullName = "Pilot_CloserName", description= "Pilot_CloserDesc", saveVal = 5, reusability = "per_pilot" },
		{id = "Popular", shortName = "Pilot_PopularName", fullName = "Pilot_PopularName", description= "Pilot_PopularDesc", saveVal = 6, reusability = "per_pilot" }, -- Maybe reusable? investigate
		{id = "Thick", shortName = "Pilot_ThickName", fullName = "Pilot_ThickName", description= "Pilot_ThickDesc", saveVal = 7, reusability = "per_pilot" },
		{id = "Skilled", shortName = "Pilot_SkilledName", fullName = "Pilot_SkilledName", description= "Pilot_SkilledDesc", bonuses = {health = 2, move = 1}, saveVal = 8, reusability = "reusable" },
		{id = "Invulnerable", shortName = "Pilot_InvulnerableName", fullName = "Pilot_InvulnerableName", description= "Pilot_InvulnerableDesc", saveVal = 9, reusability = "reusable" },
		{id = "Adrenaline", shortName = "Pilot_AdrenalineName", fullName = "Pilot_AdrenalineName", description= "Pilot_AdrenalineDesc", saveVal = 10, reusability = "per_pilot" }, -- Maybe reusable? investigate
		{id = "Pain", shortName = "Pilot_PainName", fullName = "Pilot_PainName", description= "Pilot_PainDesc", saveVal = 11, reusability = "per_pilot" }, -- Maybe reusable? investigate
		{id = "Regen", shortName = "Pilot_RegenName", fullName = "Pilot_RegenName", description= "Pilot_RegenDesc", saveVal = 12, reusability = "per_pilot" }, -- Maybe reusable? investigate
		{id = "Conservative", shortName = "Pilot_ConservativeName", fullName = "Pilot_ConservativeName", description= "Pilot_ConservativeDesc", saveVal = 13, reusability = "per_pilot" }, -- Maybe reusable? investigate
	},
	_registeredSkills = {},  -- category -> skillId -> {shortName, fullName, description, bonuses, skillType, reusability}
	_registeredSkillsIds = {},  -- skillId -> category
	_enabledSkills = {},  -- skillId -> {shortName, fullName, description, bonuses, skillType, reusability}
	_enabledSkillsIds = {},  -- Array of all enabled skill IDs
	_pilotSkillExclusionsAuto = {},  -- pilotId -> excluded skill ids (set-like table) - auto-loaded from pilot Blacklists
	_pilotSkillExclusionsManual = {},  -- pilotId -> excluded skill ids (set-like table) - manually registered via API
	_pilotSkillInclusions = {},  -- pilotId -> included skill ids (set-like table)
	_constraintFunctions = {},  -- Array of function(pilot, selectedSkills, candidateSkillId) -> boolean
	_localRandomCount = nil,  -- Track local random count for this session
	_usedSkillsPerRun = {},  -- skillId -> true for per_run skills used this run
}

function plus_manager:initGameSaveData()
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
		-- Initialize with a seed based on os.time() and 0 rolls
		GAME.cplus_plus_ex.randomSeed = os.time()
		GAME.cplus_plus_ex.randomSeedCnt = 0
	end

	if self._localRandomCount ~= GAME.cplus_plus_ex.randomSeedCnt then
		-- reset our local count to force a re-roll to ensure we
		-- stay inline
		self._localRandomCount = nil
	end

	if self.PLUS_DEBUG then LOG("PLUS Ext: Game entered, storage initialized") end
end

-- Registers all vanilla skills
function plus_manager:registerVanilla()
	-- Register all vanilla skills
	for _, skill in ipairs(self.VANILLA_SKILLS) do
		self:registerSkill("vanilla", skill)
	end
end

-- Scans global for all pilot definitions and registers their Blacklist exclusions
-- This maintains the vanilla method of defining pilot exclusions to be compatible
-- without any specific changes for using this extension
function plus_manager:registerPilotExclusionsFromGlobal()
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
function plus_manager:registerConstraintFunction(constraintFn)
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
function plus_manager:registerPilotSkillExclusions(pilotId, skillIds, isAuto)
	isAuto = isAuto or false
	local targetTable = isAuto and self._pilotSkillExclusionsAuto or self._pilotSkillExclusionsManual
	registerPilotSkillRelationship(self, targetTable, pilotId, skillIds, "exclusion", isAuto)
end

-- Registers pilot skill inclusions
-- Takes pilot id and list of skill ids to include
-- This is only needed for specific inclusion skills. Any default
-- enabled, non-excluded skill will be available as well as any added here
function plus_manager:registerPilotSkillInclusions(pilotId, skillIds)
	registerPilotSkillRelationship(self, self._pilotSkillInclusions, pilotId, skillIds, "inclusion", false)
end

-- saveVal is optional and must be between 0-13 (vanilla range). This will be used so if
-- the extension fails to load or is uninstalled, a suitable vanilla skill will be used
-- instead. If not provided or out of range, a random vanilla value will be used.
-- The save data in vanilla only supports 0-13. Anything out of range is clamped to this range
-- reusability is optional defines how the skill can be reused. Defaults to per_pilot to align with vanilla
--   "reusable" - can be assigned to any pilot any number of times
--   "per_pilot" - a pilot can only have this skill once - vanilla behavior
--   "per_run" - can only be assigned once per run across all pilots. Would be for very strong skills or skills that
--			affect the game state in a one time only way
function plus_manager:registerSkill(category, idOrTable, shortName, fullName, description, bonuses, skillType, saveVal, reusability)
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
		reusability = idOrTable.reusability
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

	-- Validate and normalize reusability
	reusability = reusability or "per_pilot"
	if reusability ~= "reusable" and reusability ~= "per_pilot" and reusability ~= "per_run" then
		LOG("PLUS Ext: Warning: Skill '" .. id .. "' has invalid reusability '" .. tostring(reusability) .. "'. Using 'per_pilot' instead.")
		reusability = "per_pilot"
	end

	-- Register the skill with its type and reusability included in the skill data
	self._registeredSkills[category][id] = { shortName = shortName, fullName = fullName, description = description,
			bonuses = bonuses or {},
			skillType = skillType or "default",
			saveVal = saveVal, reusability = reusability,
	}
	self._registeredSkillsIds[id] = category
end

-- category and skill are optional and will be searched from registered values if omitted
function plus_manager:enableSkill(id, category, skill)
	category = category or self._registeredSkillsIds[id]
	skill = skill or self._registeredSkills[category][id]

	-- Check if already enabled
	if self._enabledSkills[id] ~= nil then
		LOG("PLUS Ext warning: Skill " .. id .. " already enabled, skipping")
	else
		-- Add the skill to enabled list. We don't care at this point if its inclusion type or not
		self._enabledSkills[id] = skill
		table.insert(self._enabledSkillsIds, id)

		if self.PLUS_DEBUG then
			local skillType = skill.skillType
			local reusability = skill.reusability
			if self.PLUS_DEBUG then LOG("PLUS Ext: Enabled skill: " .. id .. " (type: " .. skillType .. ", reusability: " .. reusability .. ")") end
		end
	end
end

function plus_manager:enableCategory(category)
	if self._registeredSkills[category] == nil then
		LOG("PLUS Ext error: Attempted to enable unknown category ".. category)
		return
	end
	for id, skill in pairs(self._registeredSkills[category]) do
		self:enableSkill(id, category, skill)
	end
end

function plus_manager:disableSkill(id)
	if self._enabledSkills[id] == nil then
		LOG("PLUS Ext: Warning: Skill " .. id .. " already disabled, skipping")
	else
		self._enabledSkills[id] = nil
		for idx, skillId in ipairs(self._enabledSkillsIds) do
			if skillId == id then
				table.remove(self._enabledSkillsIds, idx)
				if self.PLUS_DEBUG then LOG("PLUS Ext: Disabled skill: " .. id .. " (idx: " .. idx .. ")") end
				break
			end
		end
	end
end

-- Uses the stored seed and sequential access count to ensure deterministic random values
-- The RNG is seeded once per session, then we fast forward to the saved count
-- skillsList - array like table of skill IDs to select from
function plus_manager:getRandomSkillId(skillsList)
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
function plus_manager:selectRandomSkills(pilot, count)
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

-- Main function to apply level up skills to a pilot (handles both skill slots)
-- Takes a memhack pilot struct and applies both skill slots (1 and 2)
-- Checks GAME memory and either loads existing skills or creates and assigns new ones
function plus_manager:applySkillsToPilot(pilot)
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
	if storedSkills ~= nil then
		if self.PLUS_DEBUG then LOG("PLUS Ext: Read stored skill") end
	-- if its the time traveler, save the current skills
	elseif self._cplus_plus_ex.timeTraveler and self._cplus_plus_ex.timeTraveler._address == pilot._address then
		local lus = self._cplus_plus_ex.timeTraveler:getLvlUpSkills()
		storedSkills = {lus:getSkill1():getIdStr(), lus:getSkill2():getIdStr()}
		GAME.cplus_plus_ex.pilotSkills[pilotId] = storedSkills
		if self.PLUS_DEBUG then LOG("PLUS Ext: Read time traveler skills") end
	-- otherwise assign random skills
	else
		-- Select 2 random skills that satisfy all registered constraint functions
		storedSkills = self:selectRandomSkills(pilot, 2)
		if storedSkills == nil then
			return
		end

		-- Store the skills in GAME
		GAME.cplus_plus_ex.pilotSkills[pilotId] = storedSkills

		-- Track newly assigned skills for per_run constraints
		self:markPerRunSkillAsUsed(storedSkills[1])
		self:markPerRunSkillAsUsed(storedSkills[2])

		if self.PLUS_DEBUG then LOG("PLUS Ext: Assigning random skills")
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

	if self.PLUS_DEBUG then
		LOG("PLUS Ext: Applying skills to pilot " .. pilotId .. ": [" .. storedSkills[1] .. ", " .. storedSkills[2] .. "]")
	end

	-- Apply both skills with their determined saveVal
	pilot:setLvlUpSkill(1, skill1Id, skill1.shortName, skill1.fullName, skill1.description, saveVal1, skill1.bonuses)
	pilot:setLvlUpSkill(2, skill2Id, skill2.shortName, skill2.fullName, skill2.description, saveVal2, skill2.bonuses)
end

-- Apply skills to all pilots in the squad
function plus_manager:applySkillsToAllPilots()
	-- ensure game data is initialized
	self:initGameSaveData()

	if #self._enabledSkillsIds == 0 then
		if self.PLUS_DEBUG then LOG("PLUS Ext: No enabled skills, skipping pilot skill assignment") end
		return
	end

	local pilots = self._cplus_plus_ex:getAllPilots()

	-- Reset per_run tracking and rebuild it from currently assigned skills
	self._usedSkillsPerRun = {}
	for _, pilot in pairs(pilots) do
		local pilotId = pilot:getIdStr()
		local storedSkills = GAME.cplus_plus_ex.pilotSkills[pilotId]

		if storedSkills ~= nil then
			-- This pilot has assigned skills, mark them as used for per_run tracking
			for _, skillId in ipairs(storedSkills) do
				self:markPerRunSkillAsUsed(skillId)
			end
		end
	end

	-- Assign skills to pilots now that we updated the per run skills
	for _, pilot in pairs(pilots) do
		self:applySkillsToPilot(pilot)
	end


	if self.PLUS_DEBUG then LOG("PLUS Ext: Applied skills to " .. #pilots .. " pilot(s)") end
end

-- Checks if a skill can be assigned to the given pilot
-- using all registered constraint functions
-- Returns true if all constraints pass, false otherwise
function plus_manager:checkSkillConstraints(pilot, selectedSkills, candidateSkillId)
	-- Check all constraint functions
	for _, constraintFn in ipairs(self._constraintFunctions) do
		if not constraintFn(pilot, selectedSkills, candidateSkillId) then
			return false
		end
	end
	return true
end


-- Registers the built-in exclusion and inclusion constraint function for pilot skills
-- so we can handle them easily similar to how vanilla does it
function plus_manager:registerPlusExclusionInclusionConstraintFunction()
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

-- Registers the reusability constraint function
-- This enforces per_pilot and per_run skill restrictions
function plus_manager:registerReusabilityConstraintFunction()
	self:registerConstraintFunction(function(pilot, selectedSkills, candidateSkillId)
		local pilotId = pilot:getIdStr()
		local skill = self._enabledSkills[candidateSkillId]

		if skill == nil then
			LOG("PLUS Ext warning: Skill " .. candidateSkillId .. " not found in enabled skills")
			return false
		end

		local reusability = skill.reusability

		-- if reusability is not allowed, treat it as per_pilot
		if not self.allowReusableSkills and reusability == "reusable" then
			reusability = "per_pilot"
			if self.PLUS_DEBUG then
				LOG("PLUS Ext: Treating reusable skill " .. candidateSkillId .. " as per_pilot (override enabled)")
			end
		end

		if reusability == "per_pilot" or reusability == "per_run" then
			-- Check if this pilot already has this skill in their selected slots
			-- This applies to both per_pilot and per_run (per_run is stricter and includes this check)
			for _, skillId in ipairs(selectedSkills) do
				if skillId == candidateSkillId then
					if self.PLUS_DEBUG then
						LOG("PLUS Ext: Prevented " .. reusability .. " skill " .. candidateSkillId .. " for pilot " .. pilotId .. " (already selected)")
					end
					return false
				end
			end

			-- Additional check for per_run: ensure not used by ANY pilot
			if reusability == "per_run" then
				if self._usedSkillsPerRun[candidateSkillId] then
					if self.PLUS_DEBUG then
						LOG("PLUS Ext: Prevented per_run skill " .. candidateSkillId .. " for pilot " .. pilotId .. " (already used this run)")
					end
					return false
				end
			end
		end
		-- reusability == "reusable" always passes

		return true
	end)
end

-- Marks a per_run skill as used for this run
-- Only per_run skills need global tracking - per_pilot is handled by constraint checking selectedSkills
function plus_manager:markPerRunSkillAsUsed(skillId)
	local skill = self._enabledSkills[skillId]
	if skill == nil then
		return
	end

	if skill.reusability == "per_run" then
		-- Check if already marked
		if self._usedSkillsPerRun[skillId] then
			LOG("PLUS Ext: Warning: per_run skill " .. skillId .. " already marked as used")
		end

		-- Mark skill as used this run
		self._usedSkillsPerRun[skillId] = true
		if self.PLUS_DEBUG then
			LOG("PLUS Ext: Marked per_run skill " .. skillId .. " as used this run")
		end
	end
	-- reusable and per_pilot skills don't need tracking
end

function plus_manager:init(parent)
	self._cplus_plus_ex = parent
	self.PLUS_DEBUG = parent.PLUS_DEBUG

	-- Register vanilla skills
	self:registerVanilla()

	-- Register built-in constraint functions
	self:registerReusabilityConstraintFunction()  -- Enforces per_pilot and per_run reusability
	self:registerPlusExclusionInclusionConstraintFunction()  -- Checks pilot exclusions and inclusion-type skills

	-- TODO: Temp. Long term control via options or other configs?
	self:enableCategory("vanilla")
end


function plus_manager:load(options)
	-- Register/refresh pilot exclusions from their global definitions
	self:registerPilotExclusionsFromGlobal()
	
	-- Load option for allowing reusable skills (defaults to false/vanilla behavior)
	if options and options["cplus_plus_ex_dup_skills_allowed"] then
		self.allowReusableSkills = options["cplus_plus_ex_dup_skills_allowed"].enabled
	end
end

return plus_manager