
local extension =  {
	id = "redactedrice_exts",
	name = "Redacted Rice Extensions",
	version = "1.1.0",
	icon = "icon.png",
	description = "Extensions originally made to support mods by Redacted Rice",
	submodFolders = {"exts/"},
	modApiVersion = "2.9.5",
	gameVersion = "1.2.93",
	dependencies = {
        modApiExt = "1.24",
        memedit = "1.2.1",
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