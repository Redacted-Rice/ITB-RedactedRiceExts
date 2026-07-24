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
--       priority = 100,  -- Optional, default 100. Lower runs first.
--       modifiesKillDamage = true,  -- Opt in to modifyKillDamage / DamageModifierLib
--   })
--
--   function MySkillModifier:modifySpaceDamage(source, attackingPawn, phase, spaceDamage, indexes, targetPawn)
--       local newDamage = self:modifyKillDamage(source, attackingPawn, spaceDamage, indexes, targetPawn, spaceDamage.iDamage)
--       if newDamage == spaceDamage.iDamage then return end
--       -- Mutate spaceDamage for real weapon effect builds (icons, sScript, etc.)
--   end
--
--   function MySkillModifier:modifyKillDamage(source, attackingPawn, spaceDamage, indexes, targetPawn, currentDamage)
--       -- Return adjusted damage for DamageModifierLib / Board:IsDeadly preview. No side effects.
--       -- DamageModifierLib passes a SpaceDamage copy; iDamage is written back from the return value.
--   end
--
-- Set modifiesKillDamage = true in :new{} to opt in. DamageModifierLib.events.onEvaluating
-- subscription is handled automatically in setupEffect/clearEvents (same lifecycle
-- as other skill events).

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

local damageModifierLib = cplus_plus_ex._subobjects.damageModifierLib

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

local function buildSkillsForAffectedPawns(affectedPawns)
	local skillsByPriority = {}
	local priorities = {}

	for _, skill in ipairs(registeredSkills) do
		local skillApplies = false
		for _, pawn in pairs(affectedPawns) do
			local pilot = pawn:GetPilot()
			if pilot and cplus_plus_ex:isSkillOnPilot(skill.id, pilot) then
				skillApplies = true
				break
			end
		end

		if skillApplies then
			if not skillsByPriority[skill.priority] then
				skillsByPriority[skill.priority] = {}
				table.insert(priorities, skill.priority)
			end
			table.insert(skillsByPriority[skill.priority], skill)
		end
	end

	table.sort(priorities)
	return skillsByPriority, priorities
end

local function applySkillsToSpaceDamage(attackingPawn, spaceDamage, phase, skillsByPriority, priorities)
	for _, priority in ipairs(priorities) do
		for _, skill in ipairs(skillsByPriority[priority]) do
			-- Check attacker
			local attackingPilot = attackingPawn:GetPilot()
			if attackingPilot and cplus_plus_ex:isSkillOnPilot(skill.id, attackingPilot) then
				local attackerIndexes = cplus_plus_ex:getPilotSkillIndices(skill.id, attackingPilot)
				local currentTargetPawn = SkillEffectModifier:getPawnAt(spaceDamage.loc)

				skill:modifySpaceDamage(SkillEffectModifier.SOURCE_ATTACKER,
						attackingPawn, phase, spaceDamage, attackerIndexes,
						currentTargetPawn)
			end

			-- Check target
			local currentTargetPawn = SkillEffectModifier:getPawnAt(spaceDamage.loc)
			if currentTargetPawn then
				local targetPilot = currentTargetPawn:GetPilot()
				if targetPilot and cplus_plus_ex:isSkillOnPilot(skill.id, targetPilot) then
					local targetIndexes = cplus_plus_ex:getPilotSkillIndices(skill.id, targetPilot)

					skill:modifySpaceDamage(SkillEffectModifier.SOURCE_TARGET,
							attackingPawn, phase, spaceDamage, targetIndexes,
							currentTargetPawn)
				end
			end
		end
	end
end

