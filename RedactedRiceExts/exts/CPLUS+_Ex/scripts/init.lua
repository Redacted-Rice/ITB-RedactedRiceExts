local extension = {
	id = "redactedrice_cplus_plus",
	name = "CPLUS+ Ex (Pilot Extension)",
	icon = "img/icon.png",
	version = "1.2.0",
	modApiVersion = "2.9.5",
	gameVersion = "1.2.93",
	requirements = {"easyEdit"}, -- ensures easy edit loads first if its enabled
	dependencies = {
        modApiExt = "1.24",
        redactedrice_memhack = "1.2.0",
    },
	isExtension = true,
}

function extension:metadata()
	-- Add config option to show pilot skill icons
	modApi:addGenerationOption(
		"showPilotSkillIcons",
		"Show Pilot Skill Icons",
		"Display icons next to pilot skill names in the hangar",
		{ enabled = true }
	)
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