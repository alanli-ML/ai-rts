# TestCompleteAIPipeline.gd
# Comprehensive test for the entire AI control pipeline:
# User Input → AICommandProcessor → OpenAI API → Command Translation → Game Execution
extends Node

# Core AI system components
var ai_command_processor: AICommandProcessor = null
var command_translator: CommandTranslator = null
var action_validator: ActionValidator = null
var plan_executor: PlanExecutor = null
var selection_manager: SelectionManager = null

# Test data and state
var test_units: Array = []
var test_commands: Array = []
var test_results: Dictionary = {}
var current_test_index: int = 0

# Test scenarios
var test_scenarios: Array = [
	{
		"name": "Basic Movement Command",
		"user_prompt": "Move the selected units to the strategic position near the base",
		"expected_type": "direct_commands",
		"expected_action": "MOVE"
	},
	{
		"name": "Attack Command",
		"user_prompt": "Attack the enemy units with selected scouts",
		"expected_type": "direct_commands", 
		"expected_action": "ATTACK"
	},
	{
		"name": "Formation Command",
		"user_prompt": "Arrange units in line formation for defensive stance",
		"expected_type": "direct_commands",
		"expected_action": "FORMATION"
	},
	{
		"name": "Multi-Step Tactical Plan",
		"user_prompt": "Scout ahead, then attack if enemies are weak, retreat if health is low",
		"expected_type": "multi_step_plan",
		"expected_actions": ["move_to", "attack", "retreat"]
	},
	{
		"name": "Conditional Retreat Plan",
		"user_prompt": "If health drops below 30%, retreat to safety and heal",
		"expected_type": "multi_step_plan",
		"expected_triggers": ["health_pct < 30"]
	},
	{
		"name": "Complex Tactical Coordination",
		"user_prompt": "Set up defensive positions, watch for enemies, attack when they're close but retreat if outnumbered",
		"expected_type": "multi_step_plan",
		"expected_actions": ["formation", "overwatch", "attack", "retreat"]
	}
]

# Signals for test coordination
signal test_completed(test_name: String, success: bool, details: Dictionary)
signal pipeline_test_finished(overall_success: bool, results: Array)

func _ready() -> void:
	print("=== COMPLETE AI PIPELINE TEST INITIALIZING ===")
	
	# Wait for scene to be ready
	await get_tree().process_frame
	
	# Initialize AI system components
	await _initialize_ai_components()
	
	# Find or create test units
	await _setup_test_units()
	
	# Display test controls
	_print_test_controls()
	
	print("=== AI PIPELINE TEST READY ===")
	print("Press SPACE to start the complete pipeline test")
	print("Press 1-6 to test individual scenarios")
	print("Press R to check system readiness")

func _initialize_ai_components() -> void:
	"""Initialize all AI system components"""
	print("Initializing AI system components...")
	
	# Create ActionValidator
	action_validator = ActionValidator.new()
	action_validator.name = "ActionValidator"
	add_child(action_validator)
	
	# Create PlanExecutor
	plan_executor = PlanExecutor.new()
	plan_executor.name = "PlanExecutor" 
	add_child(plan_executor)
	
	# Create CommandTranslator
	command_translator = CommandTranslator.new()
	command_translator.name = "CommandTranslator"
	add_child(command_translator)
	
	# Create AICommandProcessor
	ai_command_processor = AICommandProcessor.new()
	ai_command_processor.name = "AICommandProcessor"
	add_child(ai_command_processor)
	
	# Setup dependencies
	ai_command_processor.setup(null, null, action_validator, plan_executor)
	
	# Connect signals for monitoring
	ai_command_processor.command_processed.connect(_on_command_processed)
	ai_command_processor.plan_processed.connect(_on_plan_processed)
	ai_command_processor.command_failed.connect(_on_command_failed)
	ai_command_processor.processing_started.connect(_on_processing_started)
	ai_command_processor.processing_finished.connect(_on_processing_finished)
	
	command_translator.command_executed.connect(_on_command_executed)
	command_translator.command_failed.connect(_on_command_translation_failed)
	
	plan_executor.plan_started.connect(_on_plan_started)
	plan_executor.plan_completed.connect(_on_plan_completed)
	plan_executor.step_executed.connect(_on_step_executed)
	
	print("AI system components initialized and connected")

