-- Modify Pilot Skills UI
-- UI for modifying skill weights and configurations

local modify_pilot_skills_ui = {}

-- Register with logging system
local logger = memhack.logger
local SUBMODULE = logger.register("CPLUS+", "SkillsUI", cplus_plus_ex.DEBUG.UI and cplus_plus_ex.DEBUG.ENABLED)

local utils = nil

local scrollContent = nil
-- Track UI widgets for updates
local percentageLabels = {}
local expandedCollapsables = {}
local groupHeaderLabels = {}
local relationshipsContainer = nil
local relationshipsParent = nil
local groupsContainer = nil
local groupsParent = nil

-- Cache for reusing UI containers to avoid recreating widgets each change
-- as this was causing lag and missed clicks if clicking decently fast
local relationshipSections = {} -- [relationshipType] = {container, rebuildFunc}
local groupPoolSections = {} -- [groupName] = {container, rebuildFunc}

-- Surface cache to avoid recreating images
local surfaceCache = {}
local scaledSurfaceCache = {}

-- constants
local SKILL_NAME_HEADER = "Skill Name"
local REUSABLILITY_HEADER = "Reusability"
local REUSABLILITY_NAMES = { "Reusable", "Per Pilot", "Per Run" }
local REUSABLILITY_DESCRIPTIONS = {
	"Can be selected multiple times for the same pilot",
	"Can be selected once per pilot (default vanilla behavior)",
	"Can be selected once per run, once one pilot gets it, none other can for that run"
}
local SLOT_RESTRICTION_HEADER = "Slot"
local SLOT_RESTRICTION_NAMES = { "Any", "First", "Second" }
local SLOT_RESTRICTION_DESCRIPTIONS = {
	"Can appear in either skill slot (default)",
	"Can only appear in the first skill slot",
	"Can only appear in the second skill slot"
}
local SLOT_RESTRICTION_TOOLTIP = "Which skill slot this skill can appear in"
local TOTAL_WEIGHT_HEADER = "Total: %.1f"
local TOTAL_PERCENT_HEADER = "Total: %.1f%%"
local ADVANCED_PILOTS = {"Pilot_Arrogant", "Pilot_Caretaker", "Pilot_Chemical", "Pilot_Delusional"}
local SECRET_PILOTS = {"Pilot_Mantis","Pilot_Rock","Pilot_Zoltan"}

local BOARDER_SIZE = 0
local DEFAULT_VGAP = 5
local SKILL_LIST_VGAP = 10
local ROW_HEIGHT = 38
local CHECKBOX_PADDING = 40
local SKILL_ICON_BASE_SIZE = 25
local SKILL_ICON_SCALE = 2
local SKILL_ICON_OUTLINE = 1
local SKILL_ICON_SPACING = 3
local SKILL_ICON_TOTAL = (SKILL_ICON_BASE_SIZE * SKILL_ICON_SCALE) + (SKILL_ICON_OUTLINE * 2 * SKILL_ICON_SCALE) + (SKILL_ICON_SPACING * 2)
local SKILL_ICON_REL_SIZE = (SKILL_ICON_BASE_SIZE * SKILL_ICON_SCALE) + (SKILL_ICON_OUTLINE * 2 * SKILL_ICON_SCALE)
local DROPDOWN_PADDING = 40
local DROPDOWN_BUTTON_PADDING = 33
local COLLAPSE_BTN_PADDING = 40
local COLLAPSE_PADDING = 46
local PILOT_SIZE = 65
local RELATIONSHIP_BUTTON_WIDTH = 140
local SORT_WIDTH = 350
local MAX_GROUP_ICONS = 5 -- Maximum number of skill icons to display for a group
local GROUP_ICON_OVERLAP_SPACING = (SKILL_ICON_REL_SIZE / 2)

-- Helper to get cached surface
local function getCachedSurface(path)
	if not surfaceCache[path] then
		surfaceCache[path] = sdlext.getSurface({ path = path })
	end
	return surfaceCache[path]
end

-- Helper to get cached scaled surface for skill icons
local function getCachedScaledSkillSurface(path)
	if not scaledSurfaceCache[path] then
		local surface = getCachedSurface(path)
		if surface then
			scaledSurfaceCache[path] = sdl.scaled(SKILL_ICON_SCALE, sdl.outlined(surface, SKILL_ICON_OUTLINE, deco.colors.buttonborder))
		end
	end
	return scaledSurfaceCache[path]
end

-- Dialog sizing
local DIALOG_WIDTH_PREFERRED_PCT = 0.85
local DIALOG_HEIGHT_PREFERRED_PCT = 0.85
local DIALOG_MAX_WIDTH_PX = 1400

modify_pilot_skills_ui.unnamedPilotDisplayNames = {
	Pilot_Rust = "Corp. Rust",
	Pilot_Detritus = "Corp. Detritus",
	Pilot_Pinnacle = "Corp. Pinnacle",
	Pilot_Archive = "Corp. Archive",
	Pilot_HornetMech = "Cyborg Hornet",
	Pilot_ScarabMech = "Cyborg Scarab",
	Pilot_BeetleMech = "Cyborg Beetle",
}

-- Helper to sort skill IDs by name
function modify_pilot_skills_ui:getSortedIds(skillTable)
	local sortedIds = {}
	for id in pairs(skillTable) do
		table.insert(sortedIds, id)
	end
	table.sort(sortedIds, function(a, b)
		return skillTable[a]:lower() < skillTable[b]:lower()
	end)
	return sortedIds
end

function modify_pilot_skills_ui:isItemEnabled(itemId)
	-- Groups are always enabled
	if itemId:match("^group:") then
		return true
	end

	local skillConfig = cplus_plus_ex.config.skillConfigs[itemId]
	if skillConfig then
		return skillConfig.enabled
	end

	local pilot = _G[itemId]
	if pilot and type(pilot) == "table" and getmetatable(pilot) == _G.Pilot then
		-- Check if pilot is enabled. Not entirely sure how its used but its in mod loader
		-- so might as well check it
		if not pilot:IsEnabled() then
			return false
		end

		-- Check if pilot is unlocked (using checks from pilot_deck_selector.lua)
		-- Pilots not in hangar lists (recruits, cyborgs, etc.) are always shown as unlocked
		local isPilotUnlocked = (not list_contains(PilotListExtended, itemId) and not list_contains(SECRET_PILOTS, itemId))
			or (type(Profile) == "table" and type(Profile.pilots) == "table" and list_contains(Profile.pilots, itemId))
		if not isPilotUnlocked then
			return false
		end
		return true
	end
	return false
end

-- Updates the needed fields after a skill toggles on or off
function modify_pilot_skills_ui:updateAfterSkillToggle(skillId)
	-- Check if skill is in any relationships - if so, rebuild all relationship sections
	local inRelationships = false
	
	for relationshipType, _ in pairs(cplus_plus_ex.config) do
		if relationshipType == "pilotSkillExclusions" or 
		   relationshipType == "pilotSkillInclusions" or 
		   relationshipType == "skillExclusions" then
			local relTable = cplus_plus_ex.config[relationshipType]
			if relTable then
				for sourceId, targets in pairs(relTable) do
					if sourceId == skillId or sourceId == "group:" .. skillId then
						inRelationships = true
						break
					end
					for targetId, _ in pairs(targets) do
						if targetId == skillId or targetId == "group:" .. skillId then
							inRelationships = true
							break
						end
					end
					if inRelationships then break end
				end
			end
			if inRelationships then break end
		end
	end
	
	-- If skill is in relationships, rebuild each relationship section using cached rebuild functions
	if inRelationships then
		for relationshipType, section in pairs(relationshipSections) do
			if section.rebuildFunc then
				section.rebuildFunc()
			end
		end
	end
	
	-- Check if skill is in any groups - if so, rebuild those group sections
	for groupName, section in pairs(groupPoolSections) do
		local group = cplus_plus_ex:getGroup(groupName)
		if group and group.skillIds and group.skillIds[skillId] then
			if section.rebuildFunc then
				section.rebuildFunc()
			end
		end
	end
end

-- Rebuild just the group pools section when group membership changes
function modify_pilot_skills_ui:rebuildGroupPools()
	if groupsContainer and groupsParent then
		-- Clear group caches and rebuild
		groupPoolSections = {}
		
		groupsContainer:detach()
		self:buildGroups(groupsParent)
		
		-- After rebuilding groups, also rebuild relationships to update group icons
		if relationshipsContainer and relationshipsParent then
			relationshipSections = {}
			relationshipsContainer:detach()
			self:buildRelationships(relationshipsParent)
		end
	end
end

-- Rebuild all relationship sections when needed
function modify_pilot_skills_ui:rebuildAllRelationships()
	if relationshipsContainer and relationshipsParent then
		relationshipSections = {}
		relationshipsContainer:detach()
		self:buildRelationships(relationshipsParent)
	end
end

-- Full rebuild of both for major structural changes like creating/deleting groups
function modify_pilot_skills_ui:rebuildAllGroupPools()
	-- Clear all caches since we're doing a full rebuild
	relationshipSections = {}
	groupPoolSections = {}
	
	-- Rebuild both group pools and relationships to maintain correct order
	if groupsContainer and groupsParent then
		groupsContainer:detach()
	end
	if relationshipsContainer and relationshipsParent then
		relationshipsContainer:detach()
	end

	-- Rebuild in correct order
	if groupsParent then
		self:buildGroups(groupsParent)
	end
	if relationshipsParent then
		self:buildRelationships(relationshipsParent)
	end
end

function modify_pilot_skills_ui:init()
	utils = cplus_plus_ex._subobjects.utils
	sdlext.addModContent(
        "Modify Pilot Abilities",
        function()
            self:createDialog()
        end,
        "Modify skill weights and configurations"
    )
    return self
end

function modify_pilot_skills_ui:getPilotsData()
	local pilotData = {}

	for _, id in pairs(utils.searchForAllPilotIds()) do
		pilotData[id] = GetText(_G[id].Name) or _G[id].Name or id
		-- if the name is empty, we have a custom list of names to use
		-- otherwise just fall back to id
		if _G[id].Name == "" then
			if modify_pilot_skills_ui.unnamedPilotDisplayNames[id] then
				pilotData[id] = modify_pilot_skills_ui.unnamedPilotDisplayNames[id]
			else
				pilotData[id] = id
			end
		end
	end

	local ids = self:getSortedIds(pilotData)
	return pilotData, ids
end

function modify_pilot_skills_ui:getSkillsData()
	local skills = {}
	local defaultSkills = {}
	local inclusionSkills = {}

	for skillId, skill in pairs(cplus_plus_ex._subobjects.skill_registry.registeredSkills) do
		local skillName = GetText(skill.shortName) or skill.shortName
		skills[skillId] = skillName
		if skill.skillType == "inclusion" then
			inclusionSkills[skillId] = skillName
		else
			defaultSkills[skillId] = skillName
		end
	end

	return skills, defaultSkills, inclusionSkills,
	       self:getSortedIds(skills), self:getSortedIds(defaultSkills), self:getSortedIds(inclusionSkills)
end

function modify_pilot_skills_ui:getPilotPortrait(pilotId, scale)
	scale = scale or 1  -- Default scale to 1

	-- Get portrait (taken from pilot deck selector)
	local portrait = _G[pilotId].Portrait
	if portrait == "" then
		local advanced = list_contains(ADVANCED_PILOTS, pilotId)
		local prefix = advanced and "img/advanced/portraits/pilots/" or "img/portraits/pilots/"
		path = prefix .. pilotId .. ".png"
	else
		path = "img/portraits/" .. portrait .. ".png"
	end

	return sdlext.getSurface({
		path = path,
		scale = scale
	})
end

