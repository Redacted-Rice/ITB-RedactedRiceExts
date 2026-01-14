-- Modify Pilot Skills UI
-- UI for modifying skill weights and configurations

local modify_pilot_skills_ui = {}
local utils = cplus_plus_ex._modules.utils

local scrollContent = nil
-- Track UI widjets for updates
local weightInputFields = {} 
local percentageLabels = {} 
local adjustedWeightLabels = {}
local adjustedPercentLabels = {} 

-- constants
local SKILL_NAME_HEADER = "Skill Name"
local REUSABLILITY_HEADER = "Reusability"
local REUSABLILITY_NAMES = { "Reusable", "Per Pilot", "Per Run" }
local ADVANCED_PILOTS = {"Pilot_Arrogant", "Pilot_Caretaker", "Pilot_Chemical", "Pilot_Delusional"}

local ROW_HEIGHT = 41
local CHECKBOX_PADDING = 40
local DROPDOWN_PADDING = 40
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

-- todo: move
-- Check if skill is dependent (has dependencies)
function modify_pilot_skills_ui.isDependentSkill(skillId)
	return cplus_plus_ex.config.skillDependencies[skillId] ~= nil
end

function modify_pilot_skills_ui.getPilotsData(pilotIds)
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
	return pilotData
end

function modify_pilot_skills_ui.getSkillsData()
	local skills = {}
	local defaultSkills = {}
	local inclusionSkills = {}
	
	for skillId, skill in pairs(cplus_plus_ex._modules.skill_registry.registeredSkills) do
		local skillName = GetText(skill.shortName) or skill.shortName
		skills[skillId] = skillName
		if skill.skillType == "inclusion" then
			inclusionSkills[skillId] = skillName
		else
			defaultSkills[skillId] = skillName
		end
	end
	return skills, defaultSkills, inclusionSkills
end

function modify_pilot_skills_ui.getPilotPortrait(pilotId, scale)
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

-- Gets all skills organized by type (dependent vs non-dependent)
function modify_pilot_skills_ui.getAllSkillsByType()
	local dependentSkills = {}
	local nonDependentSkills = {}

	for skillId, skill in pairs(cplus_plus_ex._modules.skill_registry.registeredSkills) do
		if modify_pilot_skills_ui.isDependentSkill(skillId) then
			table.insert(dependentSkills, skill)
		else
			table.insert(nonDependentSkills, skill)
		end
	end

	-- Sort by short name
	table.sort(dependentSkills, function(a, b)
		return (a.shortName or a.id):lower() < (b.shortName or b.id):lower()
	end)
	table.sort(nonDependentSkills, function(a, b)
		return (a.shortName or a.id):lower() < (b.shortName or b.id):lower()
	end)

	return nonDependentSkills, dependentSkills
end

-- calculate total weight to use for non-dependent and dependent weights
function modify_pilot_skills_ui.calculateTotalWeights(adjusted)
	local totalWeight = 0
	local totalDepWeight = 0
	-- Calculate the total of all enabled skills
	for _, otherSkillId in ipairs(cplus_plus_ex._modules.skill_config.enabledSkillsIds) do
		local skillConfigObj = cplus_plus_ex.config.skillConfigs[otherSkillId]
		if skillConfigObj and skillConfigObj.enabled then
			local weight = adjusted and skillConfigObj.adj_weight or skillConfigObj.set_weight
			-- for non dependent, we exclude dependent skill weights
			if not modify_pilot_skills_ui.isDependentSkill(otherSkillId) then
				totalWeight = totalWeight + weight
			end
			totalDepWeight = totalDepWeight + weight
		end
	end
	
	return totalWeight, totalDepWeight
end