func _setup_test_units() -> void:
	"""Find existing units or create test units"""
	# Try to find existing units
	test_units = get_tree().get_nodes_in_group("units")
	
	if test_units.size() == 0:
		print("No existing units found, creating test units...")
		await _create_test_units()
	else:
		print("Found %d existing units for testing" % test_units.size())
	
	# Create mock selection manager if needed
	if not selection_manager:
		selection_manager = _create_mock_selection_manager()

func _create_test_units() -> void:
	"""Create test units for the pipeline test"""
	var unit_archetypes = ["scout", "soldier", "sniper", "medic", "engineer"]
	var spawn_positions = [
		Vector3(0, 0, 0),
		Vector3(5, 0, 0), 
		Vector3(10, 0, 0),
		Vector3(0, 0, 5),
		Vector3(5, 0, 5)
	]
	
	# Try to load the AnimatedUnit scene
	var unit_scene_path = "res://scenes/units/Unit.tscn"
	var unit_scene = load(unit_scene_path)
	
	if not unit_scene:
		print("Could not load unit scene, creating simple test units")
		await _create_simple_test_units()
		return
	
	for i in range(min(unit_archetypes.size(), spawn_positions.size())):
		var unit = unit_scene.instantiate()
		unit.name = "TestUnit_%s" % unit_archetypes[i]
		unit.position = spawn_positions[i]
		
		# Set archetype if the unit supports it
		if unit.has_method("set_archetype"):
			unit.set_archetype(unit_archetypes[i])
		elif "archetype" in unit:
			unit.archetype = unit_archetypes[i]
		
		# Add to groups
		unit.add_to_group("units")
		unit.add_to_group("test_units")
		
		# Add to scene
		add_child(unit)
		test_units.append(unit)
		
		print("Created test unit: %s at %s" % [unit_archetypes[i], spawn_positions[i]])

func _create_simple_test_units() -> void:
	"""Create simple test units as fallback"""
	var archetypes = ["scout", "soldier", "medic"]
	
	for i in range(3):
		var unit = Node3D.new()
		unit.name = "SimpleTestUnit_%s" % archetypes[i]
		unit.position = Vector3(i * 3, 0, 0)
		
		# Add required methods and properties
		unit.set_script(SimpleTestUnit)
		unit.archetype = archetypes[i]
		unit.team_id = 1
		unit.current_health = 100
		unit.max_health = 100
		
		# Add to groups
		unit.add_to_group("units")
		unit.add_to_group("test_units")
		
		add_child(unit)
		test_units.append(unit)

func _create_mock_selection_manager() -> SelectionManager:
	"""Create a mock selection manager for testing"""
	var mock_manager = Node.new()
	mock_manager.name = "MockSelectionManager"
	mock_manager.set_script(MockSelectionManager)
	mock_manager.selected_units = test_units.slice(0, 2) if test_units.size() >= 2 else test_units
	add_child(mock_manager)
	return mock_manager

func _input(event: InputEvent) -> void:
	"""Handle input for testing"""
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_SPACE:
				start_complete_pipeline_test()
			KEY_1:
				test_individual_scenario(0)
			KEY_2:
				test_individual_scenario(1)
			KEY_3:
				test_individual_scenario(2)
			KEY_4:
				test_individual_scenario(3)
			KEY_5:
				test_individual_scenario(4)
			KEY_6:
				test_individual_scenario(5)
			KEY_R:
				check_system_readiness()
			KEY_A:
				test_openai_api_directly()
			KEY_S:
				show_test_statistics()
			KEY_C:
				clear_test_results()
			KEY_H:
				_print_test_controls()