-- Helper to close collapse section
function modify_pilot_skills_ui:closeCollapsable(collapsable)
	if not list_contains(expandedCollapsables, collapsable) then
		return
	end

	remove_element(expandedCollapsables, collapsable)
	collapsable.dropdownHolder:hide()
	collapsable.checked = false
end

-- Helper to open collapse section
function modify_pilot_skills_ui:openCollapsable(collapsable)
	if not list_contains(expandedCollapsables, collapsable) then
		table.insert(expandedCollapsables, collapsable)
	end
	collapsable.dropdownHolder:show()
end

-- Helper to check if a UI element is a descendant of another
function modify_pilot_skills_ui:isDescendantOf(child, parent)
	while child.parent do
		child = child.parent
		if child == parent then
			return true
		end
	end
	return false
end

-- Click handler for collapse buttons
function modify_pilot_skills_ui:clickCollapse(collapsable, button)
	if button == 1 then
		-- Close any descendant dropdowns when opening/closing
		if #expandedCollapsables > 0 then
			for _, dropdown in ipairs(expandedCollapsables) do
				if dropdown ~= self then
					if self:isDescendantOf(dropdown.owner, collapsable.owner) then
						self:closeCollapsable(dropdown)
					end
				end
			end
		end

		if collapsable.checked then
			self:openCollapsable(collapsable)
		else
			self:closeCollapsable(collapsable)
		end

		-- Save collapse state if this is a group section
		if collapsable.groupName then
			cplus_plus_ex.config.groupCollapseStates[collapsable.groupName] = not collapsable.checked
			cplus_plus_ex:saveConfiguration()
		end

		return true
	end
	return false
end

function modify_pilot_skills_ui:buildCollapsibleSectionBase(title, parent, vgap, initialVgap, startCollapsed)
	initialVgap = initialVgap or DEFAULT_VGAP
	vgap = vgap or DEFAULT_VGAP
	startCollapsed = startCollapsed or false
	local sectionBox = UiBoxLayout()
		:vgap(initialVgap)
		:width(1)
		:addTo(parent)

	local headerHolder = UiWeightLayout()
		:width(1):heightpx(ROW_HEIGHT)
		:addTo(sectionBox)

	-- Create nested content holder (will be shown/hidden)
	local contentHolder = UiBoxLayout()
		:vgap(vgap)
		:width(1)
		:addTo(sectionBox)

	-- Add left padding for nested items
	contentHolder.padl = COLLAPSE_PADDING

	-- Collapse arrow button
	local collapse = UiCheckbox()
		:widthpx(COLLAPSE_BTN_PADDING):heightpx(ROW_HEIGHT)
		:decorate({
			DecoButton(),
			DecoCheckbox(
				deco.surfaces.dropdownOpenRight,
				deco.surfaces.dropdownClosed,
				deco.surfaces.dropdownOpenRightHovered,
				deco.surfaces.dropdownClosedHovered
			)
		})
		:addTo(headerHolder)

	collapse.checked = not startCollapsed
	collapse.onclicked = function(collapseSelf, button) return self:clickCollapse(collapseSelf, button) end
	collapse.dropdownHolder = contentHolder
	collapse.owner = sectionBox

	-- Set the starting state
	if startCollapsed then
		contentHolder:hide()
	else
		self:openCollapsable(collapse)
	end

	return collapse, headerHolder
end

-- Builds a generic collapsible section with title
-- Returns the content holder and the section box
function modify_pilot_skills_ui:buildCollapsibleSection(title, parent, vgap, initialVgap, startCollapsed, tooltip, sortOptions)
	local collapse, headerHolder = self:buildCollapsibleSectionBase(title, parent, vgap, initialVgap, startCollapsed)

	-- Section title
	local titleWidget = Ui()
		:width(1.0):heightpx(ROW_HEIGHT)
		:decorate({
			DecoFrame(deco.colors.buttonborder),
			DecoAlign(0, 2),
			DecoText(title, nil, nil, nil, nil, nil, nil, deco.uifont.title.font)
		})
		:addTo(headerHolder)

	if tooltip then
		titleWidget:settooltip(tooltip)
	end

	-- Optional sort dropdown in header
	local sortDropdown = nil
	if sortOptions then
		-- Generate values array dynamically based on number of options
		local sortValues = {}
		for i = 1, #sortOptions do
			table.insert(sortValues, i)
		end

		sortDropdown = UiDropDown(sortValues, sortOptions, 1)
			:widthpx(SORT_WIDTH):heightpx(ROW_HEIGHT)
			:settooltip("Sort entries by the selected criteria")
			:decorate({
				DecoButton(),
				DecoAlign(0, 2),
				DecoText("Sort: "),
				DecoDropDownText(nil, nil, nil, DROPDOWN_BUTTON_PADDING),
				DecoAlign(0, -2),
				DecoDropDown()
			})
			:addTo(headerHolder)
	end

	return collapse.dropdownHolder, sortDropdown
end

-- Builds a group section with tri checkbox
-- Returns the content holder and the checkbox for updating checked state
function modify_pilot_skills_ui:buildGroupSection(group, parent, groupSkills, skillLength, resuabilityLength, slotRestrictionLength, startCollapsed)
	logger.logDebug(SUBMODULE, "buildGroupSection: group=%s, skillLen=%d, reuseLen=%d, slotLen=%d",
			group, skillLength or -1, resuabilityLength or -1, slotRestrictionLength or -1)
	local collapse, headerHolder = self:buildCollapsibleSectionBase(group, parent, SKILL_LIST_VGAP, SKILL_LIST_VGAP, startCollapsed)

	-- Store group name for saving collapse state
	collapse.groupName = group

	-- Group checkbox (tri-state)
	local groupCheckbox = UiTriCheckbox()
		:widthpx(skillLength):heightpx(ROW_HEIGHT)
		:decorate({
			DecoButton(),
			DecoTriCheckbox(),
			DecoAlign(0, 2),
			DecoText(group, nil, nil, nil, nil, nil, nil, deco.uifont.tooltipTitle.font)
		})
		:settooltip("Enable/disable all skills in this group")
		:addTo(headerHolder)

	local reusabilityHeader = Ui()
		:widthpx(resuabilityLength):heightpx(ROW_HEIGHT)
		:decorate({
			DecoFrame(deco.colors.buttonborder),
			DecoAlign(0, 2),
			DecoCAlignedText(REUSABLILITY_HEADER, nil, nil, nil, nil, nil, nil, deco.uifont.tooltipTitle.font)
		})
		:settooltip("How the skill can be reused across pilots and runs")
		:addTo(headerHolder)

	local slotHeader = Ui()
		:widthpx(slotRestrictionLength):heightpx(ROW_HEIGHT)
		:decorate({
			DecoFrame(deco.colors.buttonborder),
			DecoAlign(0, 2),
			DecoCAlignedText(SLOT_RESTRICTION_HEADER, nil, nil, nil, nil, nil, nil, deco.uifont.tooltipTitle.font)
		})
		:settooltip(SLOT_RESTRICTION_TOOLTIP)
		:addTo(headerHolder)

	-- Weight header with total
	local groupWeight, groupPercentage = self:calculateGroupTotals(groupSkills, self:calculateTotalWeight())

	local weightDeco = DecoCAlignedText(string.format(TOTAL_WEIGHT_HEADER, groupWeight), nil, nil, nil, nil, nil, nil, deco.uifont.tooltipTitle.font)
	local weightHeader = Ui()
		:width(0.25):heightpx(ROW_HEIGHT)
		:decorate({
			DecoFrame(deco.colors.buttonborder),
			DecoAlign(0, 2),
			weightDeco
		})
		:settooltip("Total weight of all enabled skills in this group")
		:addTo(headerHolder)

	-- Percentage header with total
	local percentDeco = DecoCAlignedText(string.format(TOTAL_PERCENT_HEADER, groupPercentage), nil, nil, nil, nil, nil, nil, deco.uifont.tooltipTitle.font)
	local percentHeader = Ui()
		:width(0.25):heightpx(ROW_HEIGHT)
		:decorate({
			DecoFrame(deco.colors.buttonborder),
			DecoAlign(0, 2),
			percentDeco
		})
		:settooltip("Combined chance that any skill from this group will be selected")
		:addTo(headerHolder)

	-- Store references for updates
	if not groupHeaderLabels[group] then
		groupHeaderLabels[group] = {}
	end
	groupHeaderLabels[group].weightDeco = weightDeco
	groupHeaderLabels[group].percentDeco = percentDeco
	groupHeaderLabels[group].skills = groupSkills

	collapse.groupCheckbox = groupCheckbox

	return collapse.dropdownHolder, groupCheckbox
end

-- Builds a single skill entry row
function modify_pilot_skills_ui:buildSkillEntry(skill, skillLength, resuabilityLength, slotRestrictionLength, onToggleCallback)
	local skillConfigObj = cplus_plus_ex.config.skillConfigs[skill.id]
	if not skillConfigObj then
		logger.logWarn(SUBMODULE, "No config for skill " .. skill.id)
		local result = Ui():width(1):heightpx(0) -- Return empty element
		return result
	end

	local entryRow = UiWeightLayout()
			:width(1):heightpx(ROW_HEIGHT)

	-- Add values to the row
	local enableCheckbox = self:buildSkillEntryEnable(entryRow, skill, skillConfigObj.enabled, skillLength, onToggleCallback)
	self:buildSkillEntryReusability(entryRow, skill, skillConfigObj.reusability, resuabilityLength)
	self:buildSkillEntrySlotRestriction(entryRow, skill, skillConfigObj.slotRestriction, slotRestrictionLength)
	self:buildSkillEntryWeightInput(entryRow, skill, skillConfigObj.weight)
	self:buildSkillEntryLabels(entryRow, skill)

	-- Store the enable checkbox for group management
	entryRow.enableCheckbox = enableCheckbox

	return entryRow
end

-- Gets all skills organized by group
-- Returns: table of group -> array like table of skills
function modify_pilot_skills_ui:getSkillsByGroup()
	local skillsByGroup = {}

	for skillId, skill in pairs(cplus_plus_ex._subobjects.skill_registry.registeredSkills) do
		local group = skill.group or "Other"

		if not skillsByGroup[group] then
			skillsByGroup[group] = {}
		end
		table.insert(skillsByGroup[group], skill)
	end

	-- Sort skills within each group by short name
	for group, skills in pairs(skillsByGroup) do
		table.sort(skills, function(a, b)
			return (GetText(a.shortName) or a.shortName):lower() < (GetText(b.shortName) or b.shortName):lower()
		end)
	end

	return skillsByGroup
end

-- calculate total weight of all enabled skills
function modify_pilot_skills_ui:calculateTotalWeight()
	local totalWeight = 0
	-- Calculate the total of all enabled skills
	for _, otherSkillId in ipairs(cplus_plus_ex._subobjects.skill_config.enabledSkillsIds) do
		local skillConfigObj = cplus_plus_ex.config.skillConfigs[otherSkillId]
		if skillConfigObj and skillConfigObj.enabled then
			totalWeight = totalWeight + skillConfigObj.weight
		end
	end
	return totalWeight
end

-- Updates the displayed percentages for all skills
function modify_pilot_skills_ui:updateAllPercentages()
	local totalWeight = self:calculateTotalWeight()

	-- Update individual skill percentages
	for skillId, label in pairs(percentageLabels) do
		local percentage = 0
		local skillConfigObj = cplus_plus_ex.config.skillConfigs[skillId]
		if skillConfigObj and skillConfigObj.enabled then
			percentage = totalWeight > 0 and (skillConfigObj.weight / totalWeight * 100) or 0
		end

		for _, deco in ipairs(label.decorations) do
			if deco.__index and deco.__index:isSubclassOf(DecoText) then
				deco:setsurface(string.format("%.1f%%", percentage))
				break
			end
		end
	end

	-- Update group header totals
	for group, headerData in pairs(groupHeaderLabels) do
		local groupWeight, groupPercentage = self:calculateGroupTotals(headerData.skills, totalWeight)

		-- Update weight header
		if headerData.weightDeco then
			headerData.weightDeco:setsurface(string.format(TOTAL_WEIGHT_HEADER, groupWeight))
		end

		-- Update percentage header
		if headerData.percentDeco then
			headerData.percentDeco:setsurface(string.format(TOTAL_PERCENT_HEADER, groupPercentage))
		end
	end
