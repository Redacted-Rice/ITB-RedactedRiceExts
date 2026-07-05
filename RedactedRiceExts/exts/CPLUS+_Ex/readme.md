# Customizable Pilot Level Up Skills and More Extension (CPLUS+ Ex or C++ Ex)
RedactedRice's Pilot Extension that allows defining, customizing and adding new level up skills as well as a few other pilot related things such as leveling up and adding experience

Created by Das Keifer

Join the Redacted Rice discord for support, mods, discussion and other projects: https://discord.gg/CNjTVrpN4v

Please enjoy and contact us if you run into any issues.
* RedactedRice Discord Server: https://discord.gg/CNjTVrpN4v
* ItB Discord: Das Keifer
* Email: RedactedRice@gmail.com

# Releases
Latest release: 1.3.0

## 1.3.0
Released: 7/7/2026

compatible with:
* ItB AE        1.2.93
* ModLoader     2.9.5
* ModLoaderExt  1.24
* memhack       1.3.0

### Notes
* Making on kill effects account for boost and acid
* Made squad exclusions always show in skill config UI if enabled
* Fixing issue where health gaining skills earned weren't applied in mission correctly
* Added priorities for hooks
* Added support for internal skills not shown on UI

## 1.2.0
Released: 6/11/2026

compatible with:
* ItB AE        1.2.93
* ModLoader     2.9.5
* ModLoaderExt  1.24
* memhack       1.2.0

### Notes
* Fixing Skill Inclusions
* Added squad exclusions and inclusions
* Adding support for "virtual" skills to allow more than 2 level up skills on a pilot
* Separating out inclusions and exclusions and making them more extensible for custom/additional ones
* Validation of constraint type (inclusion/exclusion) to ensure the correct type is added for pilots/squads based on the skill (e.g. if you add a skillInclusion, its actually an inclusion type skill you passed)
* Hangar Extra Info UI for virtual skill icons with events for allowing adding custom info to it
* Optional earned-skill icons for normal level up skills
* Pilot memhack API overrides for transparent virtual skill slot access
* Added support for extra data persisting with time traveler

## 1.1.1
Released: 05/07/2026

compatible with:
* ItB AE        1.2.93
* ModLoader     2.9.5
* ModLoaderExt  1.24
* memhack       1.1.0

### Notes
* Added user guide
* UI Bug fixes
* Fix in skill effect modifier base class

## 1.1.0
Released: 05/01/2026

compatible with:
* ItB AE        1.2.93
* ModLoader     2.9.5
* ModLoaderExt  1.24
* memhack       1.1.0

### Notes
* Added base classes for skills from More+
* Significant optimization of UI to make it more responsive
* Added Group based skill exclusions where only one skill from the group will be selected per pilot
* Added slot restrictions for skills
* Added support for function defined coded exclusions
    * Added IsCyborg and IsFlyingCyborg fns for these
* Support default reusability vs reusibility limit for skills
* Fixed some confusing logs

## 1.0.2
Released: 04/10/2026

compatible with:
* ItB AE        1.2.93
* ModLoader     2.9.5
* ModLoaderExt  1.24
* memhack       1.0.0

### Notes
Miscellaneous bug fix type changes:
* Additional fix for CPLUS+ where coded disables ignored configed values

## 1.0.1
Released: 03/30/2026

compatible with:
* ItB AE        1.2.93
* ModLoader     2.9.5
* ModLoaderExt  1.24
* memhack       1.0.0

### Notes
Miscellaneous bug fix type changes:
* Enabling CPLUS+ no longer re-rolls skills
* Skills UI in configs no longer outline when highlighted and have better and consistent spacing
* Other UI spacing consistency
* Debug logging disabled by default

## 1.0.0
Released: 03/28/2026

compatible with:
* ItB AE        1.2.93
* ModLoader     2.9.5
* ModLoaderExt  1.24
* memhack       1.0.0

### Notes
Initial official release!