func start_complete_pipeline_test() -> void:
	"""Start the complete pipeline test for all scenarios"""
	print("\n=== STARTING COMPLETE AI PIPELINE TEST ===")
	
	if not _check_system_readiness():
		print("ERROR: System not ready for testing!")
		return
	
	current_test_index = 0
	test_results.clear()
	
	await _run_all_scenarios()
	
	_display_final_results()

func _run_all_scenarios() -> void:
	"""Run all test scenarios sequentially"""
	for i in range(test_scenarios.size()):
		var scenario = test_scenarios[i]
		print("\n--- Testing Scenario %d: %s ---" % [i + 1, scenario.name])
		
		var result = await _test_scenario(scenario)
		test_results[scenario.name] = result
		
		# Wait between tests
		await get_tree().create_timer(2.0).timeout

func test_individual_scenario(index: int) -> void:
	"""Test an individual scenario"""
	if index < 0 or index >= test_scenarios.size():
		print("Invalid scenario index: %d" % index)
		return
	
	var scenario = test_scenarios[index]
	print("\n--- Testing Individual Scenario: %s ---" % scenario.name)
	
	if not _check_system_readiness():
		print("ERROR: System not ready for testing!")
		return
	
	var result = await _test_scenario(scenario)
	print("Individual test result: %s" % ("SUCCESS" if result.success else "FAILED"))

func _test_scenario(scenario: Dictionary) -> Dictionary:
	"""Test a single scenario through the complete pipeline"""
	var start_time = Time.get_ticks_msec()
	var result = {
		"success": false,
		"scenario": scenario.name,
		"user_prompt": scenario.user_prompt,
		"ai_response": null,
		"commands_generated": [],
		"commands_executed": [],
		"execution_time": 0,
		"errors": []
	}
	
	print("Testing: %s" % scenario.user_prompt)
	
	# Step 1: Get selected units
	var selected_units = _get_selected_units()
	if selected_units.is_empty():
		result.errors.append("No units selected")
		return result
	
	# Step 2: Build game state
	var game_state = _build_test_game_state()
	
	# Step 3: Process command through AI
	var ai_response = await _process_ai_command(scenario.user_prompt, selected_units, game_state)
	
	if not ai_response:
		result.errors.append("AI command processing failed")
		return result
	
	result.ai_response = ai_response
	
	# Step 4: Validate response type
	if not _validate_ai_response(ai_response, scenario):
		result.errors.append("AI response validation failed")
		return result
	
	# Step 5: Execute commands/plans
	var execution_success = await _execute_ai_response(ai_response)
	
	if execution_success:
		result.success = true
		result.execution_time = Time.get_ticks_msec() - start_time
		print("Scenario completed successfully in %d ms" % result.execution_time)
	else:
		result.errors.append("Command execution failed")
	
	return result

func _process_ai_command(user_prompt: String, selected_units: Array, game_state: Dictionary) -> Dictionary:
	"""Process command through the AI system and wait for response"""
	var ai_response = null
	var response_received = false
	
	# Connect to response signals
	var command_callback = func(commands: Array, message: String):
		ai_response = {"type": "direct_commands", "commands": commands, "message": message}
		response_received = true
	
	var plan_callback = func(plans: Array, message: String):
		ai_response = {"type": "multi_step_plan", "plans": plans, "message": message}
		response_received = true
	
	var error_callback = func(error: String):
		ai_response = {"type": "error", "error": error}
		response_received = true
	
	ai_command_processor.command_processed.connect(command_callback, CONNECT_ONE_SHOT)
	ai_command_processor.plan_processed.connect(plan_callback, CONNECT_ONE_SHOT)
	ai_command_processor.command_failed.connect(error_callback, CONNECT_ONE_SHOT)
	
	# Send command to AI processor
	ai_command_processor.process_command(user_prompt, selected_units, game_state)
	
	# Wait for response (with timeout)
	var timeout = 30.0  # 30 second timeout
	var elapsed = 0.0
	var check_interval = 0.1
	
	while not response_received and elapsed < timeout:
		await get_tree().create_timer(check_interval).timeout
		elapsed += check_interval
	
	if not response_received:
		print("AI command processing timed out after %d seconds" % timeout)
		return null
	
	return ai_response

