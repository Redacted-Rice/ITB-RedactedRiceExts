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
local categoryHeaderLabels = {}

-- constants
local SKILL_NAME_HEADER = "Skill Name"
local REUSABLILITY_HEADER = "Reusability"
local REUSABLILITY_NAMES = { "Reusable", "Per Pilot", "Per Run" }
local REUSABLILITY_DESCRIPTIONS = {
	"Can be selected multiple times for the same pilot",
	"Can be selected once per pilot (default vanilla behavior)",
	"Can be selected once per run, once one pilot gets it, none other can for that run"
}
local TOTAL_WEIGHT_HEADER = "Total: %.1f"
local TOTAL_PERCENT_HEADER = "Total: %.1f%%"
local ADVANCED_PILOTS = {"Pilot_Arrogant", "Pilot_Caretaker", "Pilot_Chemical", "Pilot_Delusional"}

local BOARDER_SIZE = 0
local DEFAULT_VGAP = 5
local ROW_HEIGHT = 41
local CHECKBOX_PADDING = 40
local DROPDOWN_PADDING = 40
local DROPDOWN_BUTTON_PADDING = 33
local COLLAPSE_BTN_PADDING = 40
local COLLAPSE_PADDING = 46
local PILOT_SIZE = 65
local RELATIONSHIP_BUTTON_WIDTH = 140
local SORT_WIDTH = 350

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
local function getSortedIds(skillTable)
	local sortedIds = {}
	for id in pairs(skillTable) do
		table.insert(sortedIds, id)
	end
	table.sort(sortedIds, function(a, b)
		return skillTable[a]:lower() < skillTable[b]:lower()
	end)
	return sortedIds
end

