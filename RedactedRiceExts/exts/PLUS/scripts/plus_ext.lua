plus_ext = {
	PLUS_DEBUG = true, -- eventually default to false
	VANILLA_SKILLS = {
		{id = "Health", shortName = "Pilot_HealthShort", fullName = "Pilot_HealthName", description= "Pilot_HealthDesc", bonuses = {health = 2} },
		{id = "Move", shortName = "Pilot_MoveShort", fullName = "Pilot_MoveName", description= "Pilot_MoveDesc", bonuses = {move = 1} },
		{id = "Grid", shortName = "Pilot_GridShort", fullName = "Pilot_GridName", description= "Pilot_GridDesc", bonuses = {grid = 3} },
		{id = "Reactor", shortName = "Pilot_ReactorShort", fullName = "Pilot_ReactorName", description= "Pilot_ReactorDesc", bonuses = {cores = 1} },
		{id = "Opener", shortName = "Pilot_OpenerName", fullName = "Pilot_OpenerName", description= "Pilot_OpenerDesc" },
		{id = "Closer", shortName = "Pilot_CloserName", fullName = "Pilot_CloserName", description= "Pilot_CloserDesc" },
		{id = "Popular", shortName = "Pilot_PopularName", fullName = "Pilot_PopularName", description= "Pilot_PopularDesc" },
		{id = "Thick", shortName = "Pilot_ThickName", fullName = "Pilot_ThickName", description= "Pilot_ThickDesc" },
		{id = "Skilled", shortName = "Pilot_SkilledName", fullName = "Pilot_SkilledName", description= "Pilot_SkilledDesc", bonuses = {health = 2, move = 1} },
		{id = "Invulnerable", shortName = "Pilot_InvulnerableName", fullName = "Pilot_InvulnerableName", description= "Pilot_InvulnerableDesc" },
		{id = "Adrenaline", shortName = "Pilot_AdrenalineName", fullName = "Pilot_AdrenalineName", description= "Pilot_AdrenalineDesc" },
		{id = "Pain", shortName = "Pilot_PainName", fullName = "Pilot_PainName", description= "Pilot_PainDesc" },
		{id = "Regen", shortName = "Pilot_RegenName", fullName = "Pilot_RegenName", description= "Pilot_RegenDesc" },
		{id = "Conservative", shortName = "Pilot_ConservativeName", fullName = "Pilot_ConservativeName", description= "Pilot_ConservativeDesc" },
	},
	VANILLA_PILOT_SKILL_EXCLUSIONS = {
		{pilotId = "Pilot_Zoltan", skillIds = {"Health", "Skilled"}},
		-- Add more exclusions here
	},

	EXAMPLE_INCLUSION_SKILLS = {
		{id = "SuperGrid", shortName = "+6 Grid", fullName = "+6 Grid", description= "Increase grid defense by 6", bonuses = {grid = 6}, skillType = "inclusion" },
	},
	EXAMPLE_INCLUSIONS = {
		{pilotId = "Pilot_Example", skillIds = {"SuperGrid"}},
	},
	_registeredSkills = {},  -- category -> skillId -> {shortName, fullName, description, bonuses, skillType}
	_registeredSkillsIds = {},  -- skillId -> category
	_enabledSkills = {},  -- skillId -> {shortName, fullName, description, bonuses, skillType}
	_enabledSkillsIds = {},  -- Array of all enabled skill IDs
	_pilotSkillExclusions = {},  -- pilotId -> excluded skill ids (set-like table)
	_pilotSkillInclusions = {},  -- pilotId -> included skill ids (set-like table)
	_constraintFunctions = {},  -- Array of function(pilot, selectedSkills, candidateSkillId) -> boolean
	_localRandomCount = nil  -- Track local random count for this session
}

function plus_ext:initGameStorage()
	if GAME == nil then
		return
	end

	if GAME.plus_ext == nil then
		GAME.plus_ext = {}
	end

	if GAME.plus_ext.pilotSkills == nil then
		GAME.plus_ext.pilotSkills = {}
	end

	if GAME.plus_ext.randomSeed == nil then
		-- Initialize with a seed based on os.time()
		GAME.plus_ext.randomSeed = os.time()
	end

	if GAME.plus_ext.randomSeedCnt == nil then
		GAME.plus_ext.randomSeedCnt = 0
	end

	-- reset our local count to force a re-roll to ensure we
	-- stay inline
	self._localRandomCount = nil
end

