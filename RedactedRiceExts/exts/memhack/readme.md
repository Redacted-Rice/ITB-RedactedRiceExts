# memhack Extension
RedactedRice's memhack Extension that exposes additional functionality via direct memory access

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
* ItB AE       1.2.93
* ModLoader    2.9.5
* ModLoaderExt 1.24

### Notes
* Added priorities to hooks
* Cleaned up a bunch of extra logic for combining virtual skill effects into actual ones

## 1.2.0
Released: 6/11/2026

compatible with:
* ItB AE       1.2.93
* ModLoader    2.9.5
* ModLoaderExt 1.24

### Notes
* Adding in tracking/separation between set values for HP & Move like done for grid and core for skills to support virtual skills in CPLUS+
* Caching of struct sizes to improve run time efficiency/reduce max callstack size
* Added freeing allocated memory
* Added functions for directly setting grid power
* Added function to get the selected pawn in the strategy screen

## 1.1.0
Released: 05/01/2026

compatible with:
* ItB AE       1.2.93
* ModLoader    2.9.5
* ModLoaderExt 1.24

### Notes
* Added formatting support to logging
* Additional transition of logs to logging framework and cleaning up error handling
* Adding more testing coverage

## 1.0.0
Released: 03/28/2026

compatible with:
* ItB AE       1.2.93
* ModLoader    2.9.5
* ModLoaderExt 1.24

### Notes
Initial official release!
