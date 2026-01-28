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
	--  skill (PilotLvlUpSkill) - skill struct
	"skillInRun",

	-- args:
	--  skillId (string) - the skill ID
	--  isActive (boolean) - true if became active, false if became inactive
	--  pawnId (number) - which mech (0-2)
	--  pilot (Pilot) - pilot struct on/was on active mech
	--  skill (PilotLvlUpSkill) - skill struct
	"skillActive",

	DEBUG = true,
}

function hooks:init()
	memhack.hooks.addTo(self, cplus_plus_ex, self.DEBUG and "CPLUS+" or nil)
	self:initBroadcastHooks(self)
	return self
end

function hooks:load()
	memhack.hooks.reload(self, self.DEBUG and "CPLUS+" or nil)
	return self
end

function hooks:initBroadcastHooks(tbl)
	tbl["fireSkillEnabledHooks"] = memhack.hooks.buildBroadcastFunc("skillEnabledHooks", tbl, nil, nil, self.DEBUG and "CPLUS+" or nil)
	tbl["fireSkillInRunHooks"] = memhack.hooks.buildBroadcastFunc("skillInRunHooks", tbl, nil, nil, self.DEBUG and "CPLUS+" or nil)
	tbl["fireSkillActiveHooks"] = memhack.hooks.buildBroadcastFunc("skillActiveHooks", tbl, nil, nil, self.DEBUG and "CPLUS+" or nil)
end

return hooks
