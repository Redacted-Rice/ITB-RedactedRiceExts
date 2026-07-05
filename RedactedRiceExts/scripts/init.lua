
local extension =  {
	id = "redactedrice_exts",
	name = "Redacted Rice Extensions",
	version = "1.3.0",
	icon = "icon.png",
	description = "Extensions originally made to support mods by Redacted Rice",
	submodFolders = {"exts/"},
	modApiVersion = "2.9.5",
	gameVersion = "1.2.93",
	requirements = {"easyEdit"}, -- ensures easy edit loads first if its enabled
	dependencies = {
        modApiExt = "1.24",
    },
	isExtension = true,
}

function extension:metadata()
	-- nothing for now
end

function extension:init(options)
	-- nothing for now
end

function extension:load(options, version)
	-- nothing for now
end

return extension