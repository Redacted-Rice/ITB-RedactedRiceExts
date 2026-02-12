-- Hook system for CPLUS+ skill state events
-- Uses shared utility functions from memhack hooks

-- Register with logging system
local logger = memhack.logger
local SUBMODULE = logger.register("CPLUS+", "Hooks", cplus_plus_ex.DEBUG.HOOKS and cplus_plus_ex.DEBUG.ENABLED)

-- Create hooks object
local hooks = {
	-- args:
	--  skillId (string) - the skill ID
	--  isEnabled (boolean) - true if enabled, false if disabled
	"skillEnabled",

	-- args:
	--  skillId (string) - the skill ID
	--  isInRun (boolean) - true if added to run, false if removed
	--  pilot (Pilot) - pilot struct that has/had this skill
	--  skillStruct (PilotLvlUpSkill) - skill struct
	"skillInRun",

	-- args:
	--  skillId (string) - the skill ID
	--  isActive (boolean) - true if became active, false if became inactive
	--  pawnId (number) - which mech (0-2)
	--  pilot (Pilot) - pilot struct on/was on active mech
	--  skillStruct (PilotLvlUpSkill) - skill struct
	"skillActive",

	-- args: none
	-- Fired before skills are assigned to pilots when entering a run or when
	-- new pilots are acquired
	"preAssigningLvlUpSkills",

	-- args: none
	-- Fired after skills are assigned to pilots when entering a run or when
	-- new pilots are acquired
	"postAssigningLvlUpSkills",

	-- args:
	--  pilot (Pilot) - pilot struct that will have skills selected
	--  skillId1 (string) - first skill ID selected
	--  skillId2 (string) - second skill ID selected
	-- Fired for each pilot BEFORE their skills are applied to memory
	"skillsSelected",
}

-- Use shared utility functions from memhack.hooks
hooks.addTo = memhack.hooks.addTo
hooks.clearHooks = memhack.hooks.clearHooks
hooks.handleFailure = memhack.hooks.handleFailure
hooks.buildBroadcastFunc = memhack.hooks.buildBroadcastFunc
hooks.reload = memhack.hooks.reload

function hooks:init()
	self:addTo(cplus_plus_ex, SUBMODULE)
	self:initBroadcastHooks()
	return self
end

function hooks:load()
	self:reload(SUBMODULE)
	return self
end

function hooks:initBroadcastHooks()
	self["fireSkillEnabledHooks"] = self:buildBroadcastFunc("skillEnabledHooks", nil, nil, SUBMODULE)
	self["fireSkillInRunHooks"] = self:buildBroadcastFunc("skillInRunHooks", nil, nil, SUBMODULE)
	self["fireSkillActiveHooks"] = self:buildBroadcastFunc("skillActiveHooks", nil, nil, SUBMODULE)
	self["firePreAssigningLvlUpSkillsHooks"] = self:buildBroadcastFunc("preAssigningLvlUpSkillsHooks", nil, nil, SUBMODULE)
	self["firePostAssigningLvlUpSkillsHooks"] = self:buildBroadcastFunc("postAssigningLvlUpSkillsHooks", nil, nil, SUBMODULE)
	self["fireSkillsSelectedHooks"] = self:buildBroadcastFunc("skillsSelectedHooks", nil, nil, SUBMODULE)
end

return hooks