function modify_pilot_skills_ui.updateLabelPecentages(adjusted)
	local nonDepWeight, depWeight = modify_pilot_skills_ui.calculateTotalWeights(adjusted)
	local labels =  adjusted and adjustedPercentLabels or percentageLabels
	
	for skillId, label in pairs(labels) do
		
		local percentage = 0
		local isDependent = modify_pilot_skills_ui.isDependentSkill(skillId)
		local totalWeight = isDependent and depWeight  or nonDepWeight
		local skillConfigObj = cplus_plus_ex.config.skillConfigs[skillId]
		if skillConfigObj and skillConfigObj.enabled then
			local skillWeight = useAdjusted and skillConfigObj.adj_weight or skillConfigObj.set_weight
			percentage = totalWeight > 0 and (skillWeight / totalWeight * 100) or 0
		end

		for _, deco in ipairs(label.decorations) do
			if deco.__index and deco.__index:isSubclassOf(DecoText) then
				deco:setsurface(string.format("%.1f%%", percentage))
				break
			end
		end
	end
end

-- Update all percentage displays
function modify_pilot_skills_ui.updateAllPercentages()
	-- Update set (false) and adjusted (true) percentages
	modify_pilot_skills_ui.updateLabelPecentages(false)
	modify_pilot_skills_ui.updateLabelPecentages(true)

	-- Update adjusted weights
	for skillId, label in pairs(adjustedWeightLabels) do
		local adj_weight = 0
		local skillConfigObj = cplus_plus_ex.config.skillConfigs[skillId]
		if skillConfigObj and skillConfigObj.enabled then
			adj_weight = skillConfigObj.adj_weight
		end
		
		for _, deco in ipairs(label.decorations) do
			if deco.__index and deco.__index:isSubclassOf(DecoText) then
				deco:setsurface(string.format("%.2f", adj_weight))
				break
			end
		end
	end
end

-- Validate and parse numeric input
function modify_pilot_skills_ui.validateNumericInput(text)
	-- Allow empty string, numbers, and decimal point
	if text == "" then return true, 0 end

	-- Try to convert to number
	local num = tonumber(text)
	if num == nil then return false, 0 end
	if num < 0 then return false, 0 end

	return true, num
end

function modify_pilot_skills_ui.getLongestLength(entries)
	local maxWidth = 0
	for _, entry in pairs(entries) do
		local deco = DecoText(entry)
		LOG("length ".. sdlext.totalWidth(deco.surface).. " for entry :" .. entry)
		maxWidth = math.max(maxWidth, sdlext.totalWidth(deco.surface))
	end
	return maxWidth
end

function modify_pilot_skills_ui.determineColumnLengths()
	local names = { SKILL_NAME_HEADER }
	for skillId, skill in pairs(cplus_plus_ex._modules.skill_registry.registeredSkills) do
		table.insert(names, GetText(skill.shortName))
	end
	local longestName = modify_pilot_skills_ui.getLongestLength(names)
	-- Extra room for Checkbox
	local paddedName = longestName + CHECKBOX_PADDING

	local reuseOptions = utils.deepcopy(REUSABLILITY_NAMES)
	table.insert(reuseOptions, REUSABLILITY_HEADER)
	local longestReuse = modify_pilot_skills_ui.getLongestLength(reuseOptions)
	-- Extra room for drop down image
	local paddedReuse = longestReuse + DROPDOWN_PADDING

	return paddedName, paddedReuse
end

function modify_pilot_skills_ui.buildSkillEntryEnable(entryRow, skill, enabled, skillLength)
	local shortName = GetText(skill.shortName)
	local description = GetText(skill.description)
	local category = skill.category

	local enabledCheckbox = UiCheckbox()
		:widthpx(skillLength):heightpx(ROW_HEIGHT)
		:settooltip("Category: " .. category .. "\n\n" .. description)
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
		modify_pilot_skills_ui.updateAllPercentages()
		cplus_plus_ex:saveConfiguration()
	end)
end

function modify_pilot_skills_ui.buildSkillEntryReusability(entryRow, skill, resuability, resuabilityLength)
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

