-- FWIW I found two ways so far to get GameMap other than Game in lua


local MemhackGameMap = memhack.structManager.define("GameMap", {
	researchControl = { offset = 0x5674, type = "struct", structType = "ResearchControl" },
	reputation = { offset = 0x848C, type = "int" },
})

function onModsFirstLoaded()
	-- nothing special to do here for now at least
end

modApi.events.onModsFirstLoaded:subscribe(onModsFirstLoaded)