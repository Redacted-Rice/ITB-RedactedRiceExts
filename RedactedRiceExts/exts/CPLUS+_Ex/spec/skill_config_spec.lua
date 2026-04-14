-- Tests for skill_config module
-- Configuration management and weight adjustment logic

local helper = require("helpers/plus_manager_helper")
local plus_manager = helper.plus_manager

describe("Skill Config Module", function()
	local skill_config

	before_each(function()
		helper.resetState()
		skill_config = plus_manager._subobjects.skill_config
	end)

	describe("getRelationshipMetadata", function()
		it("should return correct metadata for all relationship types", function()
			-- Pilot skill exclusions
			local meta1 = skill_config:getRelationshipMetadata(skill_config.RelationshipType.PILOT_SKILL_EXCLUSIONS)
			assert.equals("addedPilotSkillExclusions", meta1.added)
			assert.equals("removedPilotSkillExclusions", meta1.removed)
			assert.equals("Pilot", meta1.sourceLabel)
			assert.equals("Skill", meta1.targetLabel)
			assert.is_false(meta1.isBidirectional)

			-- Pilot skill inclusions
			local meta2 = skill_config:getRelationshipMetadata(skill_config.RelationshipType.PILOT_SKILL_INCLUSIONS)
			assert.equals("addedPilotSkillInclusions", meta2.added)
			assert.is_false(meta2.isBidirectional)

			-- Skill exclusions
			local meta3 = skill_config:getRelationshipMetadata(skill_config.RelationshipType.SKILL_EXCLUSIONS)
			assert.equals("addedSkillExclusions", meta3.added)

			-- Invalid type
			assert.is_nil(skill_config:getRelationshipMetadata("invalid_type"))
		end)
	end)

	describe("Relationship Table Management", function()
		local testTable

		before_each(function()
			testTable = {}
		end)

		it("should add, check, and manage relationships", function()
			-- Initially empty
			assert.is_false(skill_config:_relationshipExists(testTable, "source1", "target1"))

			-- Add and verify
			skill_config:_addRelationship(testTable, "pilot1", "skill1")
			assert.is_true(skill_config:_relationshipExists(testTable, "pilot1", "skill1"))
			assert.is_true(testTable.pilot1.skill1)

			-- Multiple targets for same source
			skill_config:_addRelationship(testTable, "pilot1", "skill2")
			skill_config:_addRelationship(testTable, "pilot1", "skill3")
			assert.is_true(testTable.pilot1.skill2)
			assert.is_true(testTable.pilot1.skill3)

			-- Multiple sources
			skill_config:_addRelationship(testTable, "pilot2", "skill1")
			assert.is_true(testTable.pilot2.skill1)
		end)

		it("should remove relationships with proper cleanup", function()
			skill_config:_addRelationship(testTable, "pilot1", "skill1")
			skill_config:_addRelationship(testTable, "pilot1", "skill2")

			-- Remove one, source should remain
			skill_config:_removeRelationship(testTable, "pilot1", "skill1")
			assert.is_false(skill_config:_relationshipExists(testTable, "pilot1", "skill1"))
			assert.is_true(testTable.pilot1.skill2)

			-- Remove last, source should be cleaned up
			skill_config:_removeRelationship(testTable, "pilot1", "skill2")
			assert.is_nil(testTable.pilot1)

			-- Handle non-existent
			skill_config:_removeRelationship(testTable, "nonexistent", "skill1")
			assert.is_nil(testTable.nonexistent)
		end)
	end)

	describe("_mergeRelationships", function()
		it("should merge code-defined, added, and removed relationships correctly", function()
			local codeDefined = {
				pilot1 = {skill1 = true, skill2 = true}
			}
			local added = {
				pilot1 = {skill3 = true},
				pilot2 = {skill1 = true}
			}
			local removed = {
				pilot1 = {skill1 = true}
			}

			local merged = skill_config:_mergeRelationships(codeDefined, added, removed)

			-- pilot1: skill1 removed, skill2 from code, skill3 added
			assert.is_false(skill_config:_relationshipExists(merged, "pilot1", "skill1"))
			assert.is_true(merged.pilot1.skill2)
			assert.is_true(merged.pilot1.skill3)

			-- pilot2: skill1 added
			assert.is_true(merged.pilot2.skill1)
		end)

		it("should handle edge cases", function()
			-- Only code-defined
			local codeOnly = skill_config:_mergeRelationships({p1 = {s1 = true}}, {}, {})
			assert.is_true(codeOnly.p1.s1)

			-- Only added
			local addedOnly = skill_config:_mergeRelationships({}, {p1 = {s1 = true}}, {})
			assert.is_true(addedOnly.p1.s1)

			-- Removed non-existent doesn't add it
			local removedNone = skill_config:_mergeRelationships({}, {}, {p1 = {s1 = true}})
			assert.is_false(skill_config:_relationshipExists(removedNone, "p1", "s1"))
		end)
	end)

	describe("isCodeDefinedRelationship", function()
		it("should check code-defined relationships correctly", function()
			local relType = skill_config.RelationshipType.PILOT_SKILL_EXCLUSIONS

			skill_config.codeDefinedRelationships[relType] = {
				pilot1 = {skill1 = true, skill2 = true}
			}

			-- Exists
			assert.is_true(skill_config:isCodeDefinedRelationship(relType, "pilot1", "skill1"))

			-- Doesn't exist
			assert.is_false(skill_config:isCodeDefinedRelationship(relType, "pilot2", "skill1"))

			-- Source exists but target doesn't
			assert.is_false(skill_config:isCodeDefinedRelationship(relType, "pilot1", "skill3"))
		end)
	end)

describe("Group Management", function()
	before_each(function()
		skill_config.groups = {}
		skill_config.config.groupDescriptions = {}
		-- Register test skills
		helper.setupTestSkills({
			{id = "Health", shortName = "Health", fullName = "Health", description = "Health", saveVal = -1},
			{id = "Move", shortName = "Move", fullName = "Move", description = "Move", saveVal = -1},
		})
	end)


	describe("removeGroupFromRuntime", function()
		it("should delete group from all skills", function()
			-- Add skill to group
			skill_config:addSkillToGroup("Health", "testGroup")
			assert.is_true(skill_config:isSkillInGroup("Health", "testGroup"))

			local result = skill_config:removeGroupFromRuntime("testGroup")
			assert.is_true(result)

			-- Verify group removed from computed structure
			assert.is_nil(skill_config.groups.testGroup)

			-- Verify group removed from groupsAdded
			assert.is_false(skill_config.config.groupsAdded.Health and skill_config.config.groupsAdded.Health.testGroup == true)
		end)

		it("should always succeed even if group doesn't exist", function()
			local result = skill_config:removeGroupFromRuntime("nonExistent")
			assert.is_true(result)
		end)
	end)

	describe("addSkillToGroup", function()
		it("should add a skill to a group", function()
			local result = skill_config:addSkillToGroup("Health", "testGroup")
			assert.is_true(result)

			-- Check computed structure
			assert.is_not_nil(skill_config.groups.testGroup)
			assert.is_true(skill_config.groups.testGroup.skillIds.Health)

			-- Verify source of truth - groups use dictionary structure
			assert.is_not_nil(skill_config.config.groupsAdded.Health)
			assert.is_true(skill_config.config.groupsAdded.Health.testGroup)
		end)

		it("should auto-create group in computed structure", function()
			local result = skill_config:addSkillToGroup("Health", "autoGroup")
			assert.is_true(result)
			assert.is_not_nil(skill_config.groups.autoGroup)
			assert.is_true(skill_config.groups.autoGroup.skillIds.Health)
		end)

		it("should reject if skill doesn't exist", function()
			local result = skill_config:addSkillToGroup("FakeSkill", "testGroup")
			assert.is_false(result)
		end)
	end)

	describe("removeSkillFromGroup", function()
		it("should remove a skill from a group", function()
			skill_config:addSkillToGroup("Health", "testGroup")

			local result = skill_config:removeSkillFromGroup("Health", "testGroup")
			assert.is_true(result)

			-- Check computed structure
			assert.is_false(skill_config:isSkillInGroup("Health", "testGroup"))

			-- Verify skill's groups array is updated
			local skillConfig = skill_config.config.skillConfigs.Health
			local foundInArray = false
			for _, pName in ipairs(skillConfig.groups or {}) do
				if pName == "testGroup" then
					foundInArray = true
					break
				end
			end
			assert.is_false(foundInArray)
		end)

		it("should succeed even if group doesn't exist", function()
			local result = skill_config:removeSkillFromGroup("Health", "nonExistent")
			assert.is_true(result)
		end)
	end)

	describe("isSkillInGroup", function()
		it("should check if skill is in group", function()
			skill_config:addSkillToGroup("Health", "testGroup")

			assert.is_true(skill_config:isSkillInGroup("Health", "testGroup"))
			assert.is_false(skill_config:isSkillInGroup("Move", "testGroup"))
		end)

		it("should return false for non-existent group", function()
			assert.is_false(skill_config:isSkillInGroup("Health", "nonExistent"))
		end)
	end)

	describe("listGroups", function()
		it("should list all groups alphabetically from computed structure", function()
			-- Count groups before adding test groups (vanilla skills may have groups)
			local groupsBefore = skill_config:listGroups()
			local countBefore = #groupsBefore

			-- Add skills to groups
			skill_config:addSkillToGroup("Health", "zGroup")
			skill_config:addSkillToGroup("Health", "aGroup")
			skill_config:addSkillToGroup("Move", "mGroup")

			local groups = skill_config:listGroups()
			-- Should have 3 more groups than before
			assert.are.equal(countBefore + 3, #groups)

			-- Verify our groups are in the list and sorted
			local foundAGroup = false
			local foundMGroup = false
			local foundZGroup = false
			for _, groupName in ipairs(groups) do
				if groupName == "aGroup" then foundAGroup = true end
				if groupName == "mGroup" then foundMGroup = true end
				if groupName == "zGroup" then foundZGroup = true end
			end
			assert.is_true(foundAGroup, "aGroup should be in list")
			assert.is_true(foundMGroup, "mGroup should be in list")
			assert.is_true(foundZGroup, "zGroup should be in list")

			-- Verify alphabetical sorting
			for i = 2, #groups do
				assert.is_true(groups[i-1] < groups[i], "Groups should be sorted alphabetically")
			end
		end)

		it("should return empty list when no groups exist", function()
			local groups = skill_config:listGroups()
			assert.are.equal(0, #groups)
		end)
	end)

	describe("Incremental Group Definition", function()
		it("should auto-create groups when skills are registered with group arrays", function()
			-- Register skills with group definitions
			helper.setupTestSkills({
				{id = "Skill1", shortName = "S1", fullName = "Skill 1", description = "Skill 1", saveVal = -1, groups = {"groupA", "groupB"}},
				{id = "Skill2", shortName = "S2", fullName = "Skill 2", description = "Skill 2", saveVal = -1, groups = {"groupB", "groupC"}},
			})

			-- Need to rebuild groups after registration
			helper.rebuildGroups()

			-- Groups should appear in computed structure
			assert.is_not_nil(skill_config.groups.groupA)
			assert.is_not_nil(skill_config.groups.groupB)
			assert.is_not_nil(skill_config.groups.groupC)

			-- Skills should be in correct groups
			assert.is_true(skill_config.groups.groupA.skillIds.Skill1)
			assert.is_true(skill_config.groups.groupB.skillIds.Skill1)
			assert.is_true(skill_config.groups.groupB.skillIds.Skill2)
			assert.is_true(skill_config.groups.groupC.skillIds.Skill2)
		end)

		it("should handle adding skills to groups via setSkillConfig", function()
			-- Update skill config to add it to group (this stores as code-defined)
			skill_config:setSkillConfig("Health", {groups = {"testGroup"}})

			-- Need to rebuild groups after registration
			helper.rebuildGroups()

			-- Verify skill is in group
			assert.is_true(skill_config:isSkillInGroup("Health", "testGroup"))

			-- Verify source of truth - groups use dictionary structure
			assert.is_not_nil(skill_config.codeDefinedGroups.Health)
			assert.is_true(skill_config.codeDefinedGroups.Health.testGroup)
		end)
	end)
end)
end)
