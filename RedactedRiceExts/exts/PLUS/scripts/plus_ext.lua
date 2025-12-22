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
	_registeredSkills = {},
	_registeredSkillsIds = {},
	_enabledSkills = {},
	_enabledSkillsIds = {},
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

function plus_ext:registerVanilla()
	for _, skill in ipairs(self.VANILLA_SKILLS) do
		self:registerSkill("vanilla", skill)
	end
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

function plus_ext:registerSkill(category, idOrTable, shortName, fullName, description, bonuses)

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
	end

	-- Check if ID is already registered globally
	if self._registeredSkillsIds[id] ~= nil then
		self:logAndShowErrorPopup("PLUS Ext error: Skill ID '" .. id .. "' in category '" .. category .. "' conflicts with existing skill from category '" .. self._registeredSkillsIds[id] .. "'.")
		return
	end

	-- Register the skill
	self._registeredSkills[category][id] = {shortName = shortName, fullName = fullName, description = description, bonuses = bonuses or {}}
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
			-- Add the skill with its id
			self._enabledSkills[id] = skill
			table.insert(self._enabledSkillsIds, id)
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

-- Selects random level up skills based on count and constraints
-- Returns a array like table of skill IDs that satisfy the constraints
-- Constraints is an optional table of functions that take (selectedSkills, candidateSkillId) and return true if valid
--     This does not naturally enforce only one of each skill. This must be done through constraints if desired
-- I pass count even though its currently only expected to be 2 just because I feel
-- like it could be interesting and possible to have pilots with more than two skills
-- Similar story for making preventing duplicates a constraint. Some vanilla skills and
-- custom skills could certainly allow duplicates
function plus_ext:selectRandomSkills(count, constraints)
	if #self._enabledSkillsIds == 0 then
		LOG("PLUS Ext error: No enabled skills available")
		return nil
	end

	if count > #self._enabledSkillsIds then
		LOG("PLUS Ext error: Cannot select " .. count .. " skills from " .. #self._enabledSkillsIds .. " available skills")
		return nil
	end

	constraints = constraints or {}
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

		-- Check all constraints
		local isValid = true
		for _, constraint in ipairs(constraints) do
			if not constraint(selectedSkills, candidateSkillId) then
				isValid = false
				break
			end
		end

		if isValid then
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

-- Constraint: Ensures no duplicate skills are selected
function plus_ext:constraintNoDuplicates(selectedSkills, candidateSkillId)
	for _, skillId in ipairs(selectedSkills) do
		if skillId == candidateSkillId then
			return false
		end
	end
	return true
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
		-- Define constraints for skill selection
		local constraints = {
			function(selected, candidate) return self:constraintNoDuplicates(selected, candidate) end
		}

		-- Select 2 random skills that satisfy constraints
		storedSkills = self:selectRandomSkills(2, constraints)
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
	self:registerVanilla()

	-- TODO: Temp. Long term control via options or other configs?
	self:enableCategory("vanilla")

	-- Subscribe to game events
	modApi.events.onGameEntered:subscribe(function()
		plus_ext:onGameEntered()
	end)

	if self.PLUS_DEBUG then LOG("PLUS Ext: Initialized and subscribed to game events") end
end