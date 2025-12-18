plus_ext = {
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
	_enabledSkills = {}
}

function plus_ext:registerVanilla()
	for _, skill in ipairs(self.VANILLA_SKILLS) do
		self:registerSkill("vanilla", skill.id, skill.shortName, skill.fullName, skill.description)
	end
end

-- TODO: Id needs to be unique across all.. maybe instead handle at enable time and allow multiple registers?
-- TODO: Also if user needs action, should make a popup
function plus_ext:registerSkill(category, id, shortName, fullName, description)
	if self._registeredSkills[category] == nil then
		self._registeredSkills[category] = {}
	end
	
	if self._registeredSkills[category][id] ~= nil then
		LOG("PLUS Ext error: Already registered level up skill with category ".. category.. " and ID " .. id .. "... ignoring this register")
		return
	end
	self._registeredSkills[category][id] = {shortName = shortName, fullName = fullName, descritption = description}
end

function plus_ext:enableCategory(category) 
	if self._registeredSkills[category] == nil then
		LOG("PLUS Ext error: Attempted to enable unknown category ".. category)
		return
	end
	for id, skill in pairs(self._registeredSkills[category]) do
		if self._enabledSkills[id] ~= nil then
			LOG("PLUS Ext error: Already enabled level up skill with ID " .. id .. "... ignoring this register")
		else 
			self._enabledSkills[id] = skill
		end
	end
end

function plus_ext:writeToGame()
	if GAME ~= nil then
		if GAME.plus_ext == nil then
			GAME.plus_ext = {}
		end
		GAME.plus_ext.test1 = 42
	end
end

function plus_ext:init()
	self:registerVanilla()
end