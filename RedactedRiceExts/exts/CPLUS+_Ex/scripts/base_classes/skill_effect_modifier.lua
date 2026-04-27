-- Base class for pilot skills that modify weapon effects
-- Allows skills to add damage, change damage types, add effects, etc.
--
-- Requirements: modapiext (for onSkillBuild and onFinalEffectBuild events)
--
-- Usage:
--   local MySkillModifier = cplus_plus_ex.baseClasses.SkillEffectModifier:new({
--       id = "MySkill",
--       name = "My Skill",
--       description = "Modifies weapon effects",
--       priority = 100  -- Optional, default 100. Lower runs first.
--   })
--
--   function MySkillModifier:modifySpaceDamage(source, attackingPawn, phase, spaceDamage, indexes, targetPawn)
--       -- Modify spaceDamage here
--       -- Optionally return SpaceDamage or array of SpaceDamage to add new damages
--   end
--
--   MySkillModifier:baseInit()

local SkillEffectModifier = {}

-- Extend SkillActive class
setmetatable(SkillEffectModifier, { __index = cplus_plus_ex.baseClasses.SkillActive })
SkillEffectModifier.__index = SkillEffectModifier

-- Default priority. Lower values run first
SkillEffectModifier.priority = 100

-- Initialize logger
SkillEffectModifier.DEBUG = false
local logger = memhack.logger
local SUBMODULE = logger.register("CPLUS+ Ex", "SkillEffectModifier", SkillEffectModifier.DEBUG)

-- Source constants (which pawn has the skill)
SkillEffectModifier.SOURCE_ATTACKER = "attacker"
SkillEffectModifier.SOURCE_TARGET = "target"

-- Phase constants for effect processing and icon placement
-- Aligns with the WeaponPreview Lib enums
SkillEffectModifier.PHASE_NONE = 0
SkillEffectModifier.PHASE_SKILL_EFFECT = 1
SkillEffectModifier.PHASE_TARGET_AREA = 2
SkillEffectModifier.PHASE_QUEUED_SKILL = 3
SkillEffectModifier.PHASE_SECOND_TARGET_AREA = 4
SkillEffectModifier.PHASE_FINAL_EFFECT = 5
SkillEffectModifier.PHASE_QUEUED_FINAL_EFFECT = 6

-- Global list of all registered SkillEffectModifier instances
local registeredSkills = {}
-- Global event subscriptions
local globalEventSubscriptions = {}

-- Convert Point to hash for tracking pawn positions
-- spaceOrX: Point or x coordinate, y: optional y coordinate
local function getSpaceHash(spaceOrX, y)
	local pX = spaceOrX
	local pY = y
	if not y then
		pX = spaceOrX.x
		pY = spaceOrX.y
	end
	return pY * 10 + pX
end

function SkillEffectModifier:new(tbl)
	tbl = tbl or {}
	local obj = cplus_plus_ex.baseClasses.SkillActive:new(tbl)
	setmetatable(obj, self)
	return obj
end

