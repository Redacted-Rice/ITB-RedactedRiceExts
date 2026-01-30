-- Modify Pilot Skills UI
-- UI for modifying skill weights and configurations

local modify_pilot_skills_ui = {}

-- Register with logging system
local logger = memhack.logger
local SUBMODULE = logger.register("CPLUS+", "SkillsUI", cplus_plus_ex.DEBUG.UI and cplus_plus_ex.DEBUG.ENABLED)

local utils = nil

local scrollContent = nil
-- Track UI widgets for updates
local weightInputFields = {}
local percentageLabels = {}
local expandedCollapsables = {}

-- constants
local SKILL_NAME_HEADER = "Skill Name"
local REUSABLILITY_HEADER = "Reusability"
local REUSABLILITY_NAMES = { "Reusable", "Per Pilot", "Per Run" }
local ADVANCED_PILOTS = {"Pilot_Arrogant", "Pilot_Caretaker", "Pilot_Chemical", "Pilot_Delusional"}

local BOARDER_SIZE = 2
local DEFAULT_VGAP = 5
local ROW_HEIGHT = 41
local CHECKBOX_PADDING = 40
local DROPDOWN_PADDING = 40
local COLLAPSE_BTN_PADDING = 40
local COLLAPSE_PADDING = 46
local PILOT_SIZE = 65
local RELATIONSHIP_BUTTON_WIDTH = 140

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
        "Modify Pilot Skills",
        function()
            self.createDialog()
        end,
        "Modify skill weights and configurations"
    )
    return self
end

function modify_pilot_skills_ui:getPilotsData(pilotIds)
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
function modify_pilot_skills_ui:buildCollapsibleSection(title, parent, vgap, initialVgap, startCollapsed)
	local collapse, headerHolder = self:buildCollapsibleSectionBase(title, parent, vgap, initialVgap, startCollapsed)

	-- Section title
	Ui()
		:width(1):heightpx(ROW_HEIGHT)
		:decorate({
			DecoFrame(deco.colors.buttonborder),
			DecoAlign(0, 2),
			DecoText(title, nil, nil, nil, nil, nil, nil, deco.uifont.title.font)
		})
		:addTo(headerHolder)

	return collapse.dropdownHolder
end

-- Builds a category section with tri checkbox
-- Returns the content holder and the checkbox for updating checked state
function modify_pilot_skills_ui:buildCategorySection(category, parent, skillLength, resuabilityLength, startCollapsed)
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

	Ui()
		:width(0.25):heightpx(ROW_HEIGHT)
		:decorate({
			DecoFrame(deco.colors.buttonborder),
			DecoAlign(0, 2),
			DecoCAlignedText("Weight", nil, nil, nil, nil, nil, nil, deco.uifont.tooltipTitle.font)
		})
		:settooltip("How likely the skill will be picked against others")
		:addTo(headerHolder)

	Ui()
		:width(0.25):heightpx(ROW_HEIGHT)
		:decorate({
			DecoFrame(deco.colors.buttonborder),
			DecoAlign(0, 2),
			DecoCAlignedText("%", nil, nil, nil, nil, nil, nil, deco.uifont.tooltipTitle.font)
		})
		:settooltip("Percentage chance of selection for a skill")
		:addTo(headerHolder)

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

	local enableCheckbox = modify_pilot_skills_ui:buildSkillEntryEnable(entryRow, skill, skillConfigObj.enabled, skillLength, onToggleCallback)

	-- Store the enable checkbox for category management
	entryRow.enableCheckbox = enableCheckbox

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
		-- TODO: Add tool tips
		table.insert(reusabilityTooltips, REUSABLILITY_NAMES[k])
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
			:settooltip("Skill reusability setting")
			:decorate({
				DecoButton(),
				DecoAlign(0, 2),
				DecoDropDownText(nil, nil, nil, 33),
				DecoAlign(0, -2),
				DecoDropDown()
			})
			:addTo(entryRow)

		-- Handle reusability changes
		reusabilityWidget.optionSelected:subscribe(function(oldChoice, oldValue, newChoice, newValue)
			cplus_plus_ex:setSkillConfig(skillId, {reusability = newValue})
			cplus_plus_ex:saveConfiguration()
		end)
	end
