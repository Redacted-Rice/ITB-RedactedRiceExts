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
	-- For UI/display options, we want global settings and not per run
	-- so read directly from modcontent.lua instead of using the passed 
	-- options which come from GAME.modOptions
	local globalOptions = nil
	sdlext.config("modcontent.lua", function(obj)
		if obj.modOptions and obj.modOptions.redactedrice_cplus_plus then
			globalOptions = obj.modOptions.redactedrice_cplus_plus.options
		end
	end)
	
	cplus_plus_ex.config_options = {}
	if globalOptions and globalOptions.showPilotSkillIcons then
		cplus_plus_ex.config_options.showPilotSkillIcons = globalOptions.showPilotSkillIcons.enabled
	else
		cplus_plus_ex.config_options.showPilotSkillIcons = true
	end

	cplus_plus_ex:load(options, version)
end

return extension