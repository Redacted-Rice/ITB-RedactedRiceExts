-- Extra Info UI Display
-- Shows icons for virtual skills and mod-added content for the currently selected pawn in strategy view
-- Updates when Game:GetStrategySelectedPawn() changes
--
-- Panel is positioned relative to the back_1 pilot portrait in the bottom-left
-- Fixed width of 315px with background frame

local extra_info_ui = {}

-- Register with logging system
local logger = memhack.logger
local SUBMODULE = logger.register("CPLUS+", "ExtraInfoUI", cplus_plus_ex.DEBUG.EXTRA_INFO_UI and cplus_plus_ex.DEBUG.ENABLED)

-- Reference to hooks module
local hooks = nil

-- UI constants
local ICON_PADDING = 2  -- Padding between icons AND from left edge to first icon
local ICON_SCALE = 2  -- Scale factor for icon surfaces
local ICON_OUTLINE = 1  -- Outline width for icons (scaled)
local PANEL_PADDING = 4  -- Minimal padding around content
local PANEL_FIXED_WIDTH = 315  -- Fixed panel width
local PANEL_REFERENCE_OFFSET_X = -44  -- X offset from back_1 image
local PANEL_REFERENCE_OFFSET_Y = 314  -- Y offset from back_1 image

-- UI State
local panel = nil
local iconRow = nil
local lastSelectedPawnId = nil
local lastPilotId = nil
local currentPilot = nil
local currentPawn = nil
local iconData = {}  -- Array of {icon, title, description}
local lastScreenWidth = nil
local lastScreenHeight = nil

-- Load the back_1 surface for positioning reference
local back1Surface = sdlext.getSurface{ path = "img/portraits/pilots/back_1.png" }

-- Get the pilot for the currently selected pawn
function extra_info_ui:getSelectedPilot()
	logger.logDebug(SUBMODULE, "getSelectedPilot: Game=%s", tostring(Game ~= nil))
	if not Game then
		return nil
	end

	-- Use Game:GetStrategySelectedPawn() to get selected pawn index
	local selectedPawnId = Game:GetStrategySelectedPawn()
	logger.logDebug(SUBMODULE, "getSelectedPilot: selectedPawnId=%s", tostring(selectedPawnId))
	if not selectedPawnId then
		return nil
	end

	-- Get the pawn at that index
	local pawn = Game:GetPawn(selectedPawnId)
	logger.logDebug(SUBMODULE, "getSelectedPilot: pawn=%s", tostring(pawn ~= nil))
	if not pawn then
		return nil
	end

	-- Get the pilot from the pawn (memhack struct)
	local pilot = pawn:GetPilot()
	logger.logDebug(SUBMODULE, "getSelectedPilot: pilot=%s", tostring(pilot ~= nil))
	return pilot, selectedPawnId, pawn
end

-- Add an icon to the UI
-- This is called by mods via the hook to add their own icons
function extra_info_ui:addIcon(icon, title, description)
	table.insert(iconData, {
		icon = icon,
		title = title,
		description = description
	})
	logger.logDebug(SUBMODULE, "Added icon: %s, title: %s", tostring(icon), tostring(title))
end

