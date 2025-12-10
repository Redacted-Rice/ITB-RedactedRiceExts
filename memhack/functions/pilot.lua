
local PilotStruct = memhack.structManager.define("Pilot", {
	-- todo find real values
	id = { offset = 0x0, type = "string", maxLength = 16},
	name = { offset = 0x10, type = "string", maxLength = 16},
	level = { offset = 0x20, type = "int"},
	--skills = { offset = 0x30, type = "pointer", pointedType = TwoSkillsStruct},
	xp = { offset = 0x40, type = "int"},
})

function onPawnClassInitialized(BoardPawn, pawn)
	-- anything needed? Probably not - just exposing pilot struct and auto defined
    -- fns should be enough
end

-- Maybe a better event to init on?
modApi.events.onPawnClassInitialized:subscribe(onPawnClassInitialized)
