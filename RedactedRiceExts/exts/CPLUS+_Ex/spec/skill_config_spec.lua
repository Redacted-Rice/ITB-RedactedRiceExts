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

describe("Pool Management", function()
	before_each(function()
		skill_config.pools = {}
		skill_config.config.poolDescriptions = {}
		-- Register test skills
		helper.setupTestSkills({
			{id = "Health", shortName = "Health", fullName = "Health", description = "Health", saveVal = -1},
			{id = "Move", shortName = "Move", fullName = "Move", description = "Move", saveVal = -1},
		})
	end)


	describe("deletePool", function()
		it("should delete pool from all skills", function()
			-- Add skill to pool
			skill_config:addSkillToPool("Health", "testPool")
			assert.is_true(skill_config:isSkillInPool("Health", "testPool"))

			local result = skill_config:deletePool("testPool")
			assert.is_true(result)

			-- Verify pool removed from computed structure
			assert.is_nil(skill_config.pools.testPool)

			-- Verify pool removed from poolsAdded
			assert.is_false(skill_config.config.poolsAdded.Health and skill_config.config.poolsAdded.Health.testPool == true)
		end)

		it("should always succeed even if pool doesn't exist", function()
			local result = skill_config:deletePool("nonExistent")
			assert.is_true(result)
		end)
	end)

	describe("addSkillToPool", function()
		it("should add a skill to a pool", function()
			local result = skill_config:addSkillToPool("Health", "testPool")
			assert.is_true(result)

			-- Check computed structure
			assert.is_not_nil(skill_config.pools.testPool)
			assert.is_true(skill_config.pools.testPool.skillIds.Health)

			-- Verify source of truth - pools use dictionary structure
			assert.is_not_nil(skill_config.config.poolsAdded.Health)
			assert.is_true(skill_config.config.poolsAdded.Health.testPool)
		end)

		it("should auto-create pool in computed structure", function()
			local result = skill_config:addSkillToPool("Health", "autoPool")
			assert.is_true(result)
			assert.is_not_nil(skill_config.pools.autoPool)
			assert.is_true(skill_config.pools.autoPool.skillIds.Health)
		end)

		it("should reject if skill doesn't exist", function()
			local result = skill_config:addSkillToPool("FakeSkill", "testPool")
			assert.is_false(result)
		end)
	end)

	describe("removeSkillFromPool", function()
		it("should remove a skill from a pool", function()
			skill_config:addSkillToPool("Health", "testPool")

			local result = skill_config:removeSkillFromPool("Health", "testPool")
			assert.is_true(result)

			-- Check computed structure
			assert.is_false(skill_config:isSkillInPool("Health", "testPool"))

			-- Verify skill's pools array is updated
			local skillConfig = skill_config.config.skillConfigs.Health
			local foundInArray = false
			for _, pName in ipairs(skillConfig.pools or {}) do
				if pName == "testPool" then
					foundInArray = true
					break
				end
			end
			assert.is_false(foundInArray)
		end)

		it("should succeed even if pool doesn't exist", function()
			local result = skill_config:removeSkillFromPool("Health", "nonExistent")
			assert.is_true(result)
		end)
	end)

	describe("isSkillInPool", function()
		it("should check if skill is in pool", function()
			skill_config:addSkillToPool("Health", "testPool")

			assert.is_true(skill_config:isSkillInPool("Health", "testPool"))
			assert.is_false(skill_config:isSkillInPool("Move", "testPool"))
		end)

		it("should return false for non-existent pool", function()
			assert.is_false(skill_config:isSkillInPool("Health", "nonExistent"))
		end)
	end)

	describe("listPools", function()
		it("should list all pools alphabetically from computed structure", function()
			-- Add skills to pools
			skill_config:addSkillToPool("Health", "zPool")
			skill_config:addSkillToPool("Health", "aPool")
			skill_config:addSkillToPool("Move", "mPool")

			local pools = skill_config:listPools()
			-- Should have at least our 3 test pools
			assert.are.equal(3, #pools)

			-- Verify our pools are in the list and sorted
			local foundAPool = false
			local foundMPool = false
			local foundZPool = false
			for _, poolName in ipairs(pools) do
				if poolName == "aPool" then foundAPool = true end
				if poolName == "mPool" then foundMPool = true end
				if poolName == "zPool" then foundZPool = true end
			end
			assert.is_true(foundAPool, "aPool should be in list")
			assert.is_true(foundMPool, "mPool should be in list")
			assert.is_true(foundZPool, "zPool should be in list")

			-- Verify alphabetical sorting
			for i = 2, #pools do
				assert.is_true(pools[i-1] < pools[i], "Pools should be sorted alphabetically")
			end
		end)

		it("should return empty list when no pools exist", function()
			local pools = skill_config:listPools()
			assert.are.equal(0, #pools)
		end)
	end)

	describe("Incremental Pool Definition", function()
		it("should auto-create pools when skills are registered with pool arrays", function()
			-- Register skills with pool definitions
			helper.setupTestSkills({
				{id = "Skill1", shortName = "S1", fullName = "Skill 1", description = "Skill 1", saveVal = -1, pools = {"poolA", "poolB"}},
				{id = "Skill2", shortName = "S2", fullName = "Skill 2", description = "Skill 2", saveVal = -1, pools = {"poolB", "poolC"}},
			})

			-- Need to rebuild pools after registration
			helper.rebuildPools()

			-- Pools should appear in computed structure
			assert.is_not_nil(skill_config.pools.poolA)
			assert.is_not_nil(skill_config.pools.poolB)
			assert.is_not_nil(skill_config.pools.poolC)

			-- Skills should be in correct pools
			assert.is_true(skill_config.pools.poolA.skillIds.Skill1)
			assert.is_true(skill_config.pools.poolB.skillIds.Skill1)
			assert.is_true(skill_config.pools.poolB.skillIds.Skill2)
			assert.is_true(skill_config.pools.poolC.skillIds.Skill2)
		end)

		it("should handle adding skills to pools via setSkillConfig", function()
			-- Update skill config to add it to pool (this stores as code-defined)
			skill_config:setSkillConfig("Health", {pools = {"testPool"}})

			-- Need to rebuild pools after registration
			helper.rebuildPools()

			-- Verify skill is in pool
			assert.is_true(skill_config:isSkillInPool("Health", "testPool"))

			-- Verify source of truth - pools use dictionary structure
			assert.is_not_nil(skill_config.codeDefinedPools.Health)
			assert.is_true(skill_config.codeDefinedPools.Health.testPool)
		end)
	end)
end)
end)
