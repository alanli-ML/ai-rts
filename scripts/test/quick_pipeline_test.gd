# QuickPipelineTest.gd
# Quick test to verify the command pipeline is working
extends Node

func _ready() -> void:
	print("=== QUICK COMMAND PIPELINE TEST ===")
	_run_quick_test()

func _run_quick_test() -> void:
	"""Run a quick test of the command pipeline"""
	
	# Wait a moment for systems to initialize
	await get_tree().create_timer(1.0).timeout
	
	print("\n1. Testing EventBus availability...")
	if has_node("/root/EventBus"):
		print("✓ EventBus found")
		_test_eventbus_commands()
	else:
		print("✗ EventBus not found")

func _test_eventbus_commands() -> void:
	"""Test direct EventBus command functionality"""
	print("\n2. Testing EventBus command emission...")
	
	var event_bus = get_node("/root/EventBus")
	
	# Check if the signal exists
	if event_bus.has_signal("unit_command_issued"):
		print("✓ unit_command_issued signal found")
		
		# Test emitting a command
		print("3. Emitting test command...")
		event_bus.unit_command_issued.emit("test_unit_123", "move_to:25,0,25")
		print("✓ Command emitted successfully")
		
		_test_unit_spawning()
	else:
		print("✗ unit_command_issued signal not found")

func _test_unit_spawning() -> void:
	"""Test spawning a unit and sending it commands"""
	print("\n4. Testing unit spawning and command handling...")
	
	# Check if we can load the unit scene
	var unit_scene_path = "res://scenes/units/AnimatedUnit.tscn"
	if ResourceLoader.exists(unit_scene_path):
		print("✓ AnimatedUnit scene found")
		
		# Try to spawn a unit
		var unit_scene = load(unit_scene_path)
		var unit = unit_scene.instantiate()
		
		if unit:
			print("✓ Unit instantiated")
			
			# Set up the unit
			unit.unit_id = "pipeline_test_unit"
			unit.archetype = "scout"
			unit.team_id = 1
			unit.position = Vector3(-40, 0, -52)  # Use new home base spawn position
			
			# Add to scene
			add_child(unit)
			
			# Wait for unit to be ready
			await unit.ready
			await get_tree().create_timer(0.5).timeout
			
			print("✓ Unit added to scene: %s" % unit.unit_id)
			
			# Test sending command
			_test_unit_command(unit)
		else:
			print("✗ Failed to instantiate unit")
	else:
		print("✗ AnimatedUnit scene not found")

func _test_unit_command(unit: Unit) -> void:
	"""Test sending a command to the unit"""
	print("\n5. Testing command delivery to unit...")
	
	# Record initial position
	var initial_pos = unit.global_position
	print("Unit initial position: %s" % initial_pos)
	
	# Send command via EventBus
	var event_bus = get_node("/root/EventBus")
	var target_pos = Vector3(-20, 0, -30)  # Move toward center from home base
	var command = "move_to:%s,%s,%s" % [target_pos.x, target_pos.y, target_pos.z]
	
	print("Sending command: %s" % command)
	event_bus.unit_command_issued.emit(unit.unit_id, command)
	
	# Wait and check if unit moved
	await get_tree().create_timer(2.0).timeout
	
	var current_pos = unit.global_position
	var distance_moved = initial_pos.distance_to(current_pos)
	
	print("Unit current position: %s" % current_pos)
	print("Distance moved: %.2f" % distance_moved)
	
	if distance_moved > 0.5:
		print("🎉 SUCCESS: Unit responded to command and moved!")
		print("✓ Command pipeline is FUNCTIONAL!")
	else:
		print("❌ ISSUE: Unit did not move significantly")
		print("Command pipeline may have problems")
		
		# Try direct method call as fallback test
		_test_direct_method_call(unit, target_pos)
	
	_cleanup_test(unit)

func _test_direct_method_call(unit: Unit, target_pos: Vector3) -> void:
	"""Test direct method call as fallback"""
	print("\n6. Testing direct method call fallback...")
	
	var initial_pos = unit.global_position
	print("Testing direct move_to() call...")
	
	# Call move_to directly
	unit.move_to(target_pos)
	
	# Wait and check
	await get_tree().create_timer(2.0).timeout
	
	var current_pos = unit.global_position
	var distance_moved = initial_pos.distance_to(current_pos)
	
	print("Distance moved with direct call: %.2f" % distance_moved)
	
	if distance_moved > 0.5:
		print("✓ Direct method call works - signal handling issue")
	else:
		print("✗ Direct method call also failed - navigation issue")

func _cleanup_test(unit: Unit) -> void:
	"""Clean up the test"""
	print("\n7. Cleaning up test...")
	
	if unit and is_instance_valid(unit):
		unit.queue_free()
	
	print("=== QUICK TEST COMPLETED ===")

func _input(event: InputEvent) -> void:
	"""Allow manual test restart with space key"""
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE:
			print("\n--- RESTARTING TEST ---")
			_run_quick_test() 