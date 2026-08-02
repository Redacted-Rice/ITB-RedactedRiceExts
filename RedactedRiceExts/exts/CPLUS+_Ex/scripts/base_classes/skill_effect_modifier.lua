-- Base class for pilot skills that modify weapon effects
-- Allows skills to add damage, change damage types, add effects, etc.
--
-- Requirements: DamageModifierLib (via cplus_plus_ex), modapiext for skill builds
--
-- Usage:
--   local MySkillModifier = cplus_plus_ex.baseClasses.SkillEffectModifier:new({
--       id = "MySkill",
--       name = "My Skill",
--       description = "Modifies weapon effects",
--       priority = 100,  -- Optional, default 100. Lower runs first.
--       modifiesKillDamage = true,  -- Optional, default true. Set false to skip
--                                   -- Board:IsDeadly (onEvaluatingDeadly) registration.
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
--   end
--
--   function MySkillModifier:SkillEffectEvaluated(phase)
--       -- Optional. Called after all SpaceDamages in a pass are processed.
--       -- Return nil, SpaceDamage, or array of SpaceDamage to append.
--   end
--
-- Effect walking, push/move tracking, and IsDeadly live in DamageModifierLib.
-- This class only bridges CPLUS+ pilot-skill state into that API.

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

local damageModifierLib = cplus_plus_ex._subobjects.damageModifierLib

function SkillEffectModifier:new(tbl)
	tbl = tbl or {}
	local obj = cplus_plus_ex.baseClasses.SkillActive:new(tbl)
	setmetatable(obj, self)
	return obj
end

-- Apply this skill as attacker and/or target source for one SpaceDamage.
-- For IsDeadly (isKillDamage), mutates spaceDamage.iDamage via modifyKillDamage.
-- For skill builds, calls modifySpaceDamage (side effects allowed).
local function applySkillToSpaceDamage(skill, spaceDamage, attackingPawn, targetPawn, isKillDamage, phase)
	if not attackingPawn or not spaceDamage or not spaceDamage.loc then
		return
	end

	local attackingPilot = attackingPawn:GetPilot()
	if attackingPilot and cplus_plus_ex:isSkillOnPilot(skill.id, attackingPilot) then
		local indexes = cplus_plus_ex:getPilotSkillIndices(skill.id, attackingPilot)
		if isKillDamage then
			spaceDamage.iDamage = skill:modifyKillDamage(SkillEffectModifier.SOURCE_ATTACKER,
					attackingPawn, spaceDamage, indexes, targetPawn, spaceDamage.iDamage)
		else
			skill:modifySpaceDamage(SkillEffectModifier.SOURCE_ATTACKER,
					attackingPawn, phase, spaceDamage, indexes, targetPawn)
		end
	end

	if targetPawn then
		local targetPilot = targetPawn:GetPilot()
		if targetPilot and cplus_plus_ex:isSkillOnPilot(skill.id, targetPilot) then
			local indexes = cplus_plus_ex:getPilotSkillIndices(skill.id, targetPilot)
			if isKillDamage then
				spaceDamage.iDamage = skill:modifyKillDamage(SkillEffectModifier.SOURCE_TARGET,
						attackingPawn, spaceDamage, indexes, targetPawn, spaceDamage.iDamage)
			else
				skill:modifySpaceDamage(SkillEffectModifier.SOURCE_TARGET,
						attackingPawn, phase, spaceDamage, indexes, targetPawn)
			end
		end
	end
end

function SkillEffectModifier:setupEffect()
	logger.logDebug(SUBMODULE, "Setting up effect modifier for %s", self.id)

	self._skillModifySubscription = damageModifierLib.events.onSkillEffectModify:subscribe(
			function(spaceDamage, attackingPawn, targetPawn, phase)
				applySkillToSpaceDamage(self, spaceDamage, attackingPawn, targetPawn, false, phase)
			end, self.priority)

	-- If modifies kill damage, then also need to subscribe to onEvaluatingDeadly
	if self.modifiesKillDamage ~= false then
		self._deadlySubscription = damageModifierLib.events.onEvaluatingDeadly:subscribe(
				function(spaceDamage, attackingPawn, targetPawn)
					applySkillToSpaceDamage(self, spaceDamage, attackingPawn, targetPawn, true, nil)
				end, self.priority)
	end

	-- Post skill effect... effects (Vampire/Reflect). Always subscribe with default 
	-- that returns nil.
	self._effectEvaluatedSubscription = damageModifierLib.events.onSkillEffectEvaluated:subscribe(
			function(phase, outEffects)
				local evaluated = self:SkillEffectEvaluated(phase)
				if not evaluated then
					return
				end
				local effectsArray = type(evaluated) == "table" and evaluated or {evaluated}
				for _, effect in ipairs(effectsArray) do
					table.insert(outEffects, effect)
				end
			end, self.priority)

	logger.logDebug(SUBMODULE, "Registered skill %s with DamageModifierLib (priority=%d, alsoIsDeadly=%s)",
			self.id, self.priority, tostring(self.modifiesKillDamage ~= false))
end

function SkillEffectModifier:clearEvents()
	logger.logDebug(SUBMODULE, "Removing skill %s", self.id)

	if self._skillModifySubscription then
		self._skillModifySubscription:unsubscribe()
		self._skillModifySubscription = nil
	end

	if self._deadlySubscription then
		self._deadlySubscription:unsubscribe()
		self._deadlySubscription = nil
	end

	if self._effectEvaluatedSubscription then
		self._effectEvaluatedSubscription:unsubscribe()
		self._effectEvaluatedSubscription = nil
	end

	cplus_plus_ex.baseClasses.SkillActive.clearEvents(self)
end

-- Override this in derived classes to modify weapon damage during effect builds.
-- source: SOURCE_ATTACKER or SOURCE_TARGET
-- phase: One of DamageModifierLib.PHASE_* constants for icon placement
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

-- Override this in derived classes to return aggregated effects after all spaceDamages processed.
-- phase: One of DamageModifierLib.PHASE_* constants for icon placement
-- Returns: nil, SpaceDamage, or array of SpaceDamage to add
-- Called AFTER all spaceDamages in a pass have been processed by all skills.
-- NOTE: If effects are added, they will be processed and this will be called
-- AGAIN! Make sure it won't infinitely loop.
function SkillEffectModifier:SkillEffectEvaluated(phase)
	return nil
end

function SkillEffectModifier:getPawnSpace(pawn)
	return damageModifierLib:GetPawnSpace(pawn)
end

function SkillEffectModifier:getPawnAt(loc)
	return damageModifierLib:GetPawnAt(loc)
end

return SkillEffectModifier
