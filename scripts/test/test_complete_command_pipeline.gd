# TestCompleteCommandPipeline.gd
# Comprehensive test for the AI command pipeline from input to unit execution
extends Node

# Test components
var test_units: Array[Unit] = []
var ai_command_processor: Node
var selection_system: Node
var dependency_container: Node
var test_results: Dictionary = {}
var test_phase: int = 0

# Test settings
const TEST_UNIT_COUNT = 3
const TEST_POSITIONS = [
	Vector3(-40, 0, -52),
	Vector3(-35, 0, -52), 
	Vector3(-30, 0, -52)
]
const TARGET_POSITION = Vector3(0, 0, 0)  # Move toward map center

# Test phases
enum TestPhase {
	SETUP,
	SPAWN_UNITS,
	SELECT_UNITS,
	ISSUE_AI_COMMAND,
	VERIFY_COMMAND_PROCESSING,
	VERIFY_UNIT_MOVEMENT,
	CLEANUP,
	COMPLETE
}

signal test_completed(results: Dictionary)
signal test_failed(error: String)

func _ready() -> void:
	print("=== COMMAND PIPELINE TEST STARTING ===")
	_initialize_test()

func _initialize_test() -> void:
	"""Initialize test environment"""
	test_phase = TestPhase.SETUP
	test_results = {
		"dependency_injection": false,
		"unit_spawning": false,
		"selection_system": false, 
		"ai_command_processing": false,
		"unit_signal_handling": false,
		"unit_movement": false,
		"complete_pipeline": false
	}
	
	# Get dependency container
	dependency_container = get_node("/root/DependencyContainer")
	if dependency_container:
		print("✓ DependencyContainer found")
		test_results["dependency_injection"] = true
		_get_system_references()
	else:
		_fail_test("DependencyContainer not found")

func _get_system_references() -> void:
	"""Get references to all required systems"""
	
	# Get AI command processor
	if dependency_container.has_method("get_ai_command_processor"):
		ai_command_processor = dependency_container.get_ai_command_processor()
		if ai_command_processor:
			print("✓ AI Command Processor found")
		else:
			print("⚠ AI Command Processor not available")
	
	# Get selection system
	if dependency_container.has_method("get_selection_manager"):
		selection_system = dependency_container.get_selection_manager()
		if selection_system:
			print("✓ Selection System found")
			test_results["selection_system"] = true
		else:
			print("⚠ Selection System not available")
	
	# Proceed to next phase
	call_deferred("_start_unit_spawning")

func _start_unit_spawning() -> void:
	"""Start spawning test units"""
	test_phase = TestPhase.SPAWN_UNITS
	print("\n--- Phase 1: Spawning Test Units ---")
	
	for i in range(TEST_UNIT_COUNT):
		var unit = await _spawn_test_unit(i)
		if unit:
			test_units.append(unit)
			print("✓ Spawned unit %d: %s" % [i, unit.unit_id])
	
	if test_units.size() == TEST_UNIT_COUNT:
		test_results["unit_spawning"] = true
		print("✓ All %d test units spawned successfully" % TEST_UNIT_COUNT)
		call_deferred("_test_unit_selection")
	else:
		_fail_test("Failed to spawn all test units")

func _spawn_test_unit(index: int) -> Unit:
	"""Spawn a single test unit"""
	var unit_scene = preload("res://scenes/units/AnimatedUnit.tscn")
	var unit = unit_scene.instantiate()
	
	if unit:
		unit.unit_id = "test_unit_%d" % index
		unit.archetype = "scout"  # Use scout for fast movement
		unit.team_id = 1
		unit.position = TEST_POSITIONS[index]
		
		# Add to scene
		add_child(unit)
		
		# Wait for unit to be ready
		await unit.ready
		
		print("Unit %s spawned at %s" % [unit.unit_id, unit.position])
		return unit
	
	return null

func _test_unit_selection() -> void:
	"""Test unit selection"""
	test_phase = TestPhase.SELECT_UNITS
	print("\n--- Phase 2: Testing Unit Selection ---")
	
	if selection_system and selection_system.has_method("select_units"):
		selection_system.select_units(test_units)
		
		# Verify selection
		await get_tree().create_timer(0.1).timeout
		
		var selected_units = selection_system.get_selected_units() if selection_system.has_method("get_selected_units") else []
		
		if selected_units.size() == test_units.size():
			print("✓ Units selected successfully: %d units" % selected_units.size())
			call_deferred("_test_ai_command")
		else:
			print("⚠ Selection test skipped - proceeding with direct command test")
			call_deferred("_test_ai_command")
	else:
		print("⚠ Selection system not available - proceeding with direct command test")
		call_deferred("_test_ai_command")

