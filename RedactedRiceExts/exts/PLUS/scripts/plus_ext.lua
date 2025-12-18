plus_ext = {
	PLUS_DEBUG = true, -- eventually default to false
	VANILLA_SKILLS = {
		{id = "Health", shortName = "Pilot_HealthShort", fullName = "Pilot_HealthName", description= "Pilot_HealthDesc" },
		{id = "Move", shortName = "Pilot_MoveShort", fullName = "Pilot_MoveName", description= "Pilot_MoveDesc" },
		{id = "Grid", shortName = "Pilot_GridShort", fullName = "Pilot_GridName", description= "Pilot_GridDesc" },
		{id = "Reactor", shortName = "Pilot_ReactorShort", fullName = "Pilot_ReactorName", description= "Pilot_ReactorDesc" },
		{id = "Opener", shortName = "Pilot_OpenerName", fullName = "Pilot_OpenerName", description= "Pilot_OpenerDesc" },
		{id = "Closer", shortName = "Pilot_CloserName", fullName = "Pilot_CloserName", description= "Pilot_CloserDesc" },
		{id = "Popular", shortName = "Pilot_PopularName", fullName = "Pilot_PopularName", description= "Pilot_PopularDesc" },
		{id = "Thick", shortName = "Pilot_ThickName", fullName = "Pilot_ThickName", description= "Pilot_ThickDesc" },
		{id = "Skilled", shortName = "Pilot_SkilledName", fullName = "Pilot_SkilledName", description= "Pilot_SkilledDesc" },
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
		self:registerSkill("vanilla", skill.id, skill.shortName, skill.fullName, skill.description)
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

function plus_ext:registerSkill(category, id, shortName, fullName, description)
	if self._registeredSkills[category] == nil then
		self._registeredSkills[category] = {}
	end

	-- Check if ID is already registered globally
	if self._registeredSkillsIds[id] ~= nil then
		self:logAndShowErrorPopup("PLUS Ext error: Skill ID '" .. id .. "' in category '" .. category .. "' conflicts with existing skill from category '" .. self._registeredSkillsIds[id] .. "'.")
		return
	end

	-- Register the skill
	self._registeredSkills[category][id] = {shortName = shortName, fullName = fullName, description = description}
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
function plus_ext:getRandomSkillId()
	if #self._enabledSkillsIds == 0 then
		LOG("PLUS Ext error: No enabled skills available")
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
		self.PLUS_DEBUG and LOG("PLUS Ext: Initialized RNG with seed " .. seed .. " and fast-forwarded " .. savedCount .. " times")
	end

	-- Generate the next random index in the range of available skills
	local index = math.random(1, #self._enabledSkillsIds)

	-- Increment both local and saved count
	self._localRandomCount = self._localRandomCount + 1
	GAME.plus_ext.randomSeedCnt = self._localRandomCount

	return self._enabledSkillsIds[index]
end

-- Main function to apply level up skill to a pilot
-- Takes a memhack pilot struct, pilot index, and skill index
-- Checks GAME memory and either loads the skill or creates and adds one
function plus_ext:applySkillToPilot(pilot, pilotIndex, skillIndex)
	if pilot == nil then
		LOG("PLUS Ext error: Pilot is nil")
		return
	end

	if skillIndex ~= 1 and skillIndex ~= 2 then
		LOG("PLUS Ext error: Invalid skill index (must be 1 or 2): " .. tostring(skillIndex))
		return
	end

	-- Use pilot ID as the key for storing skills for now. Multiple pilots with same ID is
	-- technically possible but not allowed by vanilla so this may change later
	local pilotId = pilot:getIdStr()

	-- Check if we already have a stored skill for this pilot
	local storedSkillId = GAME.plus_ext.pilotSkills[pilotId]
	local skill = storedSkillId and self._enabledSkills[storedSkillId]

	-- If no stored skill or stored skill is no longer enabled, get a new random one
	if not skill then
		if storedSkillId ~= nil then
			LOG("PLUS Ext warning: Stored skill id " .. storedSkillId .. " is not enabled, reassigning")
		end

		local randomSkillId = self:getRandomSkillId()
		if randomSkillId == nil then
			return
		end

		-- Store and use the new random skill
		GAME.plus_ext.pilotSkills[pilotId] = randomSkillId
		skill = self._enabledSkills[randomSkillId]
		storedSkillId = randomSkillId

		self.PLUS_DEBUG and LOG("PLUS Ext: Assigning random skill " .. randomSkillId .. " to pilot " .. pilotId .. " (index " .. pilotIndex .. ")")
	else
		self.PLUS_DEBUG and LOG("PLUS Ext: Applying stored skill " .. storedSkillId .. " to pilot " .. pilotId .. " (index " .. pilotIndex .. ")")
	end

	-- Apply the skill (0 = saveVal which is not needed since we use custom saving)
	pilot:setLvlUpSkill(skillIndex, storedSkillId, skill.shortName, skill.fullName, skill.description, 0)
end

-- Helper function to get all pilots in the current squad
function plus_ext:getAllPilots()
	local pilots = {}

	-- Iterate through the 3 squad positions (0, 1, 2)
	for i = 0, 2 do
		local pawnId = i  -- Pawn IDs correspond to squad positions
		local pawn = Board:GetPawn(pawnId)

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
		self.PLUS_DEBUG and LOG("PLUS Ext: No enabled skills, skipping pilot skill assignment")
		return
	end

	local pilots = self:getAllPilots()

	for _, pilotData in ipairs(pilots) do
		-- Apply skills to both skill slots (1 and 2)
		self:applySkillToPilot(pilotData.pilot, pilotData.index, 1)
		self:applySkillToPilot(pilotData.pilot, pilotData.index, 2)
	end

	self.PLUS_DEBUG and LOG("PLUS Ext: Applied skills to " .. #pilots .. " pilot(s)")
end

-- Event handler for when the game is entered (loaded or new game)
function plus_ext:onGameEntered()
	self:initGameStorage()
	self.PLUS_DEBUG and LOG("PLUS Ext: Game entered, storage initialized")
end

-- Event handler for mission start
function plus_ext:onMissionStart()
	-- Apply skills to all pilots at mission start
	-- TODO: Not sure this is needed
	self:applySkillsToAllPilots()
end

function plus_ext:init()
	self:registerVanilla()

	-- Subscribe to game events
	modApi.events.onGameLoaded:subscribe(function()
		plus_ext:onGameEntered()
	end)

	modApi.events.onGameStarted:subscribe(function()
		plus_ext:onGameEntered()
	end)

	-- Mission start hook
	modApi.events.onMissionStart:subscribe(function()
		plus_ext:onMissionStart()
	end)

	self.PLUS_DEBUG and LOG("PLUS Ext: Initialized and subscribed to game events")
end