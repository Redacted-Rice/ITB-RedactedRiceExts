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
end)