func _validate_ai_response(response: Dictionary, scenario: Dictionary) -> bool:
	"""Validate the AI response matches expected scenario"""
	if response.get("type") == "error":
		print("AI returned error: %s" % response.get("error", "Unknown error"))
		return false
	
	# Check response type
	var expected_type = scenario.get("expected_type", "")
	var actual_type = response.get("type", "")
	
	if expected_type != "" and actual_type != expected_type:
		print("Response type mismatch: expected %s, got %s" % [expected_type, actual_type])
		return false
	
	# Check specific actions for direct commands
	if actual_type == "direct_commands":
		var commands = response.get("commands", [])
		if commands.is_empty():
			print("No commands in direct command response")
			return false
		
		var expected_action = scenario.get("expected_action", "")
		if expected_action != "":
			var found_action = false
			for command in commands:
				if command.get("action", "") == expected_action:
					found_action = true
					break
			
			if not found_action:
				print("Expected action %s not found in commands" % expected_action)
				return false
	
	# Check plans for multi-step responses
	elif actual_type == "multi_step_plan":
		var plans = response.get("plans", [])
		if plans.is_empty():
			print("No plans in multi-step response")
			return false
	
	print("AI response validation passed")
	return true

func _execute_ai_response(response: Dictionary) -> bool:
	"""Execute the AI response through the command/plan system"""
	var response_type = response.get("type", "")
	
	match response_type:
		"direct_commands":
			return await _execute_direct_commands(response.get("commands", []))
		"multi_step_plan":
			return await _execute_multi_step_plans(response.get("plans", []))
		_:
			print("Unknown response type for execution: %s" % response_type)
			return false

func _execute_direct_commands(commands: Array) -> bool:
	"""Execute direct commands through CommandTranslator"""
	if commands.is_empty():
		return false
	
	var execution_success = true
	
	for command in commands:
		var command_id = command_translator.execute_command(command)
		print("Executing direct command: %s (ID: %d)" % [command.get("action", "unknown"), command_id])
		
		# Wait a bit for execution
		await get_tree().create_timer(1.0).timeout
	
	return execution_success

func _execute_multi_step_plans(plans: Array) -> bool:
	"""Execute multi-step plans through PlanExecutor"""
	if plans.is_empty():
		return false
	
	var execution_success = true
	
	for plan in plans:
		var unit_id = plan.get("unit_id", "")
		if unit_id == "":
			print("Plan missing unit_id")
			execution_success = false
			continue
		
		var success = plan_executor.execute_plan(unit_id, plan)
		print("Executing plan for unit %s: %s" % [unit_id, "SUCCESS" if success else "FAILED"])
		
		if not success:
			execution_success = false
		
		# Wait for plan to start
		await get_tree().create_timer(1.0).timeout
	
	return execution_success

func test_openai_api_directly() -> void:
	"""Test OpenAI API directly without game integration"""
	print("\n=== TESTING OPENAI API DIRECTLY ===")
	
	if not ai_command_processor.openai_client:
		print("ERROR: OpenAI client not available")
		return
	
	# Test simple API call
	var test_messages = [
		{
			"role": "system",
			"content": "You are a helpful assistant. Respond with a simple JSON object containing a 'message' field."
		},
		{
			"role": "user",
			"content": "Test API connectivity with a simple response."
		}
	]
	
	var response_received = false
	var api_response = null
	
	var callback = func(response: Dictionary, error_type, error_message: String):
		api_response = response
		response_received = true
		if error_type != ai_command_processor.openai_client.APIError.NONE:
			print("API Error: %s" % error_message)
		else:
			print("API Response received successfully")
	
	ai_command_processor.openai_client.send_chat_completion(test_messages, callback)
	
	# Wait for response
	var timeout = 15.0
	var elapsed = 0.0
	
	while not response_received and elapsed < timeout:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1
	
	if response_received and api_response:
		print("OpenAI API test successful!")
		var content = api_response.get("choices", [{}])[0].get("message", {}).get("content", "")
		print("Response content: %s" % content)
	else:
		print("OpenAI API test failed - no response received")

