# CPLUS++ Ex User Guide

This guide is intended primarily for how to use CPLUS+ in game and what it allows players to do.

If you are a modder and want to know more technical details or how to start creating your own skills, see the
[Quick Start Guide](https://github.com/Redacted-Rice/ITB-RedactedRiceExts/wiki/%5BCPLUS-plus-ex%5D-Quick-Start-Guide)
and other modder focused documentation on the GitHub wiki.

## Outline

1. [What is CPLUS++ Ex?](#what-is-cplus-ex)
2. [How It Affects Your Game](#how-it-affects-your-game)
   - [Default Vanilla Behavior](#default-vanilla-behavior)
   - [With CPLUS++ Ex](#with-cplus-ex)
3. [Changing Configurations (Mid Run)](#changing-configurations-mid-run)
   - [Accessing the Settings](#accessing-the-settings)
4. [Understanding Skill Configuration](#understanding-skill-configuration)
   - [Enable/Disable](#enabledisable)
   - [Weight](#weight)
   - [Reusability](#reusability)
   - [Slots](#slots)
4. [Understanding Constraints](#understanding-constraints)
   - [(Exclusion) Groups](#exclusion-groups)
   - [Pilot-to-Skill Exclusions](#pilot-to-skill-exclusions)
   - [Skill-to-Skill Exclusions](#skill-to-skill-exclusions)
5. [Tips for Customizing Your Experience](#tips-for-customizing-your-experience)
   - [Reduce Randomness](#reduce-randomness)
   - [Try Themed Runs](#try-themed-runs)
   - [Balance Powerful Modded Skills](#balance-powerful-modded-skills)
6. [Getting Help](#getting-help)

## What is CPLUS++ Ex?

CPLUS++ Ex (Custom Pilot Level Up Skills Extension) lets you customize which pilot abilities appear when your pilots level up. You can control which level up skills are available, adjust how often they appear, and prevent useless or redundant level up skill combinations.

## How It Affects Your Game

### Default Vanilla Behavior

In the base game, when your pilots level up, they randomly get a new level up skill from the core 4 (without AE) or 14 (with AE) with uniform weighting.

### With CPLUS++ Ex

Gives you significantly more control over this. You can:
- **Enable/Disable Skills**: Turn specific level up skills on or off completely
- **Adjust Frequencies**: Make level up skills appear more or less often
- **Prevent Bad Combos**: Stop pilots from getting useless, redundant, or conflicting level up skill combinations
- **Add Custom Skills**: Mods can add entirely new level up skills

## Changing Configurations (Mid Run)

Configuration of the skills can be individually modified and enabled and disabled mid run or between runs. If a skill was assigned and no longer is allowed
due to being disabled or some contraint, it will re-roll only that skill. This applies to pilots in run as well as time travelers

Level up skills are selected for pilots on start or as soon as you get them so enabling skills will NOT cause existing pilots to be able to get those skills.

Disabling level up skills mid run is supported and can be done. This could be because the skill doesn't make sense for some reason (in which case an exclusion
 or pool based exclusion would be fitting) or could just be because you decided you don't like the skill (in which case disabling it would be fitting).
 Modifying level up skill configs so that a skill becomes invalid on a pilot, whether you leveled up to get that skill yet or not, will cause it to re-roll
 that skill. Newly enabled skills can then be selected for that slot.

### Accessing the Settings

1. Open the **Mod Content** menu from the main menu
2. Select **"Modify Pilot Abilities"**
3. You'll see a UI showing all available pilot skills organized by category. Without other mods, it will just show a "Vanilla" category

## Understanding Skill Configuration

Skills are organized into categories:
- **Vanilla Skills**: The original game's abilities
- **Custom Categories**: Any categories added by mods (e.g., "More+ Defensive", "More+ Movement")

For each skill, you can adjust:

### Enable/Disable
- **Enabled**: Level up skill can be selected for pilots
- **Disabled**: Level up skill will never selected for pilots

### Weight
Controls how frequently this skill appears relative to others:
- **0.5**: Half as common
- **1.0**: Normal frequency (default)
- **1.5**: 50% more common
- **2.0**: Twice as common

### Reusability

Controls how often you can get the level up skill on a pilot or in the game. Skills can have one of 3 values. What values can
 appear are defined per skill so some skills may not allow some resubility settings.

#### Reusable
Can be assigned to the same pilot multiple times and to multiple pilots.
- **Example**: Health, Move, Grid Defense

#### Once Per Pilot
Each pilot can only get this skill once (vanilla behavior).
- **Example**: Most tactical abilities like Opener, Popular Hero, etc.

#### Once Per Run
Can only be assigned once across your entire squad for the whole run. Most likely intended to be powerful skills
- **Example**: None currently

### Slots

Some skills can only appear in specific level-up slots:

#### Any Slot
Can appear at level 1 or level 2. Vanilla behavior.

#### First Slot Only
Only appears on the first level
- **Example**: Hot headed, XP-related skills that need to take effect early

#### Second Slot Only
Only appears at the pilot's second level up.
- **Example**: Powerful, rare abilities as a reward for maxing out your pilot

## Understanding Constraints

Constraints put specific restrictions on level up skills to prevent certain cases where they are incompatible or conflict with each other or other
aspects of the game.

### (Exclusion) Groups

Some skills are organized into exclusion **groups** where only one skill from the group can be selected per pilot. This prevents redundant combinations like:
- Multiple health-boosting skills
- Similar movement abilities
- Overlapping defensive bonuses

Groups can be individually enabled/disabled or can be disabled at the top level (for vanilla behavior). In order to be active, both the top level
enable groups checkbox and the individual groups enabled check boxes need to be checked.

### Pilot-to-Skill Exclusions

Certain pilots can't get certain skills because they would be:
- **Useless**: Pilot already has a better innate skill
- **Redundant**: Pilot's base ability makes the skill unnecessary
- **Incompatible**: The skill conflicts with the pilot's mechanics

**Example**: Zoltan is excluded from the Health skill because he is programmed to always have 1 health
**Example**: Kai is excluded from most boosting skills as her ability already gives her boost

### Skill-to-Skill Exclusions

Some skills prevent other skills from appearing on the same pilot to avoid:
- **Overlap**: Two skills that do very similar things
- **Conflicts**: Skills whose mechanics don't work well together
- **Redundancy**: One skill making another less useful

**Example**: Malevolent which benefits from status effects and Thick Skin which prevents them

## Tips for Customizing Your Experience

### Reduce Randomness
- Disabling skills you rarely find useful
- Increasing weights on your favorites
- Using exclusion groups to have more balanced pilots

### Try Themed Runs
- Enable only defensive skills for a tanky squad
- Focus on movement skills for a mobile, hit and run style squad
- Enable only offensive skills for an aggressive playstyle

### Balance Powerful Modded Skills
If a mod adds very strong skills, you can:
- Lower their weight so they appear rarely
- Keep them disabled and only enable them for specific runs
- Modify them to be "per run" or only appear in the second slot

## Getting Help

If you encounter issues or have questions:
- Visit the [Redacted Rice Discord](https://discord.gg/CNjTVrpN4v)
- Check the [GitHub Wiki](https://github.com/Redacted-Rice/ITB-RedactedRiceExts/wiki/%5BCPLUS-plus-ex%5D-Home) for more detailed information
- Report bugs on the Discord or GitHub
