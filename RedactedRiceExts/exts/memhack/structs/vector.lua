-- std c++ vector
local MemhackVector = memhack.structManager.define("Vector", {
	head = { offset = 0x0, type = "int" },
	next = { offset = 0x4, type = "int" },
	max = { offset = 0x8, type = "int" },
})

function onModsFirstLoaded()
	-- todo: add some functions
	-- getFirst
	-- getSize
	-- getIdx
	-- getAll
end

modApi.events.onModsFirstLoaded:subscribe(onModsFirstLoaded)