-- This is not a virtaul object. I couldn't easily find the name and its not
-- worth alot of digging to find
local MemhackUO1 = memhack.structManager.define("UnknownObj1", {
	perfectIslandRewardPilot = { offset = 0x280, type = "pointer", subType = "Pilot" },
})

function onModsFirstLoaded()
	-- nothing special to do here for now at least
end

modApi.events.onModsFirstLoaded:subscribe(onModsFirstLoaded)