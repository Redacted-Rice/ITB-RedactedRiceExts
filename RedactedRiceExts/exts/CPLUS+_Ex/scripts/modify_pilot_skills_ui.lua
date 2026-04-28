-- Modify Pilot Skills UI
-- UI for modifying skill weights and configurations

local modify_pilot_skills_ui = {}

-- Register with logging system
local logger = memhack.logger
local SUBMODULE = logger.register("CPLUS+", "SkillsUI", cplus_plus_ex.DEBUG.UI and cplus_plus_ex.DEBUG.ENABLED)

local utils = nil
local skill_config = nil
local skill_registry = nil

local scrollContent = nil
-- Track UI widgets for updates
local percentageLabels = {}
local expandedCollapsables = {}
local categoryHeaderLabels = {}

-- Cache for relationship sections to enable efficient dropdown updates
local relationshipSections = {} -- [relationshipType] = {sourceDropdown, targetDropdown, sourceLabel, targetLabel, populateFunc}
-- Maps to store precreated UI elements for relationships
local relationshipRows = {} -- [relationshipType] = {[sourceId|targetId] = {row, sourceId, targetId}}

-- Cache for group sections to enable efficient dropdown updates
local groupsContentContainer = nil
local groupSections = {} -- [groupName] = {container, addSkillDropdown, populateFunc}
local groupCells = {} -- [groupName] = {[skillId] = {cell, skillId}}
local newlyAddedGroups = {} -- Track newly added groups to show at top
local groupAddSequence = 0 -- Counter to maintain group addition order

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
local TOTAL_WEIGHT_HEADER = "%.1f"
local TOTAL_PERCENT_HEADER = "%.1f%%"
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

