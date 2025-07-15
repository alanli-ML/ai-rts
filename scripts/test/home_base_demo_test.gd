# HomeBaseDemoTest.gd
# Demonstration script for the home base system
extends Node

var home_base_manager
var spawned_units: Array[Unit] = []

func _ready() -> void:
	print("=== HOME BASE DEMO TEST ===")
	await get_tree().create_timer(1.0).timeout  # Wait for initialization
	_run_demo()

func _run_demo() -> void:
	"""Run the home base demonstration"""
	
	# Find HomeBaseManager
	home_base_manager = get_node("../HomeBaseManager")
	if not home_base_manager:
		print("❌ HomeBaseManager not found")
		return
	
	print("✓ HomeBaseManager found")
	_print_home_base_info()
	
	# Spawn test units for both teams
	await get_tree().create_timer(2.0).timeout
	_spawn_demo_units()

func _print_home_base_info() -> void:
	"""Print information about the home bases"""
	print("\n--- Home Base Information ---")
	
	var debug_info = home_base_manager.get_debug_info()
	print("Home bases created for teams: %s" % debug_info.home_bases)
	print("Spawn points: %s" % debug_info.spawn_points)
	print("Home base positions: %s" % debug_info.positions)
	
	for team_id in [1, 2]:
		var base_pos = home_base_manager.get_home_base_position(team_id)
		var spawn_pos = home_base_manager.get_team_spawn_position(team_id)
		var team_color = "Blue" if team_id == 1 else "Red"
		
		print("Team %d (%s):" % [team_id, team_color])
		print("  - Home base: %s" % base_pos)
		print("  - Spawn point: %s" % spawn_pos)

func _spawn_demo_units() -> void:
	"""Spawn demonstration units for both teams"""
	print("\n--- Spawning Demo Units ---")
	
	var unit_scene_path = "res://scenes/units/AnimatedUnit.tscn"
	if not ResourceLoader.exists(unit_scene_path):
		print("❌ AnimatedUnit scene not found")
		return
	
	var unit_scene = load(unit_scene_path)
	
	# Spawn 3 units for each team
	for team_id in [1, 2]:
		var team_name = "Blue" if team_id == 1 else "Red"
		print("\nSpawning units for Team %d (%s):" % [team_id, team_name])
		
		for i in range(3):
			var unit = unit_scene.instantiate()
			if unit:
				# Configure unit
				unit.unit_id = "demo_unit_team%d_%d" % [team_id, i]
				unit.archetype = ["scout", "tank", "medic"][i]
				unit.team_id = team_id
				
				# Get spawn position with offset
				var spawn_pos = home_base_manager.get_spawn_position_with_offset(team_id)
				unit.position = spawn_pos
				
				# Add to scene
				add_child(unit)
				spawned_units.append(unit)
				
				# Wait for unit to be ready
				await unit.ready
				
				print("  ✓ Spawned %s %s at %s" % [unit.archetype, unit.unit_id, spawn_pos])
				
				# Small delay between spawns
				await get_tree().create_timer(0.5).timeout
	
	print("\n✓ Demo units spawned successfully")
	_test_unit_commands()

func _test_unit_commands() -> void:
	"""Test sending commands to demo units"""
	print("\n--- Testing Unit Commands ---")
	
	await get_tree().create_timer(1.0).timeout
	
	# Test commanding units to move toward the center
	if has_node("/root/EventBus"):
		var event_bus = get_node("/root/EventBus")
		
		for unit in spawned_units:
			if unit and is_instance_valid(unit):
				# Command units to move toward the map center
				var target_pos = Vector3(0, 0, 0)
				var command = "move_to:%s,%s,%s" % [target_pos.x, target_pos.y, target_pos.z]
				
				print("Commanding %s to move to center" % unit.unit_id)
				event_bus.unit_command_issued.emit(unit.unit_id, command)
				
				await get_tree().create_timer(0.2).timeout
		
		print("✓ Movement commands sent to all units")
	else:
		print("❌ EventBus not found - cannot test commands")
	
	_show_demo_summary()

func _show_demo_summary() -> void:
	"""Show summary of the demonstration"""
	print("\n=== DEMO SUMMARY ===")
	print("🏠 Home Base System Features Demonstrated:")
	print("  ✓ Team-colored buildings (Blue vs Red)")
	print("  ✓ Strategic positioning (bottom-left vs top-right)")
	print("  ✓ Command center + support buildings")
	print("  ✓ Team-based spawn positions")
	print("  ✓ Unit spawning near home bases")
	print("  ✓ Integration with command pipeline")
	print("")
	print("🎮 To test manually:")
	print("  - Units spawn near their team's home base")
	print("  - Buildings are colored by team (Blue/Red)")
	print("  - Press SPACE to run pipeline test")
	print("  - Units should respond to AI commands")
	print("")
	print("📍 Strategic Layout:")
	print("  - Team 1 (Blue): Bottom-left corner")
	print("  - Team 2 (Red): Top-right corner")
	print("  - Maximum strategic distance between bases")

func _input(event: InputEvent) -> void:
	"""Handle input for manual testing"""
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_SPACE:
				print("\n--- Manual Pipeline Test ---")
				_test_ai_commands()
			KEY_R:
				print("\n--- Respawning Demo Units ---")
				_cleanup_units()
				await get_tree().create_timer(1.0).timeout
				_spawn_demo_units()
			KEY_C:
				print("\n--- Cleaning Up Demo ---")
				_cleanup_units()

func _test_ai_commands() -> void:
	"""Test AI commands on demo units"""
	if spawned_units.is_empty():
		print("No units available for testing")
		return
	
	# Select a few units for AI command test
	var test_units = spawned_units.slice(0, 3)
	
	print("Testing AI command on %d units..." % test_units.size())
	
	# Try to find AI command processor
	var ai_processor = _find_ai_command_processor()
	if ai_processor and ai_processor.has_method("process_command"):
		var command = "Move units to the center of the map for strategic positioning"
		var game_state = {"phase": "demo", "units": test_units.size()}
		
		print("Sending AI command: %s" % command)
		ai_processor.process_command(command, test_units, game_state)
	else:
		print("AI Command Processor not available - using direct commands")
		_test_direct_commands(test_units)

func _find_ai_command_processor() -> Node:
	"""Find AI command processor"""
	var dependency_container = get_node("/root/DependencyContainer")
	if dependency_container and dependency_container.has_method("get_ai_command_processor"):
		return dependency_container.get_ai_command_processor()
	return null

func _test_direct_commands(units: Array[Unit]) -> void:
	"""Test direct EventBus commands"""
	if has_node("/root/EventBus"):
		var event_bus = get_node("/root/EventBus")
		
		for unit in units:
			if unit and is_instance_valid(unit):
				var command = "move_to:0,0,0"
				event_bus.unit_command_issued.emit(unit.unit_id, command)
				print("Direct command sent to %s" % unit.unit_id)

func _cleanup_units() -> void:
	"""Clean up spawned demo units"""
	for unit in spawned_units:
		if unit and is_instance_valid(unit):
			unit.queue_free()
	
	spawned_units.clear()
	print("Demo units cleaned up") 