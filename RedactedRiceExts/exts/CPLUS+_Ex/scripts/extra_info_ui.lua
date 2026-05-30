-- Extra Info UI Display
-- Shows icons for virtual skills and earned pilot skills
-- - Virtual skills panel at bottom shows icons for mod-added virtual skills
-- - Earned skills icons next to pilot skill names in hangar (if enabled)
--
-- Both positioned relative to the back_1 pilot portrait as a known image that we can offset a fixed distances from

local extra_info_ui = {}

-- Register with logging system
local logger = memhack.logger
local SUBMODULE = logger.register("CPLUS+", "ExtraInfoUI", cplus_plus_ex.DEBUG.EXTRA_INFO_UI and cplus_plus_ex.DEBUG.ENABLED)

-- Virtual skills panel constants
local PANEL_ICON_SCALE = 2  -- Scale factor for icon surfaces
local PANEL_ICON_OUTLINE = 1  -- Outline width for icons (scaled)
local PANEL_HEIGHT = 50  -- Fixed panel height
local PANEL_ICON_PADDING = 2  -- Padding between icons and from left edge
local PANEL_FIXED_WIDTH = 315  -- Fixed panel width
local PANEL_REFERENCE_OFFSET_X = -44  -- X offset from back_1 image
local PANEL_REFERENCE_OFFSET_Y = 314  -- Y offset from back_1 image

-- Earned skills icons constants
local SKILL_ICON_SCALE = 1  -- Scale factor for icon surfaces
local SKILL_ICON_OUTLINE = 1  -- Outline width for icons (scaled)
local SKILL_ICON_CENTER_OFFSET_X = -21  -- X center offset from back_1 for first skill icon
local SKILL_ICON_CENTER_OFFSET_Y = 225  -- Y center offset from back_1 for first skill
local SKILL_ICON_CENTER_OFFSET_Y_NO_INNATE = 204
local SKILL_SPACING_Y = 45  -- Vertical spacing between skill icons

-- UI State - Virtual skills panel
local panel = nil
local iconRow = nil
local panelIconData = {}  -- Array of {icon, title, description}

-- UI State - Earned skills icons
local earnedSkillWidgets = {}  -- Array of icon UI elements

-- Shared state
local lastSelectedPawnId = nil
local lastPilotId = nil
local currentPilot = nil
local currentPawn = nil
local lastScreenWidth = nil
local lastScreenHeight = nil

-- Load the back_1 surface for positioning reference
local back1Surface = sdlext.getSurface{ path = "img/portraits/pilots/back_1.png" }

-------------------------------------------------------------------------------
-- Common helpers
-------------------------------------------------------------------------------

-- Get the pilot for the currently selected pawn
function extra_info_ui:getSelectedPilot()
	if not Game then
		return nil
	end

	local selectedPawnId = Game:GetStrategySelectedPawn()
	if not selectedPawnId then
		return nil
	end

	local pawn = Game:GetPawn(selectedPawnId)
	if not pawn then
		return nil
	end

	local pilot = pawn:GetPilot()
	return pilot, selectedPawnId, pawn
end

-- Find the back_1 portrait image position
-- Returns position if found, or nil, nil if not found
function extra_info_ui:findBack1Position()
	if back1Surface and back1Surface:wasDrawn() then
		return back1Surface.x, back1Surface.y
	end
	return nil, nil
end

-- Create an outlined and scaled icon surface
function extra_info_ui:createIconSurface(iconPath, scale, outline)
	local surface = sdlext.getSurface({ path = iconPath })
	if not surface then
		return nil
	end

	local outlined = sdl.outlined(surface, outline, deco.colors.buttonborder)
	local scaled = sdl.scaled(scale, outlined)
	return scaled
end

-------------------------------------------------------------------------------
-- COMMON UI UPDATE LOGIC
-------------------------------------------------------------------------------

-- Clear selected data to force refresh on next update
function extra_info_ui:clearSelectedData()
	if lastSelectedPawnId or lastPilotId then
		lastSelectedPawnId = nil
		lastPilotId = nil
		logger.logDebug(SUBMODULE, "Cleared selection data")
		return true
	end
	return false
end

-- Hide both UIs and clear selected data
function extra_info_ui:hideAllAndClearData()
	-- Only clear and log if there was something selected. Otherwise its already hidden
	if self:clearSelectedData() then
		self:hideVirtualSkillsPanel()
		self:hideEarnedSkillsIcons()
		logger.logDebug(SUBMODULE, "Hid all UIs and cleared data")
	end
end

