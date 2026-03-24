local extension = {
	id = "redactedrice_memhack",
	name = "Mem Hack",
	icon = "img/icon.png",
	version = "1.0.0",
	modApiVersion = "2.9.5",
	gameVersion = "1.2.93",
	dependencies = {
        modApiExt = "1.24",
    },
	isExtension = true,
}

function extension:metadata()
end

function extension:init(options)
	local path = self.resourcePath

	require(path.."memhack")
	memhack:init()
end

function extension:load(options, version)
	memhack:load()
end

return extension