function modify_pilot_skills_ui:init()
	utils = cplus_plus_ex._subobjects.utils
	sdlext.addModContent(
        "Modify Pilot Abilities",
        function()
            self.createDialog()
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

	return pilotData, getSortedIds(pilotData)
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
	       getSortedIds(skills), getSortedIds(defaultSkills), getSortedIds(inclusionSkills)
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
local function closeCollapsable(self)
	if not list_contains(expandedCollapsables, self) then
		return
	end

	remove_element(expandedCollapsables, self)
	self.dropdownHolder:hide()
	self.checked = false
end

-- Helper to open collapse section
local function openCollapsable(self)
	if not list_contains(expandedCollapsables, self) then
		table.insert(expandedCollapsables, self)
	end
	self.dropdownHolder:show()
end

-- Helper to check if a UI element is a descendant of another
local function isDescendantOf(child, parent)
	while child.parent do
		child = child.parent
		if child == parent then
			return true
		end
	end
	return false
end

-- Click handler for collapse buttons
local function clickCollapse(self, button)
	if button == 1 then
		-- Close any descendant dropdowns when opening/closing
		if #expandedCollapsables > 0 then
			for _, dropdown in ipairs(expandedCollapsables) do
				if dropdown ~= self then
					if isDescendantOf(dropdown.owner, self.owner) then
						closeCollapsable(dropdown)
					end
				end
			end
		end

		if self.checked then
			openCollapsable(self)
		else
			closeCollapsable(self)
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
	collapse.onclicked = clickCollapse
	collapse.dropdownHolder = contentHolder
	collapse.owner = sectionBox

	-- Set the starting state
	if startCollapsed then
		contentHolder:hide()
	else
		openCollapsable(collapse)
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
function modify_pilot_skills_ui:buildCategorySection(category, parent, categorySkills, skillLength, resuabilityLength, startCollapsed)
	local collapse, headerHolder = self:buildCollapsibleSectionBase(category, parent, nil, nil, startCollapsed)

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

	Ui()
		:widthpx(resuabilityLength):heightpx(ROW_HEIGHT)
		:decorate({
			DecoFrame(deco.colors.buttonborder),
			DecoAlign(0, 2),
			DecoCAlignedText(REUSABLILITY_HEADER, nil, nil, nil, nil, nil, nil, deco.uifont.tooltipTitle.font)
		})
		:settooltip("How the skill can be reused across pilots and runs")
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

	collapse.categoryCheckbox = categoryCheckbox

	return collapse.dropdownHolder, categoryCheckbox
end

-- Builds a single skill entry row
function modify_pilot_skills_ui:buildSkillEntry(skill, skillLength, resuabilityLength, onToggleCallback)
	local skillConfigObj = cplus_plus_ex.config.skillConfigs[skill.id]
	if not skillConfigObj then
		logger.logWarn(SUBMODULE, "No config for skill " .. skill.id)
		return Ui():width(1):heightpx(0) -- Return empty element
	end

	local entryRow = UiWeightLayout()
			:width(1):heightpx(ROW_HEIGHT)
			
	-- Store the enable checkbox for category management
	entryRow.enableCheckbox = modify_pilot_skills_ui:buildSkillEntryEnable(entryRow, skill, skillConfigObj.enabled, skillLength, onToggleCallback)

	return entryRow
end

-- Gets all skills organized by category
-- Returns: table of category -> array like table of skills
function modify_pilot_skills_ui:getSkillsByCategory()
	local skillsByCategory = {}

	for skillId, skill in pairs(cplus_plus_ex._subobjects.skill_registry.registeredSkills) do
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

function modify_pilot_skills_ui:determineColumnLengths()
	local names = { SKILL_NAME_HEADER }
	for skillId, skill in pairs(cplus_plus_ex._subobjects.skill_registry.registeredSkills) do
		table.insert(names, GetText(skill.shortName))
	end
	local longestName = modify_pilot_skills_ui:getLongestLength(names)
	-- Extra room for Checkbox
	local paddedName = longestName + CHECKBOX_PADDING

	local reuseOptions = utils.deepcopy(REUSABLILITY_NAMES)
	table.insert(reuseOptions, REUSABLILITY_HEADER)
	local longestReuse = modify_pilot_skills_ui:getLongestLength(reuseOptions)
	-- Extra room for drop down image
	local paddedReuse = longestReuse + DROPDOWN_PADDING

	return paddedName, paddedReuse
end

function modify_pilot_skills_ui:buildSkillEntryEnable(entryRow, skill, enabled, skillLength, onToggleCallback)
	local shortName = GetText(skill.shortName)
	local description = GetText(skill.description)
	local category = skill.category

	local enabledCheckbox = UiCheckbox()
		:widthpx(skillLength):heightpx(ROW_HEIGHT)
		:settooltip(description)
		:decorate({
			DecoButton(),
			DecoCheckbox(),
			DecoAlign(0, 2),
			DecoText(shortName)
		})
		:addTo(entryRow)

	enabledCheckbox.checked = enabled

	enabledCheckbox.onToggled:subscribe(function(checked)
		if checked then
			cplus_plus_ex:enableSkill(skill.id)
		else
			cplus_plus_ex:disableSkill(skill.id)
		end
		modify_pilot_skills_ui:updateAllPercentages()
		cplus_plus_ex:saveConfiguration()

		-- Call the callback if provided for category checkbox updates
		if onToggleCallback then
			onToggleCallback()
		end
	end)

	return enabledCheckbox
end

function modify_pilot_skills_ui:buildSkillEntryReusability(entryRow, skill, resuability, resuabilityLength)
	local allowedReusability = cplus_plus_ex:getAllowedReusability(skill.id)
	local reusabilityValues = {}
	local reusabilityStrings = {}
	local reusabilityTooltips = {}

	-- Build dropdown options from allowed values
	local count = 1
	for k, _ in pairs(allowedReusability) do
		table.insert(reusabilityValues, count)
		table.insert(reusabilityStrings, REUSABLILITY_NAMES[k])
		table.insert(reusabilityTooltips, REUSABLILITY_DESCRIPTIONS[k])
		count = count + 1
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
		reusabilityWidget = UiDropDown(reusabilityValues, reusabilityStrings, reusability, reusabilityTooltips)
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
		local function updateTooltip()
			local baseTooltip = "Skill reusability setting"
			local selectedTooltip = reusabilityTooltips[reusabilityWidget.choice] or ""
			reusabilityWidget:settooltip(baseTooltip .. "\n\nCurrent: " .. selectedTooltip)
		end
		updateTooltip()

		-- Handle reusability changes
		reusabilityWidget.optionSelected:subscribe(function(oldChoice, oldValue, newChoice, newValue)
			cplus_plus_ex:setSkillConfig(skill.id, {reusability = newValue})
			cplus_plus_ex:saveConfiguration()
			updateTooltip()
		end)
	end
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

	-- Function to apply weight changes
	local function applyWeightChange(self)
		local isValid, value = modify_pilot_skills_ui:validateNumericInput(self.textfield)
		if isValid and value >= 0 then
			-- Format to 2 decimal places
			self.textfield = string.format("%.2f", value)
			cplus_plus_ex:setSkillConfig(skill.id, {weight = value})
			modify_pilot_skills_ui:updateAllPercentages()
			cplus_plus_ex:saveConfiguration()
		else
			-- Reset to current value if invalid
			local currentConfig = cplus_plus_ex.config.skillConfigs[skill.id]
			if currentConfig then
				self.textfield = string.format("%.2f", currentConfig.weight)
			end
		end
	end

	-- Handle Enter key
	weightInput.onEnter = function(self)
		applyWeightChange(self)
		return UiInputField.onEnter(self)
	end

	-- Handle focus loss
	weightInput.onFocusChangedEvent:subscribe(function(self, focused, focused_prev)
		if not focused and focused_prev then
			-- Lost focus, apply changes
			applyWeightChange(self)
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

-- Builds a single skill entry row
function modify_pilot_skills_ui:buildSkillEntry(skill, skillLength, resuabilityLength, onToggleCallback)
	local skillConfigObj = cplus_plus_ex.config.skillConfigs[skill.id]
	if not skillConfigObj then
		logger.logWarn(SUBMODULE, "No config for skill " .. skill.id)
		return Ui():width(1):heightpx(0) -- Return empty element
	end

	local entryRow = UiWeightLayout()
		:width(1):heightpx(ROW_HEIGHT)

	-- Add values to the row
	local enableCheckbox = modify_pilot_skills_ui:buildSkillEntryEnable(entryRow, skill, skillConfigObj.enabled, skillLength, onToggleCallback)
	modify_pilot_skills_ui:buildSkillEntryReusability(entryRow, skill, skillConfigObj.reusability, resuabilityLength)
	modify_pilot_skills_ui:buildSkillEntryWeightInput(entryRow, skill, skillConfigObj.weight)
	modify_pilot_skills_ui:buildSkillEntryLabels(entryRow, skill)

	-- Store the enable checkbox for category management
	entryRow.enableCheckbox = enableCheckbox

	return entryRow
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
	local settingsContent = self:buildCollapsibleSection("General Settings", scrollContent)

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
end

function modify_pilot_skills_ui:buildSkillsList(scrollContent)
	-- Add sort options to Skills Configuration header
	local sortOptions = {"Name", "Enabled", "Reusability", "Weight/%"}
	local skillsContent, skillsSortDropdown = self:buildCollapsibleSection("Skills Configuration", scrollContent, nil, nil, false, nil, sortOptions)

	local skillLength, reuseabilityLength = modify_pilot_skills_ui:determineColumnLengths()

	-- Track current sort option
	-- 1 = Name, 2 = Enabled, 3 = Reusability, 4 = Weight/%
	local currentSkillSort = cplus_plus_ex.config.skillConfigSortOrder or 1

	-- Set initial dropdown value
	if skillsSortDropdown then
		skillsSortDropdown.value = currentSkillSort
		skillsSortDropdown.choice = currentSkillSort
	end

	-- Get all skills organized by category
	local skillsByCategory = self:getSkillsByCategory()

	-- Sort categories alphabetically
	local sortedCategories = {}
	for category in pairs(skillsByCategory) do
		table.insert(sortedCategories, category)
	end
	table.sort(sortedCategories)

	-- Function to sort skills based on current sort option
	local function sortSkills(skills)
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

	-- Function to rebuild all categories with current sort
	local function rebuildSkillCategories()
		-- Clear existing content but keep header
		while #skillsContent.children > 0 do
			skillsContent.children[#skillsContent.children]:detach()
		end
		
		-- Clear tracking tables for fresh rebuild
		percentageLabels = {}
		categoryHeaderLabels = {}

		-- Build each category section
		for _, category in ipairs(sortedCategories) do
			local skills = sortSkills(skillsByCategory[category])
			local categoryContent, categoryCheckbox = self:buildCategorySection(category, skillsContent, skills, skillLength, reuseabilityLength, false)

			-- Track checkboxes for this category
			local categorySkillCheckboxes = {}

			-- Method to update category checkbox state based on children
			categoryCheckbox.updateCheckedState = function(self)
				local enabledCount = 0
				local totalCount = #categorySkillCheckboxes

				for _, entry in ipairs(categorySkillCheckboxes) do
					local skillConfig = cplus_plus_ex.config.skillConfigs[entry.skillId]
					if skillConfig and skillConfig.enabled then
						enabledCount = enabledCount + 1
					end
				end

				-- Set tri-state based on enabled count
				if enabledCount == totalCount and totalCount > 0 then
					self.checked = true
				elseif enabledCount == 0 then
					self.checked = false
				else
					self.checked = "mixed"
				end
			end

			-- Update all child checkboxes
			categoryCheckbox.updateChildrenCheckedState = function(self)
				local newState = (self.checked == true)

				for _, entry in ipairs(categorySkillCheckboxes) do
					if newState then
						cplus_plus_ex:enableSkill(entry.skillId)
					else
						cplus_plus_ex:disableSkill(entry.skillId)
					end
					entry.checkbox.checked = newState
				end

				modify_pilot_skills_ui:updateAllPercentages()
				cplus_plus_ex:saveConfiguration()
			end

			-- Build skill entries
			for _, skill in ipairs(skills) do
				local onToggleCallback = function()
					categoryCheckbox:updateCheckedState()
				end

				local skillEntry = modify_pilot_skills_ui:buildSkillEntry(skill, skillLength, reuseabilityLength, onToggleCallback)
					:addTo(categoryContent)

				-- Track the skill's enable checkbox for category updates
				table.insert(categorySkillCheckboxes, {
					skillId = skill.id,
					checkbox = skillEntry.enableCheckbox
				})
			end

			-- Category checkbox click handler
			categoryCheckbox.onclicked = function(self, button)
				if button == 1 then
					self:updateChildrenCheckedState()
					self:updateCheckedState()
					return true
				end
				return false
			end

			-- Initial state
			categoryCheckbox:updateCheckedState()
		end
	end

	-- Subscribe to sort dropdown changes
	if skillsSortDropdown then
		skillsSortDropdown.optionSelected:subscribe(function(_, _, choice, value)
			currentSkillSort = value
			-- Save sort order preference
			cplus_plus_ex.config.skillConfigSortOrder = value
			cplus_plus_ex:saveConfiguration()
			rebuildSkillCategories()
			-- Update percentages after rebuild
			modify_pilot_skills_ui:updateAllPercentages()
		end)
	end

	-- Initial build
	rebuildSkillCategories()

	-- Initial percentage calculation
	modify_pilot_skills_ui:updateAllPercentages()
end

function modify_pilot_skills_ui:addPilotImage(pilotId, row)
	local pilotUi = Ui()
		:widthpx(PILOT_SIZE - BOARDER_SIZE * 2):heightpx(ROW_HEIGHT)

	-- Always draw frame border, add portrait on top if available
	local decorations = { DecoFrame() }

	if pilotId and pilotId ~= "All" and pilotId ~= "" then
		local portrait = modify_pilot_skills_ui:getPilotPortrait(pilotId)
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
		local skill = cplus_plus_ex._subobjects.skill_registry.registeredSkills[skillId]
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
	local function updateTooltip()
		local baseTooltip = "Select " .. label:lower() .. " (or All)"
		local selectedTooltip = listTooltips[dropDown.choice] or ""
		if selectedTooltip ~= "" then
			dropDown:settooltip(baseTooltip .. "\n\nCurrent: " .. selectedTooltip)
		else
			dropDown:settooltip(baseTooltip)
		end
	end
	updateTooltip()

	-- Handle reusability changes
	dropDown.optionSelected:subscribe(function(oldChoice, oldValue, newChoice, newValue)
		selectFn(oldChoice, oldValue, newChoice, newValue)
		updateTooltip()
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

function modify_pilot_skills_ui:createDropDownItems(dataList, sortedIds, includeSkillTooltips)
	local listDisplay = {"", "All"}
	local listVals = {"", "All"}
	local listTooltips = {"", "Add entry for each item"}

	-- Use presorted IDs if provided, otherwise use utils.sortByValue
	local keysToUse = sortedIds or utils.sortByValue(dataList)

	for _, k in ipairs(keysToUse) do
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
	return listDisplay, listVals, listTooltips
end

-- Builds a relationship editor section
function modify_pilot_skills_ui:buildRelationshipEditor(parent, relationshipTable, title, sourceList, targetList, sourceLabel, targetLabel, isSameTypeRelation, sourceIdsSorted, targetIdsSorted, sectionTooltip, sortConfigKey)
	-- create list values with empty and all (using sorted IDs)
	-- Include skill tooltips if the label is "Skill"
	local includeSourceTooltips = sourceLabel == "Skill"
	local includeTargetTooltips = targetLabel == "Skill"

	local listDisplay, listVals, listTooltips = modify_pilot_skills_ui:createDropDownItems(sourceList, sourceIdsSorted, includeSourceTooltips)
	local targetListDisplay, targetListVals, targetListTooltips = modify_pilot_skills_ui:createDropDownItems(targetList, targetIdsSorted, includeTargetTooltips)

	-- Container for this section
	local largestHeight = sourceLabel == "Pilot" and PILOT_SIZE or ROW_HEIGHT
	local padding = largestHeight - ROW_HEIGHT  + 3 + DEFAULT_VGAP
	local initialPadding = padding / 2 + DEFAULT_VGAP

	-- Build section with sort dropdown in header
	local sortOptions = {"First Column", "Second Column"}
	local sectionContainer, sortDropdown = self:buildCollapsibleSection(title, parent, padding, initialPadding, false, sectionTooltip, sortOptions)

	-- State for the add dropdowns and sorting
	local selectedSource = listVals[1]
	local selectedTarget = targetListVals[1]
	local currentPilotPortrait = nil
	local sortColumn = cplus_plus_ex.config[sortConfigKey] or 1  -- Load saved sort order (1 = source, 2 = target)
	local newlyAddedRelationships = {}  -- Track newly added items to show at top

	-- Set initial dropdown value
	if sortDropdown then
		sortDropdown.value = sortColumn
		sortDropdown.choice = sortColumn
	end

	-- Function to rebuild the list of existing relationships
	local function rebuildRelationshipList()
		-- Clear existing list (remove all but the add row)
		while #sectionContainer.children > 1 do
			sectionContainer.children[#sectionContainer.children]:detach()
		end

		-- Collect all relationships into a list for sorting
		local relationshipList = {}
		local newItemsList = {}

		for sourceId, targets in pairs(relationshipTable) do
			for targetId, _ in pairs(targets) do
				local key = sourceId .. "|" .. targetId
				local relationship = {sourceId = sourceId, targetId = targetId}

				-- Check if this is a newly added item
				if newlyAddedRelationships[key] then
					table.insert(newItemsList, relationship)
				else
					table.insert(relationshipList, relationship)
				end
			end
		end

		-- Sort only the non-new items based on the selected column
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

		-- Build newly added items first 
		for _, relationship in ipairs(newItemsList) do
			local sourceId = relationship.sourceId
			local targetId = relationship.targetId

			local entryRow = UiWeightLayout()
				:width(1):heightpx(ROW_HEIGHT)
				:addTo(sectionContainer)

			-- Pilot portrait if its a pilot
			if sourceLabel == "Pilot" then
				modify_pilot_skills_ui:addPilotImage(sourceId, entryRow)
			end

			-- Add labels with skill tooltips if applicable
			local sourceSkillId = sourceLabel == "Skill" and sourceId or nil
			local targetSkillId = targetLabel == "Skill" and targetId or nil
			modify_pilot_skills_ui:addExistingRelLabel(sourceList[sourceId], entryRow, sourceSkillId)
			modify_pilot_skills_ui:addArrowLabel(title == "Skill Exclusions", entryRow)
			modify_pilot_skills_ui:addExistingRelLabel(targetList[targetId], entryRow, targetSkillId)

				-- Remove button
				local btnRemove = sdlext.buildButton(
					"Remove",
					"Remove this relationship",
					function()
						-- Remove from config
						if relationshipTable[sourceId] then
							relationshipTable[sourceId][targetId] = nil
							-- If no more targets, remove source entry
							local hasAny = false
							for _, _ in pairs(relationshipTable[sourceId]) do
								hasAny = true
								break
							end
							if not hasAny then
								relationshipTable[sourceId] = nil
							end
						end

						-- Save and rebuild
						cplus_plus_ex:saveConfiguration()
						rebuildRelationshipList()
						return true
					end
				)
				btnRemove:widthpx(RELATIONSHIP_BUTTON_WIDTH)
					:heightpx(ROW_HEIGHT)
					:addTo(entryRow)
		end

		-- Build sorted items
		for _, relationship in ipairs(relationshipList) do
			local sourceId = relationship.sourceId
			local targetId = relationship.targetId

			local entryRow = UiWeightLayout()
				:width(1):heightpx(ROW_HEIGHT)
				:addTo(sectionContainer)

			-- Pilot portrait if its a pilot
			if sourceLabel == "Pilot" then
				modify_pilot_skills_ui:addPilotImage(sourceId, entryRow)
			end

			-- Add labels with skill tooltips if applicable
			local sourceSkillId = sourceLabel == "Skill" and sourceId or nil
			local targetSkillId = targetLabel == "Skill" and targetId or nil
			modify_pilot_skills_ui:addExistingRelLabel(sourceList[sourceId], entryRow, sourceSkillId)
			modify_pilot_skills_ui:addArrowLabel(title == "Skill Exclusions", entryRow)
			modify_pilot_skills_ui:addExistingRelLabel(targetList[targetId], entryRow, targetSkillId)

			-- Remove button
			local btnRemove = sdlext.buildButton(
				"Remove",
				"Remove this relationship",
				function()
					-- Remove from config
					if relationshipTable[sourceId] then
						relationshipTable[sourceId][targetId] = nil
						-- If no more targets, remove source entry
						local hasAny = false
						for _, _ in pairs(relationshipTable[sourceId]) do
							hasAny = true
							break
						end
						if not hasAny then
							relationshipTable[sourceId] = nil
						end
					end

					-- Remove from newly added tracking
					local key = sourceId .. "|" .. targetId
					newlyAddedRelationships[key] = nil

					-- Save and rebuild
					cplus_plus_ex:saveConfiguration()
					rebuildRelationshipList()
					return true
				end
			)
			btnRemove:widthpx(RELATIONSHIP_BUTTON_WIDTH)
				:heightpx(ROW_HEIGHT)
				:addTo(entryRow)
		end

		-- Spacer
		Ui():width(1):heightpx(1):addTo(sectionContainer)
	end

	-- add row always at the top
	local addRow = UiWeightLayout()
		:width(1):heightpx(ROW_HEIGHT)
		:addTo(sectionContainer)

	-- Pilot portrait if its a pilot
	if sourceLabel == "Pilot" then
		currentPilotPortrait = modify_pilot_skills_ui:addPilotImage(selectedSource, addRow)
	end

	-- Source dropdown
	modify_pilot_skills_ui:addNewRelDropDown(sourceLabel, listVals, listDisplay, listTooltips,
		function(oldChoice, oldValue, newChoice, newValue)
			selectedSource = newValue

			-- Update portrait if its a pilot table
			if sourceLabel == "Pilot" and currentPilotPortrait then
				-- Remove old portrait decoration
				for i = #currentPilotPortrait.decorations, 1, -1 do
					local deco = currentPilotPortrait.decorations[i]
					if deco.__index and deco.__index:isSubclassOf(DecoSurface) then
						table.remove(currentPilotPortrait.decorations, i)
					end
				end

				-- Add new portrait if not "All"
				if newValue ~= "All" and newValue ~= "" then
					local portrait = modify_pilot_skills_ui:getPilotPortrait(newValue)
					if portrait then
						table.insert(currentPilotPortrait.decorations, DecoSurface(portrait))
					end
				end
			end
		end, addRow)

	-- Arrow
	modify_pilot_skills_ui:addArrowLabel(title == "Skill Exclusions", addRow)

	-- Target dropdown
	modify_pilot_skills_ui:addNewRelDropDown(targetLabel, targetListVals, targetListDisplay, targetListTooltips,
		function(oldChoice, oldValue, newChoice, newValue)
			selectedTarget = newValue
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
				sourcesToAdd = sourceList
			else
				sourcesToAdd = {[selectedSource] = true}
			end

			if selectedTarget == "All" then
				targetsToAdd = targetList
			else
				targetsToAdd = {[selectedTarget] = true}
			end

			-- Add all combinations
			for sourceId, _ in pairs(sourcesToAdd) do
				for targetId, _ in pairs(targetsToAdd) do
					-- Skip adding to self (if all was used)
					if not (sourceId == targetId) then
						if not relationshipTable[sourceId] then
							relationshipTable[sourceId] = {}
						end
						relationshipTable[sourceId][targetId] = true

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
end

function modify_pilot_skills_ui:buildRelationships(scrollContent)
	local relationshipsContent = self:buildCollapsibleSection("Skill Relationships", scrollContent)

	-- Get lists for dropdowns (now includes sorted IDs)
	local pilotData, pilotIdsSorted = modify_pilot_skills_ui:getPilotsData()
	local skillData, exlusionSkillData, inclusionSkillData,
	      skillIdsSorted, exlusionSkillIdsSorted, inclusionSkillIdsSorted = modify_pilot_skills_ui:getSkillsData()

	-- Pilot Skill Exclusions
	modify_pilot_skills_ui:buildRelationshipEditor(
		relationshipsContent,
		cplus_plus_ex.config.pilotSkillExclusions,
		"Exclusions: Pilot → Skill",
		pilotData,
		exlusionSkillData,
		"Pilot",
		"Skill",
		false,
		pilotIdsSorted,
		exlusionSkillIdsSorted,
		"Prevent specific pilots from receiving certain skills",
		"pilotSkillExclusionsSortOrder"
	)
	
	if #inclusionSkillData > 0 then
		-- Pilot Skill Inclusions
		modify_pilot_skills_ui:buildRelationshipEditor(
			relationshipsContent,
			cplus_plus_ex.config.pilotSkillInclusions,
			"Inclusions: Pilot → Skill ",
			pilotData,
			inclusionSkillData,
			"Pilot",
			"Skill",
			false,
			pilotIdsSorted,
			inclusionSkillIdsSorted,
			"Allow specific pilots to receive the skill",
			"pilotSkillInclusionsSortOrder"
		)
	end

	-- Skill Exclusions
	modify_pilot_skills_ui:buildRelationshipEditor(
		relationshipsContent,
		cplus_plus_ex.config.skillExclusions,
		"Exclusions: Skill ↔ Skill",
		skillData,
		skillData,
		"Skill",
		"Skill",
		true,
		skillIdsSorted,
		skillIdsSorted,
		"Prevent certain skills from being selected together on the same pilot",
		"skillExclusionsSortOrder"
	)
end

-- Builds the main content for the dialog
function modify_pilot_skills_ui:buildMainContent(scroll)
	-- Clear tracking tables
	percentageLabels = {}
	categoryHeaderLabels = {}

	scrollContent = UiBoxLayout()
		:vgap(5)
		:width(1)
		:addTo(scroll)

	-- Add the settings
	modify_pilot_skills_ui:buildGeneralSettings(scrollContent)
	modify_pilot_skills_ui:buildSkillsList(scrollContent)
	modify_pilot_skills_ui:buildRelationships(scrollContent)
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
					modify_pilot_skills_ui:buildMainContent(parentScroll)
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
		function() modify_pilot_skills_ui:buildResetConfirmation() end
	)
	btnReset:addTo(buttonLayout)
end

-- Called when dialog is closed
local function onExit()
	cplus_plus_ex:saveConfiguration()
	scrollContent = nil
	percentageLabels = {}
	categoryHeaderLabels = {}
	expandedCollapsables = {}
end

-- Creates the main modification dialog
function modify_pilot_skills_ui:createDialog()
	-- Load configuration before opening dialog
	cplus_plus_ex:loadConfiguration()

	sdlext.showDialog(function(ui, quit)
		ui.onDialogExit = onExit

		local frame = sdlext.buildButtonDialog(
			"Modify Pilot Level Up Skills",
			function(scroll) modify_pilot_skills_ui:buildMainContent(scroll) end,
			function(buttonLayout) modify_pilot_skills_ui:buildDialogButtons(buttonLayout) end,
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
