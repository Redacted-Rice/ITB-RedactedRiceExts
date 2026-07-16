# Redacted Rice Extensions
All of RedactedRice's Extensions for Into the Breach

Created by Das Keifer

Join the Redacted Rice discord for support, mods, discussion and other projects: https://discord.gg/CNjTVrpN4v

See individual folders for more details on each extension

Please enjoy and contact us if you run into any issues.
* RedactedRice Discord Server: https://discord.gg/CNjTVrpN4v
* ItB Discord: Das Keifer
* Email: RedactedRice@gmail.com

# Extensions

* memhack - v1.3.0 - Extension to expose additional functionality via direct memory access
* CPLUS+ Ex - v1.3.1 - Extension to control assigning, controling, and adding custom Pilot Level Up Skills

# Releases

Latest release: 1.3.1

## 1.3.1

Released: 7/16/2026

* memhack - v1.3.0
* CPLUS+ Ex - v1.3.1

### Notes
* Fixes for some cases where the damage modifiers would error
* Fixed % chances not adding up to 100%

## 1.3.0

Released: 7/7/2026

* memhack - v1.3.0
* CPLUS+ Ex - v1.3.0

### Notes
* Making on kill effects account for boost and acid
* Made squad exclusions always show in skill config UI if enabled
* Adding priorties to hooks in memhack and cplus+
* Cleaning up of redundant logic related to combining skills
* Fixing issue where health gaining skills earned weren't applied in mission correctly

## 1.2.0

Released: 6/11/2026

* memhack - v1.2.0
* CPLUS+ Ex - v1.2.0

### Notes
* Fixing Skill Inclusions
* Added squad exclusions and inclusions
* Support for more than 2 level up skills on a pilot via "virtual" skills
* Hangar Extra Info UI for virtual skill icons and other additional info as needed
* Optional earned-skill icons for normal level up skills
* Additional lower level fixes/enhancements to support above features

## 1.1.1

Released: 05/07/2026

* memhack - v1.1.0
* CPLUS+ Ex - v1.1.1

### Notes
* Added user guide for CPLUS+
* UI Bug fixes
* Fix in skill effect modifier base class

## 1.1.0

Released: 05/01/2026

* memhack - v1.1.0
* CPLUS+ Ex - v1.1.0

### Notes

#### memhack v1.1.0
* Logging and error handle updates

#### CPLUS+ Ex v1.1.0
* Base classes from More+
* UI Optimization
* Slot restrictions for skills
* Group based exclusions
* Other minor changes

## 1.0.2

Released: 04/10/2026

* memhack - v1.0.0
* CPLUS+ Ex - v1.0.2

### Notes

Additional bug fix for CPLUS+

## 1.0.1

Released: 03/30/2026

* memhack - v1.0.0
* CPLUS+ Ex - v1.0.1

### Notes

Bug fixes for CPLUS+

## 1.0.0

Released: 03/28/2026

* memhack - v1.0.0
* CPLUS+ Ex - v1.0.0

### Notes

Initial releases of the extenstions

# Install

- Unzip the release folder
- Place the unzipped RedactedRiceExts folder in "Into the Breach/extensions" folder (create it if needed)
  - Make sure there is not an extra layer of folder - when you enter the RedactedRiceExts folder you should see the "scripts" folder. Remove any extra folder layers

To uninstall, just delete the folder

# Release Process

Build memhack-dll (if changed) and copy to memhack/memhack.dll
Copy license and this readme into RedactedRiceExts folder and zip it up