-- Hook system for CPLUS+ skill state events
-- Uses reusable functions from memhack hooks

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

-- Register with logging system
local logger = memhack.logger
local SUBMODULE = logger.register("CPLUS+", "Hooks", cplus_plus_ex.DEBUG.HOOKS and cplus_plus_ex.DEBUG.ENABLED)

function hooks:init()
	memhack.hooks.addTo(self, cplus_plus_ex, SUBMODULE)
	self:initBroadcastHooks(self)
	return self
end

function hooks:load()
	memhack.hooks.reload(self, SUBMODULE)
	return self
end

function hooks:initBroadcastHooks(tbl)
	tbl["fireSkillEnabledHooks"] = memhack.hooks.buildBroadcastFunc("skillEnabledHooks", tbl, nil, nil, SUBMODULE)
	tbl["fireSkillInRunHooks"] = memhack.hooks.buildBroadcastFunc("skillInRunHooks", tbl, nil, nil, SUBMODULE)
	tbl["fireSkillActiveHooks"] = memhack.hooks.buildBroadcastFunc("skillActiveHooks", tbl, nil, nil, SUBMODULE)
	tbl["firePreAssigningLvlUpSkillsHooks"] = memhack.hooks.buildBroadcastFunc("preAssigningLvlUpSkillsHooks", tbl, nil, nil, SUBMODULE)
	tbl["firePostAssigningLvlUpSkillsHooks"] = memhack.hooks.buildBroadcastFunc("postAssigningLvlUpSkillsHooks", tbl, nil, nil, SUBMODULE)
	tbl["fireSkillsSelectedHooks"] = memhack.hooks.buildBroadcastFunc("skillsSelectedHooks", tbl, nil, nil, SUBMODULE)
end

return hooks