function modify_pilot_skills_ui.buildSkillEntryWeightInput(entryRow, skill, setWeight)
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
	weightInput.textfield = string.format("%.2f", setWeight)

	-- Store reference for later updates
	weightInputFields[skill.id] = weightInput

	-- Handle weight changes
	weightInput.onEnter = function(self)
		local isValid, value = modify_pilot_skills_ui.validateNumericInput(self.textfield)
		if isValid and value >= 0 then
			cplus_plus_ex:setSkillConfig(skill.id, {set_weight = value})
			if cplus_plus_ex.config.autoAdjustWeights then
				cplus_plus_ex:setAdjustedWeightsConfigs()
			end
			modify_pilot_skills_ui.updateAllPercentages()
			cplus_plus_ex:saveConfiguration()
		else
			-- Reset to current value if invalid
			local currentConfig = cplus_plus_ex.config.skillConfigs[skill.id]
			self.textfield = string.format("%.2f", setWeight)
		end
		return UiInputField.onEnter(self)
	end
end

function modify_pilot_skills_ui.buildSkillEntryLabels(entryRow, skill)
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

	-- Adjusted weight label (13% width, reduced from 15%)
	local adjustedWeightLabel = Ui()
		:width(0.25):heightpx(ROW_HEIGHT)
		:settooltip("TODO")
		:decorate({
			DecoFrame(),
			DecoAlign(0, 2),
			DecoText("0.00")
		})
		:addTo(entryRow)

	adjustedWeightLabels[skill.id] = adjustedWeightLabel

	-- Adjusted percentage label 
	local adjustedPercentLabel = Ui()
		:width(0.25):heightpx(ROW_HEIGHT)
		:settooltip("TODO")
		:decorate({
			DecoFrame(),
			DecoAlign(0, 2),
			DecoText("0.0%")
		})
		:addTo(entryRow)

	adjustedPercentLabels[skill.id] = adjustedPercentLabel
end

-- Builds a single skill entry row
function modify_pilot_skills_ui.buildSkillEntry(skill, isDependent, skillLength, resuabilityLength)
	local skillConfigObj = cplus_plus_ex.config.skillConfigs[skill.id]
	if not skillConfigObj then
		LOG("PLUS Ext: Warning: No config for skill " .. skill.id)
		return Ui():width(1):heightpx(0) -- Return empty element
	end

	local entryRow = UiWeightLayout()
		:width(1):heightpx(ROW_HEIGHT)

	-- Add values to the row
	modify_pilot_skills_ui.buildSkillEntryEnable(entryRow, skill, skillConfigObj.enabled, skillLength)
	modify_pilot_skills_ui.buildSkillEntryReusability(entryRow, skill, skillConfigObj.reusability, resuabilityLength)
	modify_pilot_skills_ui.buildSkillEntryWeightInput(entryRow, skill, skillConfigObj.set_weight)
	modify_pilot_skills_ui.buildSkillEntryLabels(entryRow, skill)

	return entryRow
end

-- Builds header row for skill columns
function modify_pilot_skills_ui.buildHeaderRow(skillLength, resuabilityLength)
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

	Ui()
		:width(0.25):heightpx(ROW_HEIGHT)
		:decorate({
			DecoFrame(deco.colors.buttonborder),
			DecoAlign(0, 2),
			DecoText("Adj.", nil, nil, nil, nil, nil, nil, deco.uifont.tooltipTitle.font)
		})
		:settooltip("Adjusted weight (after auto-adjustment)")
		:addTo(headerRow)

	Ui()
		:width(0.25):heightpx(ROW_HEIGHT)
		:decorate({
			DecoFrame(deco.colors.buttonborder),
			DecoAlign(0, 2),
			DecoText("Adj. %", nil, nil, nil, nil, nil, nil, deco.uifont.tooltipTitle.font)
		})
		:settooltip("Adjusted percentage chance")
		:addTo(headerRow)

	return headerRow
end

