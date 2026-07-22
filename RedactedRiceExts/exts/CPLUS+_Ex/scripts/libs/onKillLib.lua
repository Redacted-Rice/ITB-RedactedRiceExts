--[[
OnKillLib - Adjust Board:IsDeadly checks for modified weapon damage.

Libs Wiki: https://github.com/Redacted-Rice/ITB-RedactedRiceMods/wiki

Author: Das Keifer of Redacted Rice
Discord Server: https://discord.gg/CNjTVrpN4v

Overview:
Mods can register persistent modifier functions. Each function receives the
original SpaceDamage, pawns, and the running damage total from prior modifiers.
It returns the adjusted damage (or nil to leave the total unchanged). Modifiers
run in priority order (lower priority values run first), matching the memhack/CPLUS+
hook system.

APIs:
   :AddModifier(fn, priority, name) -> modifierId
       fn(spaceDamage, targetPawn, attackingPawn, currentDamage) -> adjustedDamage|nil
       targetPawn is resolved from spaceDamage.loc; attackingPawn from the selected pawn.
       priority (optional number, default 100) - lower runs first
       name (optional string) - used in debug logs; defaults to "modifier <id>"

   :RemoveModifier(modifierId)
       Unregisters a modifier previously returned by AddModifier

Priority guidance (use the same values as SkillEffectModifier.priority):
   INTERNAL_PRIORITY (0)
       Reserved for framework use. Do not use in mods.

   30-50
       Early transformations: flat blocks or reductions that should run before
       additive bonuses (e.g. impervious-style zeroing, pre-bonus adjustments).

   80
       Standard additive bonuses that should run after acid/armor/boost
       interactions ("go after doubling").

   100 (DEFAULT_PRIORITY)
       Default for most damage modifiers.

   150
       Effects that depend on near-final damage totals (e.g. kill-shot finishers).

   180-200
       Late effects: healing, delayed bonuses, or follow-ups that should see the
       final calculated damage (e.g. vampire, vigor, anger-style reactions).
]]

local VERSION = "0.8.0"

local DEBUG = true
local modifiers = {}
local nextModifierId = 1

local DEFAULT_PRIORITY = 100
local INTERNAL_PRIORITY = 0

local function logDebug(fmt, ...)
	if DEBUG then
		LOG("OnKillLib: " .. string.format(fmt, ...))
	end
end

-- For debugging/logs
local function describePawn(pawn)
	if not pawn then
		return "nil"
	end
	return string.format("id=%s type=%s team=%s", tostring(pawn:GetId()),
			tostring(pawn:GetType()), tostring(pawn:GetTeam()) )
end

local function resolvePriority(priority)
	if priority ~= nil then
		assert(type(priority) == "number", "Modifier priority must be a number")
		return priority
	end
	return DEFAULT_PRIORITY
end

local function insertModifierByPriority(entry)
	for i = 1, #modifiers + 1 do
		if i > #modifiers or entry.priority < modifiers[i].priority then
			table.insert(modifiers, i, entry)
			return i
		end
	end
end

-- The real target is whatever pawn stands on the damaged tile.
-- Modifiers receive this resolved pawn; IsDeadly's pawn arg is the attacker.
local function resolveTargetPawn(spaceDamage)
	if Board and spaceDamage.loc and Board:IsValid(spaceDamage.loc) then
		return Board:GetPawn(spaceDamage.loc)
	end
	return nil
end

local function createModifierEntry(id, fn, priority, name)
	return {
			id = id,
			fn = fn,
			priority = priority,
			name = name or ("modifier " .. id),
	}
end

local function registerModifierEntry(entry)
	entry.priority = resolvePriority(entry.priority)
	local index = insertModifierByPriority(entry)
	logDebug("Registered modifier %s (#%d) at priority %d (index %d)",
			entry.name, entry.id, entry.priority, index)
	return entry.id
end

local function addModifier(self, fn, priority, name)
	Assert.Equals("function", type(fn), "Argument #1")
	local id = nextModifierId
	nextModifierId = nextModifierId + 1
	return registerModifierEntry(createModifierEntry(id, fn, priority, name))
end

