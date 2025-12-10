SkillStruct = {
}

TwoSkillsStruct = {
	-- todo find real values
	skill1 = {0x0, SkillStruct},
	skill2 = {0x20, SkillStruct},
}
PilotStruct = {
	-- todo find real values
	id = {0x0, "string", 16},
	name = {0x10, "string", 16},
	level = {0x20, "int"},
	skills = {0x30, "pointer", TwoSkillsStruct},
	xp = {0x40, "int"},
}

function onPawnClassInitialized(BoardPawn, pawn)
	
	PilotStruct.GetPilot = function(self)
		-- todo
	end
end

-- Maybe a better event to init on?
modApi.events.onPawnClassInitialized:subscribe(onPawnClassInitialized)