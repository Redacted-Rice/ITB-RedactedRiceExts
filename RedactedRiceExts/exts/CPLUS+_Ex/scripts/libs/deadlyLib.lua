--[[
DeadlyLib - Adjust Board:IsDeadly checks for modified weapon damage.

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
  DeadlyLib.events.onIsDeadlyEvaluating:subscribe(fn, priority) -> Subscription
      fn(spaceDamage, attackingPawn, targetPawn)
        spaceDamage   - mutable SpaceDamage COPY (mutate this)
        attackingPawn - pawn passed to Board:IsDeadly
        targetPawn    - pawn on spaceDamage.loc (may be nil)
      priority (optional number, default 100) - lower runs first

  subscription:unsubscribe()

Priority guidance (align with SkillEffectModifier.priority):
  INTERNAL_PRIORITY (0) - framework use only
  30-50  - early transformations / blocks
  80     - additive bonuses after doubling interactions
  100    - default
  150    - near-final finishers (kill shot)
  180-200 - late follow-ups
]]

local VERSION = "0.9.0"

local DEBUG = true

local DEFAULT_PRIORITY = 100
local INTERNAL_PRIORITY = 0

local function logDebug(fmt, ...)
	if DEBUG then
		LOG("DeadlyLib: " .. string.format(fmt, ...))
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

local function onBoardClassInitialized(BoardClass, board)
	local previousIsDeadly = board.IsDeadly

	BoardClass.IsDeadly = function(self, spaceDamage, attackingPawn)
		local event = DeadlyLib.events.onIsDeadlyEvaluating
		if not spaceDamage or not spaceDamage.loc or #event.subscribers == 0 then
			return previousIsDeadly(self, spaceDamage, attackingPawn)
		end

		local originalDamage = spaceDamage.iDamage
		local modified = copySpaceDamage(spaceDamage)
		local targetPawn = resolveTargetPawn(spaceDamage)

		logDebug("Dispatching onIsDeadlyEvaluating at %s: baseDamage=%s target={%s} attacker={%s} subscribers=%d",
				spaceDamage.loc:GetString(), tostring(originalDamage),
				describePawn(targetPawn), describePawn(attackingPawn),
				#event.subscribers)

		-- ModApi Event style: dispatch args directly to subscribers
		event:dispatch(modified, attackingPawn, targetPawn)

		local usedDamage = modified.iDamage
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
	if VERSION < DeadlyLib.version then
		return
	end

	if DeadlyLib.initialized then
		return
	end

	DeadlyLib:finalizeInit()
	DeadlyLib.initialized = true
end

modApi.events.onModsInitialized:subscribe(onModsInitialized)

local isNewestVersion = DeadlyLib == nil
	or modApi:isVersionAbove(VERSION, DeadlyLib.version)

if isNewestVersion then
	DeadlyLib = DeadlyLib or {}
	DeadlyLib.version = VERSION
	DeadlyLib.DEFAULT_PRIORITY = DEFAULT_PRIORITY
	DeadlyLib.INTERNAL_PRIORITY = INTERNAL_PRIORITY
	DeadlyLib.events = DeadlyLib.events or {}
	DeadlyLib.events.onIsDeadlyEvaluating = createPriorityEvent("onIsDeadlyEvaluating")

	function DeadlyLib:finalizeInit()
		logDebug("Finalized DeadlyLib %s (%d subscriber(s))",
				VERSION, #self.events.onIsDeadlyEvaluating.subscribers)
	end

	modApi.events.onBoardClassInitialized:subscribe(onBoardClassInitialized)
end

return DeadlyLib