function modify_pilot_skills_ui.buildGeneralSettings(scrollContent)
	local settingsHeader = Ui()
		:width(1):heightpx(ROW_HEIGHT)
		:decorate({
			DecoFrame(deco.colors.buttonborder),
			DecoAlign(0, 2),
			DecoText("General Settings", nil, nil, nil, nil, nil, nil, deco.uifont.title.font)
		})
		:addTo(scrollContent)

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
		:addTo(scrollContent)

	allowDupsCheckbox.checked = cplus_plus_ex.config.allowReusableSkills

	allowDupsCheckbox.onToggled:subscribe(function(checked)
		cplus_plus_ex.config.allowReusableSkills = checked
		cplus_plus_ex:saveConfiguration()
	end)
		
	-- Auto-adjust dependent weights checkbox
	local autoAdjustCheckbox = UiCheckbox()
		:width(1):heightpx(ROW_HEIGHT)
		:settooltip("Automatically adjust weights for dependent skills based on their dependencies")
		:decorate({
			DecoButton(),
			DecoCheckbox(),
			DecoAlign(0, 2),
			DecoText("Auto-Adjust Dependent Skill Weights")
		})
		:addTo(scrollContent)

	autoAdjustCheckbox.checked = cplus_plus_ex.config.autoAdjustWeights

	autoAdjustCheckbox.onToggled:subscribe(function(checked)
		cplus_plus_ex.config.autoAdjustWeights = checked
		if checked then
			cplus_plus_ex:setAdjustedWeightsConfigs()
		end
		modify_pilot_skills_ui.updateAllPercentages()
		cplus_plus_ex:saveConfiguration()
	end)
end

function modify_pilot_skills_ui.buildSkillsList(scrollContent)
local skillsHeader = Ui()
		:width(1):heightpx(ROW_HEIGHT)
		:decorate({
			DecoFrame(deco.colors.buttonborder),
			DecoAlign(0, 2),
			DecoText("Skills Configuration", nil, nil, nil, nil, nil, nil, deco.uifont.title.font)
		})
		:addTo(scrollContent)

	local skillLength, reuseabilityLength = modify_pilot_skills_ui.determineColumnLengths()

	-- Add column headers
	modify_pilot_skills_ui.buildHeaderRow(skillLength, reuseabilityLength):addTo(scrollContent)

	-- Get all skills organized by type
	local nonDependentSkills, dependentSkills = modify_pilot_skills_ui.getAllSkillsByType()

	-- Non-Dependent Skills
	if #nonDependentSkills > 0 then
		local nonDepHeader = Ui()
			:width(1):heightpx(ROW_HEIGHT)
			:decorate({
				DecoFrame(),
				DecoAlign(0, 2),
				DecoText("Standard Skills", nil, nil, nil, nil, nil, nil, deco.uifont.tooltipTitle.font)
			})
			:addTo(scrollContent)

		for _, skill in ipairs(nonDependentSkills) do
			modify_pilot_skills_ui.buildSkillEntry(skill, false, skillLength, reuseabilityLength):addTo(scrollContent)
		end
	else
		-- I guess this is technically possible if they had more skills,
		-- configured dependents then uninstalled all the non-dependent skills
		LOG("Plus Ext: Error: No non-dependent skills! How even?")
	end

	-- Dependent Skills but only if there are any
	if #dependentSkills > 0 then
		local depHeader = Ui()
			:width(1):heightpx(ROW_HEIGHT)
			:decorate({
				DecoFrame(),
				DecoAlign(0, 2),
				DecoText("Dependent Skills (Second+ Pick)", nil, nil, nil, nil, nil, nil, deco.uifont.tooltipTitle.font)
			})
			:addTo(scrollContent)

		for _, skill in ipairs(dependentSkills) do
			modify_pilot_skills_ui.buildSkillEntry(skill, true, skillLength, reuseabilityLength):addTo(scrollContent)
		end
	end
	
	-- Initial percentage calculation
	modify_pilot_skills_ui.updateAllPercentages()
end