end

function modify_pilot_skills_ui:buildSkillEntryWeightInput(entryRow, skill, weight)
	local weightInput = UiInputField()
		:width(0.25):heightpx(ROW_HEIGHT)
		:settooltip("Enter weight (numeric only, press Enter to apply)")
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

	-- Store reference for later updates
	weightInputFields[skill.id] = weightInput

	-- Handle weight changes
	weightInput.onEnter = function(self)
		local isValid, value = modify_pilot_skills_ui:validateNumericInput(self.textfield)
		if isValid and value >= 0 then
			cplus_plus_ex:setSkillConfig(skill.id, {weight = value})
			modify_pilot_skills_ui:updateAllPercentages()
			cplus_plus_ex:saveConfiguration()
		else
			-- Reset to current value if invalid
			local currentConfig = cplus_plus_ex.config.skillConfigs[skill.id]
			self.textfield = string.format("%.2f", weight)
		end
		return UiInputField.onEnter(self)
	end
end

function modify_pilot_skills_ui:buildSkillEntryLabels(entryRow, skill)
	-- Percentage label
	local percentageLabel = Ui()
		:width(0.25):heightpx(ROW_HEIGHT)
		:settooltip("TODO")
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

-- Builds header row for skill columns
function modify_pilot_skills_ui:buildHeaderRow(skillLength, resuabilityLength)
	local headerRow = UiWeightLayout()
		:width(1):heightpx(ROW_HEIGHT)
	Ui()
		:widthpx(skillLength):heightpx(ROW_HEIGHT)
		:decorate({
			DecoFrame(deco.colors.buttonborder),
			DecoAlign(0, 2),
			DecoText(SKILL_NAME_HEADER, nil, nil, nil, nil, nil, nil, deco.uifont.tooltipTitle.font)
		})
		:addTo(headerRow)

	Ui()
		:widthpx(resuabilityLength):heightpx(ROW_HEIGHT)
		:decorate({
			DecoFrame(deco.colors.buttonborder),
			DecoAlign(0, 2),
			DecoText(REUSABLILITY_HEADER, nil, nil, nil, nil, nil, nil, deco.uifont.tooltipTitle.font)
		})
		:settooltip("How the skill can be reused across pilots and runs")
		:addTo(headerRow)

	Ui()
		:width(0.25):heightpx(ROW_HEIGHT)
		:decorate({
			DecoFrame(deco.colors.buttonborder),
			DecoAlign(0, 2),
			DecoText("Weight", nil, nil, nil, nil, nil, nil, deco.uifont.tooltipTitle.font)
		})
		:addTo(headerRow)

	Ui()
		:width(0.25):heightpx(ROW_HEIGHT)
		:decorate({
			DecoFrame(deco.colors.buttonborder),
			DecoAlign(0, 2),
			DecoText("%", nil, nil, nil, nil, nil, nil, deco.uifont.tooltipTitle.font)
		})
		:settooltip("Percentage chance of selection for first skill")
		:addTo(headerRow)

	return headerRow
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
	local skillsContent = self:buildCollapsibleSection("Skills Configuration", scrollContent)

	local skillLength, reuseabilityLength = modify_pilot_skills_ui:determineColumnLengths()

	-- Get all skills organized by category
	local skillsByCategory = self:getSkillsByCategory()

	-- Sort categories alphabetically
	local sortedCategories = {}
	for category in pairs(skillsByCategory) do
		table.insert(sortedCategories, category)
	end
	table.sort(sortedCategories)

	-- Build each category section
	for _, category in ipairs(sortedCategories) do
		local skills = skillsByCategory[category]
		local categoryContent, categoryCheckbox = self:buildCategorySection(category, skillsContent, skillLength, reuseabilityLength, false)

		-- Track checkboxes for this category
		local categorySkillCheckboxes = {}

		-- Method to update category checkbox state based on children
		categoryCheckbox.updateCheckedState = function(self)
			local count = 0
			local totalCount = #categorySkillCheckboxes

			for i, entry in ipairs(categorySkillCheckboxes) do
				local skillConfig = cplus_plus_ex.config.skillConfigs[entry.skillId]
				if skillConfig then
					if skillConfig.enabled then
						count = count + 1
					else
						count = count - 1
					end

					-- Early exit optimization
					if math.abs(count) ~= i then
						break
					end
				end
			end

			-- Set tri-state based on count
			if count == totalCount and totalCount > 0 then
				self.checked = true
			elseif count == -totalCount then
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

	-- Initial percentage calculation
	modify_pilot_skills_ui:updateAllPercentages()
