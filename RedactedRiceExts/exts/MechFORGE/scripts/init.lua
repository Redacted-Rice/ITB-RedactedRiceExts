local extension = {
	id = "redactedrice_mech_forge",
	name = "MechFORGE (Mech Upgrades Extension)",
	icon = "img/icon.png",
	version = "1.0.0",
	modApiVersion = "2.9.7",
	gameVersion = "1.2.93",
	dependencies = {
		modApiExt = "1.24",
		memedit = "1.2.1",
		redactedrice_memhack = "1.5.0",
	},
	isExtension = true,
}

function extension:metadata()
end

function extension:init(options)
	local path = self.resourcePath

	-- Initialize main extension
	require(path.."mech_forge")
	mech_forge:init()
end

function extension:load(options, version)
	mech_forge:load(options, version)
end

return extension
