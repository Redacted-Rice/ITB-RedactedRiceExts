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

describe("Category Management", function()
	before_each(function()
		skill_config.categories = {}
		skill_config.config.categoryDescriptions = {}
		-- Register test skills
		helper.setupTestSkills({
			{id = "Health", shortName = "Health", fullName = "Health", description = "Health", saveVal = -1},
			{id = "Move", shortName = "Move", fullName = "Move", description = "Move", saveVal = -1},
		})
	end)


	describe("deleteCategory", function()
		it("should delete category from all skills", function()
			-- Add skill to category
			skill_config:addSkillToCategory("Health", "testCategory")
			assert.is_true(skill_config:isSkillInCategory("Health", "testCategory"))

			local result = skill_config:deleteCategory("testCategory")
			assert.is_true(result)

			-- Verify category removed from computed structure
			assert.is_nil(skill_config.categories.testCategory)

			-- Verify category removed from categoriesAdded
			assert.is_false(skill_config.config.categoriesAdded.Health and skill_config.config.categoriesAdded.Health.testCategory == true)
		end)

		it("should always succeed even if category doesn't exist", function()
			local result = skill_config:deleteCategory("nonExistent")
			assert.is_true(result)
		end)
	end)

	describe("addSkillToCategory", function()
		it("should add a skill to a category", function()
			local result = skill_config:addSkillToCategory("Health", "testCategory")
			assert.is_true(result)

			-- Check computed structure
			assert.is_not_nil(skill_config.categories.testCategory)
			assert.is_true(skill_config.categories.testCategory.skillIds.Health)

			-- Verify source of truth - categories use dictionary structure
			assert.is_not_nil(skill_config.config.categoriesAdded.Health)
			assert.is_true(skill_config.config.categoriesAdded.Health.testCategory)
		end)

		it("should auto-create category in computed structure", function()
			local result = skill_config:addSkillToCategory("Health", "autoCategory")
			assert.is_true(result)
			assert.is_not_nil(skill_config.categories.autoCategory)
			assert.is_true(skill_config.categories.autoCategory.skillIds.Health)
		end)

		it("should reject if skill doesn't exist", function()
			local result = skill_config:addSkillToCategory("FakeSkill", "testCategory")
			assert.is_false(result)
		end)
	end)

	describe("removeSkillFromCategory", function()
		it("should remove a skill from a category", function()
			skill_config:addSkillToCategory("Health", "testCategory")

			local result = skill_config:removeSkillFromCategory("Health", "testCategory")
			assert.is_true(result)

			-- Check computed structure
			assert.is_false(skill_config:isSkillInCategory("Health", "testCategory"))

			-- Verify skill's categories array is updated
			local skillConfig = skill_config.config.skillConfigs.Health
			local foundInArray = false
			for _, pName in ipairs(skillConfig.categories or {}) do
				if pName == "testCategory" then
					foundInArray = true
					break
				end
			end
			assert.is_false(foundInArray)
		end)

		it("should succeed even if category doesn't exist", function()
			local result = skill_config:removeSkillFromCategory("Health", "nonExistent")
			assert.is_true(result)
		end)
	end)

	describe("isSkillInCategory", function()
		it("should check if skill is in category", function()
			skill_config:addSkillToCategory("Health", "testCategory")

			assert.is_true(skill_config:isSkillInCategory("Health", "testCategory"))
			assert.is_false(skill_config:isSkillInCategory("Move", "testCategory"))
		end)

		it("should return false for non-existent category", function()
			assert.is_false(skill_config:isSkillInCategory("Health", "nonExistent"))
		end)
	end)

	describe("listCategories", function()
		it("should list all categories alphabetically from computed structure", function()
			-- Count categories before adding test categories (vanilla skills may have categories)
			local categoriesBefore = skill_config:listCategories()
			local countBefore = #categoriesBefore

			-- Add skills to categories
			skill_config:addSkillToCategory("Health", "zCategory")
			skill_config:addSkillToCategory("Health", "aCategory")
			skill_config:addSkillToCategory("Move", "mCategory")

			local categories = skill_config:listCategories()
			-- Should have 3 more categories than before
			assert.are.equal(countBefore + 3, #categories)

			-- Verify our categories are in the list and sorted
			local foundACategory = false
			local foundMCategory = false
			local foundZCategory = false
			for _, categoryName in ipairs(categories) do
				if categoryName == "aCategory" then foundACategory = true end
				if categoryName == "mCategory" then foundMCategory = true end
				if categoryName == "zCategory" then foundZCategory = true end
			end
			assert.is_true(foundACategory, "aCategory should be in list")
			assert.is_true(foundMCategory, "mCategory should be in list")
			assert.is_true(foundZCategory, "zCategory should be in list")

			-- Verify alphabetical sorting
			for i = 2, #categories do
				assert.is_true(categories[i-1] < categories[i], "Categories should be sorted alphabetically")
			end
		end)

		it("should return empty list when no categories exist", function()
			local categories = skill_config:listCategories()
			assert.are.equal(0, #categories)
		end)
	end)

	describe("Incremental Category Definition", function()
		it("should auto-create categories when skills are registered with category arrays", function()
			-- Register skills with category definitions
			helper.setupTestSkills({
				{id = "Skill1", shortName = "S1", fullName = "Skill 1", description = "Skill 1", saveVal = -1, categories = {"categoryA", "categoryB"}},
				{id = "Skill2", shortName = "S2", fullName = "Skill 2", description = "Skill 2", saveVal = -1, categories = {"categoryB", "categoryC"}},
			})

			-- Need to rebuild categories after registration
			helper.rebuildCategories()

			-- Categories should appear in computed structure
			assert.is_not_nil(skill_config.categories.categoryA)
			assert.is_not_nil(skill_config.categories.categoryB)
			assert.is_not_nil(skill_config.categories.categoryC)

			-- Skills should be in correct categories
			assert.is_true(skill_config.categories.categoryA.skillIds.Skill1)
			assert.is_true(skill_config.categories.categoryB.skillIds.Skill1)
			assert.is_true(skill_config.categories.categoryB.skillIds.Skill2)
			assert.is_true(skill_config.categories.categoryC.skillIds.Skill2)
		end)

		it("should handle adding skills to categories via setSkillConfig", function()
			-- Update skill config to add it to category (this stores as code-defined)
			skill_config:setSkillConfig("Health", {categories = {"testCategory"}})

			-- Need to rebuild categories after registration
			helper.rebuildCategories()

			-- Verify skill is in category
			assert.is_true(skill_config:isSkillInCategory("Health", "testCategory"))

			-- Verify source of truth - categories use dictionary structure
			assert.is_not_nil(skill_config.codeDefinedCategories.Health)
			assert.is_true(skill_config.codeDefinedCategories.Health.testCategory)
		end)
	end)
end)
end)