-- Registers all vanilla skills and their pilot exclusions
function plus_ext:registerVanilla()
	-- Register all vanilla skills
	for _, skill in ipairs(self.VANILLA_SKILLS) do
		self:registerSkill("vanilla", skill)
	end

	-- Register all vanilla pilot skill exclusions
	for _, entry in ipairs(self.VANILLA_PILOT_SKILL_EXCLUSIONS) do
		self:registerPilotSkillExclusions(entry.pilotId, entry.skillIds)
	end
end

-- Registers all example inclusion skills and their pilot inclusions
function plus_ext:registerExample()
	-- Register all example skills
	for _, skill in ipairs(self.EXAMPLE_INCLUSION_SKILLS) do
		self:registerSkill("example", skill)
	end

	-- Register all example pilot skill inclusions
	for _, entry in ipairs(self.EXAMPLE_INCLUSIONS) do
		self:registerPilotSkillInclusions(entry.pilotId, entry.skillIds)
	end
end


-- Registers a constraint function for skill assignment
-- These functions take pilot, selectedSkills, and candidateSkillId and return true if the candidateskill can be assigned to the pilot
--   pilot - The memhack pilot struct
--   selectedSkills - Array like table of skill IDs that have already been selected for this pilot
--   candidateSkillId - The skill ID being considered for assignment
-- The default pilot inclusion/exclusion and duplicate prevention use this same function. These can be
-- used as examples for using constraint functions
function plus_ext:registerConstraintFunction(constraintFn)
	table.insert(self._constraintFunctions, constraintFn)
	if self.PLUS_DEBUG then
		LOG("PLUS Ext: Registered constraint function")
	end
end

-- Helper function to register pilot-skill relationships
-- targetTable: either _pilotSkillExclusions or _pilotSkillInclusions
-- relationshipType: "exclusion" or "inclusion" (for debug logging)
local function registerPilotSkillRelationship(self, targetTable, pilotId, skillIds, relationshipType)
	local pilotIdLower = string.lower(pilotId)

	if targetTable[pilotIdLower] == nil then
		targetTable[pilotIdLower] = {}
	end

	for _, skillId in ipairs(skillIds) do
		local skillIdLower = string.lower(skillId)
		-- store with skillId as key so it acts like a set
		targetTable[pilotIdLower][skillIdLower] = true

		if self.PLUS_DEBUG then
			local action = relationshipType == "exclusion" and "cannot have" or "can have"
			LOG("PLUS Ext: Registered " .. relationshipType .. " - Pilot " .. pilotId .. " " .. action .. " skill " .. skillId)
		end
	end
end

-- Registers pilot skill exclusions
-- Takes pilot id and list of skill ids to exclude
function plus_ext:registerPilotSkillExclusions(pilotId, skillIds)
	registerPilotSkillRelationship(self, self._pilotSkillExclusions, pilotId, skillIds, "exclusion")
end

-- Registers pilot skill inclusions
-- Takes pilot id and list of skill ids to include
-- This is only needed for specific inclusion skills. Any default
-- enabled, non-excluded skill will be available as well as any added here
function plus_ext:registerPilotSkillInclusions(pilotId, skillIds)
	registerPilotSkillRelationship(self, self._pilotSkillInclusions, pilotId, skillIds, "inclusion")
end

-- Shows an error popup to the user
function plus_ext:showErrorPopup(message)
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

function plus_ext:logAndShowErrorPopup(message)
	LOG(message)
	self:showErrorPopup(message)
end

function plus_ext:registerSkill(category, idOrTable, shortName, fullName, description, bonuses, skillType)

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
	end

	-- Check if ID is already registered globally
	if self._registeredSkillsIds[id] ~= nil then
		self:logAndShowErrorPopup("PLUS Ext error: Skill ID '" .. id .. "' in category '" .. category .. "' conflicts with existing skill from category '" .. self._registeredSkillsIds[id] .. "'.")
		return
	end

	-- Register the skill with its type included in the skill data
	self._registeredSkills[category][id] = { shortName = shortName, fullName = fullName, description = description,
			bonuses = bonuses or {},
			skillType = skillType or "default",
	}
	self._registeredSkillsIds[id] = category
end

function plus_ext:enableCategory(category)
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
function plus_ext:getRandomSkillId(skillsList)
	if #skillsList == 0 then
		LOG("PLUS Ext error: No skills available in list")
		return nil
	end

	-- Get the stored seed and count from GAME
	local seed = GAME.plus_ext.randomSeed
	local savedCount = GAME.plus_ext.randomSeedCnt

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
	GAME.plus_ext.randomSeedCnt = self._localRandomCount

	return skillsList[index]
end