local function registerGlobalCallbacks()
	logger.logDebug(SUBMODULE, "Registering global SkillEffectModifier callbacks")

	table.insert(globalEventSubscriptions, modapiext.events.onSkillBuild:subscribe(
		function(mission, pawn, weaponId, p1, p2, skillEffect)
			SkillEffectModifier.processAllSkills(pawn, false, skillEffect, p2)
		end))
	table.insert(globalEventSubscriptions, modapiext.events.onFinalEffectBuild:subscribe(
		function(mission, pawn, weaponId, p1, p2, p3, skillEffect)
			SkillEffectModifier.processAllSkills(pawn, true, skillEffect, p2)
		end))

	logger.logDebug(SUBMODULE, "Registered %d global callbacks", #globalEventSubscriptions)
end

local function unregisterGlobalCallbacks()
	logger.logDebug(SUBMODULE, "Unregistering global SkillEffectModifier callbacks")

	for _, subscription in ipairs(globalEventSubscriptions) do
		subscription:unsubscribe()
	end
	globalEventSubscriptions = {}

	logger.logDebug(SUBMODULE, "Unregistered all global callbacks")
end

function SkillEffectModifier:setupEffect()
	logger.logDebug(SUBMODULE, "Setting up effect modifier for %s", self.id)

	if #registeredSkills == 0 then
		registerGlobalCallbacks()
	end

	table.insert(registeredSkills, self)
	logger.logDebug(SUBMODULE, "Registered skill %s (total: %d)", self.id, #registeredSkills)
end

function SkillEffectModifier:clearEvents()
	logger.logDebug(SUBMODULE, "Removing skill %s", self.id)

	cplus_plus_ex.baseClasses.SkillActive.clearEvents(self)

	for i, skill in ipairs(registeredSkills) do
		if skill.id == self.id then
			table.remove(registeredSkills, i)
			logger.logDebug(SUBMODULE, "Removed skill %s from global list (remaining: %d)", self.id, #registeredSkills)
			break
		end
	end

	if #registeredSkills == 0 then
		unregisterGlobalCallbacks()
	end
end

-- Override this in derived classes to modify weapon damage
-- source: SOURCE_ATTACKER or SOURCE_TARGET
-- phase: One of PHASE_* constants for icon placement
-- indexes: Array of skill slot numbers (e.g., {1}, {2}, or {1,2})
-- Returns: nil, SpaceDamage, or array of SpaceDamage to add
function SkillEffectModifier:modifySpaceDamage(source, attackingPawn, phase, spaceDamage, indexes, targetPawn)
	logger.logError(SUBMODULE, string.format("SkillEffectModifier modifySpaceDamage not implemented for skill %s", self.id))
end

function SkillEffectModifier:getPawnAt(loc, pawnPositions)
	local hash = getSpaceHash(loc)
	if pawnPositions[hash] ~= nil then
		return pawnPositions[hash]
	end
	return Board:GetPawn(loc)
end

-- Process damage list and return new damages to add
function SkillEffectModifier:processDamageList(source, attackingPawn, isFinalEffect, damageList, indexes, pawnPositions, pendingMoves, isQueued)
	local spaceDamagesToAdd = {}

	-- Calculate phase once for all damages in this list
	local phase = isFinalEffect and self.PHASE_FINAL_EFFECT or self.PHASE_SKILL_EFFECT
	if isQueued then
		phase = isFinalEffect and self.PHASE_QUEUED_FINAL_EFFECT or self.PHASE_QUEUED_SKILL
	end

	for i, spaceDamage in ipairs(damageList) do
		if spaceDamage:IsMovement() then
			local moveStart = spaceDamage:MoveStart()
			local moveEnd = spaceDamage:MoveEnd()
			local movingPawn = self:getPawnAt(moveStart, pawnPositions)

			if movingPawn then
				table.insert(pendingMoves, {
					pawn = movingPawn,
					pawnId = movingPawn:GetId(),
					from = moveStart,
					to = moveEnd
				})
				logger.logDebug(SUBMODULE, "Tracked move for pawn %d from %s to %s",
					movingPawn:GetId(), moveStart:GetString(), moveEnd:GetString())
			end

			if spaceDamage.fDelay ~= 0 or i == #damageList then
				for _, moveData in ipairs(pendingMoves) do
					local fromHash = getSpaceHash(moveData.from)
					local toHash = getSpaceHash(moveData.to)
					pawnPositions[fromHash] = false
					pawnPositions[toHash] = moveData.pawn
				end
				pendingMoves = {}
			end
		else
			if #pendingMoves > 0 then
				for _, moveData in ipairs(pendingMoves) do
					local fromHash = getSpaceHash(moveData.from)
					local toHash = getSpaceHash(moveData.to)
					pawnPositions[fromHash] = false
					pawnPositions[toHash] = moveData.pawn
				end
				pendingMoves = {}
			end

			local targetPawn = self:getPawnAt(spaceDamage.loc, pawnPositions)
			if source ~= self.SOURCE_TARGET or (targetPawn and cplus_plus_ex:isSkillOnPawn(self.id, targetPawn)) then
				local additionalDamages = self:modifySpaceDamage(source, attackingPawn, phase, spaceDamage, indexes, targetPawn)

				-- If modifySpaceDamage returns an array of space damages, collect them
				if additionalDamages then
					if type(additionalDamages) == "table" then
						for _, newDamage in ipairs(additionalDamages) do
							table.insert(spaceDamagesToAdd, newDamage)
						end
					else
						table.insert(spaceDamagesToAdd, additionalDamages)
					end
				end
			end
		end
	end

	return spaceDamagesToAdd
end

-- Process effects with specific queued flag
local function processEffectsWithQueuedFlag(attackingPawn, skillEffect, effectsTable, isFinalEffect, isQueued)
	if #effectsTable == 0 then
		logger.logDebug(SUBMODULE, "No effects to process for isQueued=%s", tostring(isQueued))
		return
	end

	-- Find all targeted pawns
	local allTargetedPawns = {}
	for _, spaceDamage in ipairs(effectsTable) do
		if not spaceDamage:IsMovement() then
			local targetPawn = Board:GetPawn(spaceDamage.loc)
			if targetPawn then
				allTargetedPawns[targetPawn:GetId()] = targetPawn
			end
		end
	end

	-- Build list of all skill+pawn combinations that apply
	local skillPawnCombos = {}
	for _, skill in ipairs(registeredSkills) do
		-- Check attacking pawn
		local attackingPilot = attackingPawn:GetPilot()
		if attackingPilot and cplus_plus_ex:isSkillOnPilot(skill.id, attackingPilot) then
			local indexes = cplus_plus_ex:getPilotSkillIndices(skill.id, attackingPilot)
			if not skillPawnCombos[skill.priority] then skillPawnCombos[skill.priority] = {} end
			table.insert(skillPawnCombos[skill.priority], {
				skill = skill,
				pawn = attackingPawn,
				indexes = indexes,
				source = SkillEffectModifier.SOURCE_ATTACKER
			})
			logger.logDebug(SUBMODULE, "Skill %s applies to attacking pawn %d (isQueued=%s)",
					skill.id, attackingPawn:GetId(), tostring(isQueued))
		end

		-- Check all targeted pawns
		for pawnId, targetPawn in pairs(allTargetedPawns) do
			local targetPilot = targetPawn:GetPilot()
			if targetPilot and cplus_plus_ex:isSkillOnPilot(skill.id, targetPilot) then
				local indexes = cplus_plus_ex:getPilotSkillIndices(skill.id, targetPilot)
				if not skillPawnCombos[skill.priority] then skillPawnCombos[skill.priority] = {} end
				table.insert(skillPawnCombos[skill.priority], {
					skill = skill,
					pawn = targetPawn,
					indexes = indexes,
					source = SkillEffectModifier.SOURCE_TARGET
				})
				logger.logDebug(SUBMODULE, "Skill %s applies to targeted pawn %d (isQueued=%s)",
						skill.id, targetPawn:GetId(), tostring(isQueued))
			end
		end
	end

	local priorities = {}
	local skillPawnCombosCount = 0
	for priority, priorityList in pairs(skillPawnCombos) do
		skillPawnCombosCount = skillPawnCombosCount + #priorityList
		table.insert(priorities, priority)
	end
	if skillPawnCombosCount == 0 then
		logger.logDebug(SUBMODULE, "No skills apply to this effect (isQueued=%s)", tostring(isQueued))
		return
	end
	table.sort(priorities)
	logger.logDebug(SUBMODULE, "Processing %d skill+pawn combinations (isQueued=%s)",
			skillPawnCombosCount, tostring(isQueued))

	-- Loop through all skills, checking for new damages and repeating until no new damages
	local pawnPositions = {}
	local damagesToProcess = effectsTable
	local maxPasses = 10
	local currentPass = 0

	while damagesToProcess and #damagesToProcess > 0 and currentPass < maxPasses do
		local allNewDamages = {}
		local pendingMoves = {}

		-- Process ALL skill+pawn combinations for this pass
		for _, priority in ipairs(priorities) do
			for _, combo in ipairs(skillPawnCombos[priority]) do
				logger.logDebug(SUBMODULE, "Pass %d: Processing skill %s with %d space damages for pawn %d (%s, isQueued=%s)",
						currentPass, combo.skill.id, #damagesToProcess, combo.pawn:GetId(), combo.source, tostring(isQueued))

				local newDamages = combo.skill:processDamageList(combo.source, attackingPawn, isFinalEffect, damagesToProcess,
						combo.indexes, pawnPositions, pendingMoves, isQueued)

				if newDamages and #newDamages > 0 then
					for _, newDamage in ipairs(newDamages) do
						table.insert(allNewDamages, newDamage)
					end
				end
			end
		end

		-- Add all new damages from this pass to the skill effect
		if #allNewDamages > 0 then
			for _, newDamage in ipairs(allNewDamages) do
				if isQueued then
					skillEffect:AddQueuedDamage(newDamage)
				else
					skillEffect:AddDamage(newDamage)
				end
				logger.logDebug(SUBMODULE, "Added space damage at %s (pass %d, isQueued=%s)",
						newDamage.loc:GetString(), currentPass, tostring(isQueued))
			end

			-- Prepare for next pass with the new damages
			damagesToProcess = allNewDamages
			currentPass = currentPass + 1
		else
			-- No new damages, exit loop
			break
		end
	end

	-- Warn if we hit the max passes limit
	if currentPass >= maxPasses and damagesToProcess and #damagesToProcess > 0 then
		logger.logWarn(SUBMODULE, "Chaining effect limit reached (%d passes, isQueued=%s) with %d damages remaining",
				maxPasses, tostring(isQueued), #damagesToProcess)
	end
end

-- Main processing function called by modapiext events
function SkillEffectModifier.processAllSkills(attackingPawn, isFinalEffect, skillEffect, p2)
	if modApiExt_internal.nestedCall_GetSkillEffect or modApiExt_internal.nestedCall_GetFinalEffect then
		logger.logDebug(SUBMODULE, "Skipping nested call for SkillEffectModifier (GetSkillEffect: %s, GetFinalEffect: %s)",
				tostring(modApiExt_internal.nestedCall_GetSkillEffect), tostring(modApiExt_internal.nestedCall_GetFinalEffect))
		return
	end

	if not attackingPawn then
		logger.logDebug(SUBMODULE, "No attacking pawn found")
		return
	end

	local regularEffects = extract_table(skillEffect.effect)
	if #regularEffects > 0 then
		logger.logDebug(SUBMODULE, "Processing %d regular effects", #regularEffects)
		processEffectsWithQueuedFlag(attackingPawn, skillEffect, regularEffects, isFinalEffect, false)
	end

	if not skillEffect.q_effect:empty() then
		local queuedEffects = extract_table(skillEffect.q_effect)
		if #queuedEffects > 0 then
			logger.logDebug(SUBMODULE, "Processing %d queued effects", #queuedEffects)
			processEffectsWithQueuedFlag(attackingPawn, skillEffect, queuedEffects, isFinalEffect, true)
		end
	end
end

return SkillEffectModifier