end

function modify_pilot_skills_ui:addPilotImage(pilotId, row)
	local pilotUi = Ui()
		:widthpx(PILOT_SIZE - BOARDER_SIZE * 2):heightpx(ROW_HEIGHT)

	-- Add portrait if we have one, or draw empty frame
	if pilotId and pilotId ~= "All" and pilotId ~= "" then
		local portrait = modify_pilot_skills_ui:getPilotPortrait(pilotId)
		if portrait then
			pilotUi:decorate({
				DecoSurface(portrait),
			})
		else
			-- Draw empty frame when portrait not found
			pilotUi:decorate({
				DecoFrame(),
			})
		end
	else
		-- Draw empty frame for "All" or empty selection
		pilotUi:decorate({
			DecoFrame(),
		})
	end

	pilotUi:addTo(row)
	-- Add some spacing
	Ui():widthpx(BOARDER_SIZE * 2):heightpx(ROW_HEIGHT):addTo(row)
	return pilotUi
end

function modify_pilot_skills_ui:addExistingRelLabel(text, row)
	Ui()
		:width(0.5):heightpx(ROW_HEIGHT)
		:decorate({
			DecoFrame(),
			DecoAlign(0, 2),
			DecoText(text)
		})
		:addTo(row)
end

function modify_pilot_skills_ui:addNewRelDropDown(label, listVals, listDisplay, selectFn, row)
	local dropDown = UiDropDown(listVals, listDisplay, listVals[1])
		-- Half the usable space
		:width(0.5):heightpx(ROW_HEIGHT)
		:settooltip("Select " .. label:lower() .. " (or All)")
		:decorate({
			DecoButton(),
			DecoAlign(0, 2),
			DecoDropDownText(nil, nil, nil, 33),
			DecoAlign(0, -2),
			DecoDropDown()
		})
		:addTo(row)

	dropDown.optionSelected:subscribe(selectFn)
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

function modify_pilot_skills_ui:createDropDownItems(dataList, sortedIds)
	local listDisplay = {"", "All"}
	local listVals = {"", "All"}

	-- Use presorted IDs if provided, otherwise use utils.sortByValue
	local keysToUse = sortedIds or utils.sortByValue(dataList)

	for _, k in ipairs(keysToUse) do
		table.insert(listDisplay, dataList[k])
		table.insert(listVals, k)
	end
	return listDisplay, listVals
end