-- Check if the selected pawn has changed and update both UIs
function extra_info_ui:checkAndUpdate()
	-- Hide if in mission
	if GetCurrentMission() then
		self:hideAllAndClearData()
		return
	end

	if not Game then
		self:hideAllAndClearData()
		return
	end

	-- Calculate back_1 position
	local back1X, back1Y = self:findBack1Position()
	if not back1X then
		self:hideAllAndClearData()
		return
	end

	local selectedPawnId = Game:GetStrategySelectedPawn()
	if not selectedPawnId then
		self:hideAllAndClearData()
		return
	end

	local pilot, pawnId, pawn = self:getSelectedPilot()
	local pilotId = pilot and pilot:getIdStr() or nil

	-- Check screen size changes
	local currentWidth = ScreenSizeX()
	local currentHeight = ScreenSizeY()
	local sizeChanged = (lastScreenWidth ~= currentWidth or lastScreenHeight ~= currentHeight)
	if sizeChanged then
		lastScreenWidth = currentWidth
		lastScreenHeight = currentHeight
		logger.logDebug(SUBMODULE, "Screen size changed to %dx%d", currentWidth, currentHeight)
		self:clearSelectedData()
	end

	-- Check if selection changed
	local selectionChanged = (selectedPawnId ~= lastSelectedPawnId) or (pilotId ~= lastPilotId)
	if selectionChanged or sizeChanged then
		logger.logInfo(SUBMODULE, "Update triggered: selectionChanged=%s, sizeChanged=%s",
			tostring(selectionChanged), tostring(sizeChanged))
		lastSelectedPawnId = selectedPawnId
		lastPilotId = pilotId

		-- Update both UIs with the same back_1 position
		self:showVirtualSkillsPanel(back1X, back1Y, pilot, pilotId)
		self:showEarnedSkillsIcons(back1X, back1Y, pilot, pilotId)
	end
end

-------------------------------------------------------------------------------
-- VIRTUAL SKILLS PANEL
-------------------------------------------------------------------------------

-- Add an icon to the virtual skills panel
-- This is called by mods via the hook to add their own icons
-- Both title and description are required
function extra_info_ui:addIcon(icon, title, description)
	if not icon or not title or not description then
		logger.logWarn(SUBMODULE, "addIcon: icon, title, and description are all required. Skipping.")
		return
	end

	table.insert(panelIconData, {
		icon = icon,
		title = title,
		description = description
	})
	logger.logDebug(SUBMODULE, "Added panel icon: %s, title: %s", tostring(icon), tostring(title))
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