-- Called by DamageModifierLib for a single registered skill modifier.
-- Mutates spaceDamage.iDamage in place (receives DamageModifierLib's SpaceDamage copy).
local function applySkillKillDamage(skill, spaceDamage, targetPawn, attackingPawn)
	if not skill.modifiesKillDamage or not attackingPawn or not spaceDamage or not spaceDamage.loc then
		return
	end

	local damage = spaceDamage.iDamage
	local attackingPilot = attackingPawn:GetPilot()
	if attackingPilot and cplus_plus_ex:isSkillOnPilot(skill.id, attackingPilot) then
		local attackerIndexes = cplus_plus_ex:getPilotSkillIndices(skill.id, attackingPilot)
		damage = skill:modifyKillDamage(SkillEffectModifier.SOURCE_ATTACKER,
				attackingPawn, spaceDamage, attackerIndexes,
				targetPawn, damage)
	end

	if targetPawn then
		local targetPilot = targetPawn:GetPilot()
		if targetPilot and cplus_plus_ex:isSkillOnPilot(skill.id, targetPilot) then
			local targetIndexes = cplus_plus_ex:getPilotSkillIndices(skill.id, targetPilot)
			damage = skill:modifyKillDamage(SkillEffectModifier.SOURCE_TARGET,
					attackingPawn, spaceDamage, targetIndexes,
					targetPawn, damage)
		end
	end

	spaceDamage.iDamage = damage
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
			SkillEffectModifier.processAllSkills(pawn, false, skillEffect)
		end))
	table.insert(globalEventSubscriptions, modapiext.events.onFinalEffectBuild:subscribe(
		function(mission, pawn, weaponId, p1, p2, p3, skillEffect)
			SkillEffectModifier.processAllSkills(pawn, true, skillEffect)
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

local function registerOnKillModifier(skill)
	if skill._damageModifierSubscription then
		logger.logWarn(SUBMODULE, "DamageModifierLib subscriber for skill %s already registered", skill.id)
		return
	end

	skill._damageModifierSubscription = damageModifierLib.events.onEvaluating:subscribe(function(spaceDamage, attackingPawn, targetPawn)
		applySkillKillDamage(skill, spaceDamage, targetPawn, attackingPawn)
	end, skill.priority)
	logger.logDebug(SUBMODULE, "Subscribed skill %s to DamageModifierLib.onEvaluating at priority %d",
			skill.id, skill.priority)
end

local function unregisterOnKillModifier(skill)
	if skill._damageModifierSubscription then
		skill._damageModifierSubscription:unsubscribe()
		skill._damageModifierSubscription = nil
		logger.logDebug(SUBMODULE, "Unsubscribed skill %s from DamageModifierLib.onEvaluating", skill.id)
	end
end

function SkillEffectModifier:setupEffect()
	logger.logDebug(SUBMODULE, "Setting up effect modifier for %s", self.id)

	if #registeredSkills == 0 then
		registerGlobalCallbacks()
	end

	table.insert(registeredSkills, self)
	logger.logDebug(SUBMODULE, "Registered skill %s (total: %d)", self.id, #registeredSkills)

	if self.modifiesKillDamage then
		registerOnKillModifier(self)
	end
end

function SkillEffectModifier:clearEvents()
	logger.logDebug(SUBMODULE, "Removing skill %s", self.id)

	-- Just always try to unregister
	unregisterOnKillModifier(self)

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

-- Override this in derived classes to modify weapon damage during effect builds.
-- source: SOURCE_ATTACKER or SOURCE_TARGET
-- phase: One of PHASE_* constants for icon placement
-- indexes: Array of skill slot numbers (e.g., {1}, {2}, or {1,2})
-- NOTE: This should modify spaceDamage in place and not return anything
function SkillEffectModifier:modifySpaceDamage(source, attackingPawn, phase, spaceDamage, indexes, targetPawn)
	logger.logError(SUBMODULE, string.format("SkillEffectModifier modifySpaceDamage not implemented for skill %s", self.id))
end

-- Override in derived classes to adjust damage for DamageModifierLib / Board:IsDeadly preview.
-- Returns the adjusted damage total. No side effects (icons, sScript, etc.).
function SkillEffectModifier:modifyKillDamage(source, attackingPawn, spaceDamage, indexes, targetPawn, currentDamage)
	return currentDamage
end

-- Override this in derived classes to return aggregated effects after all spaceDamages processed
-- phase: One of PHASE_* constants for icon placement
-- Returns: nil, SpaceDamage, or array of SpaceDamage to add
-- This is called AFTER all spaceDamages have been processed by all skills
-- Use this to return aggregated/accumulated effects
-- NOTE: If effects are added, they will be processed and this will be called
-- AGAIN! Make sure it won't infinitely loop
function SkillEffectModifier:SkillEffectEvaluated(phase)
	return nil
end

SkillEffectModifier.spacesWithPawns = {}
SkillEffectModifier.pawnPositions = {}
SkillEffectModifier.pendingMoves = {}

function SkillEffectModifier:getPawnSpace(pawn)
	if SkillEffectModifier.pawnPositions[pawn:GetId()] ~= nil then
		return SkillEffectModifier.pawnPositions[pawn:GetId()]
	end
	return pawn:GetSpace()
end

function SkillEffectModifier:getPawnAt(loc)
	local hash = getSpaceHash(loc)
	if SkillEffectModifier.spacesWithPawns[hash] ~= nil then
		return SkillEffectModifier.spacesWithPawns[hash]
	end
	return Board:GetPawn(loc)
end

local function accountForMove(moveStart, moveEnd)
	-- Track movement
	local movingPawn = SkillEffectModifier:getPawnAt(moveStart)

	if movingPawn then
		table.insert(SkillEffectModifier.pendingMoves, {
			pawn = movingPawn,
			pawnId = movingPawn:GetId(),
			from = moveStart,
			to = moveEnd
		})
		logger.logDebug(SUBMODULE, "Tracked move for pawn %d from %s to %s",
				movingPawn:GetId(), moveStart:GetString(), moveEnd:GetString())
	end
end

local function applyAndClearPendingMoves()
	for _, moveData in ipairs(SkillEffectModifier.pendingMoves) do
		local fromHash = getSpaceHash(moveData.from)
		local toHash = getSpaceHash(moveData.to)
		SkillEffectModifier.spacesWithPawns[fromHash] = false
		SkillEffectModifier.spacesWithPawns[toHash] = moveData.pawn
		SkillEffectModifier.pawnPositions[moveData.pawn:GetId()] = moveData.to
	end
	SkillEffectModifier.pendingMoves = {}
end

-- Process damage list effect by effect, running all skills per effect in priority order
-- This ensures positions are always current and skills see each other's modifications
local function processEffectByEffect(attackingPawn, effectsTable, skillsByPriority, priorities, phase)
	if #effectsTable == 0 then
		return
	end

	-- Reset position tracking
	SkillEffectModifier.spacesWithPawns = {}
	SkillEffectModifier.pawnPositions = {}
	SkillEffectModifier.pendingMoves = {}

	local i = 1
	-- Arbitrary max space damage processing
	local maxIterations = 250
	local iterations = 0
	local initialTableSize = #effectsTable

	while i <= #effectsTable and iterations < maxIterations do
		iterations = iterations + 1
		local spaceDamage = effectsTable[i]

		if spaceDamage:IsMovement() then
			-- Track the movement if needed
			accountForMove(spaceDamage:MoveStart(), spaceDamage:MoveEnd())

			-- Apply moves at delay or end of list
			if spaceDamage.fDelay ~= 0 or i == #effectsTable then
				applyAndClearPendingMoves()
			end

		else
			-- Apply any pending moves before processing this damage
			applyAndClearPendingMoves()
			applySkillsToSpaceDamage(attackingPawn, spaceDamage, phase, skillsByPriority, priorities)

			-- See if its a push we need to account for
			if spaceDamage.iPush ~= DIR_NONE and spaceDamage.iPush >= 0 and spaceDamage.iPush <= 3 and
					SkillEffectModifier:getPawnAt(spaceDamage.loc + DIR_VECTORS[spaceDamage.iPush]) == nil then
				-- Track the movement if needed
				accountForMove(spaceDamage.loc, spaceDamage.loc + DIR_VECTORS[spaceDamage.iPush])

				-- Apply moves at delay or end of list
				if spaceDamage.fDelay ~= 0 or i == #effectsTable then
					applyAndClearPendingMoves()
				end
			end
		end

		i = i + 1
	end

	if iterations >= maxIterations then
		logger.logError(SUBMODULE, "Hit max iterations in processEffectByEffect! Possible infinite loop.")
		logger.logError(SUBMODULE, "  Final state: i=%d, #effectsTable=%d, initialSize=%d, iterations=%d",
			i, #effectsTable, initialTableSize, iterations)
	else
		logger.logDebug(SUBMODULE, "processEffectByEffect completed: %d iterations, processed %d effects",
			iterations, initialTableSize)
	end

	-- Now that all effects have been processed, call SkillEffectEvaluated on all skills
	-- This allows skills like vampire to return aggregated effects
	local newEffects = {}
	for _, priority in ipairs(priorities) do
		for _, skill in ipairs(skillsByPriority[priority]) do
			local evaluatedEffects = skill:SkillEffectEvaluated(phase)

			if evaluatedEffects then
				local effectsArray = type(evaluatedEffects) == "table"
					and evaluatedEffects or {evaluatedEffects}

				for _, newEffect in ipairs(effectsArray) do
					table.insert(newEffects, newEffect)
					logger.logDebug(SUBMODULE, "Skill %s returned effect from SkillEffectEvaluated", skill.id)
				end
			end
		end
	end

	return newEffects
end

-- Process effects with specific queued flag
local function processEffectsWithQueuedFlag(attackingPawn, skillEffect, effectsTable, isFinalEffect, isQueued)
	-- Determine the attack phase
	local phase = isFinalEffect and SkillEffectModifier.PHASE_FINAL_EFFECT or SkillEffectModifier.PHASE_SKILL_EFFECT
	if isQueued then
		phase = isFinalEffect and SkillEffectModifier.PHASE_QUEUED_FINAL_EFFECT or SkillEffectModifier.PHASE_QUEUED_SKILL
	end

	if #effectsTable == 0 then
		logger.logDebug(SUBMODULE, "No effects to process for phase=%s", tostring(phase))
		return
	end

	-- Only grab skills from the attacking pawn and any pawns targeted by any skill effect
	-- to limit to what is possibly in effect. What pawns CAN be affected does not depend on if they move
	-- so we can build this before hand

	-- Find all potentially affected pawns - attacking pawn + any pawn at a space damage
	local affectedPawns = {}
	affectedPawns[attackingPawn:GetId()] = attackingPawn
	for _, spaceDamage in ipairs(effectsTable) do
		if not spaceDamage:IsMovement() then
			local targetPawn = Board:GetPawn(spaceDamage.loc)
			if targetPawn then
				affectedPawns[targetPawn:GetId()] = targetPawn
			end
		end
	end

	local skillsByPriority, priorities = buildSkillsForAffectedPawns(affectedPawns)

	if #priorities == 0 then
		logger.logDebug(SUBMODULE, "No skills apply to affected pawns (phase=%s)", tostring(phase))
		return
	end

	logger.logDebug(SUBMODULE, "Processing %d applicable skills across %d priority levels (phase=%s)",
			#registeredSkills, #priorities, tostring(phase))


	-- Process effects one by one with all skills applied per effect
	local damagesToProcess = effectsTable
	-- Arbitrary max number of new space damages that can be added to prevent infinite loops
	local maxPasses = 25
	local currentPass = 0

	while damagesToProcess and #damagesToProcess > 0 and currentPass < maxPasses do
		logger.logDebug(SUBMODULE, "Pass %d: Processing %d effects (phase=%s)",
				currentPass, #damagesToProcess, tostring(phase))

		-- Process effects and get any new effects from SkillEffectEvaluated
		local newEffects = processEffectByEffect(attackingPawn, damagesToProcess,
				skillsByPriority, priorities, phase)

		if newEffects and #newEffects > 0 then
			logger.logDebug(SUBMODULE, "Pass %d: %d new effects from SkillEffectEvaluated",
					currentPass, #newEffects)

			-- Add the new effects to the skill effect
			for _, newEffect in ipairs(newEffects) do
				if isQueued then
					skillEffect:AddQueuedDamage(newEffect)
				else
					skillEffect:AddDamage(newEffect)
				end
			end

			-- Process the new effects in next pass
			damagesToProcess = newEffects
			currentPass = currentPass + 1
		else
			-- No new effects, we're done
			logger.logDebug(SUBMODULE, "Pass %d complete: no new effects", currentPass)
			break
		end
	end

	-- Warn if we hit the max passes limit
	if currentPass >= maxPasses and damagesToProcess and #damagesToProcess > 0 then
		logger.logWarn(SUBMODULE, "Chaining effect limit reached (%d passes, phase=%s) with %d damages remaining",
				maxPasses, tostring(phase), #damagesToProcess)
		logger.logWarn(SUBMODULE, "  Attacker: pawn %d", attackingPawn:GetId())

		-- Log which skills were active
		local activeSkills = {}
		for _, priority in ipairs(priorities) do
			for _, skill in ipairs(skillsByPriority[priority]) do
				table.insert(activeSkills, skill.id)
			end
		end
		logger.logWarn(SUBMODULE, "  Active skills: %s", table.concat(activeSkills, ", "))
	end
end

-- Main processing function called by modapiext events
function SkillEffectModifier.processAllSkills(attackingPawn, isFinalEffect, skillEffect)
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