func check_system_readiness() -> bool:
	"""Check if all systems are ready for testing"""
	print("\n=== SYSTEM READINESS CHECK ===")
	
	var ready = true
	var checks = []
	
	# Check AI components
	checks.append({"name": "AICommandProcessor", "ready": ai_command_processor != null})
	checks.append({"name": "CommandTranslator", "ready": command_translator != null})
	checks.append({"name": "ActionValidator", "ready": action_validator != null})
	checks.append({"name": "PlanExecutor", "ready": plan_executor != null})
	
	# Check OpenAI client
	var openai_ready = ai_command_processor != null and ai_command_processor.openai_client != null
	checks.append({"name": "OpenAI Client", "ready": openai_ready})
	
	# Check API key
	var api_key_set = false
	if openai_ready:
		api_key_set = ai_command_processor.openai_client.api_key != ""
	checks.append({"name": "OpenAI API Key", "ready": api_key_set})
	
	# Check test units
	checks.append({"name": "Test Units", "ready": test_units.size() > 0})
	
	# Display results
	for check in checks:
		var status = "✓" if check.ready else "✗"
		print("  %s %s" % [status, check.name])
		if not check.ready:
			ready = false
	
	print("\nOverall system status: %s" % ("READY" if ready else "NOT READY"))
	
	if not ready:
		print("\nTo fix:")
		if not api_key_set:
			print("  - Set OPENAI_API_KEY environment variable")
		if test_units.size() == 0:
			print("  - Add units to the scene or press R to create test units")
	
	return ready

func _check_system_readiness() -> bool:
	"""Internal readiness check"""
	return (ai_command_processor != null and 
			command_translator != null and 
			action_validator != null and 
			plan_executor != null and
			test_units.size() > 0)

func _get_selected_units() -> Array:
	"""Get currently selected units for testing"""
	if selection_manager and selection_manager.has_method("get_selected_units"):
		return selection_manager.get_selected_units()
	
	# Fallback: return first 2 test units
	return test_units.slice(0, min(2, test_units.size()))

func _build_test_game_state() -> Dictionary:
	"""Build test game state for AI context"""
	var game_state = {
		"timestamp": Time.get_ticks_msec() / 1000.0,
		"units": [],
		"teams": {
			"1": {"energy": 100, "materials": 50},
			"2": {"energy": 80, "materials": 30}
		},
		"map_info": {
			"size": Vector2(100, 100),
			"control_points": 9
		}
	}
	
	# Add unit information
	for unit in test_units:
		if unit and is_instance_valid(unit):
			var unit_info = {
				"id": unit.name,
				"archetype": unit.get("archetype", "unknown"),
				"position": unit.global_position,
				"health": 100,
				"team_id": unit.get("team_id", 1)
			}
			game_state.units.append(unit_info)
	
	return game_state

func _display_final_results() -> void:
	"""Display final test results"""
	print("\n=== COMPLETE AI PIPELINE TEST RESULTS ===")
	
	var total_tests = test_results.size()
	var successful_tests = 0
	
	for scenario_name in test_results:
		var result = test_results[scenario_name]
		var status = "SUCCESS" if result.success else "FAILED"
		print("  %s: %s" % [scenario_name, status])
		
		if result.success:
			successful_tests += 1
			print("    Execution time: %d ms" % result.execution_time)
		else:
			print("    Errors: %s" % str(result.errors))
	
	var success_rate = float(successful_tests) / float(total_tests) * 100.0 if total_tests > 0 else 0.0
	print("\nOverall Success Rate: %.1f%% (%d/%d)" % [success_rate, successful_tests, total_tests])
	
	if success_rate >= 80.0:
		print("🎉 AI PIPELINE TEST PASSED!")
	else:
		print("❌ AI PIPELINE TEST NEEDS IMPROVEMENT")
	
	pipeline_test_finished.emit(success_rate >= 80.0, test_results.values())