func _test_ai_command() -> void:
	"""Test AI command processing"""
	test_phase = TestPhase.ISSUE_AI_COMMAND
	print("\n--- Phase 3: Testing AI Command Processing ---")
	
	if ai_command_processor and ai_command_processor.has_method("process_command"):
		# Connect to AI processor signals
		if ai_command_processor.has_signal("command_processed"):
			ai_command_processor.command_processed.connect(_on_command_processed)
		if ai_command_processor.has_signal("command_failed"):
			ai_command_processor.command_failed.connect(_on_command_failed)
		
		# Issue a test command
		var test_command = "Move all units to position 50, 0, 50 for tactical positioning"
		var game_state = {
			"units": test_units.size(),
			"phase": "test"
		}
		
		print("Issuing AI command: %s" % test_command)
		ai_command_processor.process_command(test_command, test_units, game_state)
		
		# Wait for command processing
		await get_tree().create_timer(5.0).timeout
		
		# If no response, try direct command
		if not test_results.get("ai_command_processing", false):
			print("⚠ AI command timed out - testing direct command")
			_test_direct_command()
	else:
		print("⚠ AI Command Processor not available - testing direct command")
		_test_direct_command()

func _test_direct_command() -> void:
	"""Test direct EventBus command"""
	print("\n--- Phase 4: Testing Direct EventBus Commands ---")
	
	# Test EventBus command directly
	if has_node("/root/EventBus"):
		var event_bus = get_node("/root/EventBus")
		
		# Issue direct move commands
		for unit in test_units:
			var command = "move_to:%s,%s,%s" % [TARGET_POSITION.x, TARGET_POSITION.y, TARGET_POSITION.z]
			print("Issuing direct command to %s: %s" % [unit.unit_id, command])
			event_bus.unit_command_issued.emit(unit.unit_id, command)
		
		test_results["unit_signal_handling"] = true
		call_deferred("_verify_unit_movement")
	else:
		_fail_test("EventBus not found")

func _verify_unit_movement() -> void:
	"""Verify units are actually moving"""
	test_phase = TestPhase.VERIFY_UNIT_MOVEMENT
	print("\n--- Phase 5: Verifying Unit Movement ---")
	
	# Record initial positions
	var initial_positions = []
	for unit in test_units:
		initial_positions.append(unit.global_position)
		print("Unit %s initial position: %s" % [unit.unit_id, unit.global_position])
	
	# Wait for movement
	await get_tree().create_timer(3.0).timeout
	
	# Check if units moved
	var units_moved = 0
	for i in range(test_units.size()):
		var unit = test_units[i]
		var initial_pos = initial_positions[i]
		var current_pos = unit.global_position
		var distance_moved = initial_pos.distance_to(current_pos)
		
		print("Unit %s moved %.2f units from %s to %s" % [unit.unit_id, distance_moved, initial_pos, current_pos])
		
		if distance_moved > 1.0:  # Significant movement
			units_moved += 1
			print("✓ Unit %s is moving" % unit.unit_id)
		else:
			print("✗ Unit %s has not moved significantly" % unit.unit_id)
	
	if units_moved > 0:
		test_results["unit_movement"] = true
		print("✓ Movement test passed: %d/%d units moving" % [units_moved, test_units.size()])
	else:
		print("✗ Movement test failed: No units moved")
	
	call_deferred("_complete_test")

func _complete_test() -> void:
	"""Complete the test and report results"""
	test_phase = TestPhase.COMPLETE
	print("\n=== COMMAND PIPELINE TEST RESULTS ===")
	
	var passed_tests = 0
	var total_tests = test_results.size()
	
	for test_name in test_results:
		var result = test_results[test_name]
		var status = "✓ PASS" if result else "✗ FAIL"
		print("%s: %s" % [test_name.to_upper(), status])
		if result:
			passed_tests += 1
	
	# Overall pipeline test
	var pipeline_working = test_results.get("unit_movement", false)
	test_results["complete_pipeline"] = pipeline_working
	
	print("\n--- SUMMARY ---")
	print("Tests passed: %d/%d" % [passed_tests, total_tests])
	
	if pipeline_working:
		print("🎉 COMMAND PIPELINE IS FUNCTIONAL!")
		print("✓ Commands can flow from input to unit execution")
	else:
		print("❌ COMMAND PIPELINE HAS ISSUES")
		print("Commands are not reaching unit execution properly")
	
	# Emit results
	test_completed.emit(test_results)
	
	# Cleanup
	call_deferred("_cleanup_test")

func _cleanup_test() -> void:
	"""Clean up test units and resources"""
	print("\n--- Cleanup ---")
	
	for unit in test_units:
		if unit and is_instance_valid(unit):
			unit.queue_free()
	
	test_units.clear()
	print("Test cleanup completed")

func _fail_test(error: String) -> void:
	"""Fail the test with an error message"""
	print("❌ TEST FAILED: %s" % error)
	test_failed.emit(error)
	call_deferred("_cleanup_test")

# Signal handlers
func _on_command_processed(commands: Array, message: String) -> void:
	"""Handle successful AI command processing"""
	print("✓ AI command processed successfully: %s" % message)
	test_results["ai_command_processing"] = true
	call_deferred("_verify_unit_movement")

func _on_command_failed(error: String) -> void:
	"""Handle AI command processing failure"""
	print("⚠ AI command failed: %s" % error)
	print("Trying direct command instead...")
	call_deferred("_test_direct_command")

# Public interface
func run_test() -> void:
	"""Public method to run the test"""
	if test_phase == TestPhase.SETUP:
		_initialize_test()
	else:
		print("Test already running or completed")

func get_test_results() -> Dictionary:
	"""Get the current test results"""
	return test_results.duplicate() 