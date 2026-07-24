--[[
DamageModifierLib - Adjust Board:IsDeadly checks for modified weapon damage.

Libs Wiki: https://github.com/Redacted-Rice/ITB-RedactedRiceMods/wiki

Author: Das Keifer of Redacted Rice
Discord Server: https://discord.gg/CNjTVrpN4v

Overview:
Uses a priority-aware modloader Event (Event:subscribe / Event:dispatch).
On Board:IsDeadly, a SpaceDamage copy is passed to subscribers. They mutate
that copy (typically iDamage). If iDamage differs from the original, the
modified copy is used for the real IsDeadly check; otherwise the original
is used unchanged.

API:
  DamageModifierLib.events.onEvaluating:subscribe(fn, priority) -> Subscription
      fn(spaceDamage, attackingPawn, targetPawn)
        spaceDamage   - mutable SpaceDamage COPY (mutate this)
        attackingPawn - pawn passed to Board:IsDeadly
        targetPawn    - pawn on spaceDamage.loc (may be nil)
      priority (optional number, default 100) - lower runs first

  subscription:unsubscribe()

  DamageModifierLib:GetModifiedDamage(spaceDamage, attackingPawn) -> number
      Runs subscribers against a copy of spaceDamage and returns the final
      iDamage. Does not mutate the original SpaceDamage.

  DamageModifierLib:GetDamageDelta(spaceDamage, attackingPawn) -> number
      Same evaluation as GetModifiedDamage, returns (modified - original).

Priority guidance (align with SkillEffectModifier.priority):
  INTERNAL_PRIORITY (0) - framework use only
  30-50  - early transformations / blocks
  80     - additive bonuses after doubling interactions
  100    - default
  150    - near-final finishers (kill shot)
  180-200 - late follow-ups
]]

local VERSION = "0.9.1"

local DEBUG = true

local DEFAULT_PRIORITY = 100
local INTERNAL_PRIORITY = 0

local function logDebug(fmt, ...)
	if DEBUG then
		LOG("DamageModifierLib: " .. string.format(fmt, ...))
	end
end

local function describePawn(pawn)
	if not pawn then
		return "nil"
	end
	return string.format("id=%s type=%s team=%s",
			tostring(pawn:GetId()), tostring(pawn:GetType()), tostring(pawn:GetTeam()))
end

local function resolvePriority(priority)
	if priority ~= nil then
		assert(type(priority) == "number", "Event priority must be a number")
		return priority
	end
	return DEFAULT_PRIORITY
end

-- Priority-aware Event wrapper around modloader Event.
-- Functionally equivalent to Event:subscribe/dispatch; adds optional priority.
local function createPriorityEvent(eventName)
	local event = Event({ eventName = eventName })
	local subscriberPriorities = {}
	local originalSubscribe = event.subscribe
	local originalUnsubscribe = event.unsubscribe

	event.subscribe = function(eventSelf, fn, priority)
		local sub = originalSubscribe(eventSelf, fn)
		subscriberPriorities[sub] = resolvePriority(priority)
		table.sort(eventSelf.subscribers, function(a, b)
			local priorityA = subscriberPriorities[a] or DEFAULT_PRIORITY
			local priorityB = subscriberPriorities[b] or DEFAULT_PRIORITY
			return priorityA < priorityB
		end)
		return sub
	end

	event.unsubscribe = function(eventSelf, subscription)
		local result = originalUnsubscribe(eventSelf, subscription)
		if result and type(subscription) == "table" then
			subscriberPriorities[subscription] = nil
		end
		return result
	end

	return event
end

-- The real target is whatever pawn stands on the damaged tile.
-- Board:IsDeadly's pawn arg is the acting/attacking pawn.
local function resolveTargetPawn(spaceDamage)
	if Board and spaceDamage.loc and Board:IsValid(spaceDamage.loc) then
		return Board:GetPawn(spaceDamage.loc)
	end
	return nil
end

local function copySpaceDamage(spaceDamage)
	return SpaceDamage(
			Point(spaceDamage.loc.x, spaceDamage.loc.y),
			spaceDamage.iDamage,
			spaceDamage.iPush or DIR_NONE
	)