-- Builds a relationship editor section
function modify_pilot_skills_ui:buildRelationshipEditor(parent, relationshipTable, title, sourceList, targetList, sourceLabel, targetLabel, isSameTypeRelation, sourceIdsSorted, targetIdsSorted)
	-- create list values with empty and all (using sorted IDs)
	local listDisplay, listVals = modify_pilot_skills_ui:createDropDownItems(sourceList, sourceIdsSorted)
	local targetListDisplay, targetListVals = modify_pilot_skills_ui:createDropDownItems(targetList, targetIdsSorted)

	-- Container for this section
	local largestHeight = sourceLabel == "Pilot" and PILOT_SIZE or ROW_HEIGHT
	local padding = largestHeight - ROW_HEIGHT  + 3 + DEFAULT_VGAP
	local initialPadding = padding / 2 + DEFAULT_VGAP
	
	local sectionContainer = self:buildCollapsibleSection(title, parent, padding, initialPadding)

	-- State for the add dropdowns
	local selectedSource = listVals[1]
	local selectedTarget = targetListVals[1]
	local currentPilotPortrait = nil

	-- Function to rebuild the list of existing relationships
	local function rebuildRelationshipList()
		-- Clear existing list (remove all but the add row)
		while #sectionContainer.children > 1 do
			sectionContainer.children[#sectionContainer.children]:detach()
		end

		-- Build list of all existing relationships
		for sourceId, targets in pairs(relationshipTable) do
			for targetId, _ in pairs(targets) do
				local entryRow = UiWeightLayout()
					:width(1):heightpx(ROW_HEIGHT)
					:addTo(sectionContainer)

				-- Pilot portrait if its a pilot
				if sourceLabel == "Pilot" then
					modify_pilot_skills_ui:addPilotImage(sourceId, entryRow)
				end

				modify_pilot_skills_ui:addExistingRelLabel(sourceList[sourceId], entryRow)
				modify_pilot_skills_ui:addArrowLabel(title == "Skill Exclusions", entryRow)
				modify_pilot_skills_ui:addExistingRelLabel(targetList[targetId], entryRow)

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
		end
		-- Spacer
		Ui():width(1):heightpx(1):addTo(sectionContainer)
	end

	-- add row
	local addRow = UiWeightLayout()
		:width(1):heightpx(ROW_HEIGHT)
		:addTo(sectionContainer)

	-- Pilot portrait if its a pilot
	if sourceLabel == "Pilot" then
		currentPilotPortrait = modify_pilot_skills_ui:addPilotImage(selectedSource, addRow)
	end

	-- Source dropdown
	modify_pilot_skills_ui:addNewRelDropDown(sourceLabel, listVals, listDisplay,
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
	modify_pilot_skills_ui:addNewRelDropDown(targetLabel, targetListVals, targetListDisplay,
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
		"Pilot Skill Exclusions",
		pilotData,
		exlusionSkillData,
		"Pilot",
		"Skill",
		false,
		pilotIdsSorted,
		exlusionSkillIdsSorted
	)

	-- Pilot Skill Inclusions
	modify_pilot_skills_ui:buildRelationshipEditor(
		relationshipsContent,
		cplus_plus_ex.config.pilotSkillInclusions,
		"Pilot Skill Inclusions",
		pilotData,
		inclusionSkillData,
		"Pilot",
		"Skill",
		false,
		pilotIdsSorted,
		inclusionSkillIdsSorted
	)

	-- Skill Exclusions
	modify_pilot_skills_ui:buildRelationshipEditor(
		relationshipsContent,
		cplus_plus_ex.config.skillExclusions,
		"Skill Exclusions",
		skillData,
		skillData,
		"Skill",
		"Skill",
		true,
		skillIdsSorted,
		skillIdsSorted
	)
end

-- Builds the main content for the dialog
function modify_pilot_skills_ui:buildMainContent(scroll)
	-- Clear tracking tables
	weightInputFields = {}
	percentageLabels = {}

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
					weightInputFields = {}
					percentageLabels = {}
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
	weightInputFields = {}
	percentageLabels = {}
	expandedCollapsables = {}
end

-- Creates the main modification dialog
function modify_pilot_skills_ui:createDialog()
	-- Load configuration before opening dialog
	cplus_plus_ex:loadConfiguration()

	sdlext.showDialog(function(ui, quit)
		ui.onDialogExit = onExit

		local frame = sdlext.buildButtonDialog(
			"Modify Pilot Skills",
			function(scroll) modify_pilot_skills_ui:buildMainContent(scroll) end,
			function(buttonLayout) modify_pilot_skills_ui:buildDialogButtons(buttonLayout) end,
			{
				maxW = 0.8 * ScreenSizeX(),
				maxH = 0.85 * ScreenSizeY(),
				compactH = false
			}
		)

		frame:addTo(ui)
			:pospx((ui.w - frame.w) / 2, (ui.h - frame.h) / 2)
	end)
end

return modify_pilot_skills_ui