-- Selects random level up skills based on count and configured constraints
-- Returns a array like table of skill IDs that satisfy the constraints
-- I pass count even though its currently only expected to be 2 just because I feel
-- like it could be interesting and possible to have pilots with more than two skills
function plus_ext:selectRandomSkills(pilot, count)
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
function plus_ext:checkSkillConstraints(pilot, selectedSkills, candidateSkillId)
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
function plus_ext:registerNoDupsConstraintFunction()
	self:registerConstraintFunction(function(pilot, selectedSkills, candidateSkillId)
		-- Check if this skill has already been selected
		for _, skillId in ipairs(selectedSkills) do
			if skillId == candidateSkillId then
				return false
			end
		end
		return true
	end)
end

-- Registers the built-in exclusion and inclusion constraint function for pilot skills
-- so we can handle them easily similar to how vanilla does it
function plus_ext:registerPlusExclusionInclusionConstraintFunction()
	self:registerConstraintFunction(function(pilot, selectedSkills, candidateSkillId)
		-- Normalize to lowercase
		local pilotIdLower = string.lower(pilot:getIdStr())
		local candidateSkillIdLower = string.lower(candidateSkillId)

		-- Get the skill object to check its type
		local skill = self._enabledSkills[candidateSkillId]
		if skill == nil then
			LOG("PLUS Ext warning: Skill " .. candidateSkillId .. " not found in enabled skills")
			return false
		end

		-- For inclusion skills check if pilot is in inclusion list
		-- For default skills check if pilot is NOT in exclusion list (must be absent)
		local isInclusionSkill = skill.skillType == "inclusion"
		local pilotList = isInclusionSkill and self._pilotSkillInclusions[pilotIdLower] or self._pilotSkillExclusions[pilotIdLower]
		local skillInList = pilotList and pilotList[candidateSkillIdLower]

		-- Return true if (inclusion skill AND in list) OR (default skill AND not in list)
		return isInclusionSkill == (skillInList == true)
	end)
end

-- Main function to apply level up skills to a pilot (handles both skill slots)
-- Takes a memhack pilot struct and applies both skill slots (1 and 2)
-- Checks GAME memory and either loads existing skills or creates and assigns new ones
function plus_ext:applySkillsToPilot(pilot)
	if pilot == nil then
		LOG("PLUS Ext error: Pilot is nil")
		return
	end

	-- Use pilot ID as the key for storing skills for now. Multiple pilots with same ID is
	-- technically possible but not allowed by vanilla so this may change later
	local pilotId = pilot:getIdStr()

	-- Try to get stored skills
	local storedSkills = GAME.plus_ext.pilotSkills[pilotId]

	-- If the skills are not stored, we need to assign them
	if storedSkills == nil then
		-- Select 2 random skills that satisfy all registered constraint functions
		storedSkills = self:selectRandomSkills(pilot, 2)
		if storedSkills == nil then
			return
		end

		-- Store the skills in GAME
		GAME.plus_ext.pilotSkills[pilotId] = storedSkills

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

	-- Apply both skills (0 = saveVal which is not needed since we use custom saving)
	pilot:setLvlUpSkill(1, skill1Id, skill1.shortName, skill1.fullName, skill1.description, 0, skill1.bonuses)
	pilot:setLvlUpSkill(2, skill2Id, skill2.shortName, skill2.fullName, skill2.description, 0, skill2.bonuses)
end

-- Helper function to get all pilots in the current squad
function plus_ext:getAllPilots()
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
function plus_ext:applySkillsToAllPilots()
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
function plus_ext:onGameEntered()
	self:initGameStorage()
	if self.PLUS_DEBUG then LOG("PLUS Ext: Game entered, storage initialized") end
	self:applySkillsToAllPilots()
end

function plus_ext:init()
	-- Register vanilla skills and exclusions
	self:registerVanilla()

	-- Register example inclusion skills and inclusions
	-- TODO: May remove eventually or rename to testing?
	self:registerExample()

	-- Register built-in constraint functions
	self:registerNoDupsConstraintFunction()  -- Prevents same skill in multiple slots
	self:registerPlusExclusionInclusionConstraintFunction()  -- Checks pilot exclusions and inclusion-type skills

	-- TODO: Temp. Long term control via options or other configs?
	self:enableCategory("vanilla")
	self:enableCategory("example")

	-- Subscribe to game events
	modApi.events.onGameEntered:subscribe(function()
		plus_ext:onGameEntered()
	end)

	if self.PLUS_DEBUG then LOG("PLUS Ext: Initialized and subscribed to game events") end
end