local extension = {
	id = "redactedrice_plus",
	name = "Pilot Level Up Skills",
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
end

function extension:init(options)
	local path = self.resourcePath

	require(path.."scripts/plus_ext")
	plus_ext:init()
end

function extension:load(options, version)
end

return extension