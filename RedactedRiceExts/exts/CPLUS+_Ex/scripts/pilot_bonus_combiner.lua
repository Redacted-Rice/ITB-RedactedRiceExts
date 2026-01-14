-- Pilot Bonus Combiner Module
-- Handles combining cores and grid bonuses from both level up skills
-- When both skills are active AND both have non zero values for a bonus type,
-- combines their values into skill1 and clears skill2 for that bonus type

local pilot_bonus_combiner = {}

-- Reference to owner (set during init)
local owner = nil
local skill_registry = nil

-- Initialize the module with reference to owner
function pilot_bonus_combiner.init(ownerRef)
	owner = ownerRef
	skill_registry = ownerRef._modules.skill_registry
end

-- Get the base bonus value for a specific skill and bonus type
-- Pulls directly from skill registry
function pilot_bonus_combiner.getBaseBonusValue(skillId, bonusType)
	local skill = skill_registry.registeredSkills[skillId]
	if skill and skill.bonuses and skill.bonuses[bonusType] then
		return skill.bonuses[bonusType]
	end
	return 0
end

function pilot_bonus_combiner.checkPilot(pilot)
	if pilot == nil then
		LOG("PLUS Ext: Error: Nil pilot passed!")
		return nil, nil
	end

	local lvlUpSkills = pilot:getLvlUpSkills()
	if lvlUpSkills == nil then
		LOG("PLUS Ext: Error: Failed to find lvl up skills for pilot")
		return nil, nil
	end

	local skill1 = lvlUpSkills:getSkill1()
	local skill2 = lvlUpSkills:getSkill2()
	return skill1, skill2
end

-- Set both skills to their base values
local function restoreBaseValues(skill1, skill2, skill1_base_cores, skill1_base_grid, skill2_base_cores, skill2_base_grid)
	-- We reset all them to base in case this was a result of a skill change which could cause
	-- use to leave a combined value in skill1
	skill1:setCoresBonus(skill1_base_cores)
	skill1:setGridBonus(skill1_base_grid)
	skill2:setCoresBonus(skill2_base_cores)
	skill2:setGridBonus(skill2_base_grid)

	if owner.PLUS_DEBUG then
		LOG(string.format("PLUS Ext: Restored base values - Skill1: cores=%d, grid=%d", skill1_base_cores, skill1_base_grid))
	end
end

-- Combine bonuses into skill1 when BOTH skills have non zero values for that bonus type
-- Otherwise leave bonuses at their base values
local function combineWhenBothHaveValues(skill1, skill2, skill1_base_cores, skill1_base_grid, skill2_base_cores, skill2_base_grid)
	if skill1_base_cores > 0 and skill2_base_cores > 0 then
		-- Both have cores - combine into skill1
		skill1:setCoresBonus(skill1_base_cores + skill2_base_cores)
		skill2:setCoresBonus(0)
		if owner.PLUS_DEBUG then
			LOG(string.format("PLUS Ext: Combined cores - Skill1: %d+%d=%d, Skill2: 0", skill1_base_cores, skill2_base_cores, skill1_base_cores + skill2_base_cores))
		end
	else
		-- At least one has zero cores - reset to default values (again in case the skill was changed)
		skill1:setCoresBonus(skill1_base_cores)
		skill2:setCoresBonus(skill2_base_cores)
		if owner.PLUS_DEBUG then
			LOG(string.format("PLUS Ext: Cores not combined (at least one is 0) - Skill1: %d, Skill2: %d", skill1_base_cores, skill2_base_cores))
		end
	end

	-- Same for grid
	if skill1_base_grid > 0 and skill2_base_grid > 0 then
		-- Both have grid - combine into skill1
		skill1:setGridBonus(skill1_base_grid + skill2_base_grid)
		skill2:setGridBonus(0)
		if owner.PLUS_DEBUG then
			LOG(string.format("PLUS Ext: Combined grid - Skill1: %d+%d=%d, Skill2: 0", skill1_base_grid, skill2_base_grid, skill1_base_grid + skill2_base_grid))
		end
	else
		-- At least one has zero grid - reset to default values (again in case the skill was changed)
		skill1:setGridBonus(skill1_base_grid)
		skill2:setGridBonus(skill2_base_grid)
		if owner.PLUS_DEBUG then
			LOG(string.format("PLUS Ext: Grid not combined (at least one is 0) - Skill1: %d, Skill2: %d", skill1_base_grid, skill2_base_grid))
		end
	end
end

-- Combine bonuses from both skills when appropriate
-- This is called whenever a pilot's level changes or
-- when skills are first assigned (in case they are
-- already leveled up)
function pilot_bonus_combiner.combinePilotBonuses(pilot)
	local skill1, skill2 = pilot_bonus_combiner.checkPilot(pilot)
	if skill1 == nil or skill2 == nil then
		LOG("PLUS Ext: Error: Failed to find skills for pilot")
		return
	end

	-- Get skill IDs and then use it to get base bonus values
	local skill1_id = skill1:getIdStr()
	local skill2_id = skill2:getIdStr()
	local skill1_base_cores = pilot_bonus_combiner.getBaseBonusValue(skill1_id, "cores")
	local skill1_base_grid = pilot_bonus_combiner.getBaseBonusValue(skill1_id, "grid")
	local skill2_base_cores = pilot_bonus_combiner.getBaseBonusValue(skill2_id, "cores")
	local skill2_base_grid = pilot_bonus_combiner.getBaseBonusValue(skill2_id, "grid")

	-- Get pilot level to determine if both skills are active
	local pilotLevel = pilot:getLevel()

	if owner.PLUS_DEBUG then
		LOG(string.format("PLUS Ext: combinePilotBonuses for pilot level %d", pilotLevel))
		LOG(string.format("  Skill1 (%s): cores=%d, grid=%d", skill1_id, skill1_base_cores, skill1_base_grid))
		LOG(string.format("  Skill2 (%s): cores=%d, grid=%d", skill2_id, skill2_base_cores, skill2_base_grid))
	end

	-- If level is <= 1, we use the default values
	-- Otherwise we need to combine them when both have values
	if pilotLevel <= 1 then
		if pilotLevel < 0 then
			LOG("PLUS Ext: Error: Pilot level " .. pilotLevel .. " is less than 0. Setting assuming level 0")
		end
		-- Ensure both skills are at their base values in case the pilot
		-- levels down for whatever reason
		restoreBaseValues(skill1, skill2, skill1_base_cores, skill1_base_grid, skill2_base_cores, skill2_base_grid)
	else
		if pilotLevel > 2 then
			LOG("PLUS Ext: Error: Pilot level " .. pilotLevel .. " is greater than 2. Setting assuming level 2")
		end

		-- Both skills are active - combine bonuses only when both have non zero values
		combineWhenBothHaveValues(skill1, skill2, skill1_base_cores, skill1_base_grid, skill2_base_cores, skill2_base_grid)
	end
end

-- Hook handler for pilot level change
-- Logs and delegates to our main combine function
function pilot_bonus_combiner.onPilotLevelChanged(pilot, previousLevel, previousXp)
	if owner.PLUS_DEBUG then
		LOG(string.format("PLUS Ext: Pilot level changed from %d to %d", previousLevel, pilot:getLevel()))
	end
	pilot_bonus_combiner.combinePilotBonuses(pilot)
end

return pilot_bonus_combiner