-- Rebuilds dropdown items after updateOptions
-- Rebuilds dropdown items after updateOptions is called
-- Only rebuilds if the dropdown is currently open
local function rebuildDropdownItems(dropdown)
	if not dropdown.dropdown then return end

	local scrollarea = dropdown.dropdown.children and dropdown.dropdown.children[1]
	if not scrollarea or not scrollarea.children then return end

	local layout = scrollarea.children[1]
	if not layout then return end

	-- Clear existing items
	while #layout.children > 0 do
		layout.children[#layout.children]:detach()
	end

	-- Rebuild items from updated values/strings
	for i, v in ipairs(dropdown.values) do
		local txt = DecoRAlignedText(dropdown.strings[i] or tostring(v))

		local item = Ui()
			:width(1):heightpx(40)
			:decorate({
				DecoSolidHoverable(deco.colors.button, deco.colors.buttonborder),
				DecoAlign(0, 2),
				txt
			})

		-- Capture i in closure
		local index = i
		item.onclicked = function(btn, button)
			if button == 1 then
				local oldChoice = dropdown.choice
				local oldValue = dropdown.value

				dropdown.choice = index
				dropdown.value = dropdown.values[index]

				dropdown.optionSelected:dispatch(oldChoice, oldValue, dropdown.choice, dropdown.value)
				dropdown:destroyDropDown()

				return true
			end
			return false
		end

		layout:add(item)
	end
end

-- Updates relationship dropdown contents when skill enabled state changes
function modify_pilot_skills_ui:updateRelationshipDropdowns()
	for relationshipType, section in pairs(relationshipSections) do
		if section.sourceDropdown and section.targetDropdown then
			-- Dynamically regenerate source and target lists based on current enabled state
			local sourceList, targetList, sourceIdsSorted, targetIdsSorted

			if section.sourceLabel == "Pilot" then
				-- Get current pilot data
				sourceList, sourceIdsSorted = self:getPilotsData()
			elseif section.sourceLabel == "Skill" then
				-- Get current skill data
				local skillData, exlusionSkillData, inclusionSkillData,
				      skillIdsSorted, exlusionSkillIdsSorted, inclusionSkillIdsSorted = self:getSkillsData()

				if relationshipType == skill_config.RelationshipType.SKILL_EXCLUSIONS then
					sourceList = exlusionSkillData
					sourceIdsSorted = exlusionSkillIdsSorted
				else
					sourceList = skillData
					sourceIdsSorted = skillIdsSorted
				end
			end

			if section.targetLabel == "Pilot" then
				-- Get current pilot data
				targetList, targetIdsSorted = self:getPilotsData()
			elseif section.targetLabel == "Skill" then
				-- Get current skill data
				local skillData, exlusionSkillData, inclusionSkillData,
				      skillIdsSorted, exlusionSkillIdsSorted, inclusionSkillIdsSorted = self:getSkillsData()

				if relationshipType == skill_config.RelationshipType.PILOT_SKILL_EXCLUSIONS then
					targetList = exlusionSkillData
					targetIdsSorted = exlusionSkillIdsSorted
				elseif relationshipType == skill_config.RelationshipType.PILOT_SKILL_INCLUSIONS then
					targetList = inclusionSkillData
					targetIdsSorted = inclusionSkillIdsSorted
				else
					targetList = exlusionSkillData
					targetIdsSorted = exlusionSkillIdsSorted
				end
			end

			-- Create dropdown items with current enabled state
			local includeSourceTooltips = section.sourceLabel == "Skill"
			local includeTargetTooltips = section.targetLabel == "Skill"

			local sourceDisplay, sourceVals, sourceTooltips = self:createDropDownItems(
				sourceList,
				sourceIdsSorted,
				includeSourceTooltips
			)

			local targetDisplay, targetVals, targetTooltips = self:createDropDownItems(
				targetList,
				targetIdsSorted,
				includeTargetTooltips
			)

			-- Update dropdown data
			section.sourceDropdown:updateOptions(sourceVals, sourceDisplay)
			section.targetDropdown:updateOptions(targetVals, targetDisplay)

			-- Rebuild dropdown items if currently open
			rebuildDropdownItems(section.sourceDropdown)
			rebuildDropdownItems(section.targetDropdown)
		end
	end
end

-- Called when a skill is enabled or disabled in the Skills Configuration section
function modify_pilot_skills_ui:skillEnableChanged(skillId, enabled)
	logger.logInfo(SUBMODULE, "skillEnableChanged called: skillId=%s, enabled=%s", skillId, tostring(enabled))

	-- Repopulate all relationship sections
	for relationshipType, section in pairs(relationshipSections) do
		if section.populateFunc then
			section.populateFunc()
		end
	end

	-- Repopulate all group sections showing/hiding cells based on enabled state
	for groupName, section in pairs(groupSections) do
		if section.populateFunc then
			section.populateFunc()
		end
	end

	-- Always update dropdowns to reflect the enabled/disabled state
	self:updateRelationshipDropdowns()
	self:updateGroupDropdowns()
end


function modify_pilot_skills_ui:init()
	utils = cplus_plus_ex._subobjects.utils
	skill_config = cplus_plus_ex._subobjects.skill_config
	skill_registry = cplus_plus_ex._subobjects.skill_registry
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

	for skillId, skill in pairs(skill_registry.registeredSkills) do
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

		-- Save collapse state if this is a category section
		if collapsable.categoryName then
			cplus_plus_ex.config.categoryCollapseStates[collapsable.categoryName] = not collapsable.checked
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

-- Builds a category section with tri checkbox
-- Returns the content holder and the checkbox for updating checked state
function modify_pilot_skills_ui:buildCategorySection(category, parent, categorySkills, skillLength, resuabilityLength, slotRestrictionLength, startCollapsed)
	logger.logDebug(SUBMODULE, "buildCategorySection: category=%s, skillLen=%d, reuseLen=%d, slotLen=%d",
			category, skillLength or -1, resuabilityLength or -1, slotRestrictionLength or -1)
	local collapse, headerHolder = self:buildCollapsibleSectionBase(category, parent, SKILL_LIST_VGAP, SKILL_LIST_VGAP, startCollapsed)

	-- Store category name for saving collapse state
	collapse.categoryName = category

	-- Category checkbox (tri-state)
	local categoryCheckbox = UiTriCheckbox()
		:widthpx(skillLength):heightpx(ROW_HEIGHT)
		:decorate({
			DecoButton(),
			DecoTriCheckbox(),
			DecoAlign(0, 2),
			DecoText(category, nil, nil, nil, nil, nil, nil, deco.uifont.tooltipTitle.font)
		})
		:settooltip("Enable/disable all skills in this category")
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
	local categoryWeight, categoryPercentage = self:calculateCategoryTotals(categorySkills, self:calculateTotalWeight())

	local weightDeco = DecoCAlignedText(string.format(TOTAL_WEIGHT_HEADER, categoryWeight), nil, nil, nil, nil, nil, nil, deco.uifont.tooltipTitle.font)
	local weightHeader = Ui()
		:width(0.25):heightpx(ROW_HEIGHT)
		:decorate({
			DecoFrame(deco.colors.buttonborder),
			DecoAlign(0, 2),
			weightDeco
		})
		:settooltip("Total weight of all enabled skills in this category")
		:addTo(headerHolder)

	-- Percentage header with total
	local percentDeco = DecoCAlignedText(string.format(TOTAL_PERCENT_HEADER, categoryPercentage), nil, nil, nil, nil, nil, nil, deco.uifont.tooltipTitle.font)
	local percentHeader = Ui()
		:width(0.25):heightpx(ROW_HEIGHT)
		:decorate({
			DecoFrame(deco.colors.buttonborder),
			DecoAlign(0, 2),
			percentDeco
		})
		:settooltip("Combined chance that any skill from this category will be selected")
		:addTo(headerHolder)

	-- Store references for updates
	if not categoryHeaderLabels[category] then
		categoryHeaderLabels[category] = {}
	end
	categoryHeaderLabels[category].weightDeco = weightDeco
	categoryHeaderLabels[category].percentDeco = percentDeco
	categoryHeaderLabels[category].skills = categorySkills

	return collapse.dropdownHolder, categoryCheckbox
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

	-- Store the enable checkbox for category management
	entryRow.enableCheckbox = enableCheckbox

	return entryRow
end

-- Gets all skills organized by category
-- Returns: table of category -> array like table of skills
function modify_pilot_skills_ui:getSkillsByCategory()
	local skillsByCategory = {}

	for skillId, skill in pairs(skill_registry.registeredSkills) do
		local category = skill.category or "Other"

		if not skillsByCategory[category] then
			skillsByCategory[category] = {}
		end
		table.insert(skillsByCategory[category], skill)
	end

	-- Sort skills within each category by short name
	for category, skills in pairs(skillsByCategory) do
		table.sort(skills, function(a, b)
			return (GetText(a.shortName) or a.shortName):lower() < (GetText(b.shortName) or b.shortName):lower()
		end)
	end

	return skillsByCategory
end

-- calculate total weight of all enabled skills
function modify_pilot_skills_ui:calculateTotalWeight()
	local totalWeight = 0
	-- Calculate the total of all enabled skills
	for _, otherSkillId in ipairs(skill_config.enabledSkillsIds) do
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

	-- Update category header totals
	for category, headerData in pairs(categoryHeaderLabels) do
		local categoryWeight, categoryPercentage = self:calculateCategoryTotals(headerData.skills, totalWeight)

		-- Update weight header
		if headerData.weightDeco then
			headerData.weightDeco:setsurface(string.format(TOTAL_WEIGHT_HEADER, categoryWeight))
		end

		-- Update percentage header
		if headerData.percentDeco then
			headerData.percentDeco:setsurface(string.format(TOTAL_PERCENT_HEADER, categoryPercentage))
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
	for skillId, skill in pairs(skill_registry.registeredSkills) do
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

	for skillId, skill in pairs(skill_registry.registeredSkills) do
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
	local category = skill.category

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

		-- Call the callback if provided for category checkbox updates
		if onToggleCallback then
			onToggleCallback()
		end

		-- Notify that skill enabled state changed
		self:skillEnableChanged(skill.id, checked)
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

-- Calculates total weight and percentage for a specific category
function modify_pilot_skills_ui:calculateCategoryTotals(categorySkills, totalWeight)
	local categoryWeight = 0
	local categoryPercentage = 0

	-- Calculate category weight
	for _, skill in ipairs(categorySkills) do
		local skillConfig = cplus_plus_ex.config.skillConfigs[skill.id]
		if skillConfig and skillConfig.enabled then
			categoryWeight = categoryWeight + skillConfig.weight
		end
	end

	-- Calculate category percentage
	if totalWeight > 0 then
		categoryPercentage = (categoryWeight / totalWeight) * 100
	end

	return categoryWeight, categoryPercentage
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
		:settooltip("If checked, no pilot will be assigned more than one skill from any single enabled group. If unchecked NO groups will be enabled (even if they are checked).")
		:decorate({
			DecoButton(),
			DecoCheckbox(),
			DecoAlign(0, 2),
			DecoText("Enable Group Exclusions")
		})
		:addTo(settingsContent)

	-- Default to true if not set
	if cplus_plus_ex.config.enableGroupExclusions == nil then
		cplus_plus_ex.config.enableGroupExclusions = true
	end
	enableGroupsCheckbox.checked = cplus_plus_ex.config.enableGroupExclusions

	enableGroupsCheckbox.onToggled:subscribe(function(checked)
		cplus_plus_ex.config.enableGroupExclusions = checked
		cplus_plus_ex:saveConfiguration()
		-- Update relationship dropdowns when group exclusions are toggled
		self:updateRelationshipDropdowns()
	end)
end

function modify_pilot_skills_ui:buildSkillsList(scrollContent)
	-- Build skills configuration section without sort dropdown - always sort alphabetically
	local skillsContent = self:buildCollapsibleSection("Skills Configuration", scrollContent, nil, nil, false, nil, nil)

	local skillLength, reuseabilityLength, slotRestrictionLength = self:_determineColumnLengths()

	-- Get all skills organized by category
	local skillsByCategory = self:getSkillsByCategory()

	-- Sort categories alphabetically
	local sortedCategories = {}
	for category in pairs(skillsByCategory) do
		table.insert(sortedCategories, category)
	end
	table.sort(sortedCategories)

	-- Build each category section - always sorted alphabetically by name
	for _, category in ipairs(sortedCategories) do
		-- Skills within categories are already sorted alphabetically in getSkillsByCategory
		local skills = skillsByCategory[category]
		-- Use saved collapse state if available, default to expanded (false = not collapsed)
		local startCollapsed = cplus_plus_ex.config.categoryCollapseStates[category] or false
		local categoryContent, categoryCheckbox = self:buildCategorySection(category, skillsContent, skills, skillLength, reuseabilityLength, slotRestrictionLength, startCollapsed)

		-- Track checkboxes for this category
		local categorySkillCheckboxes = {}

		-- Method to update category checkbox state based on children
		categoryCheckbox.updateCheckedState = function(cc)
			local enabledCount = 0
			local totalCount = #categorySkillCheckboxes

			for _, entry in ipairs(categorySkillCheckboxes) do
				local skillConfig = cplus_plus_ex.config.skillConfigs[entry.skillId]
				if skillConfig and skillConfig.enabled then
					enabledCount = enabledCount + 1
				end
			end

			-- Set tri state based on enabled count
			if enabledCount == totalCount and totalCount > 0 then
				cc.checked = true
			elseif enabledCount == 0 then
				cc.checked = false
			else
				cc.checked = "mixed"
			end
		end

		-- Update all child checkboxes
		categoryCheckbox.updateChildrenCheckedState = function(cc)
			local newState = (cc.checked == true)

			-- Batch update all skills in category without triggering individual updates
			for _, entry in ipairs(categorySkillCheckboxes) do
				if newState then
					cplus_plus_ex:enableSkill(entry.skillId, true)
				else
					cplus_plus_ex:disableSkill(entry.skillId, true)
				end
				entry.checkbox.checked = newState
			end

			-- Now update UI once for the entire category change
			for relationshipType, section in pairs(relationshipSections) do
				if section.populateFunc then
					section.populateFunc()
				end
			end

			for groupName, section in pairs(groupSections) do
				if section.populateFunc then
					section.populateFunc()
				end
			end

			self:updateRelationshipDropdowns()
			self:updateGroupDropdowns()
			self:updateAllPercentages()
			cplus_plus_ex:saveConfiguration()
		end

		-- Build skill entries
		for _, skill in ipairs(skills) do
			local onToggleCallback = function()
				categoryCheckbox:updateCheckedState()
			end

			local skillEntry = self:buildSkillEntry(skill, skillLength, reuseabilityLength, slotRestrictionLength, onToggleCallback)
				:addTo(categoryContent)

			-- Track the skill's enable checkbox for category updates
			table.insert(categorySkillCheckboxes, {
				skillId = skill.id,
				checkbox = skillEntry.enableCheckbox
			})
		end

		-- Category checkbox click handler
		categoryCheckbox.onclicked = function(cc, button)
			if button == 1 then
				cc:updateChildrenCheckedState()
				cc:updateCheckedState()
				return true
			end
			return false
		end

		-- Initial state
		categoryCheckbox:updateCheckedState()
	end

	-- Initial percentage calculation
	self:updateAllPercentages()
end

function modify_pilot_skills_ui:addPilotImage(pilotId, row)
	local pilotUi = Ui()
		:widthpx(PILOT_SIZE - BOARDER_SIZE * 2):heightpx(ROW_HEIGHT)

	-- Always draw frame border, add portrait on top if available
	local decorations = { }

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

function modify_pilot_skills_ui:addSkillIcon(skillId, row, iconWidth)
	iconWidth = iconWidth or SKILL_ICON_REL_SIZE
	local skillUi = Ui()
		:widthpx(iconWidth - BOARDER_SIZE * 2):heightpx(ROW_HEIGHT)

	-- Always draw frame border, add icon on top if available
	local decorations = {  }

	if skillId and skillId ~= "All" and skillId ~= "" then
		local skill = skill_registry.registeredSkills[skillId]
		if skill and skill.icon and skill.icon ~= "" then
			local surface = sdlext.getSurface({ path = skill.icon })
			if surface then
				-- Center the icon in the box (no hover highlight)
				local scaledSurface = sdl.scaled(SKILL_ICON_SCALE, sdl.outlined(surface, SKILL_ICON_OUTLINE, deco.colors.buttonborder))
				table.insert(decorations, DecoSurfaceAligned(scaledSurface, "center", "center"))
			end
		end
	end

	skillUi:decorate(decorations)
	skillUi:addTo(row)

	-- Add some spacing
	Ui():widthpx(BOARDER_SIZE * 2):heightpx(ROW_HEIGHT):addTo(row)

	return skillUi
end

function modify_pilot_skills_ui:addExistingRelLabel(text, row, skillId)
	local label = Ui()
		:width(0.5):heightpx(ROW_HEIGHT)
		:decorate({
			DecoFrame(),
			DecoAlign(0, 2),
			DecoText(text)
		})
		:addTo(row)

	-- Add skill description tooltip if this is a skill
	if skillId then
		local skill = skill_registry.registeredSkills[skillId]
		if skill then
			local description = GetText(skill.description) or skill.description or ""
			if description ~= "" then
				label:settooltip(description)
			end
		end
	end
end

function modify_pilot_skills_ui:addNewRelDropDown(label, listVals, listDisplay, listTooltips, selectFn, row)
	local dropDown = UiDropDown(listVals, listDisplay, listVals[1], listTooltips)
		:width(0.5):heightpx(ROW_HEIGHT)
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

	return dropDown
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

function modify_pilot_skills_ui:createDropDownItems(dataList, sortedIds, includeSkillTooltips)
	local listDisplay = {"", "All"}
	local listVals = {"", "All"}
	local listTooltips = {"", "Add entry for each item"}

	-- Use presorted IDs if provided, otherwise use utils.sortByValue
	local keysToUse = sortedIds or utils.sortByValue(dataList)

	local totalItems = #keysToUse
	local enabledItems = 0

	for _, k in ipairs(keysToUse) do
		-- Only show enabled items
		local enabled = self:isItemEnabled(k)
		if enabled then
			enabledItems = enabledItems + 1
			table.insert(listDisplay, dataList[k])
			table.insert(listVals, k)

			-- Add skill description as tooltip if requested
			if includeSkillTooltips then
				local skill = skill_registry.registeredSkills[k]
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
	local sourceLabel = metadata.sourceLabel
	local targetLabel = metadata.targetLabel
	local isBidirectional = metadata.isBidirectional

	-- Get the active relationship table
	local relationshipTable = cplus_plus_ex.config[relationshipType]

	-- create list values with empty and all (using sorted IDs)
	-- Include skill tooltips if the label is "Skill"
	local includeSourceTooltips = sourceLabel == "Skill"
	local includeTargetTooltips = targetLabel == "Skill"

	local listDisplay, listVals, listTooltips = self:createDropDownItems(sourceList, sourceIdsSorted, includeSourceTooltips)
	local targetListDisplay, targetListVals, targetListTooltips = self:createDropDownItems(targetList, targetIdsSorted, includeTargetTooltips)

	-- Calculate dynamic icon width
	local maxSkillIconWidth = self:getLargestIconWidth()

	-- Container for this section
	-- Determine largest height based on whether we have pilot portraits or skill icons
	local largestHeight = ROW_HEIGHT
	if sourceLabel == "Pilot" then
		largestHeight = PILOT_SIZE
	elseif sourceLabel == "Skill" or targetLabel == "Skill" then
		largestHeight = math.max(ROW_HEIGHT, maxSkillIconWidth)
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

	-- Get metadata for sort order config key
	local sortConfigKey = metadata.sortOrder

	-- State for the add dropdowns and sorting
	local selectedSource = listVals[1]
	local selectedTarget = targetListVals[1]
	local currentSourceImage = nil
	local currentTargetImage = nil
	local sortColumn = cplus_plus_ex.config[sortConfigKey] or 1  -- Load saved sort order
	local newlyAddedRelationships = {}  -- Track newly added items to show at top. Cleared only when sort changes
	local addSequence = 0  -- Counter to maintain addition order. Most recent = highest number

	-- Set initial dropdown value
	if sortDropdown then
		sortDropdown.value = sortColumn
		sortDropdown.choice = sortColumn
	end

	-- Initialize relationship rows map for this type
	if not relationshipRows[relationshipType] then
		relationshipRows[relationshipType] = {}
	end
	local rowsMap = relationshipRows[relationshipType]

	-- Forward declare populate function
	local populateRelationshipList

	-- Helper function to create a single relationship row UI element
	local function createRelationshipRow(sourceId, targetId)
		local entryRow = UiWeightLayout()
			:width(1):heightpx(ROW_HEIGHT)

		-- Pilot portrait if its a pilot
		if sourceLabel == "Pilot" then
			self:addPilotImage(sourceId, entryRow)
		elseif sourceLabel == "Skill" then
			self:addSkillIcon(sourceId, entryRow, maxSkillIconWidth)
		end

		-- Add labels with skill tooltips if applicable
		local sourceSkillId = sourceLabel == "Skill" and sourceId or nil
		local targetSkillId = targetLabel == "Skill" and targetId or nil
		self:addExistingRelLabel(sourceList[sourceId], entryRow, sourceSkillId)
		self:addArrowLabel(isBidirectional, entryRow)

		-- Skill icon for target if its a skill
		if targetLabel == "Skill" then
			self:addSkillIcon(targetId, entryRow, maxSkillIconWidth)
		end

		self:addExistingRelLabel(targetList[targetId], entryRow, targetSkillId)

		-- Remove button
		local isCodeDefined = cplus_plus_ex:isCodeDefinedRelationship(relationshipType, sourceId, targetId)
		local btnText = "Remove"
		local btnTooltip = isCodeDefined and "Remove this code defined relationship"
				or "Remove this user added relationship"

		local btnRemove = sdlext.buildButton(
			btnText,
			btnTooltip,
			function()
				cplus_plus_ex:removeRelationshipFromRuntime(relationshipType, sourceId, targetId)
				if isBidirectional then
					cplus_plus_ex:removeRelationshipFromRuntime(relationshipType, targetId, sourceId)
				end

				-- Remove UI element from map
				local key = sourceId .. "|" .. targetId
				if rowsMap[key] then
					rowsMap[key].row:detach()
					rowsMap[key] = nil
				end

				-- Save and repopulate
				cplus_plus_ex:saveConfiguration()
				populateRelationshipList()
				return true
			end
		)
		btnRemove:widthpx(RELATIONSHIP_BUTTON_WIDTH)
			:heightpx(ROW_HEIGHT)
			:addTo(entryRow)

		return entryRow
	end

	-- Function to populate/repopulate the list using existing UI elements
	populateRelationshipList = function()
		-- Clear existing list (remove all but the add row)
		while #sectionContainer.children > 1 do
			sectionContainer.children[#sectionContainer.children]:detach()
		end

		-- Collect all relationships into lists for sorting
		local relationshipList = {}
		local newItemsList = {}

		for sourceId, targets in pairs(relationshipTable) do
			for targetId, _ in pairs(targets) do
				-- Only show relationships where both source and target are enabled
				if self:isItemEnabled(sourceId) and self:isItemEnabled(targetId) then
					local key = sourceId .. "|" .. targetId
					-- Ensure UI element exists for this relationship
					if not rowsMap[key] then
						rowsMap[key] = {
							row = createRelationshipRow(sourceId, targetId),
							sourceId = sourceId,
							targetId = targetId
						}
					end

					-- Check if this is a newly added item
					if newlyAddedRelationships[key] then
						table.insert(newItemsList, {sourceId = sourceId, targetId = targetId, key = key, sequence = newlyAddedRelationships[key]})
					else
						table.insert(relationshipList, {sourceId = sourceId, targetId = targetId, key = key})
					end
				end
			end
		end

		-- Sort newly added items by sequence. Most recent first = highest number
		table.sort(newItemsList, function(a, b)
			return a.sequence > b.sequence
		end)

		-- Sort non new items based on current sort column
		table.sort(relationshipList, function(a, b)
			if sortColumn == 1 then
				-- Sort by source then target
				local aSourceName = sourceList[a.sourceId] or ""
				local bSourceName = sourceList[b.sourceId] or ""
				if aSourceName:lower() ~= bSourceName:lower() then
					return aSourceName:lower() < bSourceName:lower()
				end
				-- Secondary sort by target
				local aTargetName = targetList[a.targetId] or ""
				local bTargetName = targetList[b.targetId] or ""
				return aTargetName:lower() < bTargetName:lower()
			else
				-- Sort by target then source
				local aTargetName = targetList[a.targetId] or ""
				local bTargetName = targetList[b.targetId] or ""
				if aTargetName:lower() ~= bTargetName:lower() then
					return aTargetName:lower() < bTargetName:lower()
				end
				-- Secondary sort by source
				local aSourceName = sourceList[a.sourceId] or ""
				local bSourceName = sourceList[b.sourceId] or ""
				return aSourceName:lower() < bSourceName:lower()
			end
		end)

		-- Add newly added items first (at the top)
		for _, relationship in ipairs(newItemsList) do
			rowsMap[relationship.key].row:addTo(sectionContainer)
		end

		-- Add sorted rows back to container
		for _, relationship in ipairs(relationshipList) do
			rowsMap[relationship.key].row:addTo(sectionContainer)
		end

		-- Spacer
		Ui():width(1):heightpx(1):addTo(sectionContainer)
	end

	-- add row always at the top
	local addRow = UiWeightLayout()
		:width(1):heightpx(ROW_HEIGHT)
		:addTo(sectionContainer)

	-- Source image (pilot portrait or skill icon)
	if sourceLabel == "Pilot" then
		currentSourceImage = self:addPilotImage(selectedSource, addRow)
	elseif sourceLabel == "Skill" then
		currentSourceImage = self:addSkillIcon(selectedSource, addRow, maxSkillIconWidth)
	end

	-- Source dropdown
	local sourceDropdown = self:addNewRelDropDown(sourceLabel, listVals, listDisplay, listTooltips,
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

				-- Add new image if not "All"
				if newValue ~= "All" and newValue ~= "" then
					if sourceLabel == "Pilot" then
						local portrait = self:getPilotPortrait(newValue)
						if portrait then
							table.insert(currentSourceImage.decorations, DecoSurface(portrait))
						end
					elseif sourceLabel == "Skill" then
						local skill = skill_registry.registeredSkills[newValue]
						if skill and skill.icon and skill.icon ~= "" then
							local scaledSurface = getCachedScaledSkillSurface(skill.icon)
							if scaledSurface then
								table.insert(currentSourceImage.decorations, DecoSurfaceAligned(scaledSurface, "center", "center"))
							end
						end
					end
				end
			end
		end, addRow)

	-- Arrow
	self:addArrowLabel(isBidirectional, addRow)

	-- Target image (skill icon only, since target is always skill in current relationships)
	if targetLabel == "Skill" then
		currentTargetImage = self:addSkillIcon(selectedTarget, addRow, maxSkillIconWidth)
	end

	-- Target dropdown
	local targetDropdown = self:addNewRelDropDown(targetLabel, targetListVals, targetListDisplay, targetListTooltips,
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

				-- Add new icon if not "All"
				if newValue ~= "All" and newValue ~= "" then
					local skill = skill_registry.registeredSkills[newValue]
					if skill and skill.icon and skill.icon ~= "" then
						local scaledSurface = getCachedScaledSkillSurface(skill.icon)
						if scaledSurface then
							table.insert(currentTargetImage.decorations, DecoSurfaceAligned(scaledSurface, "center", "center"))
						end
					end
				end
			end
		end, addRow)

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
			else
				sourcesToAdd = {[selectedSource] = true}
			end

			if selectedTarget == "All" then
				for targetId, _ in pairs(targetList) do
					if self:isItemEnabled(targetId) then
						targetsToAdd[targetId] = true
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
						cplus_plus_ex:addRelationshipToRuntime(relationshipType, sourceId, targetId)

						if isBidirectional then
							cplus_plus_ex:addRelationshipToRuntime(relationshipType, targetId, sourceId)
						end

						-- Create UI element for this relationship and mark as newly added
						local key = sourceId .. "|" .. targetId
						if not rowsMap[key] then
							rowsMap[key] = {
								row = createRelationshipRow(sourceId, targetId),
								sourceId = sourceId,
								targetId = targetId
							}
						end
						-- Mark as newly added to show at top with sequence number
						addSequence = addSequence + 1
						newlyAddedRelationships[key] = addSequence
					end
				end
			end

			-- Save and repopulate
			cplus_plus_ex:saveConfiguration()
			populateRelationshipList()
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
			addSequence = 0
			-- Repopulate with new sort order
			populateRelationshipList()
		end)
	end

	-- Build initial list
	populateRelationshipList()

	-- Cache only what's needed for updates
	relationshipSections[relationshipType] = {
		sourceDropdown = sourceDropdown,
		targetDropdown = targetDropdown,
		sourceLabel = sourceLabel,
		targetLabel = targetLabel,
		populateFunc = populateRelationshipList
	}
end

function modify_pilot_skills_ui:buildRelationships(scrollContent)
	local relationshipsContent = self:buildCollapsibleSection("Skill Relationships", scrollContent, SKILL_LIST_VGAP, SKILL_LIST_VGAP)

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
-- Build the skill groups UI section
function modify_pilot_skills_ui:buildGroups(parent)
	local groupsMainSection = self:buildCollapsibleSection("Skill Groups", parent, DEFAULT_VGAP, SKILL_LIST_VGAP, false,
		"Create groups of skills where only one skill from each enabled group can be assigned per pilot")

	-- Create new group controls
	local controlsRow = UiWeightLayout()
		:width(1):heightpx(ROW_HEIGHT)
		:addTo(groupsMainSection)

	local newGroupInput = UiInputField()
		:width(1):heightpx(ROW_HEIGHT)
		:settooltip("Enter new group name")
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

	local btnCreateGroup = sdlext.buildButton(
		"Create Group",
		"Create a new empty skill group",
		function()
			local groupName = newGroupInput.textfield:gsub("^%s*(.-)%s*$", "%1")
			if groupName == "" then
				return true
			end

			if cplus_plus_ex:getGroup(groupName) then
				sdlext.showButtonDialog(
					"Group Exists",
					"Group '" .. groupName .. "' already exists.",
					function() end,
					{"OK"}
				)
				return true
			end

			cplus_plus_ex:addGroupToRuntime(groupName)
			cplus_plus_ex.config.groupsCollapseStates[groupName] = false
			newGroupInput.textfield = ""
			cplus_plus_ex:saveConfiguration()
			-- Build section for new group
			self:buildGroupSection(groupsContentContainer, groupName)
			-- Mark as newly added with sequence number
			groupAddSequence = groupAddSequence + 1
			newlyAddedGroups[groupName] = groupAddSequence
			-- Repopulate all groups
			self:populateAllGroups()
			return true
		end
	)
	btnCreateGroup:widthpx(270):heightpx(ROW_HEIGHT):addTo(controlsRow)

	-- Grid size control
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

	local gridSizeDropdown = UiDropDown(gridSizeValues, gridSizeDisplay, currentGridSize, nil)
		:widthpx(105):heightpx(40)
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
		-- Repopulate all groups with new grid size
		for groupName, section in pairs(groupSections) do
			if section.populateFunc then
				section.populateFunc()
			end
		end
	end)

	-- Content container for group sections
	groupsContentContainer = UiBoxLayout()
		:vgap(DEFAULT_VGAP)
		:width(1)
		:addTo(groupsMainSection)

	-- Build the actual group sections
	self:buildGroupSections()
