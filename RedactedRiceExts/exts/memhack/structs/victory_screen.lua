local MemhackVictoryScreen = memhack.structManager.define("VictoryScreen", {
	-- Pod contents are stored here for some reason. The name seems odd but this
	-- is what the code tells me...
	podRewardPilot = { offset = 0x404, type = "pointer", pointedType = "Pilot" },
})

function onModsFirstLoaded()
	-- nothing special to do here for now at least
end

modApi.events.onModsFirstLoaded:subscribe(onModsFirstLoaded)