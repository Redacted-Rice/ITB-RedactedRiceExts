local extension = {
	id = "redactedrice_memhack",
	name = "MemHack",
	icon = "img/icon.png",
	version = "0.1.0",
	modApiVersion = "2.9.4",
	gameVersion = "1.2.93",
	dependencies = {
        modApiExt = "1.23",
        memedit = "1.2.0",
    },
	isExtension = true,
	enabled = false,
}

function extension:metadata()
end

function extension:init(options)
	local path = self.resourcePath

	require(path.."memhack")
	require(path.."functions/pawn")
	require(path.."functions/pilot")

	memhack:init()
end

function extension:load(options, version)
end

return extension