-- Tests for "fire once" behavior of assignment hooks
-- Verifies that hooks only fire once per pilot per run, even when
-- applySkillsToAllPilots() is called multiple times

local helper = require("helpers/plus_manager_helper")
local mocks = require("helpers/mocks")

-- Initialize the extension
local cplus_plus_ex = helper.plus_manager
local skill_selection = cplus_plus_ex._subobjects.skill_selection
local hooks = cplus_plus_ex.hooks

describe("Assignment Hooks Fire Once Behavior", function()
	local originalPreHooks, originalPostHooks, originalSelectedHooks
	local testPilots
	
	before_each(function()
		helper.resetState()
		
		-- Register test skills
		cplus_plus_ex:registerSkill("test", "TestSkill1", "TS1", "Test Skill 1", "Description")
		cplus_plus_ex:registerSkill("test", "TestSkill2", "TS2", "Test Skill 2", "Description")
		cplus_plus_ex:registerSkill("test", "TestSkill3", "TS3", "Test Skill 3", "Description")
		
		-- Create test pilots
		testPilots = {
			mocks.createMockPilot("Pilot_Test1"),
			mocks.createMockPilot("Pilot_Test2"),
			mocks.createMockPilot("Pilot_Test3")
		}
		
		-- Set up Game mock with pilots
		_G.Game.GetAvailablePilots = function() return testPilots end
		
		-- Save and clear hooks
		originalPreHooks = hooks.preAssigningLvlUpSkillsHooks
		originalPostHooks = hooks.postAssigningLvlUpSkillsHooks
		originalSelectedHooks = hooks.skillsSelectedHooks
		hooks.preAssigningLvlUpSkillsHooks = {}
		hooks.postAssigningLvlUpSkillsHooks = {}
		hooks.skillsSelectedHooks = {}
	end)
	
	after_each(function()
		-- Restore hooks
		if originalPreHooks then hooks.preAssigningLvlUpSkillsHooks = originalPreHooks end
		if originalPostHooks then hooks.postAssigningLvlUpSkillsHooks = originalPostHooks end
		if originalSelectedHooks then hooks.skillsSelectedHooks = originalSelectedHooks end
	end)
	
	describe("first call to applySkillsToAllPilots", function()
		it("should fire hooks for all pilots on first call", function()
			local preCount = 0
			local postCount = 0
			local selectedCount = 0
			
			cplus_plus_ex:addPreAssigningLvlUpSkillsHook(function()
				preCount = preCount + 1
			end)
			
			cplus_plus_ex:addPostAssigningLvlUpSkillsHook(function()
				postCount = postCount + 1
			end)
			
			cplus_plus_ex:addSkillsSelectedHook(function(pilot, skill1, skill2)
				selectedCount = selectedCount + 1
			end)
			
			-- First call - should fire hooks
			cplus_plus_ex:applySkillsToAllPilots()
			
			assert.are.equal(1, preCount, "Pre hook should fire once")
			assert.are.equal(1, postCount, "Post hook should fire once")
			assert.are.equal(3, selectedCount, "Selected hook should fire once per pilot (3 pilots)")
		end)
	end)
	
	describe("second call to applySkillsToAllPilots", function()
		it("should NOT fire hooks on second call with same pilots", function()
			local preCount = 0
			local postCount = 0
			local selectedCount = 0
			
			cplus_plus_ex:addPreAssigningLvlUpSkillsHook(function()
				preCount = preCount + 1
			end)
			
			cplus_plus_ex:addPostAssigningLvlUpSkillsHook(function()
				postCount = postCount + 1
			end)
			
			cplus_plus_ex:addSkillsSelectedHook(function(pilot, skill1, skill2)
				selectedCount = selectedCount + 1
			end)
			
			-- First call
			cplus_plus_ex:applySkillsToAllPilots()
			
			-- Second call - should NOT fire hooks
			cplus_plus_ex:applySkillsToAllPilots()
			
			assert.are.equal(1, preCount, "Pre hook should only fire once (first call)")
			assert.are.equal(1, postCount, "Post hook should only fire once (first call)")
			assert.are.equal(3, selectedCount, "Selected hook should only fire for first call")
		end)
		
		it("should fire hooks only for NEW pilots on subsequent calls", function()
			local preCount = 0
			local postCount = 0
			local selectedPilots = {}
			
			cplus_plus_ex:addPreAssigningLvlUpSkillsHook(function()
				preCount = preCount + 1
			end)
			
			cplus_plus_ex:addPostAssigningLvlUpSkillsHook(function()
				postCount = postCount + 1
			end)
			
			cplus_plus_ex:addSkillsSelectedHook(function(pilot, skill1, skill2)
				table.insert(selectedPilots, pilot:getIdStr())
			end)
			
			-- First call - 3 pilots
			cplus_plus_ex:applySkillsToAllPilots()
			assert.are.equal(3, #selectedPilots, "First call: 3 pilots selected")
			
			-- Add a new pilot to the game
			local newPilot = mocks.createMockPilot("Pilot_NewGuy")
			table.insert(testPilots, newPilot)
			_G.Game.GetAvailablePilots = function() return testPilots end
			
			-- Second call - should only fire hooks for new pilot
			cplus_plus_ex:applySkillsToAllPilots()
			
			assert.are.equal(2, preCount, "Pre hook should fire twice (once per batch with new pilots)")
			assert.are.equal(2, postCount, "Post hook should fire twice (once per batch with new pilots)")
			assert.are.equal(4, #selectedPilots, "Selected hook should fire 4 times total (3 + 1 new)")
			
			-- Verify the new pilot was the one assigned
			assert.are.equal("Pilot_NewGuy", selectedPilots[4], "New pilot should be selected")
		end)
	end)
	
	describe("pod pilot assignment", function()
		it("should fire hooks for new pod pilot", function()
			local preCount = 0
			local postCount = 0
			local selectedCount = 0
			
			cplus_plus_ex:addPreAssigningLvlUpSkillsHook(function()
				preCount = preCount + 1
			end)
			
			cplus_plus_ex:addPostAssigningLvlUpSkillsHook(function()
				postCount = postCount + 1
			end)
			
			cplus_plus_ex:addSkillsSelectedHook(function(pilot, skill1, skill2)
				selectedCount = selectedCount + 1
			end)
			
			-- Create and assign pod pilot
			local podPilot = mocks.createMockPilot("Pilot_PodReward")
			_G.Game.GetPodRewardPilot = function() return podPilot end
			
			skill_selection:applySkillToPodPilot()
			
			assert.are.equal(1, preCount, "Pre hook should fire for pod pilot")
			assert.are.equal(1, postCount, "Post hook should fire for pod pilot")
			assert.are.equal(1, selectedCount, "Selected hook should fire for pod pilot")
		end)
		
		it("should NOT fire hooks on second call for same pod pilot", function()
			local preCount = 0
			local postCount = 0
			local selectedCount = 0
			
			cplus_plus_ex:addPreAssigningLvlUpSkillsHook(function()
				preCount = preCount + 1
			end)
			
			cplus_plus_ex:addPostAssigningLvlUpSkillsHook(function()
				postCount = postCount + 1
			end)
			
			cplus_plus_ex:addSkillsSelectedHook(function(pilot, skill1, skill2)
				selectedCount = selectedCount + 1
			end)
			
			local podPilot = mocks.createMockPilot("Pilot_PodReward")
			_G.Game.GetPodRewardPilot = function() return podPilot end
			
			-- First call
			skill_selection:applySkillToPodPilot()
			
			-- Second call - should not fire hooks
			skill_selection:applySkillToPodPilot()
			
			assert.are.equal(1, preCount, "Pre hook should only fire once")
			assert.are.equal(1, postCount, "Post hook should only fire once")
			assert.are.equal(1, selectedCount, "Selected hook should only fire once")
		end)
	end)
	
	describe("perfect island pilot assignment", function()
		it("should fire hooks for new perfect island pilot", function()
			local preCount = 0
			local postCount = 0
			local selectedCount = 0
			
			cplus_plus_ex:addPreAssigningLvlUpSkillsHook(function()
				preCount = preCount + 1
			end)
			
			cplus_plus_ex:addPostAssigningLvlUpSkillsHook(function()
				postCount = postCount + 1
			end)
			
			cplus_plus_ex:addSkillsSelectedHook(function(pilot, skill1, skill2)
				selectedCount = selectedCount + 1
			end)
			
			-- Create and assign perfect island pilot
			local perfectPilot = mocks.createMockPilot("Pilot_PerfectIsland")
			_G.Game.GetPerfectIslandRewardPilot = function() return perfectPilot end
			
			skill_selection:applySkillToPerfectIslandPilot()
			
			assert.are.equal(1, preCount, "Pre hook should fire for perfect island pilot")
			assert.are.equal(1, postCount, "Post hook should fire for perfect island pilot")
			assert.are.equal(1, selectedCount, "Selected hook should fire for perfect island pilot")
		end)
		
		it("should NOT fire hooks on second call for same perfect island pilot", function()
			local preCount = 0
			local postCount = 0
			local selectedCount = 0
			
			cplus_plus_ex:addPreAssigningLvlUpSkillsHook(function()
				preCount = preCount + 1
			end)
			
			cplus_plus_ex:addPostAssigningLvlUpSkillsHook(function()
				postCount = postCount + 1
			end)
			
			cplus_plus_ex:addSkillsSelectedHook(function(pilot, skill1, skill2)
				selectedCount = selectedCount + 1
			end)
			
			local perfectPilot = mocks.createMockPilot("Pilot_PerfectIsland")
			_G.Game.GetPerfectIslandRewardPilot = function() return perfectPilot end
			
			-- First call
			skill_selection:applySkillToPerfectIslandPilot()
			
			-- Second call (e.g., menu reopened) - should not fire hooks
			skill_selection:applySkillToPerfectIslandPilot()
			
			assert.are.equal(1, preCount, "Pre hook should only fire once")
			assert.are.equal(1, postCount, "Post hook should only fire once")
			assert.are.equal(1, selectedCount, "Selected hook should only fire once")
		end)
	end)
end)