end

-- Validate and parse numeric input
function modify_pilot_skills_ui:validateNumericInput(text)
	-- Allow empty string, numbers, and decimal point
	if text == "" then return true, 0 end

	-- Try to convert to number
	local num = tonumber(text)
	if num == nil then return false, 0 end
	if num < 0 then return false, 0 end

	return true, num
end

function modify_pilot_skills_ui:getLongestLength(entries)
	local maxWidth = 0
	for _, entry in pairs(entries) do
		local deco = DecoText(entry)
		logger.logDebug(SUBMODULE, "Entry width: %d for entry: %s", sdlext.totalWidth(deco.surface), entry)
		maxWidth = math.max(maxWidth, sdlext.totalWidth(deco.surface))
	end
	return maxWidth
end

function modify_pilot_skills_ui:getLargestIconWidth()
	local maxWidth = 0
	for skillId, skill in pairs(cplus_plus_ex._subobjects.skill_registry.registeredSkills) do
		if skill.icon and skill.icon ~= "" then
			local surface = getCachedSurface(skill.icon)
			if surface then
				local scaledWidth = surface:w() * SKILL_ICON_SCALE + (SKILL_ICON_OUTLINE * 2 * SKILL_ICON_SCALE)
				maxWidth = math.max(maxWidth, scaledWidth)
			end
		end
	end
	-- If no icons found, use default size
	if maxWidth == 0 then
		maxWidth = SKILL_ICON_REL_SIZE
	end
	return maxWidth
end

function modify_pilot_skills_ui:_determineColumnLengths()
	local names = { SKILL_NAME_HEADER }

	for skillId, skill in pairs(cplus_plus_ex._subobjects.skill_registry.registeredSkills) do
		table.insert(names, GetText(skill.shortName))
	end

	-- Get max icon width and add spacing
	local maxIconWidth = self:getLargestIconWidth()
	local iconTotalWidth = maxIconWidth + (SKILL_ICON_SPACING * 2)

	local longestName = self:getLongestLength(names)
	-- Extra room for Checkbox and dynamically sized icon
	local paddedName = longestName + CHECKBOX_PADDING + iconTotalWidth

	local reuseOptions = utils.deepcopy(REUSABLILITY_NAMES)
	table.insert(reuseOptions, REUSABLILITY_HEADER)
	local longestReuse = self:getLongestLength(reuseOptions)
	-- Extra room for drop down image
	local paddedReuse = longestReuse + DROPDOWN_PADDING

	local slotOptions = utils.deepcopy(SLOT_RESTRICTION_NAMES)
	table.insert(slotOptions, SLOT_RESTRICTION_HEADER)
	local longestSlot = self:getLongestLength(slotOptions)
	-- Extra room for drop down image
	local paddedSlot = longestSlot + DROPDOWN_PADDING

	logger.logDebug(SUBMODULE, "Column lengths: skill=%d, reuse=%d, slot=%d", paddedName, paddedReuse, paddedSlot)

	return paddedName, paddedReuse, paddedSlot
end

function modify_pilot_skills_ui:buildSkillEntryEnable(entryRow, skill, enabled, skillLength, onToggleCallback)
	local shortName = GetText(skill.shortName)
	local description = GetText(skill.description)
	local group = skill.group

	local decorations = {
		DecoButton(),
		DecoCheckbox(),
		DecoAlign(2, 0),
	}

	-- Add icon if available (icons are 21x21 base, scaled to display size)
	if skill.icon and skill.icon ~= "" then
		local surface = getCachedSurface(skill.icon)
		if surface then
			table.insert(decorations, DecoAlign(SKILL_ICON_SPACING, 0))
			table.insert(decorations, DecoSurfaceOutlined(surface, SKILL_ICON_OUTLINE, nil, nil, SKILL_ICON_SCALE))
			table.insert(decorations, DecoAlign(SKILL_ICON_SPACING, 0))
		else
			table.insert(decorations, DecoAlign(SKILL_ICON_TOTAL, 0))
		end
	else
		table.insert(decorations, DecoAlign(SKILL_ICON_TOTAL, 0))
	end

	-- Add text alignment and text
	table.insert(decorations, DecoAlign(0, 2))
	table.insert(decorations, DecoText(shortName))

	local enabledCheckbox = UiCheckbox()
		:widthpx(skillLength):heightpx(ROW_HEIGHT)
		:settooltip(description)
		:decorate(decorations)
		:addTo(entryRow)

	enabledCheckbox.checked = enabled

	enabledCheckbox.onToggled:subscribe(function(checked)
		if checked then
			cplus_plus_ex:enableSkill(skill.id, true)
		else
			cplus_plus_ex:disableSkill(skill.id, true)
		end
		self:updateAllPercentages()
		cplus_plus_ex:saveConfiguration()

		-- Call the callback if provided for group checkbox updates
		if onToggleCallback then
			onToggleCallback()
		end

		-- Rebuild only affected sections using cached rebuild functions
		self:updateAfterSkillToggle(skill.id)
	end)

	return enabledCheckbox
end

-- Apply weight changes to a skill from weight input field
function modify_pilot_skills_ui:_applyWeightChange(weightInput, skill)
	local isValid, value = self:validateNumericInput(weightInput.textfield)
	if isValid and value >= 0 then
		-- Format to 2 decimal places
		weightInput.textfield = string.format("%.2f", value)
		cplus_plus_ex:setSkillConfig(skill.id, {weight = value})
		self:updateAllPercentages()
		cplus_plus_ex:saveConfiguration()
	else
		-- Reset to current value if invalid
		local currentConfig = cplus_plus_ex.config.skillConfigs[skill.id]
		if currentConfig then
			weightInput.textfield = string.format("%.2f", currentConfig.weight)
		end
	end
end

-- Sort skills based on current sort option
function modify_pilot_skills_ui:_sortSkillsByCurrentSort(skills, currentSkillSort)
	local sortedSkills = {}
	for _, skill in ipairs(skills) do
		-- Only include valid skill objects with an id
		if skill and skill.id then
			table.insert(sortedSkills, skill)
		end
	end

	table.sort(sortedSkills, function(a, b)
		-- Safety checks
		if not a or not a.id then return false end
		if not b or not b.id then return true end

		local aConfig = cplus_plus_ex.config.skillConfigs[a.id]
		local bConfig = cplus_plus_ex.config.skillConfigs[b.id]

		-- Get names
		local aName = ""
		if a.shortName then
			aName = GetText(a.shortName) or a.shortName or ""
		end
		local bName = ""
		if b.shortName then
			bName = GetText(b.shortName) or b.shortName or ""
		end

		-- Fallback to name if either config is missing
		if not aConfig or not bConfig then
			return aName:lower() < bName:lower()
		end

		-- 1 falls down to the default (name)
		-- Each option sorts primary then falls back to name (secondary)
		if currentSkillSort == 2 then
			-- Sort by enabled then name
			if aConfig.enabled ~= bConfig.enabled then
				return aConfig.enabled
			end
		elseif currentSkillSort == 3 then
			-- Sort by reusability then name
			if aConfig.reusability ~= bConfig.reusability then
				return aConfig.reusability < bConfig.reusability
			end
		elseif currentSkillSort == 4 then
			-- Sort by slot restriction then name
			if aConfig.slotRestriction ~= bConfig.slotRestriction then
				return aConfig.slotRestriction < bConfig.slotRestriction
			end
		elseif currentSkillSort == 5 then
			-- Sort by Weight/% then name
			if aConfig.weight ~= bConfig.weight then
				return aConfig.weight > bConfig.weight
			end
		end
		-- Fallback to name
		return aName:lower() < bName:lower()
	end)

	return sortedSkills
end

-- Update tooltip for a dropdown with base message and choice-specific tooltip
function modify_pilot_skills_ui:_updateDropdownTooltip(widget, baseTooltip, tooltips)
	local selectedTooltip = tooltips[widget.choice] or ""
	if selectedTooltip ~= "" then
		widget:settooltip(baseTooltip .. "\n\nCurrent: " .. selectedTooltip)
	else
		widget:settooltip(baseTooltip)
	end
end

function modify_pilot_skills_ui:buildSkillEntryReusability(entryRow, skill, resuability, resuabilityLength)
	local allowedReusability = cplus_plus_ex:getAllowedReusability(skill.id)
	local reusabilityValues = {}
	local reusabilityStrings = {}
	local reusabilityTooltips = {}

	-- Build dropdown options in hierarchy order
	-- Store actual enum values and not sequential indices
	for k = cplus_plus_ex.REUSABLILITY.REUSABLE, cplus_plus_ex.REUSABLILITY.PER_RUN do
		if allowedReusability[k] then
			table.insert(reusabilityValues, k)
			table.insert(reusabilityStrings, REUSABLILITY_NAMES[k])
			table.insert(reusabilityTooltips, REUSABLILITY_DESCRIPTIONS[k])
		end
	end

	-- Validate that the current reusability value is in the allowed list
    -- UiDropDown expects the actual VALUE (not an index) - it searches for it internally
	local currentReusabilityValue = resuability
	local isValueAllowed = false
	for i, val in ipairs(reusabilityValues) do
		if val == resuability then
			isValueAllowed = true
			break
		end
	end
	-- If the current value is not in the allowed list, use the first allowed value
	if not isValueAllowed then
		logger.logWarn(SUBMODULE, "Skill " .. skill.id .. " has reusability=" .. tostring(resuability) ..
				" but it's not in allowed values [" .. table.concat(reusabilityValues, ",") .. "]. Using first allowed value.")
		currentReusabilityValue = reusabilityValues[1]
		-- Update config to match the first allowed value
		cplus_plus_ex:setSkillConfig(skill.id, {reusability = currentReusabilityValue})
	end

	local reusabilityWidget
	if #reusabilityValues == 1 then
		-- Only one option: show as read-only label
		reusabilityWidget = Ui()
			:widthpx(resuabilityLength):heightpx(ROW_HEIGHT)
			:settooltip(reusabilityStrings[1] .. " (fixed)")
			:decorate({
				DecoFrame(),
				DecoAlign(0, 2),
				DecoText(reusabilityStrings[1])
			})
			:addTo(entryRow)
	else
		-- Pass the actual values to UiDropDown - it will find the index internally
		reusabilityWidget = UiDropDown(reusabilityValues, reusabilityStrings, currentReusabilityValue, reusabilityTooltips)
				:widthpx(resuabilityLength)
				:heightpx(40)
				:decorate({
				DecoButton(),
				DecoAlign(0, 2),
				DecoDropDownText(nil, nil, nil, DROPDOWN_BUTTON_PADDING),
				DecoAlign(0, -2),
				DecoDropDown()
			})
			:addTo(entryRow)

		-- Set initial tooltip with selected option description
		self:_updateDropdownTooltip(reusabilityWidget, "Skill reusability setting", reusabilityTooltips)

		-- Handle reusability changes
		reusabilityWidget.optionSelected:subscribe(function(oldChoice, oldValue, newChoice, newValue)
			cplus_plus_ex:setSkillConfig(skill.id, {reusability = newValue})
			cplus_plus_ex:saveConfiguration()
			self:_updateDropdownTooltip(reusabilityWidget, "Skill reusability setting", reusabilityTooltips)
		end)
	end
end