-- Build a panel icon UI element with tooltip
function extra_info_ui:buildPanelIcon(iconInfo, container)
	if not iconInfo.icon then
		logger.logWarn(SUBMODULE, "buildPanelIcon: no icon path provided")
		return
	end

	local scaled = self:createIconSurface(iconInfo.icon, PANEL_ICON_SCALE, PANEL_ICON_OUTLINE)
	if not scaled then
		logger.logWarn(SUBMODULE, "buildPanelIcon: failed to load icon from %s", iconInfo.icon)
		return
	end

	-- Create icon UI with outlined surface, vertically centered
	local iconUi = Ui()
		:widthpx(scaled:w())
		:height(1)
		:decorate({ DecoSurfaceAligned(scaled, "center", "center") })
		:addTo(container)

	-- Set tooltip with title and description (both guaranteed to exist by addIcon)
	local tooltipText = iconInfo.title .. "\n\n" .. iconInfo.description
	iconUi:settooltip(tooltipText)

	-- Add padding after icon
	Ui():widthpx(PANEL_ICON_PADDING):heightpx(1):addTo(container)
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
	panelIconData = {}

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
	cplus_plus_ex.hooks.fireExtraInfoSelectedChangedHooks(self, pawn, pilot)
	logger.logDebug(SUBMODULE, "rebuildContent: hooks fired, icon count=%d", #panelIconData)

	-- Build all icons
	if #panelIconData > 0 then
		logger.logDebug(SUBMODULE, "rebuildContent: building %d icons", #panelIconData)

		-- Add padding before first icon
		Ui():widthpx(PANEL_ICON_PADDING):heightpx(1):addTo(iconRow)

		for i, icon in ipairs(panelIconData) do
			self:buildPanelIcon(icon, iconRow)
		end
	else
		logger.logDebug(SUBMODULE, "rebuildContent: no icons to display")
	end

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
	-- Start offscreen until we have a valid position
	panel = Ui()
		:widthpx(PANEL_FIXED_WIDTH)
		:heightpx(PANEL_HEIGHT)
		:pospx(-1000, -1000)
		:decorate({
			DecoSolid(deco.colors.framebg),
			DecoFrame(deco.colors.framebg, deco.colors.buttonborder, 2)
		})
		:addTo(uiRoot)

	-- Icon row container (horizontal layout)
	iconRow = UiWeightLayout()
		:width(1)
		:height(1)
		:addTo(panel)

	-- Build initial content
	self:rebuildContent()

	-- Start hidden - will be shown when appropriate
	panel:hide()

	logger.logDebug(SUBMODULE, "Extra info panel created")
end

-- Hide the virtual skills panel
function extra_info_ui:hideVirtualSkillsPanel()
	if panel then
		panel:hide()
		logger.logDebug(SUBMODULE, "Virtual skills panel hidden")
	end
end

-- Show/update the virtual skills panel with given back_1 position
function extra_info_ui:showVirtualSkillsPanel(back1X, back1Y, pilot, pilotId)
	if not panel then return end

	if not pilot or not pilotId then
		self:hideVirtualSkillsPanel()
		return
	end

	-- Rebuild panel content
	self:rebuildContent()

	-- If no content, hide and return
	if #panelIconData == 0 then
		logger.logDebug(SUBMODULE, "No virtual skills for pilot %s, hiding panel", pilotId)
		self:hideVirtualSkillsPanel()
		return
	end

	-- Position panel relative to back_1
	panel.x = back1X + PANEL_REFERENCE_OFFSET_X
	panel.y = back1Y + PANEL_REFERENCE_OFFSET_Y
	logger.logInfo(SUBMODULE, "Showing virtual skills panel for pilot %s with %d icons at (%d, %d)",
		pilotId, #panelIconData, panel.x, panel.y)

	-- Show panel
	panel:show()
end

-------------------------------------------------------------------------------
-- EARNED SKILLS ICONS
-------------------------------------------------------------------------------

-- Check if earned skill icons should be displayed (config option)
function extra_info_ui:shouldShowEarnedSkillIcons()
	return cplus_plus_ex.config_options.showPilotSkillIcons
end

-- Create an icon widget for an earned skill
function extra_info_ui:createEarnedSkillIcon(skillInfo, x, y)
	if not skillInfo or not skillInfo.icon then
		return nil
	end

	local scaled = self:createIconSurface(skillInfo.icon, SKILL_ICON_SCALE, SKILL_ICON_OUTLINE)
	if not scaled then
		logger.logWarn(SUBMODULE, "Failed to load earned skill icon from %s", skillInfo.icon)
		return nil
	end

	-- Create icon UI positioned absolutely
	local iconUi = Ui()
		:widthpx(scaled:w())
		:heightpx(scaled:h())
		:pospx(x - scaled:w() / 2, y - scaled:h() / 2)
		:decorate({ DecoSurfaceAligned(scaled, "center", "center") })
		:addTo(sdlext.getUiRoot())

	logger.logDebug(SUBMODULE, "Created earned skill icon for %s at (%d, %d)", skillInfo.id, x, y)
	return iconUi
end

-- Hide the earned skills icons
function extra_info_ui:hideEarnedSkillsIcons()
	logger.logDebug(SUBMODULE, "Hiding %d earned skill icon widgets", #earnedSkillWidgets)
	for _, widget in ipairs(earnedSkillWidgets) do
		if widget then
			widget:detach()
		end
	end
	earnedSkillWidgets = {}
end

-- Show/update earned skill icons with given back_1 position
function extra_info_ui:showEarnedSkillsIcons(back1X, back1Y, pilot, pilotId)
	if not self:shouldShowEarnedSkillIcons() then
		self:hideEarnedSkillsIcons()
		return
	end

	if not pilot or not pilotId then
		self:hideEarnedSkillsIcons()
		return
	end

	-- Clear existing icons
	self:hideEarnedSkillsIcons()

	local skills = {}

	-- Get earned skill IDs from the skill object
	local earnedIdx = cplus_plus_ex:getPilotEarnedSkillIndexes(pilot)
	for _, idx in ipairs(earnedIdx) do
		if idx > 0 and idx <= 2 then
			table.insert(skills, pilot:getLvlUpSkill(idx):getIdStr())
		end
	end

	local pilotSkill = pilot:getSkillStr()
	local baseYOffset = SKILL_ICON_CENTER_OFFSET_Y
	if pilotSkill == nil or pilotSkill == "" then
		baseYOffset = SKILL_ICON_CENTER_OFFSET_Y_NO_INNATE
	end

	-- Create icon for each skill
	for i, skillId in ipairs(skills) do
		local skillInfo = cplus_plus_ex:getRegisteredSkillInfo(skillId)
		if skillInfo then
			local iconX = back1X + SKILL_ICON_CENTER_OFFSET_X
			local iconY = back1Y + baseYOffset + ((i - 1) * SKILL_SPACING_Y)

			local widget = self:createEarnedSkillIcon(skillInfo, iconX, iconY)
			if widget then
				table.insert(earnedSkillWidgets, widget)
			end
		end
	end

	logger.logInfo(SUBMODULE, "Showing %d earned skill icons for pilot %s at (%d, %d)",
		#earnedSkillWidgets, pilotId, back1X, back1Y)
end

-------------------------------------------------------------------------------
-- INITIALIZATION
-------------------------------------------------------------------------------

-- Initialize hooks
function extra_info_ui:init()
	logger.logDebug(SUBMODULE, "Initializing extra info UI")

	-- Create the panel when UI root is ready
	modApi.events.onUiRootCreated:subscribe(function(screen, uiRoot)
		logger.logDebug(SUBMODULE, "UI root created, creating extra info panel")
		self:createPanel()
	end)

	-- Use onFrameDrawStart to check for changes every frame
	modApi.events.onFrameDrawStart:subscribe(function()
		self:checkAndUpdate()
	end)

	logger.logDebug(SUBMODULE, "Extra info UI initialized")
end

return extra_info_ui
