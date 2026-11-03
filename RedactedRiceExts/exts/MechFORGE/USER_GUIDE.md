# MechFORGE User Guide

This guide covers what MechFORGE does in game and how mod authors hook into it.

## Outline

1. [What is MechFORGE?](#what-is-mechforge)
2. [For players](#for-players)
3. [For mod authors](#for-mod-authors)
   - [Dependencies](#dependencies)
   - [Registering a custom upgrade](#registering-a-custom-upgrade)
   - [Hooks](#hooks)
   - [Vanilla stat handling](#vanilla-stat-handling)
4. [Getting help](#getting-help)

## What is MechFORGE?

MechFORGE is an **extension**, not a gameplay mod by itself. It exposes APIs so squad mods can change how specific mechs use the two innate upgrade slots every mech has:

* **Health slot** (vanilla: +2 max HP when powered)
* **Move slot** (vanilla: +1 move when powered)

Mods can show different labels in the hangar and run custom logic when the player installs or removes cores in those slots. MechFORGE will automatically undo the typical bonuses when a custom one is set up.

You only see MechFORGE listed in the mod loader if it is installed. Gameplay changes come from **mods that depend on it**.

## For players

### Default behavior

With MechFORGE enabled but no mods using it, the game behaves as usual. The extension does not add menus or options on its own.

### With mods that use MechFORGE

Depending on the mod, you may see:

* Different names on a mech's Health or Move reactor line in the hangar (for example a "Armored" upgrade instead of "+2 Health").
* Different stats or effects when you power those slots, as defined by that mod.

## For mod authors

This provides APIs to register custom effects when upgrades are added or removed. MechFORGE will automatically revert the vanilla upgrade behavior if a custom one is set so all you have to do is define how to enable/disable your custom effect.

An example custom upgrade can be found in the AT-AT mech in the Star Wars Empire squad. In it I replace the "+1 Move" upgrade with an "Armored" upgrade.

Custom upgrades are currently only defined based on PawnType. If there is a need for other options, refer to the [Getting Help](#getting-help) section to ask for what is needed.

### Dependencies

In your mod or extension `init.lua` include dependencies for `redactedrice_memhack` and `redactedrice_mech_forge`

### Registering a custom upgrade

Global API: `mech_forge`

Slots (use these constants, not raw strings):

* `mech_forge.VANILLA_UPGRADES.HEALTH`
* `mech_forge.VANILLA_UPGRADES.MOVE`

`mechType` must match the pawn type string from your mech definition - the same value as `pawn:GetType()`.

Minimal label only example:

```lua
mech_forge:registerMechUpgrade("MyCustomMech", mech_forge.VANILLA_UPGRADES.HEALTH, "Cool Effect")
```

Full example with callbacks:

```lua
mech_forge:registerMechUpgrade("MyCustomMech", mech_forge.VANILLA_UPGRADES.HEALTH, {
  label = "Cool Effect",
  onPowered = function(slot, pawn, pawnId, mechType, newCore)
    -- core just became powered
  end,
  onUnpowered = function(slot, pawn, pawnId, mechType, oldCore)
    -- core just became unpowered
  end,
  onCoreChanged = function(slot, pawn, pawnId, mechType, oldCore, newCore)
    -- any change on this slot, including first sync when entering a run
  end,
})
```

Registration Args:

* `label` is a required non-empty string, text id, or `function(pawn)` returning a string.
* `onPowered` and `onUnpowered` are optional but are a pair. Either both are set or both omitted.
* `onCoreChanged` is optional if you want to vary behavior based on what type of core is installed.

Note: The callbacks are optional but its expected you will want to use one or the other to apply the effects of your custom upgrade. You could do this a different way though if it makes sense for your use case.

Table and positional argument styles are both supported. See `mech_upgrade_registry.lua` for validation errors logged via memhack.

### Events

MechFORGE creates and uses events/hooks to call the functions registered with a custom upgrade. These can be regestered with like most other extensions as either hooks or events.

MechFORGE events/hooks support priority. The code to revert vanilla upgrade effects and run the registered functions are called with INTERNAL_PRIORITY (0)

Examples:
```lua
mech_forge:addMechUpgradePoweredHook(function(slot, pawn, pawnId, mechType, newCore)
  -- ...
end)

mech_forge.events.onMechUpgradeCoreChanged:subscribe(function(slot, pawn, pawnId, mechType, oldCore, newCore)
  -- ...
end)
```

Events:

* `onMechUpgradeCoreChanged` - any core value change on HP or Move slot
* `onMechUpgradePowered` - transition from unpowered to powered
* `onMechUpgradeUnpowered` - powered to unpowered

Powered state uses `memhack.CORE_TYPE_NONE` for an empty slot. Other `memhack.CORE_TYPE_*` values count as powered.

## Getting help

If you encounter issues or have questions:

* Visit the [Redacted Rice Discord](https://discord.gg/CNjTVrpN4v)
- Check the [GitHub Wiki](https://github.com/Redacted-Rice/ITB-RedactedRiceExts/wiki/%5BMechFORGE%5D-Home) for more detailed information
- Report bugs on the Discord or GitHub
