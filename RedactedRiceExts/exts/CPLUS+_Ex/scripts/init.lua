local extension = {
	id = "redactedrice_cplus_plus",
	name = "CPLUS+ Ex (Pilot Extension)",
	icon = "img/icon.png",
	version = "1.1.0",
	modApiVersion = "2.9.5",
	gameVersion = "1.2.93",
	dependencies = {
        modApiExt = "1.24",
        redactedrice_memhack = "1.0.0",
    },
	isExtension = true,
}

function extension:metadata()
	-- Configuration handled through custom UI
end

function extension:init(options)
	local path = self.resourcePath

	-- Initialize main extension
	require(path.."cplus_plus_ex")
	cplus_plus_ex:init()
end

function extension:load(options, version)
	cplus_plus_ex:load(options)
end

return extension