func show_test_statistics() -> void:
	"""Show detailed test statistics"""
	print("\n=== AI PIPELINE TEST STATISTICS ===")
	
	if test_results.is_empty():
		print("No test results available. Run tests first.")
		return
	
	var total_execution_time = 0
	var command_types = {}
	var error_categories = {}
	
	for scenario_name in test_results:
		var result = test_results[scenario_name]
		total_execution_time += result.execution_time
		
		# Categorize errors
		for error in result.errors:
			error_categories[error] = error_categories.get(error, 0) + 1
	
	print("Total execution time: %d ms" % total_execution_time)
	print("Average execution time: %.1f ms" % (total_execution_time / float(test_results.size())))
	
	if not error_categories.is_empty():
		print("\nError breakdown:")
		for error in error_categories:
			print("  %s: %d occurrences" % [error, error_categories[error]])

func clear_test_results() -> void:
	"""Clear all test results"""
	test_results.clear()
	print("Test results cleared")

func _print_test_controls() -> void:
	"""Print available test controls"""
	print("\n=== AI PIPELINE TEST CONTROLS ===")
	print("  SPACE - Run complete pipeline test (all scenarios)")
	print("  1-6   - Test individual scenarios")
	print("  R     - Check system readiness")
	print("  A     - Test OpenAI API directly")
	print("  S     - Show test statistics")
	print("  C     - Clear test results")
	print("  H     - Show this help")
	print("\nTest Scenarios:")
	for i in range(test_scenarios.size()):
		print("  %d. %s" % [i + 1, test_scenarios[i].name])

# Signal handlers for monitoring pipeline execution
func _on_processing_started() -> void:
	print("  → AI processing started...")

func _on_processing_finished() -> void:
	print("  → AI processing finished")

func _on_command_processed(commands: Array, message: String) -> void:
	print("  → Commands processed: %d commands (%s)" % [commands.size(), message])

func _on_plan_processed(plans: Array, message: String) -> void:
	print("  → Plans processed: %d plans (%s)" % [plans.size(), message])

func _on_command_failed(error: String) -> void:
	print("  ✗ Command failed: %s" % error)

func _on_command_executed(command_id: int, result: String) -> void:
	print("  → Command executed (ID %d): %s" % [command_id, result])

func _on_command_translation_failed(command_id: int, error: String) -> void:
	print("  ✗ Command translation failed (ID %d): %s" % [command_id, error])

func _on_plan_started(unit_id: String, plan: Array) -> void:
	print("  → Plan started for unit %s: %d steps" % [unit_id, plan.size()])

func _on_plan_completed(unit_id: String, success: bool) -> void:
	var status = "completed" if success else "failed"
	print("  → Plan %s for unit %s" % [status, unit_id])

func _on_step_executed(unit_id: String, step) -> void:
	print("  → Step executed for unit %s: %s" % [unit_id, step.action if step.has("action") else "unknown"])

# Helper classes for simple test units
class SimpleTestUnit:
	extends Node3D
	
	var archetype: String = "test"
	var team_id: int = 1
	var current_health: int = 100
	var max_health: int = 100
	var unit_state: String = "idle"
	
	func get_unit_id() -> String:
		return name
	
	func get_team_id() -> int:
		return team_id
	
	func get_health_percentage() -> float:
		return float(current_health) / float(max_health) * 100.0
	
	func get_current_state() -> String:
		return unit_state
	
	func move_to(target_position: Vector3) -> void:
		unit_state = "moving"
		print("Unit %s moving to %s" % [name, target_position])
	
	func attack_target(target) -> void:
		unit_state = "attacking"
		print("Unit %s attacking target" % name)

# Mock selection manager for testing
class MockSelectionManager:
	extends Node
	
	var selected_units: Array = []
	
	func get_selected_units() -> Array:
		return selected_units
	
	func select_unit(unit) -> void:
		if unit not in selected_units:
			selected_units.append(unit)
	
	func deselect_unit(unit) -> void:
		selected_units.erase(unit)
	
	func clear_selection() -> void:
		selected_units.clear() 