function modify_pilot_skills_ui.addPilotImage(pilotId, row)
	local pilotUi = Ui()
		:widthpx(PILOT_SIZE):heightpx(ROW_HEIGHT)
	
	-- Add potrait if we have one
	if pilotId and pilotId ~= "All" and pilotId ~= "" then
		local portrait = modify_pilot_skills_ui.getPilotPortrait(pilotId)
		if portrait then
			pilotUi:decorate({
					DecoSurface(portrait),
				})
		end
	end
	
	pilotUi:addTo(row)
	return pilotUi
end

function modify_pilot_skills_ui.addExistingRelLabel(text, row)
	Ui()
		:width(0.5):heightpx(ROW_HEIGHT)
		:decorate({
			DecoFrame(),
			DecoAlign(0, 2),
			DecoText(text)
		})
		:addTo(row)
end

function modify_pilot_skills_ui.addNewRelDropDown(label, listVals, listDisplay, selectFn, row)
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

function modify_pilot_skills_ui.addArrowLabel(bidirectional, row)
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

function modify_pilot_skills_ui.createDropDownItems(dataList)
	local listDisplay = {"", "All"}
	local listVals = {"", "All"}
	local sortedSourceKeys = utils.sortByValue(dataList)
	for _, k in ipairs(sortedSourceKeys) do
		table.insert(listDisplay, dataList[k])
		table.insert(listVals, k)
	end
	return listDisplay, listVals
end