-- Collect virtual skill icons for a pilot
function extra_info_ui:collectVirtualSkillIcons(pilot)
	if not pilot then
		return
	end

	local pilotId = pilot:getIdStr()
	local virtualSkills = cplus_plus_ex:getVirtualSkills(pilotId)

	if virtualSkills and #virtualSkills > 0 then
		logger.logDebug(SUBMODULE, "Collecting %d virtual skill icons for pilot %s", #virtualSkills, pilotId)
		for _, skillId in ipairs(virtualSkills) do
			local skillInfo = cplus_plus_ex:getRegisteredSkillInfo(skillId)
			if skillInfo and skillInfo.icon then
				local title = GetText(skillInfo.fullName)
				local description = GetText(skillInfo.description)
				logger.logDebug(SUBMODULE, "Adding virtual skill icon: %s", skillId)
				self:addIcon(skillInfo.icon, title, description)
			end
		end
	end
	logger.logDebug(SUBMODULE, "Collected virtual skill icons for pilot %s", pilotId)
end

-- Build an icon UI element with tooltip
function extra_info_ui:buildIcon(iconInfo, container)
	logger.logDebug(SUBMODULE, "buildIcon: icon=%s, title=%s", tostring(iconInfo.icon), tostring(iconInfo.title))

	if not iconInfo.icon then
		logger.logWarn(SUBMODULE, "buildIcon: no icon path provided")
		return
	end

	-- Load the icon surface
	local surface = sdlext.getSurface({ path = iconInfo.icon })
	if not surface then
		logger.logWarn(SUBMODULE, "buildIcon: failed to load icon from %s", iconInfo.icon)
		return
	end

	-- Outline and scale the surface (outline first, then scale)
	local outlined = sdl.outlined(surface, ICON_OUTLINE, deco.colors.buttonborder)
	local scaled = sdl.scaled(ICON_SCALE, outlined)

	-- Calculate actual icon size based on scaled surface dimensions
	local iconWidth = scaled:w()
	local iconHeight = scaled:h()
	logger.logDebug(SUBMODULE, "buildIcon: calculated size %dx%d", iconWidth, iconHeight)

	-- Create icon UI with outlined surface, sized to actual surface dimensions
	local iconUi = Ui()
		:widthpx(iconWidth)
		:height(1)
		:decorate({ DecoSurfaceAligned(scaled, "center", "center") })
		:addTo(container)

	-- Set tooltip with title and description combined
	if iconInfo.title or iconInfo.description then
		local tooltipText = ""
		if iconInfo.title and iconInfo.title ~= "" then
			tooltipText = iconInfo.title
		end
		if iconInfo.description and iconInfo.description ~= "" then
			if tooltipText ~= "" then
				tooltipText = tooltipText .. "\n\n" .. iconInfo.description
			else
				tooltipText = iconInfo.description
			end
		end
		if tooltipText ~= "" then
			iconUi:settooltip(tooltipText)
			logger.logDebug(SUBMODULE, "buildIcon: added tooltip for %s", iconInfo.title or "icon")
		end
	end

	-- Add padding after icon (spacing between icons)
	Ui():widthpx(ICON_PADDING):heightpx(1):addTo(container)
	logger.logDebug(SUBMODULE, "buildIcon: icon complete")
end

-- Find the back_1 portrait image position using the surface approach from traitReplace
local function findBack1Position()
	-- Check if the back_1 surface was drawn this frame
	if back1Surface and back1Surface:wasDrawn() then
		logger.logDebug(SUBMODULE, "back_1 found at (%d, %d)", back1Surface.x, back1Surface.y)
		return back1Surface.x, back1Surface.y
	end
	return nil, nil
end

-- Update panel position and size
function extra_info_ui:updatePanelLayout()
	if not panel then return end

	local currentWidth = ScreenSizeX()
	local currentHeight = ScreenSizeY()

	-- Check if screen size changed
	local sizeChanged = (lastScreenWidth ~= currentWidth or lastScreenHeight ~= currentHeight)
	if sizeChanged then
		lastScreenWidth = currentWidth
		lastScreenHeight = currentHeight
		logger.logDebug(SUBMODULE, "Screen size changed to %dx%d", currentWidth, currentHeight)
	end

	-- Try to find back_1 position
	local back1X, back1Y = findBack1Position()
	local panelX, panelY

	if back1X and back1Y then
		-- Position relative to back_1
		panelX = back1X + PANEL_REFERENCE_OFFSET_X
		panelY = back1Y + PANEL_REFERENCE_OFFSET_Y
		logger.logDebug(SUBMODULE, "Positioning panel relative to back_1 at (%d, %d), calculated panel pos: (%d, %d)",
			back1X, back1Y, panelX, panelY)
	else
		-- back_1 not found - keep offscreen
		panelX = -1000
		panelY = -1000
		logger.logDebug(SUBMODULE, "back_1 not found, keeping offscreen")
	end

	-- Update panel position (width is fixed)
	panel.x = panelX
	panel.y = panelY

	-- Force relayout if screen size changed
	if sizeChanged then
		panel:relayout()
	end
end

-- Rebuild the panel content
function extra_info_ui:rebuildContent()
	logger.logDebug(SUBMODULE, "rebuildContent: starting")

	if not iconRow then
		logger.logWarn(SUBMODULE, "rebuildContent: iconRow is nil, aborting")
		return
	end

	-- Clear existing icons
	logger.logDebug(SUBMODULE, "rebuildContent: clearing %d children", #iconRow.children)
	while #iconRow.children > 0 do
		iconRow.children[#iconRow.children]:detach()
	end

	-- Reset icon data for this rebuild
	iconData = {}

	local pilot, selectedPawnId, pawn = self:getSelectedPilot()
	if not pilot then
		logger.logDebug(SUBMODULE, "rebuildContent: no pilot")
		return
	end

	-- Store current pilot and pawn for hook access
	currentPilot = pilot
	currentPawn = pawn

	-- Collect virtual skill icons
	logger.logDebug(SUBMODULE, "rebuildContent: collecting virtual skill icons")
	self:collectVirtualSkillIcons(pilot)

	-- Fire hook to allow mods to add their own icons
	logger.logDebug(SUBMODULE, "rebuildContent: firing ExtraInfoSelectedChanged hooks for pilot %s", pilot:getIdStr())
	hooks.fireExtraInfoSelectedChangedHooks(self, pawn, pilot)
	logger.logDebug(SUBMODULE, "rebuildContent: hooks fired, icon count=%d", #iconData)

	-- Build all icons
	if #iconData > 0 then
		logger.logDebug(SUBMODULE, "rebuildContent: building %d icons", #iconData)

		-- Add padding before first icon
		Ui():widthpx(ICON_PADDING):heightpx(1):addTo(iconRow)

		for i, icon in ipairs(iconData) do
			self:buildIcon(icon, iconRow)
		end
	else
		logger.logDebug(SUBMODULE, "rebuildContent: no icons to display")
	end

	-- Update panel layout after building icons
	self:updatePanelLayout()

	logger.logDebug(SUBMODULE, "rebuildContent: complete")
end


-- Create the panel on init
function extra_info_ui:createPanel()
	if panel then
		return
	end

	logger.logDebug(SUBMODULE, "Creating extra info panel")

	local uiRoot = sdlext.getUiRoot()
	if not uiRoot then
		logger.logError(SUBMODULE, "Cannot create panel: UI root not available")
		return
	end

	-- Initialize screen size tracking
	lastScreenWidth = ScreenSizeX()
	lastScreenHeight = ScreenSizeY()

	-- Main panel container with fixed width
	-- Height will be calculated based on actual icon sizes
	-- Start offscreen until we have a valid position
	panel = Ui()
		:widthpx(PANEL_FIXED_WIDTH)
		:heightpx(50)
		:pospx(-1000, -1000)
		:decorate({
			DecoSolid(deco.colors.framebg),
			DecoFrame(deco.colors.framebg, deco.colors.buttonborder, 2)
		})
		:addTo(uiRoot)

	-- Icon row container (horizontal layout)
	-- We'll calculate actual height after building icons
	iconRow = UiWeightLayout()
		:width(1)
		:height(1)  -- Will fill panel height
		:addTo(panel)

	-- Build initial content
	self:rebuildContent()

	-- Start hidden - will be shown when appropriate
	panel:hide()

	logger.logDebug(SUBMODULE, "Extra info panel created")
end

-- Show the panel
function extra_info_ui:showPanel()
	if panel then
		panel:show()
		logger.logDebug(SUBMODULE, "Extra info panel shown")
	end
end

-- Hide the panel
function extra_info_ui:hidePanel()
	if panel then
		panel:hide()
		logger.logDebug(SUBMODULE, "Extra info panel hidden")
	end
end

-- Check if the selected pawn has changed and update UI accordingly
function extra_info_ui:checkAndUpdate()
	-- Don't do anything if panel hasn't been created yet
	if not panel then
		return
	end

	-- Check and update panel layout for screen size changes
	self:updatePanelLayout()

	-- Not in game, hide panel
	if not Game then
		if panel.visible then
			logger.logDebug(SUBMODULE, "checkAndUpdate: Game is nil, hiding panel")
		end
		self:hidePanel()
		lastSelectedPawnId = nil
		lastPilotId = nil
		return
	end

	-- If no pawn selected, hide panel
	local selectedPawnId = Game:GetStrategySelectedPawn()
	if not selectedPawnId then
		if panel.visible then
			logger.logDebug(SUBMODULE, "checkAndUpdate: No pawn selected, hiding panel")
		end
		self:hidePanel()
		lastSelectedPawnId = nil
		lastPilotId = nil
		return
	end

	-- Get the pilot for the selected pawn
	local pilot, pawnId, pawn = self:getSelectedPilot()
	local pilotId = pilot and pilot:getIdStr() or nil

	-- Check if selection changed
	local selectionChanged = (selectedPawnId ~= lastSelectedPawnId) or (pilotId ~= lastPilotId)

	if selectionChanged then
		logger.logInfo(SUBMODULE, "Selection changed: pawnId=%s->%s, pilotId=%s->%s",
			tostring(lastSelectedPawnId), tostring(selectedPawnId),
			tostring(lastPilotId), tostring(pilotId))
		lastSelectedPawnId = selectedPawnId
		lastPilotId = pilotId

		-- If we have a valid pilot, rebuild content and check if we should show
		if pilot and pilotId then
			logger.logDebug(SUBMODULE, "checkAndUpdate: valid pilot found, rebuilding content")

			-- Rebuild content (this will fire hooks and collect icons)
			self:rebuildContent()

			-- Show if we have any icons
			if #iconData > 0 then
				logger.logInfo(SUBMODULE, "Showing panel for pilot %s with %d icons",
					pilotId, #iconData)
				self:showPanel()
			else
				logger.logDebug(SUBMODULE, "No content for pilot %s, hiding panel", pilotId)
				self:hidePanel()
			end
		else
			logger.logWarn(SUBMODULE, "No valid pilot (pilot=%s, pilotId=%s), hiding panel",
				tostring(pilot ~= nil), tostring(pilotId))
			self:hidePanel()
		end
	end
end

-- Initialize hooks
function extra_info_ui:init()
	logger.logDebug(SUBMODULE, "Initializing extra info UI")

	-- Verify back_1 surface loaded
	if back1Surface then
		logger.logInfo(SUBMODULE, "back_1 surface loaded successfully")
	else
		logger.logError(SUBMODULE, "Failed to load back_1 surface!")
	end

	-- Get reference to hooks module
	hooks = cplus_plus_ex._subobjects.hooks

	-- Create the panel when UI root is ready
	modApi.events.onUiRootCreated:subscribe(function(screen, uiRoot)
		logger.logDebug(SUBMODULE, "UI root created, creating extra info panel")
		self:createPanel()
	end)

	-- Use onFrameDrawStart to check for changes every frame
	modApi.events.onFrameDrawStart:subscribe(function()
		self:checkAndUpdate()
	end)

	-- Hide UI when entering test mode or combat
	modApi.events.onTestMechEntered:subscribe(function()
		logger.logDebug(SUBMODULE, "Test mode entered, hiding panel")
		self:hidePanel()
	end)
	-- Hide UI when entering test mode or combat
	modApi.events.onTestMechExited:subscribe(function()
		logger.logDebug(SUBMODULE, "Test mode exited, checking for selected pawn")
		-- Give the game a moment to update, then check and update
		modApi:runLater(function()
			self:checkAndUpdate()
			logger.logDebug(SUBMODULE, "Re-checked panel after test mode exit")
		end)
	end)

	modApi.events.onMissionStart:subscribe(function()
		logger.logDebug(SUBMODULE, "Mission started, hiding panel")
		self:hidePanel()
	end)

	logger.logDebug(SUBMODULE, "Extra info UI initialized")
end

return extra_info_ui