function modify_pilot_skills_ui:buildSkillEntrySlotRestriction(entryRow, skill, slotRestriction, slotRestrictionLength)
	local slotRestrictionValues = {1, 2, 3}
	local slotRestrictionStrings = SLOT_RESTRICTION_NAMES
	local slotRestrictionTooltips = SLOT_RESTRICTION_DESCRIPTIONS

	local slotRestrictionWidget = UiDropDown(slotRestrictionValues, slotRestrictionStrings, slotRestriction, slotRestrictionTooltips)
			:widthpx(slotRestrictionLength)
			:heightpx(40)
			:decorate({
			DecoButton(),
			DecoAlign(0, 2),
			DecoDropDownText(nil, nil, nil, DROPDOWN_BUTTON_PADDING),
			DecoAlign(0, -2),
			DecoDropDown()
		})
		:addTo(entryRow)

	-- Set initial tooltip with selected option description
	self:_updateDropdownTooltip(slotRestrictionWidget, SLOT_RESTRICTION_TOOLTIP, slotRestrictionTooltips)

	-- Handle slot restriction changes
	slotRestrictionWidget.optionSelected:subscribe(function(oldChoice, oldValue, newChoice, newValue)
		cplus_plus_ex:setSkillConfig(skill.id, {slotRestriction = newValue})
		cplus_plus_ex:saveConfiguration()
		self:_updateDropdownTooltip(slotRestrictionWidget, SLOT_RESTRICTION_TOOLTIP, slotRestrictionTooltips)
	end)
end

function modify_pilot_skills_ui:buildSkillEntryWeightInput(entryRow, skill, weight)
	local weightInput = UiInputField()
		:width(0.25):heightpx(ROW_HEIGHT)
		:settooltip("Enter weight (numeric only). Press Enter or click away to update.")
		:decorate({
			DecoButton(),
			DecoAlign(0, 2),
			DecoInputField{
				alignV = "center",
				offsetX = 10,
				offsetY = 2,
			},
		})
		:addTo(entryRow)

	-- Set alphabet to numbers and decimal point
	weightInput:setAlphabet("0123456789.")
	weightInput.textfield = string.format("%.2f", weight)

	-- Handle Enter key
	weightInput.onEnter = function(wi)
		self:_applyWeightChange(wi, skill)
		local result = UiInputField.onEnter(wi)
		return result
	end

	-- Handle focus loss
	weightInput.onFocusChangedEvent:subscribe(function(wi, focused, focused_prev)
		if not focused and focused_prev then
			-- Lost focus, apply changes
			self:_applyWeightChange(wi, skill)
		end
	end)
end

function modify_pilot_skills_ui:buildSkillEntryLabels(entryRow, skill)
	-- Percentage label
	local percentageLabel = Ui()
		:width(0.25):heightpx(ROW_HEIGHT)
		:settooltip("Chance this skill will be selected")
		:decorate({
			DecoFrame(),
			DecoAlign(0, 2),
			DecoText("0.0%")
		})
		:addTo(entryRow)

	percentageLabels[skill.id] = percentageLabel
end

-- Calculates total weight and percentage for a specific group
function modify_pilot_skills_ui:calculateGroupTotals(groupSkills, totalWeight)
	local groupWeight = 0
	local groupPercentage = 0

	-- Calculate group weight
	for _, skill in ipairs(groupSkills) do
		local skillConfig = cplus_plus_ex.config.skillConfigs[skill.id]
		if skillConfig and skillConfig.enabled then
			groupWeight = groupWeight + skillConfig.weight
		end
	end

	-- Calculate group percentage
	if totalWeight > 0 then
		groupPercentage = (groupWeight / totalWeight) * 100
	end

	return groupWeight, groupPercentage
end

function modify_pilot_skills_ui:buildGeneralSettings(scrollContent)
	local settingsContent = self:buildCollapsibleSection("General Settings", scrollContent, SKILL_LIST_VGAP, SKILL_LIST_VGAP)

	-- Allow duplicate skills checkbox
	local allowDupsCheckbox = UiCheckbox()
		:width(1):heightpx(ROW_HEIGHT)
		:settooltip("Allow reusable skills to be assigned multiple times to the same pilot")
		:decorate({
			DecoButton(),
			DecoCheckbox(),
			DecoAlign(0, 2),
			DecoText("Allow Duplicate Skills")
		})
		:addTo(settingsContent)

	allowDupsCheckbox.checked = cplus_plus_ex.config.allowReusableSkills

	allowDupsCheckbox.onToggled:subscribe(function(checked)
		cplus_plus_ex.config.allowReusableSkills = checked
		cplus_plus_ex:saveConfiguration()
	end)

	-- Enable group exclusions checkbox
	local enableGroupsCheckbox = UiCheckbox()
		:width(1):heightpx(ROW_HEIGHT)
		:settooltip("Enable group based exclusions so only one skill from each group can be chosen per pilot. Vanilla behavior would be disabling this")
		:decorate({
			DecoButton(),
			DecoCheckbox(),
			DecoAlign(0, 2),
			DecoText("Enable Group Based Exclusions")
		})
		:addTo(settingsContent)
	enableGroupsCheckbox.checked = cplus_plus_ex.config.enableGroupExclusions

	enableGroupsCheckbox.onToggled:subscribe(function(checked)
		cplus_plus_ex.config.enableGroupExclusions = checked
		cplus_plus_ex:saveConfiguration()
	end)
end