end

-- Runs onEvaluating against a copy of spaceDamage.
-- Returns originalDamage, modifiedDamage, modifiedCopy.
local function evaluate(spaceDamage, attackingPawn)
	Assert.Equals("userdata", type(spaceDamage), "Argument #1")

	local originalDamage = spaceDamage.iDamage
	local event = DamageModifierLib.events.onEvaluating

	if not spaceDamage.loc or #event.subscribers == 0 then
		return originalDamage, originalDamage, spaceDamage
	end

	local modified = copySpaceDamage(spaceDamage)
	local targetPawn = resolveTargetPawn(spaceDamage)

	logDebug("Evaluating at %s: baseDamage=%s target={%s} attacker={%s} subscribers=%d",
			spaceDamage.loc:GetString(), tostring(originalDamage),
			describePawn(targetPawn), describePawn(attackingPawn),
			#event.subscribers)

	event:dispatch(modified, attackingPawn, targetPawn)

	logDebug("Evaluated at %s: baseDamage=%s modifiedDamage=%s delta=%s",
			spaceDamage.loc:GetString(), tostring(originalDamage),
			tostring(modified.iDamage), tostring(modified.iDamage - originalDamage))

	return originalDamage, modified.iDamage, modified
end

local function getModifiedDamage(self, spaceDamage, attackingPawn)
	local _, modifiedDamage = evaluate(spaceDamage, attackingPawn)
	return modifiedDamage
end

local function getDamageDelta(self, spaceDamage, attackingPawn)
	local originalDamage, modifiedDamage = evaluate(spaceDamage, attackingPawn)
	return modifiedDamage - originalDamage
end

local function onBoardClassInitialized(BoardClass, board)
	local previousIsDeadly = board.IsDeadly

	BoardClass.IsDeadly = function(self, spaceDamage, attackingPawn)
		if not spaceDamage or not spaceDamage.loc
				or #DamageModifierLib.events.onEvaluating.subscribers == 0 then
			return previousIsDeadly(self, spaceDamage, attackingPawn)
		end

		local originalDamage, usedDamage, modified = evaluate(spaceDamage, attackingPawn)
		local damageChanged = usedDamage ~= originalDamage
		local toCheck = damageChanged and modified or spaceDamage

		local result = previousIsDeadly(self, toCheck, attackingPawn)
		logDebug("IsDeadly result at %s: baseDamage=%s modifiedDamage=%s changed=%s deadly=%s",
				spaceDamage.loc:GetString(), tostring(originalDamage),
				tostring(usedDamage), tostring(damageChanged), tostring(result))
		return result
	end
end

local function onModsInitialized()
	if VERSION < DamageModifierLib.version then
		return
	end

	if DamageModifierLib.initialized then
		return
	end

	DamageModifierLib:finalizeInit()
	DamageModifierLib.initialized = true
end

modApi.events.onModsInitialized:subscribe(onModsInitialized)

local isNewestVersion = DamageModifierLib == nil
	or modApi:isVersionAbove(VERSION, DamageModifierLib.version)

if isNewestVersion then
	DamageModifierLib = DamageModifierLib or {}
	DamageModifierLib.version = VERSION
	DamageModifierLib.DEFAULT_PRIORITY = DEFAULT_PRIORITY
	DamageModifierLib.INTERNAL_PRIORITY = INTERNAL_PRIORITY
	DamageModifierLib.events = DamageModifierLib.events or {}
	DamageModifierLib.events.onEvaluating = createPriorityEvent("onEvaluating")

	function DamageModifierLib:finalizeInit()
		self.GetModifiedDamage = getModifiedDamage
		self.GetDamageDelta = getDamageDelta

		logDebug("Finalized DamageModifierLib %s (%d subscriber(s))",
				VERSION, #self.events.onEvaluating.subscribers)
	end

	-- Available immediately for callers that need it before finalizeInit.
	DamageModifierLib.GetModifiedDamage = getModifiedDamage
	DamageModifierLib.GetDamageDelta = getDamageDelta

	modApi.events.onBoardClassInitialized:subscribe(onBoardClassInitialized)
end

return DamageModifierLib