-- Builds a relationship editor section
function modify_pilot_skills_ui.buildRelationshipEditor(parent, relationshipTable, title, sourceList, targetList, sourceLabel, targetLabel, isSameTypeRelation)
	-- create list values with empty and all
	local listDisplay, listVals = modify_pilot_skills_ui.createDropDownItems(sourceList)
	local targetListDisplay, targetListVals = modify_pilot_skills_ui.createDropDownItems(targetList)
	
	-- Section header
	Ui()
		:width(1):heightpx(ROW_HEIGHT)
		:decorate({
			DecoFrame(deco.colors.buttonborder),
			DecoAlign(0, 2),
			DecoText(title, nil, nil, nil, nil, nil, nil, deco.uifont.title.font)
		})
		:addTo(parent)
	
	-- Container for this section
	local largestHeight = sourceLabel == "Pilot" and PILOT_SIZE or ROW_HEIGHT
	local padding = largestHeight - ROW_HEIGHT  + 3
	
	local sectionContainer = UiBoxLayout()
		:vgap(padding)
		:width(1)
		:addTo(parent)
	
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
					modify_pilot_skills_ui.addPilotImage(sourceId, entryRow)
				end
				
				modify_pilot_skills_ui.addExistingRelLabel(sourceList[sourceId], entryRow)
				modify_pilot_skills_ui.addArrowLabel(title == "Skill Exclusions", entryRow)
				modify_pilot_skills_ui.addExistingRelLabel(targetList[targetId], entryRow)
				
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
	end
	
	-- add row
	local addRow = UiWeightLayout()
		:width(1):heightpx(ROW_HEIGHT)
		:addTo(sectionContainer)
	
	-- Pilot portrait if its a pilot
	if sourceLabel == "Pilot" then
		currentPilotPortrait = modify_pilot_skills_ui.addPilotImage(selectedSource, addRow)
	end
	
	-- Source dropdown
	modify_pilot_skills_ui.addNewRelDropDown(sourceLabel, listVals, listDisplay, 
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
					local portrait = modify_pilot_skills_ui.getPilotPortrait(newValue)
					if portrait then
						table.insert(currentPilotPortrait.decorations, DecoSurface(portrait))
					end
				end
			end
		end, addRow)
	
	-- Arrow
	modify_pilot_skills_ui.addArrowLabel(title == "Skill Exclusions", addRow)
	
	-- Target dropdown
	modify_pilot_skills_ui.addNewRelDropDown(targetLabel, targetListVals, targetListDisplay, 
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
				sourcesToAdd = {selectedSource = true}
			end
			
			if selectedTarget == "All" then
				targetsToAdd = targetList
			else
				targetsToAdd = {selectedTarget = true}
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

function modify_pilot_skills_ui.buildRelationships(scrollContent)
	-- Section header
	Ui()
		:width(1):heightpx(ROW_HEIGHT)
		:decorate({
			DecoFrame(deco.colors.buttonborder),
			DecoAlign(0, 2),
			DecoText("Skill Relationships", nil, nil, nil, nil, nil, nil, deco.uifont.title.font)
		})
		:addTo(scrollContent)
	
	-- Get lists for dropdowns
	local pilotData = modify_pilot_skills_ui.getPilotsData()
	local skillData, exlusionSkillData, inclusionSkillData = modify_pilot_skills_ui.getSkillsData()
	
	-- Pilot Skill Exclusions
	modify_pilot_skills_ui.buildRelationshipEditor(
		scrollContent,
		cplus_plus_ex.config.pilotSkillExclusions,
		"Pilot Skill Exclusions",
		pilotData,
		exlusionSkillData,
		"Pilot",
		"Skill",
		false
	)
	
	-- Pilot Skill Inclusions
	modify_pilot_skills_ui.buildRelationshipEditor(
		scrollContent,
		cplus_plus_ex.config.pilotSkillInclusions,
		"Pilot Skill Inclusions",
		pilotData,
		inclusionSkillData,
		"Pilot",
		"Skill",
		false
	)
	
	-- Skill Exclusions
	modify_pilot_skills_ui.buildRelationshipEditor(
		scrollContent,
		cplus_plus_ex.config.skillExclusions,
		"Skill Exclusions",
		skillData,
		skillData,
		"Skill",
		"Skill",
		true
	)
	
	-- Skill Dependencies
	modify_pilot_skills_ui.buildRelationshipEditor(
		scrollContent,
		cplus_plus_ex.config.skillDependencies,
		"Skill Dependencies",
		skillData,
		skillData,
		"Skill",
		"Dependent Skill",
		true
	)
end

-- Builds the main content for the dialog
function modify_pilot_skills_ui.buildMainContent(scroll)
	-- Clear tracking tables
	weightInputFields = {}
	percentageLabels = {}
	adjustedWeightLabels = {}
	adjustedPercentLabels = {}

	scrollContent = UiBoxLayout()
		:vgap(5)
		:width(1)
		:addTo(scroll)
		
	-- Add the settings
	modify_pilot_skills_ui.buildGeneralSettings(scrollContent)
	modify_pilot_skills_ui.buildSkillsList(scrollContent)
	modify_pilot_skills_ui.buildRelationships(scrollContent)
end

function modify_pilot_skills_ui.buildResetConfirmation()
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
					adjustedWeightLabels = {}
					adjustedPercentLabels = {}
					-- Rebuild the content with fresh values
					modify_pilot_skills_ui.buildMainContent(parentScroll)
				end
			end
		end,
		{ "Reset", "Cancel" },
		{ "Reset everything to defaults", "Cancel and keep current settings" }
	)
	return true
end

-- Builds the button layout for the dialog
function modify_pilot_skills_ui.buildDialogButtons(buttonLayout)
	-- for now at least only a reset button
	local btnReset = sdlext.buildButton(
		"Reset to Defaults",
		"Reset all settings to their default values",
		modify_pilot_skills_ui.buildResetConfirmation
	)
	btnReset:addTo(buttonLayout)
end

-- Called when dialog is closed
local function onExit()
	cplus_plus_ex:saveConfiguration()
	scrollContent = nil
	weightInputFields = {}
	percentageLabels = {}
	adjustedWeightLabels = {}
	adjustedPercentLabels = {}
end

-- Creates the main modification dialog
function modify_pilot_skills_ui.createDialog()
	-- Load configuration before opening dialog
	cplus_plus_ex:loadConfiguration()

	sdlext.showDialog(function(ui, quit)
		ui.onDialogExit = onExit

		local frame = sdlext.buildButtonDialog(
			"Modify Pilot Skills",
			modify_pilot_skills_ui.buildMainContent,
			modify_pilot_skills_ui.buildDialogButtons,
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