end

-- Build all group sections
function modify_pilot_skills_ui:buildGroupSections()
	if not groupsContentContainer then return end

	local groupNames = cplus_plus_ex:listGroups()

	-- Build sections for all groups
	for _, groupName in ipairs(groupNames) do
		self:buildGroupSection(groupsContentContainer, groupName)
	end

	-- Initial populate
	self:populateAllGroups()
end

-- Populate/repopulate all group sections
function modify_pilot_skills_ui:populateAllGroups()
	if not groupsContentContainer then return end

	-- Clear container
	while #groupsContentContainer.children > 0 do
		groupsContentContainer.children[#groupsContentContainer.children]:detach()
	end

	local groupNames = cplus_plus_ex:listGroups()
	local newGroups = {}
	local existingGroups = {}

	-- Separate newly added from existing
	for _, groupName in ipairs(groupNames) do
		if newlyAddedGroups[groupName] then
			table.insert(newGroups, {name = groupName, sequence = newlyAddedGroups[groupName]})
		else
			table.insert(existingGroups, groupName)
		end
	end

	-- Sort newly added groups by sequence. Most recent first = highest number
	table.sort(newGroups, function(a, b)
		return a.sequence > b.sequence
	end)

	-- Add newly added groups first
	for _, groupData in ipairs(newGroups) do
		local groupName = groupData.name
		if groupSections[groupName] then
			groupSections[groupName].container:addTo(groupsContentContainer)
			-- Populate this group's grid
			if groupSections[groupName].populateFunc then
				groupSections[groupName].populateFunc()
			end
		end
	end

	-- Add existing groups in sorted order
	for _, groupName in ipairs(existingGroups) do
		if groupSections[groupName] then
			groupSections[groupName].container:addTo(groupsContentContainer)
			-- Populate this group's grid
			if groupSections[groupName].populateFunc then
				groupSections[groupName].populateFunc()
			end
		end
	end
end

-- Build a single group section
function modify_pilot_skills_ui:buildGroupSection(parent, groupName)
	local group = cplus_plus_ex:getGroup(groupName)
	if not group then return end

	-- Create main container (detached initially, will be added by populateAllGroups)
	local sectionContainer = UiBoxLayout()
		:vgap(DEFAULT_VGAP)
		:width(1)

	local groupCollapse, groupHeader = self:buildCollapsibleSectionBase(groupName, sectionContainer, DEFAULT_VGAP, DEFAULT_VGAP,
		cplus_plus_ex.config.groupsCollapseStates[groupName] or false)

	-- Save collapse state
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

	-- Group title row with enable checkbox and delete button
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

	-- Enable/disable checkbox
	local enableCheckbox = UiCheckbox()
		:widthpx(270):heightpx(ROW_HEIGHT)
		:settooltip("When checked, if top level Enable Group Exclusions is also "..
				"checked then only one skill from this group can be assigned per pilot")
		:decorate({
			DecoButton(),
			DecoCheckbox(),
			DecoAlign(0, 2),
			DecoText("Enabled")
		})
		:addTo(titleRow)

	enableCheckbox.checked = group.enabled or false
	enableCheckbox.onToggled:subscribe(function(checked)
		if checked then
			cplus_plus_ex:enableGroup(groupName)
		else
			cplus_plus_ex:disableGroup(groupName)
		end
		cplus_plus_ex:saveConfiguration()
	end)

	-- Delete button
	local btnDeleteGroup = sdlext.buildButton(
		"Delete Group",
		"Delete this group",
		function()
			sdlext.showButtonDialog(
				"Confirm Delete",
				"Delete group '" .. groupName .. "'?",
				function(btnIndex)
					if btnIndex == 1 then
						cplus_plus_ex:deleteGroupFromRuntime(groupName)
						cplus_plus_ex:saveConfiguration()
						-- Remove from maps and repopulate
						if groupSections[groupName] then
							groupSections[groupName].container:detach()
							groupSections[groupName] = nil
						end
						groupCells[groupName] = nil
						self:populateAllGroups()
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
	local addSkillDropdown = self:buildGroupAddSkill(groupContent, groupName)

	-- Create persistent grid container
	local gridContainer = UiBoxLayout()
		:vgap(0)
		:width(1)
		:addTo(groupContent)

	-- Initialize cells map for this group
	if not groupCells[groupName] then
		groupCells[groupName] = {}
	end

	-- Create cells for all skills in this group
	self:createGroupCells(groupName)

	-- Forward declare populate function
	local populateGroupGrid

	-- Function to populate/repopulate the grid
	populateGroupGrid = function()
		-- Clear grid
		while #gridContainer.children > 0 do
			gridContainer.children[#gridContainer.children]:detach()
		end

		local group = cplus_plus_ex:getGroup(groupName)
		if not group then return end

		-- Get all skills in this group
		local skillIds = {}
		for skillId in pairs(group.skillIds) do
			table.insert(skillIds, skillId)
		end

		-- Sort by name
		table.sort(skillIds, function(a, b)
			local skillA = skill_registry.registeredSkills[a]
			local skillB = skill_registry.registeredSkills[b]
			local nameA = skillA and (GetText(skillA.shortName) or skillA.shortName) or a
			local nameB = skillB and (GetText(skillB.shortName) or skillB.shortName) or b
			return nameA:lower() < nameB:lower()
		end)

		-- Filter to only enabled skills for display
		local enabledSkillIds = {}
		for _, skillId in ipairs(skillIds) do
			if self:isItemEnabled(skillId) then
				table.insert(enabledSkillIds, skillId)
			end
		end

		-- Build grid with blanks to fill
		local itemsPerRow = cplus_plus_ex.config.groupsItemsPerRow
		local skillIndex = 1

		-- Always show grid even if empty
		if #enabledSkillIds == 0 then
			return -- No cells to show
		end

		while skillIndex <= #enabledSkillIds do
			local gridRow = UiWeightLayout()
				:width(1):heightpx(ROW_HEIGHT + 10)
				:addTo(gridContainer)

			for i = 1, itemsPerRow do
				if skillIndex <= #enabledSkillIds then
					local skillId = enabledSkillIds[skillIndex]
					-- Add the pre created cell with dynamic width
					if groupCells[groupName] and groupCells[groupName][skillId] then
						groupCells[groupName][skillId].cell
							:width(1.0 / itemsPerRow)
							:addTo(gridRow)
					end
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

	-- Cache only what's needed for updates
	groupSections[groupName] = {
		container = sectionContainer,
		addSkillDropdown = addSkillDropdown,
		populateFunc = populateGroupGrid
	}
end

-- Build add skill dropdown for a group
function modify_pilot_skills_ui:buildGroupAddSkill(parent, groupName)
	local group = cplus_plus_ex:getGroup(groupName)
	if not group then return nil end

	-- Get all enabled skills not in this group
	local availableSkills = {""}
	local availableSkillsMap = {}

	for skillId, skill in pairs(skill_registry.registeredSkills) do
		if self:isItemEnabled(skillId) and not group.skillIds[skillId] then
			availableSkillsMap[skillId] = {
				name = GetText(skill.shortName) or skill.shortName,
				tooltip = GetText(skill.description) or skill.description
			}
		end
	end

	-- Sort skills
	local skillsToSort = {}
	for skillId, _ in pairs(availableSkillsMap) do
		table.insert(skillsToSort, skillId)
	end
	table.sort(skillsToSort, function(a, b)
		return (availableSkillsMap[a].name or a):lower() < (availableSkillsMap[b].name or b):lower()
	end)

	-- Build parallel arrays
	availableSkills = {""}
	local availableSkillsDisplay = {""}
	for _, skillId in ipairs(skillsToSort) do
		table.insert(availableSkills, skillId)
		table.insert(availableSkillsDisplay, availableSkillsMap[skillId].name)
	end

	local addSkillRow = UiWeightLayout()
		:width(1):heightpx(ROW_HEIGHT)
		:addTo(parent)

	local addSkillDropdown = UiDropDown(availableSkills, availableSkillsDisplay, "", nil)
		:width(0.7):heightpx(40)
		:decorate({
			DecoButton(),
			DecoAlign(0, 2),
			DecoDropDownText(nil, nil, nil, DROPDOWN_BUTTON_PADDING),
			DecoAlign(0, -2),
			DecoDropDown()
		})
		:addTo(addSkillRow)

	local btnAddSkill = sdlext.buildButton(
		"Add Skill",
		"Add selected skill to this group",
		function()
			local selectedSkillId = addSkillDropdown.value or ""
			if selectedSkillId == "" then
				return true
			end

			if cplus_plus_ex:registerSkillToGroupToRuntime(selectedSkillId, groupName) then
				-- Find the current index of selected skill before updating
				local currentIndex = nil
				for i, skillId in ipairs(addSkillDropdown.values) do
					if skillId == selectedSkillId then
						currentIndex = i
						break
					end
				end

				cplus_plus_ex:saveConfiguration()
				-- Create cell for the new skill
				if not groupCells[groupName] then
					groupCells[groupName] = {}
				end
				if not groupCells[groupName][selectedSkillId] then
					groupCells[groupName][selectedSkillId] = {
						cell = self:createGroupSkillCell(selectedSkillId, groupName),
						skillId = selectedSkillId
					}
				end
				-- Repopulate only this group's grid
				if groupSections[groupName] and groupSections[groupName].populateFunc then
					groupSections[groupName].populateFunc()
				end
				-- Update all group dropdowns after adding skill
				self:updateGroupDropdowns()

				-- Auto select the next available skill
				if addSkillDropdown.values and #addSkillDropdown.values > 1 then
					-- Try to select the skill at the same index, or previous if we removed the last one
					local newIndex = currentIndex
					if newIndex and newIndex > #addSkillDropdown.values then
						newIndex = #addSkillDropdown.values
					end
					if newIndex and newIndex >= 1 and newIndex <= #addSkillDropdown.values then
						addSkillDropdown.value = addSkillDropdown.values[newIndex]
						addSkillDropdown.choice = newIndex
					else
						addSkillDropdown.value = ""
						addSkillDropdown.choice = 1
					end
				else
					-- No skills available
					addSkillDropdown.value = ""
					addSkillDropdown.choice = 1
				end
			end
			return true
		end
	)
	btnAddSkill:widthpx(270):heightpx(ROW_HEIGHT):addTo(addSkillRow)

	return addSkillDropdown
end

-- Create all cells for skills in a group
function modify_pilot_skills_ui:createGroupCells(groupName)
	local group = cplus_plus_ex:getGroup(groupName)
	if not group then return end

	-- Create cells for all skills in the group
	for skillId in pairs(group.skillIds) do
		if not groupCells[groupName][skillId] then
			groupCells[groupName][skillId] = {
				cell = self:createGroupSkillCell(skillId, groupName),
				skillId = skillId
			}
		end
	end
end

-- Create a single skill cell in a group grid
function modify_pilot_skills_ui:createGroupSkillCell(skillId, groupName)
	local skill = skill_registry.registeredSkills[skillId]
	local skillName = skill and (GetText(skill.shortName) or skill.shortName) or skillId

	-- Note: width will be set dynamically when added to grid based on itemsPerRow
	local skillCell = UiBoxLayout()
		:heightpx(ROW_HEIGHT + 10)
		:padding(2)

	local cellRow = UiWeightLayout()
		:width(1):heightpx(ROW_HEIGHT)
		:addTo(skillCell)

	-- Icon using cached surface
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
		:settooltip(skill and (GetText(skill.description) or skill.description) or "")
		:addTo(cellRow)

	-- Remove button
	local btnRemove = sdlext.buildButton(
		"X",
		"Remove " .. skillName .. " from group",
		function()
			cplus_plus_ex:removeSkillFromGroupFromRuntime(skillId, groupName)
			cplus_plus_ex:saveConfiguration()
			-- Remove cell from map
			if groupCells[groupName] and groupCells[groupName][skillId] then
				groupCells[groupName][skillId].cell:detach()
				groupCells[groupName][skillId] = nil
			end
			-- Repopulate only this group's grid
			if groupSections[groupName] and groupSections[groupName].populateFunc then
				groupSections[groupName].populateFunc()
			end
			-- Update all group dropdowns after removing skill
			self:updateGroupDropdowns()
			return true
		end
	)
	btnRemove:widthpx(30):heightpx(ROW_HEIGHT):addTo(cellRow)

	return skillCell
end

-- Updates group dropdown contents when skills are enabled/disabled
function modify_pilot_skills_ui:updateGroupDropdowns()
	for groupName, section in pairs(groupSections) do
		if section.addSkillDropdown then
			local group = cplus_plus_ex:getGroup(groupName)
			if group then
				-- Get all enabled skills not in this group
				local availableSkills = {""}
				local availableSkillsMap = {}

				for skillId, skill in pairs(skill_registry.registeredSkills) do
					if self:isItemEnabled(skillId) and not group.skillIds[skillId] then
						availableSkillsMap[skillId] = {
							name = GetText(skill.shortName) or skill.shortName,
							tooltip = GetText(skill.description) or skill.description
						}
					end
				end

				-- Sort skills
				local skillsToSort = {}
				for skillId, _ in pairs(availableSkillsMap) do
					table.insert(skillsToSort, skillId)
				end
				table.sort(skillsToSort, function(a, b)
					return (availableSkillsMap[a].name or a):lower() < (availableSkillsMap[b].name or b):lower()
				end)

				-- Build parallel arrays
				availableSkills = {""}
				local availableSkillsDisplay = {""}

				for _, skillId in ipairs(skillsToSort) do
					table.insert(availableSkills, skillId)
					table.insert(availableSkillsDisplay, availableSkillsMap[skillId].name)
				end

				-- Update dropdown data
				section.addSkillDropdown:updateOptions(availableSkills, availableSkillsDisplay)

				-- Check if current selection is still valid after update
				local currentValue = section.addSkillDropdown.value
				local isValidSelection = false
				for _, skillId in ipairs(availableSkills) do
					if skillId == currentValue then
						isValidSelection = true
						break
					end
				end

				-- If current selection is no longer valid, select first available item
				if not isValidSelection then
					if #availableSkills > 1 then
						-- Select first non-empty item
						section.addSkillDropdown.value = availableSkills[2]
						section.addSkillDropdown.choice = 2
					else
						-- No skills available, select empty
						section.addSkillDropdown.value = ""
						section.addSkillDropdown.choice = 1
					end
				end

				-- Rebuild dropdown items if currently open
				rebuildDropdownItems(section.addSkillDropdown)
			end
		end
	end
end

function modify_pilot_skills_ui:buildMainContent(scroll)
	-- Clear tracking tables
	percentageLabels = {}
	categoryHeaderLabels = {}
	groupsContentContainer = nil
	-- Clear caches
	relationshipSections = {}
	relationshipRows = {}
	groupSections = {}
	groupCells = {}
	newlyAddedGroups = {}
	groupAddSequence = 0

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
					categoryHeaderLabels = {}
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
	categoryHeaderLabels = {}
	expandedCollapsables = {}
	groupsContentContainer = nil
	relationshipSections = {}
	relationshipRows = {}
	groupSections = {}
	groupCells = {}
	newlyAddedGroups = {}
	groupAddSequence = 0
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