function modify_pilot_skills_ui:buildSkillsList(scrollContent)
	-- Add sort options to Skills Configuration header
	local sortOptions = {"Name", "Enabled", REUSABLILITY_HEADER, SLOT_RESTRICTION_HEADER, "Weight/%"}
	local skillsContent, skillsSortDropdown = self:buildCollapsibleSection("Skills Configuration", scrollContent, nil, nil, false, nil, sortOptions)

	local skillLength, reuseabilityLength, slotRestrictionLength = self:_determineColumnLengths()

	-- Track current sort option
	-- 1 = Name, 2 = Enabled, 3 = Reusability, 4 = Slot, 5 = Weight/%
	local currentSkillSort = cplus_plus_ex.config.skillConfigSortOrder or 1

	-- Set initial dropdown value
	if skillsSortDropdown then
		skillsSortDropdown.value = currentSkillSort
		skillsSortDropdown.choice = currentSkillSort
	end

	-- Get all skills organized by group
	local skillsByGroup = self:getSkillsByGroup()

	-- Sort groups alphabetically
	local sortedGroups = {}
	for group in pairs(skillsByGroup) do
		table.insert(sortedGroups, group)
	end
	table.sort(sortedGroups)

	-- Function to rebuild all groups with current sort
	local function rebuildSkillGroups()
		-- Clear existing content but keep header
		while #skillsContent.children > 0 do
			skillsContent.children[#skillsContent.children]:detach()
		end

		-- Clear tracking tables for fresh rebuild
		percentageLabels = {}
		groupHeaderLabels = {}

		-- Build each group section
		for _, group in ipairs(sortedGroups) do
			local skills = self:_sortSkillsByCurrentSort(skillsByGroup[group], currentSkillSort)
			-- Use saved collapse state if available, default to expanded (false = not collapsed)
			local startCollapsed = cplus_plus_ex.config.groupCollapseStates[group] or false
			local groupContent, groupCheckbox = self:buildGroupSection(group, skillsContent, skills, skillLength, reuseabilityLength, slotRestrictionLength, startCollapsed)

			-- Track checkboxes for this group
			local groupSkillCheckboxes = {}

			-- Method to update group checkbox state based on children
			groupCheckbox.updateCheckedState = function(cc)
				local enabledCount = 0
				local totalCount = #groupSkillCheckboxes

				for _, entry in ipairs(groupSkillCheckboxes) do
					local skillConfig = cplus_plus_ex.config.skillConfigs[entry.skillId]
					if skillConfig and skillConfig.enabled then
						enabledCount = enabledCount + 1
					end
				end

				-- Set tri-state based on enabled count
				if enabledCount == totalCount and totalCount > 0 then
					cc.checked = true
				elseif enabledCount == 0 then
					cc.checked = false
				else
					cc.checked = "mixed"
				end
			end

			-- Update all child checkboxes
			groupCheckbox.updateChildrenCheckedState = function(cc)
				local newState = (cc.checked == true)

				for _, entry in ipairs(groupSkillCheckboxes) do
					if newState then
						cplus_plus_ex:enableSkill(entry.skillId, true)
					else
						cplus_plus_ex:disableSkill(entry.skillId, true)
					end
					entry.checkbox.checked = newState
				end

				self:updateAllPercentages()
				cplus_plus_ex:saveConfiguration()
				
				-- Rebuild all relationship sections after toggling group
				for relationshipType, section in pairs(relationshipSections) do
					if section.rebuildFunc then
						section.rebuildFunc()
					end
				end
				
				-- Also rebuild all group pool sections 
				for groupName, section in pairs(groupPoolSections) do
					if section.rebuildFunc then
						section.rebuildFunc()
					end
				end
			end

			-- Build skill entries
			for _, skill in ipairs(skills) do
				local onToggleCallback = function()
					groupCheckbox:updateCheckedState()
				end

				local skillEntry = self:buildSkillEntry(skill, skillLength, reuseabilityLength, slotRestrictionLength, onToggleCallback)
					:addTo(groupContent)

				-- Track the skill's enable checkbox for group updates
				table.insert(groupSkillCheckboxes, {
					skillId = skill.id,
					checkbox = skillEntry.enableCheckbox
				})
			end

			-- Group checkbox click handler
			groupCheckbox.onclicked = function(cc, button)
				if button == 1 then
					cc:updateChildrenCheckedState()
					cc:updateCheckedState()
					return true
				end
				return false
			end

			-- Initial state
			groupCheckbox:updateCheckedState()
		end
	end

	-- Subscribe to sort dropdown changes
	if skillsSortDropdown then
		skillsSortDropdown.optionSelected:subscribe(function(_, _, choice, value)
			currentSkillSort = value
			-- Save sort order preference
			cplus_plus_ex.config.skillConfigSortOrder = value
			cplus_plus_ex:saveConfiguration()
			rebuildSkillGroups()
			-- Update percentages after rebuild
			self:updateAllPercentages()
		end)
	end

	-- Initial build
	rebuildSkillGroups()

	-- Initial percentage calculation
	self:updateAllPercentages()
end

function modify_pilot_skills_ui:addPilotImage(pilotId, row)
	local pilotUi = Ui()
		:widthpx(PILOT_SIZE - BOARDER_SIZE * 2):heightpx(ROW_HEIGHT)

	local decorations = {}

	if pilotId and pilotId ~= "All" and pilotId ~= "" then
		local portrait = self:getPilotPortrait(pilotId)
		if portrait then
			table.insert(decorations, DecoSurface(portrait))
		end
	end

	pilotUi:decorate(decorations)
	pilotUi:addTo(row)

	-- Add some spacing
	Ui():widthpx(BOARDER_SIZE * 2):heightpx(ROW_HEIGHT):addTo(row)

	return pilotUi
end

-- Helper function to display one or more skill icons with consistent sizing
function modify_pilot_skills_ui:addSkillIcons(skillIds, row)
	local numIcons = #skillIds
	
	-- Load surfaces
	local iconData = {}
	for i = 1, numIcons do
		local skillId = skillIds[i]
		local skill = cplus_plus_ex._subobjects.skill_registry.registeredSkills[skillId]
		if skill and skill.icon and skill.icon ~= "" then
			local surface = sdlext.getSurface({ path = skill.icon })
			if surface then
				local scaledSurface = sdl.scaled(SKILL_ICON_SCALE, sdl.outlined(surface, SKILL_ICON_OUTLINE, deco.colors.buttonborder))
				table.insert(iconData, {
					scaledSurface = scaledSurface,
					width = scaledSurface:w()
				})
			end
		end
	end
	
	local numActualIcons = #iconData
	local maxWidth, overlapSpacing, iconsWidth
	
	-- For single icons, adjust size based on actual icon size
	if numActualIcons == 1 then
		maxWidth = math.max(SKILL_ICON_REL_SIZE, iconData[1].width)
		iconsWidth = maxWidth
	else
		-- For multiple icons (groups), use standard sizing
		maxWidth = SKILL_ICON_REL_SIZE
		overlapSpacing = GROUP_ICON_OVERLAP_SPACING
		iconsWidth = numActualIcons > 0
			and (SKILL_ICON_REL_SIZE + ((numActualIcons - 1) * GROUP_ICON_OVERLAP_SPACING))
			or SKILL_ICON_REL_SIZE
	end

	-- Create container with calculated width
	local container = Ui()
		:widthpx(iconsWidth):heightpx(ROW_HEIGHT)
		:addTo(row)

	-- Add each icon positioned by center point
	for i, data in ipairs(iconData) do
		-- Calculate center position for this icon
		local centerX
		if numActualIcons == 1 then
			-- Single icon: center in container
			centerX = iconsWidth / 2
		else
			-- Multiple icons: center at regular intervals
			centerX = (SKILL_ICON_REL_SIZE / 2) + ((i - 1) * overlapSpacing)
		end
		
		-- Offset to position icon centered at centerX
		local xOffset = math.floor(centerX - (data.width / 2))
		
		Ui()
			:widthpx(maxWidth):heightpx(ROW_HEIGHT)
			:decorate({
				DecoAlign(xOffset, 0),
				DecoSurfaceAligned(data.scaledSurface, "left", "center")
			})
			:addTo(container)
	end

	return container
end

function modify_pilot_skills_ui:addSkillIcon(skillId, row, iconWidth)
	-- Use the unified function with a single skill
	if skillId and skillId ~= "All" and skillId ~= "" then
		return self:addSkillIcons({skillId}, row)
	else
		-- Empty container for missing skills
		local container = Ui()
			:widthpx(SKILL_ICON_REL_SIZE):heightpx(ROW_HEIGHT)
			:addTo(row)
		return container
	end
end

function modify_pilot_skills_ui:addExistingRelLabel(text, row, skillId, tooltip)
	local label = Ui()
		:width(1):heightpx(ROW_HEIGHT)
		:decorate({
			DecoFrame(),
			DecoAlign(0, 2),
			DecoText(text)
		})
		:addTo(row)

	-- Use provided tooltip or skill description
	if tooltip then
		label:settooltip(tooltip)
	elseif skillId then
		local skill = cplus_plus_ex._subobjects.skill_registry.registeredSkills[skillId]
		if skill then
			local description = GetText(skill.description) or skill.description or ""
			if description ~= "" then
				label:settooltip(description)
			end
		end
	end

	return label
end

-- Helper to add icon + text as a fixed width unit in relationship rows
-- Returns the icon container for potential updates
function modify_pilot_skills_ui:addRelationshipColumn(itemId, itemType, isGroup, displayText, skillId, tooltip, parentRow)
	-- Create a fixed width container for icon + text
	local columnContainer = UiWeightLayout()
		:width(0.4):heightpx(ROW_HEIGHT)
		:addTo(parentRow)

	-- Add icon which can change size especially as a group
	local iconContainer = nil
	if isGroup then
		iconContainer = self:addGroupIcons(itemId, columnContainer)
	elseif itemType == "Pilot" then
		iconContainer = self:addPilotImage(itemId, columnContainer)
	elseif itemType == "Skill" then
		-- For single skill icons, use a smaller fixed width
		iconContainer = self:addSkillIcon(itemId, columnContainer, SKILL_ICON_REL_SIZE)
	end

	-- Add text label that takes the remaining space
	self:addExistingRelLabel(displayText, columnContainer, skillId, tooltip)

	return iconContainer
end

function modify_pilot_skills_ui:addGroupIcons(groupName, row)
	local group = cplus_plus_ex:getGroup(groupName)
	if not group then
		-- Empty space if group doesn't exist
		Ui():width(0.1):heightpx(ROW_HEIGHT):addTo(row)
		return nil
	end

	-- Get all enabled skills in this group with their names for sorting
	local groupSkills = {}
	if group.skillIds then
		for skillId in pairs(group.skillIds) do
			if cplus_plus_ex:isSkillEnabled(skillId) then
				local skill = cplus_plus_ex._subobjects.skill_registry.registeredSkills[skillId]
				if skill then
					local name = GetText(skill.shortName) or skill.shortName or skillId
					table.insert(groupSkills, {id = skillId, name = name})
				end
			end
		end
	end

	-- Sort alphabetically by name
	table.sort(groupSkills, function(a, b)
		return a.name:lower() < b.name:lower()
	end)

	-- Extract sorted IDs
	local groupSkillIds = {}
	for i, skillData in ipairs(groupSkills) do
		if i <= MAX_GROUP_ICONS then
			table.insert(groupSkillIds, skillData.id)
		end
	end

	-- Use the unified function to display the icons
	return self:addSkillIcons(groupSkillIds, row)
end

function modify_pilot_skills_ui:addNewRelDropDown(label, listVals, listDisplay, listTooltips, selectFn, row, width)
	width = width or 0.5
	local dropDown = UiDropDown(listVals, listDisplay, listVals[1], listTooltips)
		:width(width):heightpx(ROW_HEIGHT)
		:settooltip()
		:decorate({
			DecoButton(),
			DecoAlign(0, 2),
			DecoDropDownText(nil, nil, nil, DROPDOWN_BUTTON_PADDING),
			DecoAlign(0, -2),
			DecoDropDown()
		})
		:addTo(row)

	-- Set initial tooltip with selected option description
	local baseTooltip = "Select " .. label:lower() .. " (or All)"
	self:_updateDropdownTooltip(dropDown, baseTooltip, listTooltips)

	-- Handle reusability changes
	dropDown.optionSelected:subscribe(function(oldChoice, oldValue, newChoice, newValue)
		selectFn(oldChoice, oldValue, newChoice, newValue)
		self:_updateDropdownTooltip(dropDown, baseTooltip, listTooltips)
	end)
end

function modify_pilot_skills_ui:addArrowLabel(bidirectional, row)
	local text = bidirectional and "↔" or "→"
	Ui()
		:widthpx(36):heightpx(ROW_HEIGHT)
		:decorate({
			-- center doesn't seem to do what I expect it to
			DecoAlign(5, 0),
			DecoCAlignedText(text)
		})
		:addTo(row)
end

function modify_pilot_skills_ui:createDropDownItems(dataList, sortedIds, includeSkillTooltips, includeGroups)
	local listDisplay = {"", "All"}
	local listVals = {"", "All"}
	local listTooltips = {"", "Add entry for each item"}

	-- Use presorted IDs if provided, otherwise use utils.sortByValue
	local keysToUse = sortedIds or utils.sortByValue(dataList)

	for _, k in ipairs(keysToUse) do
		-- Only show enabled items
		if self:isItemEnabled(k) then
			table.insert(listDisplay, dataList[k])
			table.insert(listVals, k)

			-- Add skill description as tooltip if requested
			if includeSkillTooltips then
				local skill = cplus_plus_ex._subobjects.skill_registry.registeredSkills[k]
				if skill then
					local description = GetText(skill.description) or skill.description or ""
					table.insert(listTooltips, description)
				else
					table.insert(listTooltips, "")
				end
			else
				table.insert(listTooltips, "")
			end
		end
	end

	-- Add groups at the end if requested
	if includeGroups then
		local groupNames = cplus_plus_ex:listGroups()
		table.sort(groupNames)

		for _, groupName in ipairs(groupNames) do
			table.insert(listDisplay, "Group: " .. groupName)
			table.insert(listVals, "group:" .. groupName)
			table.insert(listTooltips, "")
		end
	end

	return listDisplay, listVals, listTooltips
end

-- Builds a relationship editor section
function modify_pilot_skills_ui:buildRelationshipEditor(parent, relationshipType, sourceList, targetList, sourceIdsSorted, targetIdsSorted)
	-- Get metadata for this relationship type
	local metadata = cplus_plus_ex:getRelationshipMetadata(relationshipType)
	if not metadata then
		logger.logError(SUBMODULE, "Invalid relationship type: " .. tostring(relationshipType))
		return
	end

	local title = metadata.title
	local sectionTooltip = metadata.tooltip
	local sortConfigKey = metadata.sortOrder
	local sourceLabel = metadata.sourceLabel
	local targetLabel = metadata.targetLabel
	local isBidirectional = metadata.isBidirectional

	-- Get the active relationship table
	local relationshipTable = cplus_plus_ex.config[relationshipType]

	-- create list values with empty and all (using sorted IDs)
	-- Include skill tooltips if the label is "Skill"
	local includeSourceTooltips = sourceLabel == "Skill"
	local includeTargetTooltips = targetLabel == "Skill"

	-- Include groups in dropdowns whenever skills are included
	local includeSourceGroups = sourceLabel == "Skill"
	local includeTargetGroups = targetLabel == "Skill"

	local listDisplay, listVals, listTooltips = self:createDropDownItems(sourceList, sourceIdsSorted, includeSourceTooltips, includeSourceGroups)
	local targetListDisplay, targetListVals, targetListTooltips = self:createDropDownItems(targetList, targetIdsSorted, includeTargetTooltips, includeTargetGroups)

	-- Container for this section
	-- Determine largest height based on whether we have pilot portraits
	local largestHeight = ROW_HEIGHT
	if sourceLabel == "Pilot" then
		largestHeight = PILOT_SIZE
	end

	-- Use consistent spacing throughout
	local itemSpacing = SKILL_LIST_VGAP
	if largestHeight > ROW_HEIGHT then
		-- Add extra spacing for taller items (pilots/large icons)
		itemSpacing = itemSpacing + (largestHeight - ROW_HEIGHT)
	end

	-- Build section with sort dropdown in header
	local sortOptions = {"First Column", "Second Column"}
	local sectionContainer, sortDropdown = self:buildCollapsibleSection(title, parent, itemSpacing, itemSpacing, false, sectionTooltip, sortOptions)

	-- State for the add dropdowns and sorting
	local selectedSource = listVals[1]
	local selectedTarget = targetListVals[1]
	local currentSourceImage = nil
	local currentTargetImage = nil
	local sortColumn = cplus_plus_ex.config[sortConfigKey] or 1  -- Load saved sort order (1 = source, 2 = target)
	local newlyAddedRelationships = {}  -- Track newly added items to show at top

	-- Set initial dropdown value
	if sortDropdown then
		sortDropdown.value = sortColumn
		sortDropdown.choice = sortColumn
	end

	-- Ideally i'd avoid the circular dependency but for simplicity I'm
	-- just predefnining the fn
	local rebuildRelationshipList

	-- Helper function to build tooltip description for a group
	local function buildGroupTooltip(groupName)
		local group = cplus_plus_ex:getGroup(groupName)
		if not group then return "" end

		-- Get all enabled skills in this group with their names
		local groupSkills = {}
		if group.skillIds then
			for skillId in pairs(group.skillIds) do
				if cplus_plus_ex:isSkillEnabled(skillId) then
					local skill = cplus_plus_ex._subobjects.skill_registry.registeredSkills[skillId]
					if skill then
						local name = GetText(skill.shortName) or skill.shortName or skillId
						table.insert(groupSkills, {id = skillId, name = name})
					end
				end
			end
		end

		-- Sort alphabetically by name
		table.sort(groupSkills, function(a, b)
			return a.name:lower() < b.name:lower()
		end)

		-- Build skill names array for description
		local skillNames = {}
		for _, skillData in ipairs(groupSkills) do
			table.insert(skillNames, skillData.name)
		end

		-- Format description as "groupName: [skill1, skill2, ...]"
		return groupName .. ": [" .. table.concat(skillNames, ", ") .. "]"
	end

	-- Helper function to build a single relationship row
	local function buildRelationshipRow(sourceId, targetId, isSourceGroup, isTargetGroup)
		local entryRow = UiWeightLayout()
			:width(1):heightpx(ROW_HEIGHT)
			:addTo(sectionContainer)

		-- Prepare display data
		local sourceDisplay = isSourceGroup and ("Group: " .. sourceId) or sourceList[sourceId]
		local sourceSkillId = (not isSourceGroup and sourceLabel == "Skill") and sourceId or nil
		local sourceTooltip = isSourceGroup and buildGroupTooltip(sourceId) or nil

		local targetDisplay = isTargetGroup and ("Group: " .. targetId) or targetList[targetId]
		local targetSkillId = (not isTargetGroup and targetLabel == "Skill") and targetId or nil
		local targetTooltip = isTargetGroup and buildGroupTooltip(targetId) or nil

		-- Add source column (icon + text as fixed width unit)
		self:addRelationshipColumn(sourceId, sourceLabel, isSourceGroup, sourceDisplay, sourceSkillId, sourceTooltip, entryRow)

		-- Add arrow
		self:addArrowLabel(isBidirectional, entryRow)

		-- Add target column (icon + text as fixed width unit)
		self:addRelationshipColumn(targetId, targetLabel, isTargetGroup, targetDisplay, targetSkillId, targetTooltip, entryRow)

		local isCodeDefined = not (isSourceGroup or isTargetGroup) and cplus_plus_ex:isCodeDefinedRelationship(relationshipType, sourceId, targetId)
		local btnTooltip = isCodeDefined and "Remove this code defined relationship"
				or "Remove this user added relationship"

		local btnRemove = sdlext.buildButton(
			"×",
			btnTooltip,
			function()
				-- Groups are stored with "group:" prefix in the same table as skills
				local fullSourceId = isSourceGroup and ("group:" .. sourceId) or sourceId
				local fullTargetId = isTargetGroup and ("group:" .. targetId) or targetId

				cplus_plus_ex:removeRelationshipFromRuntime(relationshipType, fullSourceId, fullTargetId)
				if isBidirectional then
					cplus_plus_ex:removeRelationshipFromRuntime(relationshipType, fullTargetId, fullSourceId)
				end

				cplus_plus_ex:saveConfiguration()
				rebuildRelationshipList()
				return true
			end
		)
		btnRemove:widthpx(40)
			:heightpx(ROW_HEIGHT)
			:addTo(entryRow)
	end

	-- Function to rebuild the list of existing relationships
	rebuildRelationshipList = function()
		-- Clear existing list (remove all but the add row)
		while #sectionContainer.children > 1 do
			sectionContainer.children[#sectionContainer.children]:detach()
		end

		-- Collect all relationships into a list for sorting
		local relationshipList = {}
		local newItemsList = {}

		-- Add all relationships
		for sourceId, targets in pairs(relationshipTable) do
			for targetId, _ in pairs(targets) do
				-- Only show relationships where both source and target are enabled
				if self:isItemEnabled(sourceId) and self:isItemEnabled(targetId) then
					local key = sourceId .. "|" .. targetId
					local isSourceGroup = sourceId:match("^group:")
					local isTargetGroup = targetId:match("^group:")

					-- Strip "group:" prefix for display purposes only
					local displaySourceId = isSourceGroup and sourceId:gsub("^group:", "") or sourceId
					local displayTargetId = isTargetGroup and targetId:gsub("^group:", "") or targetId

					local relationship = {
						sourceId = displaySourceId,
						targetId = displayTargetId,
						isSourceGroup = isSourceGroup and true or false,
						isTargetGroup = isTargetGroup and true or false
					}

					-- Check if this is a newly added item
					if newlyAddedRelationships[key] then
						table.insert(newItemsList, relationship)
					else
						table.insert(relationshipList, relationship)
					end
				end
			end
		end

		-- Sort only the non-new items based on the selected column
		table.sort(relationshipList, function(a, b)
			if sortColumn == 1 then
				-- Sort by source then target
				local aSourceName = a.isSourceGroup and ("Group: " .. a.sourceId) or (sourceList[a.sourceId] or "")
				local bSourceName = b.isSourceGroup and ("Group: " .. b.sourceId) or (sourceList[b.sourceId] or "")
				if aSourceName:lower() ~= bSourceName:lower() then
					return aSourceName:lower() < bSourceName:lower()
				end
				-- Secondary sort by target
				local aTargetName = a.isTargetGroup and ("Group: " .. a.targetId) or (targetList[a.targetId] or "")
				local bTargetName = b.isTargetGroup and ("Group: " .. b.targetId) or (targetList[b.targetId] or "")
				return aTargetName:lower() < bTargetName:lower()
			else
				-- Sort by target then source
				local aTargetName = a.isTargetGroup and ("Group: " .. a.targetId) or (targetList[a.targetId] or "")
				local bTargetName = b.isTargetGroup and ("Group: " .. b.targetId) or (targetList[b.targetId] or "")
				if aTargetName:lower() ~= bTargetName:lower() then
					return aTargetName:lower() < bTargetName:lower()
				end
				-- Secondary sort by source
				local aSourceName = a.isSourceGroup and ("Group: " .. a.sourceId) or (sourceList[a.sourceId] or "")
				local bSourceName = b.isSourceGroup and ("Group: " .. b.sourceId) or (sourceList[b.sourceId] or "")
				return aSourceName:lower() < bSourceName:lower()
			end
		end)

		-- Build newly added items first
		for _, relationship in ipairs(newItemsList) do
			buildRelationshipRow(relationship.sourceId, relationship.targetId, relationship.isSourceGroup, relationship.isTargetGroup)
		end

		-- Build sorted items
		for _, relationship in ipairs(relationshipList) do
			buildRelationshipRow(relationship.sourceId, relationship.targetId, relationship.isSourceGroup, relationship.isTargetGroup)
		end

		-- Spacer
		Ui():width(1):heightpx(1):addTo(sectionContainer)
	end

	-- add row always at the top
	local addRow = UiWeightLayout()
		:width(1):heightpx(ROW_HEIGHT)
		:addTo(sectionContainer)

	-- Source column (icon + dropdown)
	local sourceColumn = UiWeightLayout()
		:width(0.4):heightpx(ROW_HEIGHT)
		:addTo(addRow)

	-- Source image (pilot portrait or skill icon)
	if sourceLabel == "Pilot" then
		currentSourceImage = self:addPilotImage(selectedSource, sourceColumn)
	elseif sourceLabel == "Skill" then
		currentSourceImage = self:addSkillIcon(selectedSource, sourceColumn, SKILL_ICON_REL_SIZE)
	end

	-- Source dropdown
	self:addNewRelDropDown(sourceLabel, listVals, listDisplay, listTooltips,
		function(oldChoice, oldValue, newChoice, newValue)
			selectedSource = newValue

			-- Update image if we have one
			if currentSourceImage then
				-- Remove old decoration
				for i = #currentSourceImage.decorations, 1, -1 do
					local deco = currentSourceImage.decorations[i]
					if deco.__index and deco.__index:isSubclassOf(DecoSurface) then
						table.remove(currentSourceImage.decorations, i)
					end
				end

				-- Add new image only if not a group, not "All", and not empty
				if not newValue:match("^group:") and newValue ~= "All" and newValue ~= "" then
					if sourceLabel == "Pilot" then
						local portrait = self:getPilotPortrait(newValue)
						if portrait then
							table.insert(currentSourceImage.decorations, DecoSurface(portrait))
						end
					elseif sourceLabel == "Skill" then
						local skill = cplus_plus_ex._subobjects.skill_registry.registeredSkills[newValue]
						if skill and skill.icon and skill.icon ~= "" then
							local scaledSurface = getCachedScaledSkillSurface(skill.icon)
							if scaledSurface then
								table.insert(currentSourceImage.decorations, DecoSurfaceAligned(scaledSurface, "center", "center"))
							end
						end
					end
				end
			end
		end, sourceColumn, 1)

	-- Arrow
	self:addArrowLabel(isBidirectional, addRow)

	-- Target column (icon + dropdown)
	local targetColumn = UiWeightLayout()
		:width(0.4):heightpx(ROW_HEIGHT)
		:addTo(addRow)

	-- Target image (skill icon only, since target is always skill in current relationships)
	if targetLabel == "Skill" then
		currentTargetImage = self:addSkillIcon(selectedTarget, targetColumn, SKILL_ICON_REL_SIZE)
	end

	-- Target dropdown
	self:addNewRelDropDown(targetLabel, targetListVals, targetListDisplay, targetListTooltips,
		function(oldChoice, oldValue, newChoice, newValue)
			selectedTarget = newValue

			-- Update skill icon if we have one
			if currentTargetImage and targetLabel == "Skill" then
				-- Remove old decoration
				for i = #currentTargetImage.decorations, 1, -1 do
					local deco = currentTargetImage.decorations[i]
					if deco.__index and deco.__index:isSubclassOf(DecoSurface) then
						table.remove(currentTargetImage.decorations, i)
					end
				end

				-- Add new icon only if not a group, not "All", and not empty
				if not newValue:match("^group:") and newValue ~= "All" and newValue ~= "" then
					local skill = cplus_plus_ex._subobjects.skill_registry.registeredSkills[newValue]
					if skill and skill.icon and skill.icon ~= "" then
						local scaledSurface = getCachedScaledSkillSurface(skill.icon)
						if scaledSurface then
							table.insert(currentTargetImage.decorations, DecoSurfaceAligned(scaledSurface, "center", "center"))
						end
					end
				end
			end
		end, targetColumn, 1)

	-- Add button
	local btnAdd = sdlext.buildButton(
		"Add",
		"Add this relationship",
		function()
			-- Validation
			if not selectedSource or selectedSource == "" then
				sdlext.showButtonDialog(
					"Invalid Selection",
					"Please select a " .. sourceLabel:lower() .. " from the first dropdown.",
					function() end,
					{"OK"}
				)
				return true
			end
			if not selectedTarget or selectedTarget == "" then
				sdlext.showButtonDialog(
					"Invalid Selection",
					"Please select a " .. targetLabel:lower() .. " from the second dropdown.",
					function() end,
					{"OK"}
				)
				return true
			end

			-- Cannot select All for both
			if selectedSource == "All" and selectedTarget == "All" then
				sdlext.showButtonDialog(
					"Invalid Selection",
					"Cannot select 'All' for both source and target.\n\nPlease select at least one specific item.",
					function() end,
					{"OK"}
				)
				return true
			end

			-- source and target can't be the same
			if selectedSource == selectedTarget then
				sdlext.showButtonDialog(
					"Invalid Selection",
					"Cannot create a relationship from a skill to itself (or all to all).\n\nPlease select different skills.",
					function() end,
					{"OK"}
				)
				return true
			end

			-- Handle "All" selections
			local sourcesToAdd = {}
			local targetsToAdd = {}

			if selectedSource == "All" then
				for sourceId, _ in pairs(sourceList) do
					if self:isItemEnabled(sourceId) then
						sourcesToAdd[sourceId] = true
					end
				end
				-- Include groups when source is skill based
				if includeSourceGroups then
					local groupNames = cplus_plus_ex:listGroups()
					for _, groupName in ipairs(groupNames) do
						sourcesToAdd["group:" .. groupName] = true
					end
				end
			else
				sourcesToAdd = {[selectedSource] = true}
			end

			if selectedTarget == "All" then
				for targetId, _ in pairs(targetList) do
					if self:isItemEnabled(targetId) then
						targetsToAdd[targetId] = true
					end
				end
				-- Include groups when target is skill based
				if includeTargetGroups then
					local groupNames = cplus_plus_ex:listGroups()
					for _, groupName in ipairs(groupNames) do
						targetsToAdd["group:" .. groupName] = true
					end
				end
			else
				targetsToAdd = {[selectedTarget] = true}
			end

			-- Add all combinations
			for sourceId, _ in pairs(sourcesToAdd) do
				for targetId, _ in pairs(targetsToAdd) do
					-- Skip adding to self (if all was used)
					if not (sourceId == targetId) then
						-- Add relationship in exact order specified
						cplus_plus_ex:addRelationshipToRuntime(relationshipType, sourceId, targetId)

						if isBidirectional then
							cplus_plus_ex:addRelationshipToRuntime(relationshipType, targetId, sourceId)
						end

						-- Mark as newly added to show at top
						local key = sourceId .. "|" .. targetId
						newlyAddedRelationships[key] = true
					end
				end
			end

			-- Save and rebuild
			cplus_plus_ex:saveConfiguration()
			rebuildRelationshipList()
			return true
		end
	)
	btnAdd:widthpx(RELATIONSHIP_BUTTON_WIDTH)
		:heightpx(ROW_HEIGHT)
		:addTo(addRow)

	-- Subscribe to sort dropdown changes
	if sortDropdown then
		sortDropdown.optionSelected:subscribe(function(_, _, choice, value)
			sortColumn = value
			-- Save sort order preference
			cplus_plus_ex.config[sortConfigKey] = value
			cplus_plus_ex:saveConfiguration()
			-- Clear newly added tracking when sort changes
			newlyAddedRelationships = {}
			rebuildRelationshipList()
		end)
	end

	-- Build initial list
	rebuildRelationshipList()
	
	-- Cache the section container and rebuild function for efficient updates
	relationshipSections[relationshipType] = {
		container = sectionContainer,
		rebuildFunc = function()
			-- Clear and rebuild this section's list
			-- Keep everything except the add row which is the first child
			while #sectionContainer.children > 1 do
				sectionContainer.children[#sectionContainer.children]:detach()
			end
			rebuildRelationshipList()
		end
	}
end

-- Helper to build groups container which includes skills per row and a button to create new groups
function modify_pilot_skills_ui:buildAllGroupsSection(parent, rebuildCallback)
	local controlsRow = UiWeightLayout()
		:width(1):heightpx(ROW_HEIGHT)
		:addTo(parent)

	-- Create group input field
	local newGroupInput = UiInputField()
		:width(1):heightpx(ROW_HEIGHT)
		:settooltip("Enter new group name/id")
		:decorate({
			DecoButton(),
			DecoAlign(0, 2),
			DecoInputField{
				alignV = "center",
				offsetX = 10,
				offsetY = 2,
			},
		})
		:addTo(controlsRow)

	newGroupInput.textfield = ""

	-- Create group button
	local btnCreateGroup = sdlext.buildButton(
		"Add Group",
		"Adds a new empty skill group",
		function()
			local groupName = newGroupInput.textfield:gsub("^%s*(.-)%s*$", "%1")
			if groupName == "" then
				return true
			end

			-- Check if group already exists
			if cplus_plus_ex:getGroup(groupName) then
				sdlext.showButtonDialog(
					"Group Exists",
					"Group '" .. groupName .. "' already exists.",
					function() end,
					{"OK"}
				)
				return true
			end

			-- Create empty group by tracking it in emptyGroups
			cplus_plus_ex.config.emptyGroups[groupName] = true
			cplus_plus_ex.config.groupsCollapseStates[groupName] = false
			newGroupInput.textfield = ""
			logger.logInfo(SUBMODULE, "Created empty group '%s'", groupName)
			cplus_plus_ex:saveConfiguration()
			rebuildCallback()
			return true
		end
	)
	btnCreateGroup:widthpx(270):heightpx(ROW_HEIGHT):addTo(controlsRow)

	-- Grid size label
	Ui()
		:widthpx(160):heightpx(ROW_HEIGHT)
		:decorate({
			DecoAlign(0, 2),
			DecoRAlignedText("Grid Size:", nil, nil, nil, nil, nil, nil, deco.uifont.tooltipText.font)
		})
		:addTo(controlsRow)

	local gridSizeValues = {2, 3, 4, 5}
	local gridSizeDisplay = {"2", "3", "4", "5"}

	local currentGridSize = cplus_plus_ex.config.groupsItemsPerRow or 4

	logger.logDebug(SUBMODULE, "Grid size dropdown: current value=%d", currentGridSize)

	local gridSizeDropdown = UiDropDown(gridSizeValues, gridSizeDisplay, currentGridSize, nil)
		:widthpx(105)
		:heightpx(40)
		:decorate({
			DecoButton(),
			DecoAlign(0, 2),
			DecoDropDownText(nil, nil, nil, DROPDOWN_BUTTON_PADDING),
			DecoAlign(0, -2),
			DecoDropDown()
		})
		:addTo(controlsRow)

	gridSizeDropdown.optionSelected:subscribe(function(oldChoice, oldValue, newChoice, newValue)
		cplus_plus_ex.config.groupsItemsPerRow = newValue
		cplus_plus_ex:saveConfiguration()
		rebuildCallback()
	end)
end

-- Helper to build add skill line in each group pool to add skills to that group
function modify_pilot_skills_ui:buildGroupPoolAddSkill(parent, groupName, newlyAddedGroupSkills, rebuildCallback)
	local group = cplus_plus_ex:getGroup(groupName)
	if not group then return end

	-- Get all enabled skills not in this group
	local availableSkills = {""}  -- Start with empty entry
	local availableSkillsMap = {}

	for skillId, skill in pairs(cplus_plus_ex._subobjects.skill_registry.registeredSkills) do
		if self:isItemEnabled(skillId) and not group.skillIds[skillId] then
			table.insert(availableSkills, skillId)
			availableSkillsMap[skillId] = {
				name = GetText(skill.shortName) or skill.shortName,
				tooltip = GetText(skill.description) or skill.description
			}
		end
	end

	-- Sort skills keeping empty one at index 1
	local skillsToSort = {}
	for i = 2, #availableSkills do
		table.insert(skillsToSort, availableSkills[i])
	end
	table.sort(skillsToSort, function(a, b)
		return (availableSkillsMap[a].name or a):lower() < (availableSkillsMap[b].name or b):lower()
	end)
	availableSkills = {""}
	for _, skillId in ipairs(skillsToSort) do
		table.insert(availableSkills, skillId)
	end

	-- Build parallel arrays for skill selection dropdown
	local availableSkillsDisplay = {""}  -- Empty entry
	local availableSkillsTooltips = {"Select a skill to add to this group"}
	for i = 2, #availableSkills do
		local skillId = availableSkills[i]
		table.insert(availableSkillsDisplay, availableSkillsMap[skillId].name)
		table.insert(availableSkillsTooltips, availableSkillsMap[skillId].tooltip)
	end

	local addSkillRow = UiWeightLayout()
		:width(1):heightpx(ROW_HEIGHT)
		:addTo(parent)

	local selectedSkillId = ""  -- Start with empty selection

	local addSkillDropdown = UiDropDown(availableSkills, availableSkillsDisplay, selectedSkillId, availableSkillsTooltips)
		:width(0.7)
		:heightpx(40)
		:decorate({
			DecoButton(),
			DecoAlign(0, 2),
			DecoDropDownText(nil, nil, nil, DROPDOWN_BUTTON_PADDING),
			DecoAlign(0, -2),
			DecoDropDown()
		})
		:addTo(addSkillRow)

	addSkillDropdown.optionSelected:subscribe(function(oldChoice, oldValue, newChoice, newValue)
		selectedSkillId = newValue
	end)

	local btnAddSkill = sdlext.buildButton(
		"Add Skill",
		"Add selected skill to this group",
		function()
			-- Don't add if empty selection
			if selectedSkillId == "" then
				return true
			end

			if cplus_plus_ex:addSkillToGroup(selectedSkillId, groupName) then
				-- Track as newly added (UI-only state)
				if not newlyAddedGroupSkills[groupName] then
					newlyAddedGroupSkills[groupName] = {}
				end
				newlyAddedGroupSkills[groupName][selectedSkillId] = true

				cplus_plus_ex:saveConfiguration()
				rebuildCallback()
			end
			return true
		end
	)
	btnAddSkill:widthpx(270):heightpx(ROW_HEIGHT):addTo(addSkillRow)
end

-- Helper to build a single skill cell in group grid
function modify_pilot_skills_ui:buildGroupSkillCell(parent, skillId, groupName, itemsPerRow, rebuildCallback)
	local skill = cplus_plus_ex._subobjects.skill_registry.registeredSkills[skillId]
	local skillName = skill and (GetText(skill.shortName) or skill.shortName) or skillId

	local skillCell = UiBoxLayout()
		:width(1.0 / itemsPerRow)
		:heightpx(ROW_HEIGHT + 10)
		:padding(2)
		:addTo(parent)

	local cellRow = UiWeightLayout()
		:width(1):heightpx(ROW_HEIGHT)
		:addTo(skillCell)

	-- Icon
	if skill and skill.icon and skill.icon ~= "" then
		local iconUi = Ui()
			:widthpx(SKILL_ICON_TOTAL):heightpx(ROW_HEIGHT)

		local scaledSurface = getCachedScaledSkillSurface(skill.icon)
		if scaledSurface then
			iconUi:decorate({DecoSurfaceAligned(scaledSurface, "center", "center")})
		end
		iconUi:addTo(cellRow)
	end

	-- Name
	Ui()
		:width(0.6):heightpx(ROW_HEIGHT)
		:decorate({
			DecoAlign(0, 2),
			DecoText(skillName, nil, nil, nil, nil, nil, nil, deco.uifont.tooltipText.font)
		})
		:settooltip(GetText(skill.description) or skill.description)
		:addTo(cellRow)

	-- Remove button
	local btnRemove = sdlext.buildButton(
		"X",
		"Remove " .. skillName .. " from group",
		function()
			cplus_plus_ex:removeSkillFromGroup(skillId, groupName)
			cplus_plus_ex:saveConfiguration()
			rebuildCallback()
			return true
		end
	)
	btnRemove:widthpx(30):heightpx(ROW_HEIGHT):addTo(cellRow)
end

-- Helper to build skill grid for a group pool
function modify_pilot_skills_ui:buildGroupPoolSkillGrid(parent, groupName, newlyAddedGroupSkills, rebuildCallback)
	local group = cplus_plus_ex:getGroup(groupName)
	if not group then return end

	-- Separate newly added from existing skills
	local newlyAddedSkills = {}
	local existingSkills = {}
	local newlyAddedSet = newlyAddedGroupSkills[groupName] or {}

	for skillId in pairs(group.skillIds) do
		-- Only include enabled skills in display
		if self:isItemEnabled(skillId) then
			if newlyAddedSet[skillId] then
				table.insert(newlyAddedSkills, skillId)
			else
				table.insert(existingSkills, skillId)
			end
		end
	end

	-- Sort each group by skill name
	local function sortBySkillName(a, b)
		local skillA = cplus_plus_ex._subobjects.skill_registry.registeredSkills[a]
		local skillB = cplus_plus_ex._subobjects.skill_registry.registeredSkills[b]
		local nameA = skillA and (GetText(skillA.shortName) or skillA.shortName) or a
		local nameB = skillB and (GetText(skillB.shortName) or skillB.shortName) or b
		return nameA:lower() < nameB:lower()
	end

	table.sort(newlyAddedSkills, sortBySkillName)
	table.sort(existingSkills, sortBySkillName)

	-- Combine with newly added at top
	local sortedSkillIds = {}
	for _, skillId in ipairs(newlyAddedSkills) do
		table.insert(sortedSkillIds, skillId)
	end
	for _, skillId in ipairs(existingSkills) do
		table.insert(sortedSkillIds, skillId)
	end

	if #sortedSkillIds == 0 then
		UiBoxLayout()
			:vgap(DEFAULT_VGAP)
			:width(1)
			:addTo(parent)
			:beginUi()
				:width(1):heightpx(ROW_HEIGHT)
				:decorate({DecoText("No skills in this group.", nil, nil, nil, nil, nil, nil, deco.uifont.tooltipText.font)})
			:endUi()
		return
	end

	-- Build grid with consistent column spacing
	local itemsPerRow = cplus_plus_ex.config.groupsItemsPerRow
	local skillIndex = 1

	while skillIndex <= #sortedSkillIds do
		local gridRow = UiWeightLayout()
			:width(1):heightpx(ROW_HEIGHT + 10)
			:addTo(parent)

		-- Always create itemsPerRow cells to preserve column spacing
		for i = 1, itemsPerRow do
			if skillIndex <= #sortedSkillIds then
				local skillId = sortedSkillIds[skillIndex]
				self:buildGroupSkillCell(gridRow, skillId, groupName, itemsPerRow, rebuildCallback)
				skillIndex = skillIndex + 1
			else
				-- Empty cell to preserve grid spacing
				Ui()
					:width(1.0 / itemsPerRow)
					:heightpx(ROW_HEIGHT + 10)
					:addTo(gridRow)
			end
		end
	end
end

-- Helper to build a single group pool section
function modify_pilot_skills_ui:buildGroupPoolSection(parent, groupName, newlyAddedGroupSkills, rebuildCallback)
	local group = cplus_plus_ex:getGroup(groupName)
	logger.logDebug(SUBMODULE, "buildGroupSection: Building group '%s'", groupName)

	local groupCollapse, groupHeader = self:buildCollapsibleSectionBase(groupName, parent, DEFAULT_VGAP, DEFAULT_VGAP,
		cplus_plus_ex.config.groupsCollapseStates[groupName] or false)

	-- Save collapse state
	groupCollapse.groupName = groupName
	groupCollapse.onclicked = function(cc, button)
		if button == 1 then
			local result = self:clickCollapse(cc, button)
			if result then
				cplus_plus_ex.config.groupsCollapseStates[groupName] = not cc.checked
				cplus_plus_ex:saveConfiguration()
			end
			return result
		end
		return false
	end

	-- Group title with delete button
	local titleRow = UiWeightLayout()
		:width(1.0):heightpx(ROW_HEIGHT)
		:addTo(groupHeader)

	Ui()
		:width(1):heightpx(ROW_HEIGHT)
		:decorate({
			DecoFrame(deco.colors.buttonborder),
			DecoAlign(0, 2),
			DecoText(groupName, nil, nil, nil, nil, nil, nil, deco.uifont.title.font)
		})
		:addTo(titleRow)

	-- Only One Per Pilot checkbox
	local settings = cplus_plus_ex:getGroupSettings(groupName)
	local onlyOneCheckbox = UiCheckbox()
		:widthpx(270):heightpx(ROW_HEIGHT)
		:settooltip("When checked, only one skill from this group can be assigned per pilot")
		:decorate({
			DecoButton(),
			DecoCheckbox(),
			DecoAlign(0, 2),
			DecoText("One Per Pilot")
		})
		:addTo(titleRow)

	onlyOneCheckbox.checked = settings.onlyOnePerPilot or false
	onlyOneCheckbox.onToggled:subscribe(function(checked)
		cplus_plus_ex:setGroupSettings(groupName, {onlyOnePerPilot = checked})
		cplus_plus_ex:saveConfiguration()
	end)

	local btnDeleteGroup = sdlext.buildButton(
		"Delete Group",
		"Delete this group and remove all skills from it",
		function()
			sdlext.showButtonDialog(
				"Confirm Delete",
				"Delete group '" .. groupName .. "'?",
				function(btnIndex)
					if btnIndex == 1 then
						cplus_plus_ex:deleteGroup(groupName)
						cplus_plus_ex:saveConfiguration()
						rebuildCallback()
					end
				end,
				{"Yes", "No"}
			)
			return true
		end
	)
	btnDeleteGroup:widthpx(270):heightpx(ROW_HEIGHT):addTo(titleRow)

	local groupContent = groupCollapse.dropdownHolder

	-- Add skill control
	self:buildGroupPoolAddSkill(groupContent, groupName, newlyAddedGroupSkills, rebuildCallback)

	-- Create a persistent container for the skill grid
	local gridContainer = UiBoxLayout()
		:vgap(0)
		:width(1)
		:addTo(groupContent)
	
	-- Build initial grid of skills
	self:buildGroupPoolSkillGrid(gridContainer, groupName, newlyAddedGroupSkills, rebuildCallback)
	
	-- Cache the grid container and rebuild function for efficient updates
	groupPoolSections[groupName] = {
		container = gridContainer,
		rebuildFunc = function()
			-- Clear only the grid children
			while #gridContainer.children > 0 do
				gridContainer.children[#gridContainer.children]:detach()
			end
			-- Rebuild just the grid
			self:buildGroupPoolSkillGrid(gridContainer, groupName, {}, rebuildCallback)
		end
	}
end

-- Build the skill groups UI section
function modify_pilot_skills_ui:buildGroups(scrollContent)
	local groupsMainSection = self:buildCollapsibleSection("Skill Groups", scrollContent, DEFAULT_VGAP, SKILL_LIST_VGAP, false,
		"Groups group skills into logical groups where only one skill from each group can be assigned per pilot (if group constraints are enabled)")

	-- Store reference to the entire section box (parent of content) for rebuilding
	groupsContainer = groupsMainSection.parent
	groupsParent = scrollContent

	-- Top controls
	self:buildAllGroupsSection(groupsMainSection, function() self:rebuildAllGroupPools() end)

	-- Content container for group sections
	local groupsContent = UiBoxLayout()
		:vgap(DEFAULT_VGAP)
		:width(1)
		:addTo(groupsMainSection)

	-- Get all groups sorted by name
	local groupNames = cplus_plus_ex:listGroups()

	if #groupNames == 0 then
		UiBoxLayout()
			:vgap(DEFAULT_VGAP)
			:width(1)
			:addTo(groupsContent)
			:beginUi()
				:width(1):heightpx(ROW_HEIGHT)
				:decorate({DecoText("No groups defined. Create a group above or skills with group definitions will auto-create groups.", nil, nil, nil, nil, nil, nil, deco.uifont.tooltipText.font)})
			:endUi()
		return
	end

	-- Build each group
	-- Use rebuildGroupPools for skill add/remove
	for _, groupName in ipairs(groupNames) do
		self:buildGroupPoolSection(groupsContent, groupName, {}, function() self:rebuildGroupPools() end)
	end
end

function modify_pilot_skills_ui:buildRelationships(scrollContent)
	local relationshipsContent = self:buildCollapsibleSection("Skill Relationships", scrollContent, SKILL_LIST_VGAP, SKILL_LIST_VGAP)

	-- Store reference to the entire section box (parent of content) for rebuilding
	relationshipsContainer = relationshipsContent.parent
	relationshipsParent = scrollContent

	-- Get lists for dropdowns (now includes sorted IDs)
	local pilotData, pilotIdsSorted = self:getPilotsData()
	local skillData, exlusionSkillData, inclusionSkillData,
	      skillIdsSorted, exlusionSkillIdsSorted, inclusionSkillIdsSorted = self:getSkillsData()

	-- Pilot Skill Exclusions
	self:buildRelationshipEditor(
		relationshipsContent,
		cplus_plus_ex.RelationshipType.PILOT_SKILL_EXCLUSIONS,
		pilotData,
		exlusionSkillData,
		pilotIdsSorted,
		exlusionSkillIdsSorted
	)

	if #inclusionSkillData > 0 then
		-- Pilot Skill Inclusions
		self:buildRelationshipEditor(
			relationshipsContent,
			cplus_plus_ex.RelationshipType.PILOT_SKILL_INCLUSIONS,
			pilotData,
			inclusionSkillData,
			pilotIdsSorted,
			inclusionSkillIdsSorted
		)
	end

	-- Skill Exclusions
	self:buildRelationshipEditor(
		relationshipsContent,
		cplus_plus_ex.RelationshipType.SKILL_EXCLUSIONS,
		skillData,
		skillData,
		skillIdsSorted,
		skillIdsSorted
	)
end

-- Builds the main content for the dialog
function modify_pilot_skills_ui:buildMainContent(scroll)
	-- Clear tracking tables
	percentageLabels = {}
	groupHeaderLabels = {}
	relationshipsContainer = nil
	relationshipsParent = nil
	groupsContainer = nil
	groupsParent = nil
	-- Clear caches
	relationshipSections = {}
	groupPoolSections = {}

	scrollContent = UiBoxLayout()
		:vgap(SKILL_LIST_VGAP)
		:width(1)
		:addTo(scroll)

	-- Add the settings
	self:buildGeneralSettings(scrollContent)
	self:buildSkillsList(scrollContent)
	self:buildGroups(scrollContent)
	self:buildRelationships(scrollContent)
end

function modify_pilot_skills_ui:buildResetConfirmation()
	sdlext.showButtonDialog(
		"Confirm Reset",
		"Reset all skill settings to defaults?\n\nThis cannot be undone.",
		function(btnIndex)
			if btnIndex == 1 then
				-- Reset configuration to defaults
				cplus_plus_ex:resetToDefaults()
				-- Save the reset configuration immediately
				cplus_plus_ex:saveConfiguration()
				-- Refresh the UI to show new values
				if scrollContent and scrollContent.parent then
					local parentScroll = scrollContent.parent
					scrollContent:detach()
					-- Clear tracking tables before rebuild
					percentageLabels = {}
					groupHeaderLabels = {}
					-- Rebuild the content with fresh values
					self:buildMainContent(parentScroll)
				end
			end
		end,
		{ "Reset", "Cancel" },
		{ "Reset everything to defaults", "Cancel and keep current settings" }
	)
	return true
end

-- Builds the button layout for the dialog
function modify_pilot_skills_ui:buildDialogButtons(buttonLayout)
	-- for now at least only a reset button
	local btnReset = sdlext.buildButton(
		"Reset to Defaults",
		"Reset all settings to their default values",
		function() self:buildResetConfirmation() end
	)
	btnReset:addTo(buttonLayout)
end

-- Called when dialog is closed
function modify_pilot_skills_ui:onExit()
	cplus_plus_ex:saveConfiguration()
	scrollContent = nil
	percentageLabels = {}
	groupHeaderLabels = {}
	expandedCollapsables = {}
	relationshipsContainer = nil
	relationshipsParent = nil
	groupsContainer = nil
	groupsParent = nil
	-- Clear caches
	relationshipSections = {}
	groupPoolSections = {}
	-- Clear surface caches to free memory
	surfaceCache = {}
	scaledSurfaceCache = {}
end

-- Creates the main modification dialog
function modify_pilot_skills_ui:createDialog()
	-- Load configuration before opening dialog
	cplus_plus_ex:loadConfiguration()

	sdlext.showDialog(function(ui, quit)
		ui.onDialogExit = function() self:onExit() end

		local frame = sdlext.buildButtonDialog(
			"Modify Pilot Level Up Skills",
			function(scroll) self:buildMainContent(scroll) end,
			function(buttonLayout) self:buildDialogButtons(buttonLayout) end,
			{
				maxW = math.min(DIALOG_MAX_WIDTH_PX, DIALOG_WIDTH_PREFERRED_PCT * ScreenSizeX()),
				maxH = DIALOG_HEIGHT_PREFERRED_PCT * ScreenSizeY(),
				compactH = false
			}
		)

		frame:addTo(ui)
			:pospx((ui.w - frame.w) / 2, (ui.h - frame.h) / 2)
	end)
end

return modify_pilot_skills_ui
