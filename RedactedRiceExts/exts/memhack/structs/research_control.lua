local MemhackResearchControl = memhack.structManager.define("ResearchControl", {
	-- intersetingly storage seems to always have at least 3 items.. Maybe it has to do with that
	-- there are 3 spaces in the UI? Anyways we need to be able to account for this
	-- Should I define and expose the vector or wrap it at this point? I'm kind of thinking
	-- of wrapping it. Maybe just a special vector to account for the 3? StorageVector?
	storage = { offset = 0x68, type = "struct", structType = "Vector" },
})

function onModsFirstLoaded()
	-- nothing special to do here for now at least
end

modApi.events.onModsFirstLoaded:subscribe(onModsFirstLoaded)