local function removeModifier(self, modifierId)
	for i, entry in ipairs(modifiers) do
		if entry.id == modifierId then
			table.remove(modifiers, i)
			logDebug("Removed modifier %s (#%d)", entry.name, modifierId)
			return true
		end
	end

	if self.queued then
		for i, entry in ipairs(self.queued) do
			if entry.id == modifierId then
				table.remove(self.queued, i)
				logDebug("Removed queued modifier %s (#%d)", entry.name, modifierId)
				return true
			end
		end
	end

	return false
end

local function applyModifiers(spaceDamage, attackingPawn)
	local targetPawn = resolveTargetPawn(spaceDamage)
	local damage = spaceDamage.iDamage

	logDebug("Applying %d modifier(s) at %s: baseDamage=%s target={%s} attacker={%s}",
			#modifiers, spaceDamage.loc:GetString(), tostring(damage),
			describePawn(targetPawn), describePawn(attackingPawn))

	for i, entry in ipairs(modifiers) do
		local before = damage
		local adjusted = entry.fn(spaceDamage, targetPawn, attackingPawn, damage)
		if adjusted ~= nil then
			damage = adjusted
		end
		logDebug("Modifier %s (#%d) (priority %d) at %s: damage %s -> %s",
				entry.name, entry.id, entry.priority, spaceDamage.loc:GetString(),
				tostring(before), tostring(damage))
	end
	return damage
end

local function onBoardClassInitialized(BoardClass, board)
	local previousIsDeadly = board.IsDeadly

	BoardClass.IsDeadly = function(self, spaceDamage, attackingPawn)
		if #modifiers == 0 or not spaceDamage or not spaceDamage.loc then
			return previousIsDeadly(self, spaceDamage, attackingPawn)
		end

		local newDamage = applyModifiers(spaceDamage, attackingPawn)
		local modified = SpaceDamage(
				Point(spaceDamage.loc.x, spaceDamage.loc.y),
				newDamage,
				spaceDamage.iPush or DIR_NONE
		)
		local result = previousIsDeadly(self, modified, attackingPawn)
		logDebug( "IsDeadly result at %s: baseDamage=%s modifiedDamage=%s deadly=%s",
				spaceDamage.loc:GetString(), tostring(spaceDamage.iDamage), tostring(modified.iDamage), tostring(result))
		return result
	end
end

local function onModsInitialized()
	if VERSION < OnKillLib.version then
		return
	end

	if OnKillLib.initialized then
		return
	end

	OnKillLib:finalizeInit()
	OnKillLib.initialized = true
end

modApi.events.onModsInitialized:subscribe(onModsInitialized)

local isNewestVersion = OnKillLib == nil
	or modApi:isVersionAbove(VERSION, OnKillLib.version)

if isNewestVersion then
	OnKillLib = OnKillLib or {}
	OnKillLib.version = VERSION
	OnKillLib.DEFAULT_PRIORITY = DEFAULT_PRIORITY
	OnKillLib.INTERNAL_PRIORITY = INTERNAL_PRIORITY
	OnKillLib.queued = OnKillLib.queued or {}

	function OnKillLib:AddModifier(fn, priority, name)
		Assert.Equals("function", type(fn), "Argument #1")
		local id = nextModifierId
		nextModifierId = nextModifierId + 1
		local entry = createModifierEntry(id, fn, priority, name)
		table.insert(self.queued, entry)
		logDebug("Queued modifier %s (#%d) at priority %s",
				entry.name, entry.id, tostring(priority))
		return id
	end

	function OnKillLib:RemoveModifier(modifierId)
		Assert.Equals("number", type(modifierId), "Argument #1")
		return removeModifier(self, modifierId)
	end

	function OnKillLib:finalizeInit()
		self.AddModifier = function(onKillSelf, fn, priority, name)
			return addModifier(onKillSelf, fn, priority, name)
		end
		self.RemoveModifier = removeModifier

		logDebug("Finalizing %d queued modifier(s)", #self.queued)
		for _, entry in ipairs(self.queued) do
			registerModifierEntry(entry)
		end
		self.queued = nil
	end

	modApi.events.onBoardClassInitialized:subscribe(onBoardClassInitialized)
end

return OnKillLib
