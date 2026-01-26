-- Mock objects for memhack structs (Pilot, PilotLvlUpSkill, etc.)

local M = {}

-- Helper: Create a simple getter function
local function makeGetter(field)
	return function(self) return self[field] end
end

-- Helper: Create a simple setter function
local function makeSetter(field)
	return function(self, value) self[field] = value end
end

-- Helper: Create parent getter that looks up parent by type name
local function makeParentGetter(parentTypeName)
	return function(self)
		if not self._parent then return nil end
		return self._parent[parentTypeName]
	end
end

-- Create a mock skill with all required methods
-- Optional params: skillId, coresBonus, gridBonus, healthBonus, moveBonus, saveVal, address
function M.createMockSkill(params)
	params = params or {}

	local skill = {
		_id = params.skillId or "",
		_cores_bonus = params.coresBonus or 0,
		_grid_bonus = params.gridBonus or 0,
		_health_bonus = params.healthBonus or 0,
		_move_bonus = params.moveBonus or 0,
		_save_val = params.saveVal or 0,
		_address = params.address or math.random(1000000, 9999999),
		_name = "PilotLvlUpSkill",
		isMemhackObj = true,
	}

	-- Add getters using helper
	skill.getIdStr = makeGetter("_id")
	skill.getShortNameStr = function(self) return "Short" end  -- Mock value
	skill.getFullNameStr = function(self) return "Full Name" end  -- Mock value
	skill.getDescriptionStr = function(self) return "Description" end  -- Mock value
	skill.getCoresBonus = makeGetter("_cores_bonus")
	skill.getGridBonus = makeGetter("_grid_bonus")
	skill.getHealthBonus = makeGetter("_health_bonus")
	skill.getMoveBonus = makeGetter("_move_bonus")
	skill.getSaveVal = makeGetter("_save_val")
	skill.getAddress = makeGetter("_address")

	-- Add setters using helper
	skill.setCoresBonus = makeSetter("_cores_bonus")
	skill.setGridBonus = makeSetter("_grid_bonus")
	skill.setHealthBonus = makeSetter("_health_bonus")
	skill.setMoveBonus = makeSetter("_move_bonus")
	skill.setSaveVal = makeSetter("_save_val")

	-- Add parent getters using helper
	skill.getParentPilot = makeParentGetter("Pilot")
	skill.getParentSkillsArray = makeParentGetter("PilotLvlUpSkillsArray")
	skill.getParentPilotLvlUpSkillsArray = skill.getParentSkillsArray  -- Alias

	return skill
end

-- Helper: Inject parent references into child object
-- Copies parent references from self._parent and adds self to the parent map
local function injectParentReferences(self, child, selfTypeName)
	if not child then return child end

	local parentMap = {}

	-- Copy existing parent references from self
	if self._parent then
		for typeName, parent in pairs(self._parent) do
			parentMap[typeName] = parent
		end
	end

	-- Add self to parent map
	parentMap[selfTypeName] = self

	-- Inject into child
	child._parent = parentMap

	return child
end

-- Create a mock lvl up skills array with two skills
-- Can optionally pass in existing skill mocks, otherwise creates new ones
function M.createMockLvlUpSkills(skill1, skill2)
	local mockLvlUpSkills = {
		_skill1 = skill1 or M.createMockSkill(),
		_skill2 = skill2 or M.createMockSkill(),
		_name = "PilotLvlUpSkillsArray",
		isMemhackObj = true,
	}

	-- Getters that inject parent references
	mockLvlUpSkills.getSkill1 = function(self)
		return injectParentReferences(self, self._skill1, "PilotLvlUpSkillsArray")
	end

	mockLvlUpSkills.getSkill2 = function(self)
		return injectParentReferences(self, self._skill2, "PilotLvlUpSkillsArray")
	end

	return mockLvlUpSkills
end

-- Create a minimal mock pilot struct
-- Params can be:
--   - string: pilot ID
--   - table: {pilotId, level, xp, lvlUpSkills, address}
function M.createMockPilot(params)
	-- Handle string argument (just pilot ID)
	if type(params) == "string" then
		params = {pilotId = params}
	end
	params = params or {}

	local mockPilot = {
		_id = params.pilotId or params[1] or "MockPilot",
		_level = params.level or 0,
		_xp = params.xp or 0,
		_address = params.address or math.random(1000000, 9999999),
		_lvlUpSkills = params.lvlUpSkills or M.createMockLvlUpSkills(),
		_name = "Pilot",
		isMemhackObj = true,
	}

	-- Add basic getters
	mockPilot.getIdStr = makeGetter("_id")
	mockPilot.getNameStr = function(self) return "Pilot Name" end  -- Mock value
	mockPilot.getSkillStr = function(self) return "Skill" end  -- Mock value
	mockPilot.getLevel = makeGetter("_level")
	mockPilot.getXp = makeGetter("_xp")
	mockPilot.getLevelUpXp = function(self) return 100 end  -- Mock value
	mockPilot.getPrevTimelines = function(self) return 0 end  -- Mock value
	mockPilot.getAddress = makeGetter("_address")
	
	-- Add setters
	mockPilot.setLevel = makeSetter("_level")
	mockPilot.setXp = makeSetter("_xp")

	-- Add getLvlUpSkills with parent injection
	mockPilot.getLvlUpSkills = function(self)
		return injectParentReferences(self, self._lvlUpSkills, "Pilot")
	end

	-- Convenience method to get skill by index
	mockPilot.getLvlUpSkill = function(self, index)
		local skills = self:getLvlUpSkills()
		if index == 1 then
			return skills:getSkill1()
		elseif index == 2 then
			return skills:getSkill2()
		else
			error(string.format("Invalid skill index %d. Expected 1 or 2", index))
		end
	end

	-- Simplified setLvlUpSkill for testing
	mockPilot.setLvlUpSkill = function(self, skillNum, skillId, shortName, fullName, description, saveVal, bonuses)
		local skill = (skillNum == 1) and self._lvlUpSkills._skill1 or self._lvlUpSkills._skill2
		skill._id = skillId
		skill._save_val = saveVal
		if bonuses then
			skill._cores_bonus = bonuses.cores or 0
			skill._grid_bonus = bonuses.grid or 0
			skill._health_bonus = bonuses.health or 0
			skill._move_bonus = bonuses.move or 0
		end
	end

	return mockPilot
end

return M
