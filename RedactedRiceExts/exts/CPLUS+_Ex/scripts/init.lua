local extension = {
	id = "redactedrice_cplus_plus",
	name = "CPLUS+ Ex (Pilot Extension)",
	icon = "img/icon.png",
	version = "0.1.0",
	modApiVersion = "2.9.4",
	gameVersion = "1.2.93",
	dependencies = {
        modApiExt = "1.23",
        redactedrice_memhack = "0.1.0",
    },
	isExtension = true,
	enabled = false,
}

function extension:metadata()
	-- will handled through custom UI
end

function extension:init(options)
	local path = self.resourcePath

	require(path.."scripts/cplus_plus_ex")
	cplus_plus_ex:init()
end

function extension:load(options, version)
	cplus_plus_ex:load(options)
end

return extension