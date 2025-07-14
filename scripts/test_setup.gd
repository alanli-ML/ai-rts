# test_setup.gd
extends Node3D

# const GameController = preload("res://scripts/core/game_controller.gd")
const UnitSpawner = preload("res://scripts/units/unit_spawner.gd")

var map_scene: PackedScene
var game_controller
var unit_spawner: Node3D

func _ready() -> void:
	Logger.info("TestSetup", "Starting test setup...")
	
	# Verify all singletons are loaded
	_verify_singletons()
	
	# Create game controller
	var GameControllerScript = load("res://scripts/core/game_controller.gd")
	game_controller = GameControllerScript.new()
	game_controller.name = "GameController"
	add_child(game_controller)
	
	# Create unit spawner programmatically
	unit_spawner = UnitSpawner.new()
	unit_spawner.name = "UnitSpawner"
	add_child(unit_spawner)
	
	# Verify creation
	if not unit_spawner:
		Logger.error("TestSetup", "Failed to create UnitSpawner!")
		return
	
	# Load the test map
	_load_test_map()
	
	# Set initial game state
	GameManager.change_state(GameManager.GameState.IN_GAME)
	
	# Wait a moment for everything to initialize
	await get_tree().process_frame
	
	# Spawn test units
	_spawn_test_units()
	
	# Test camera controls
	Logger.info("TestSetup", "Camera controls: WASD/Arrow keys to pan, Mouse wheel to zoom, Middle mouse to drag")
	Logger.info("TestSetup", "Command input: Press Enter to type commands, Q for radial menu")
	Logger.info("TestSetup", "Unit testing: Click to select units, multiple archetypes spawned")
	Logger.info("TestSetup", "AI testing: Press 'I' to test AI commands, 'O' to test AI status, 'P' to test voice commands")

func _verify_singletons() -> void:
	# Check if all autoloads are accessible
	var singletons = ["GameManager", "EventBus", "ConfigManager"]
	
	for singleton_name in singletons:
		var singleton = get_node("/root/" + singleton_name)
		if singleton:
			Logger.info("TestSetup", singleton_name + " singleton verified")
		else:
			Logger.error("TestSetup", singleton_name + " singleton not found!")

func _load_test_map() -> void:
	# Load the test map scene
	var test_map_path = "res://scenes/maps/test_map.tscn"
	
	if ResourceLoader.exists(test_map_path):
		map_scene = load(test_map_path)
		var map_instance = map_scene.instantiate()
		add_child(map_instance)
		Logger.info("TestSetup", "Test map loaded successfully")
		
		# Find and configure the RTS camera
		var rts_camera = map_instance.get_node_or_null("RTSCamera")
		if rts_camera:
			rts_camera.add_to_group("cameras")
			Logger.info("TestSetup", "RTS camera configured")
		
		# Configure spawn points
		var spawn_points = map_instance.get_node_or_null("SpawnPoints")
		if spawn_points:
			for child in spawn_points.get_children():
				child.add_to_group("spawn_points")
				Logger.debug("TestSetup", "Configured spawn point: " + child.name)
	else:
		Logger.error("TestSetup", "Test map scene not found at: " + test_map_path)

func _spawn_test_units() -> void:
	if not unit_spawner:
		Logger.error("TestSetup", "Unit spawner not available")
		return
	
	Logger.info("TestSetup", "Spawning test units...")
	
	# Spawn units for team 1
	unit_spawner.spawn_unit("scout", 1)
	await get_tree().create_timer(0.2).timeout
	
	unit_spawner.spawn_unit("tank", 1)
	await get_tree().create_timer(0.2).timeout
	
	unit_spawner.spawn_unit("sniper", 1)
	await get_tree().create_timer(0.2).timeout
	
	unit_spawner.spawn_unit("medic", 1)
	await get_tree().create_timer(0.2).timeout
	
	unit_spawner.spawn_unit("engineer", 1)
	await get_tree().create_timer(0.2).timeout
	
	# Spawn units for team 2
	unit_spawner.spawn_unit("scout", 2)
	await get_tree().create_timer(0.2).timeout
	
	unit_spawner.spawn_unit("tank", 2)
	await get_tree().create_timer(0.2).timeout
	
	unit_spawner.spawn_unit("sniper", 2)
	await get_tree().create_timer(0.2).timeout
	
	unit_spawner.spawn_unit("medic", 2)
	await get_tree().create_timer(0.2).timeout
	
	unit_spawner.spawn_unit("engineer", 2)
	
	Logger.info("TestSetup", "Test units spawned - 5 units per team")
	Logger.info("TestSetup", "Team 1 units: Scout, Tank, Sniper, Medic, Engineer")
	Logger.info("TestSetup", "Team 2 units: Scout, Tank, Sniper, Medic, Engineer")
	
	# Start AI behavior test after basic setup
	_start_ai_behavior_test()
	
	# Test multiplayer lobby
	_test_multiplayer_lobby()

func _input(event: InputEvent) -> void:
	# Test hotkeys
	if event.is_action_pressed("ui_cancel"):
		Logger.info("TestSetup", "ESC pressed - would normally open menu")
	
	# Test state changes with number keys
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				GameManager.change_state(GameManager.GameState.MENU)
				Logger.info("TestSetup", "Changed to MENU state")
			KEY_2:
				GameManager.change_state(GameManager.GameState.IN_GAME)
				Logger.info("TestSetup", "Changed to IN_GAME state")
			KEY_3:
				GameManager.change_state(GameManager.GameState.PAUSED)
				Logger.info("TestSetup", "Changed to PAUSED state")
			KEY_H:
				_test_host_game()
			KEY_J:
				_test_join_game()
			KEY_L:
				_show_lobby_ui()
			KEY_T:
				_test_team_based_units()
			KEY_I:
				_test_ai_commands()
			KEY_O:
				_test_ai_status()
			KEY_P:
				_test_voice_commands()

func _start_ai_behavior_test() -> void:
	Logger.info("TestSetup", "Starting AI behavior test in 3 seconds...")
	await get_tree().create_timer(3.0).timeout
	
	# Test 1: Combat between opposing units
	Logger.info("TestSetup", "Test 1: Combat test - spawning opposing units close together")
	var scout1 = unit_spawner.spawn_unit("scout", 1, Vector3(50, 1, 50))
	var tank2 = unit_spawner.spawn_unit("tank", 2, Vector3(55, 1, 55))  # 7 units apart
	
	# Test 2: Medic healing wounded ally
	Logger.info("TestSetup", "Test 2: Healing test - spawning medic near wounded ally")
	var medic1 = unit_spawner.spawn_unit("medic", 1, Vector3(60, 1, 50))
	var scout1_wounded = unit_spawner.spawn_unit("scout", 1, Vector3(65, 1, 50))
	
	# Damage the scout to test healing
	await get_tree().create_timer(1.0).timeout
	if scout1_wounded:
		scout1_wounded.take_damage(40.0)  # Damage the scout
		Logger.info("TestSetup", "Damaged scout for medic healing test")
	
	# Test 3: Multiple unit combat
	Logger.info("TestSetup", "Test 3: Multi-unit combat test")
	var sniper1 = unit_spawner.spawn_unit("sniper", 1, Vector3(70, 1, 50))
	var engineer2 = unit_spawner.spawn_unit("engineer", 2, Vector3(75, 1, 50))
	var tank1 = unit_spawner.spawn_unit("tank", 1, Vector3(72, 1, 52))
	
	# Monitor the test results
	_monitor_ai_behavior_test()

func _monitor_ai_behavior_test() -> void:
	Logger.info("TestSetup", "Monitoring AI behavior test results for 30 seconds...")
	
	# Monitor for 30 seconds
	for i in range(30):
		await get_tree().create_timer(1.0).timeout
		
		# Check for any combat or healing events
		if i % 5 == 0:  # Every 5 seconds
			Logger.info("TestSetup", "--- Status Check at %d seconds ---" % (i + 1))
			var units = get_tree().get_nodes_in_group("units")
			for unit in units:
				if unit.has_method("get_health_percentage"):
					var health_pct = unit.get_health_percentage() * 100
					Logger.info("TestSetup", "%s: %d%% health, state: %s" % [unit.unit_id, health_pct, unit.get_state_name()])
	
	Logger.info("TestSetup", "AI behavior test complete!")

func _test_multiplayer_lobby() -> void:
	Logger.info("TestSetup", "Testing multiplayer lobby system...")
	
	# Wait a bit to let the unit system stabilize
	await get_tree().create_timer(5.0).timeout
	
	# Test NetworkManager basic functionality
	Logger.info("TestSetup", "NetworkManager state: %s" % NetworkManager.NetworkState.keys()[NetworkManager.current_state])
	
	# Test lobby UI loading
	var lobby_scene = load("res://scenes/ui/lobby.tscn")
	if lobby_scene:
		Logger.info("TestSetup", "Lobby scene loaded successfully")
		var lobby_instance = lobby_scene.instantiate()
		
		# Test script attachment
		var lobby_script = load("res://scripts/ui/lobby_ui.gd")
		if lobby_script:
			lobby_instance.script = lobby_script
			Logger.info("TestSetup", "Lobby script attached successfully")
		
		# Clean up test instance
		lobby_instance.queue_free()
	else:
		Logger.error("TestSetup", "Failed to load lobby scene")
	
	# Test network functionality
	Logger.info("TestSetup", "Testing network host functionality...")
	Logger.info("TestSetup", "Press 'H' to test host game")
	Logger.info("TestSetup", "Press 'J' to test join game")
	Logger.info("TestSetup", "Press 'L' to show lobby UI")
	Logger.info("TestSetup", "Press 'T' to test team-based unit spawning")

func _test_host_game() -> void:
	Logger.info("TestSetup", "Testing host game functionality...")
	if NetworkManager.host_game():
		Logger.info("TestSetup", "Successfully hosting game on port %d" % NetworkManager.server_port)
	else:
		Logger.error("TestSetup", "Failed to host game")

func _test_join_game() -> void:
	Logger.info("TestSetup", "Testing join game functionality...")
	if NetworkManager.join_game("127.0.0.1"):
		Logger.info("TestSetup", "Attempting to join game at 127.0.0.1:7777")
	else:
		Logger.error("TestSetup", "Failed to join game")

func _show_lobby_ui() -> void:
	Logger.info("TestSetup", "Showing cooperative team lobby UI...")
	
	# Load and instantiate lobby scene
	var lobby_scene = load("res://scenes/ui/lobby.tscn")
	if lobby_scene:
		var lobby_instance = lobby_scene.instantiate()
		
		# Attach script
		var lobby_script = load("res://scripts/ui/lobby_ui.gd")
		if lobby_script:
			lobby_instance.script = lobby_script
			
		# Add to scene
		add_child(lobby_instance)
		
		# Position in center of screen
		var screen_size = get_viewport().get_visible_rect().size
		lobby_instance.position = Vector2(screen_size.x / 2 - 300, screen_size.y / 2 - 200)
		lobby_instance.size = Vector2(600, 400)
		
		Logger.info("TestSetup", "Cooperative team lobby UI displayed")
	else:
		Logger.error("TestSetup", "Failed to load lobby scene")

func _test_team_based_units() -> void:
	Logger.info("TestSetup", "Testing team-based unit spawning...")
	
	# Create team unit spawner
	var team_spawner = preload("res://scripts/units/team_unit_spawner.gd").new()
	team_spawner.name = "TeamUnitSpawner"
	add_child(team_spawner)
	
	# Test team unit spawning
	await get_tree().create_timer(2.0).timeout
	team_spawner.spawn_team_units()
	
	Logger.info("TestSetup", "Team-based unit spawning test complete")

func _test_ai_commands() -> void:
	Logger.info("TestSetup", "Testing AI command processing...")
	
	# Get reference to game controller
	if not game_controller:
		Logger.error("TestSetup", "Game controller not found")
		return
	
	# Test commands
	var test_commands = [
		"Move the selected units to the center",
		"All scouts move to position 20 0 20",
		"Attack the enemy tank",
		"Medic unit heal nearby allies",
		"Form a line formation",
		"Set defensive stance",
		"Patrol between waypoints",
		"Stop all units"
	]
	
	Logger.info("TestSetup", "Testing %d AI commands..." % test_commands.size())
	
	for i in range(test_commands.size()):
		var command = test_commands[i]
		Logger.info("TestSetup", "AI Command %d: %s" % [i + 1, command])
		
		# Simulate command input
		EventBus.ui_command_entered.emit(command)
		
		# Wait between commands
		await get_tree().create_timer(2.0).timeout
	
	Logger.info("TestSetup", "AI command testing complete!")

func _test_ai_status() -> void:
	Logger.info("TestSetup", "Testing AI system status...")
	
	if not game_controller:
		Logger.error("TestSetup", "Game controller not found")
		return
	
	# Get AI status
	var ai_status = game_controller.get_ai_status()
	
	Logger.info("TestSetup", "AI Status:")
	Logger.info("TestSetup", "  - AI Available: %s" % ai_status.ai_available)
	Logger.info("TestSetup", "  - Currently Processing: %s" % ai_status.processing)
	Logger.info("TestSetup", "  - Queue Size: %d" % ai_status.queue_size)
	Logger.info("TestSetup", "  - Selected Units: %d" % ai_status.selected_units)
	
	# Test OpenAI client status
	if game_controller.ai_command_processor and game_controller.ai_command_processor.openai_client:
		var openai_client = game_controller.ai_command_processor.openai_client
		var usage_info = openai_client.get_usage_info()
		
		Logger.info("TestSetup", "OpenAI Client Status:")
		Logger.info("TestSetup", "  - Active Requests: %d" % usage_info.active_requests)
		Logger.info("TestSetup", "  - Queued Requests: %d" % usage_info.queued_requests)
		Logger.info("TestSetup", "  - Requests Last Minute: %d" % usage_info.requests_last_minute)
		Logger.info("TestSetup", "  - Rate Limit: %d/min" % usage_info.rate_limit)
	
	# Test command history
	if game_controller.ai_command_processor:
		var command_history = game_controller.ai_command_processor.get_command_history()
		Logger.info("TestSetup", "Recent Commands: %s" % command_history)
	
	Logger.info("TestSetup", "AI status testing complete!")

func _test_voice_commands() -> void:
	Logger.info("TestSetup", "Testing voice command integration...")
	
	# Note: This is a placeholder for future voice integration
	Logger.info("TestSetup", "Voice commands not yet implemented")
	Logger.info("TestSetup", "Future implementation will include:")
	Logger.info("TestSetup", "  - Speech-to-text integration")
	Logger.info("TestSetup", "  - Voice activity detection")
	Logger.info("TestSetup", "  - Audio input processing")
	Logger.info("TestSetup", "  - Real-time voice command parsing")
	
	# For now, simulate voice commands with text
	var voice_commands = [
		"Move forward",
		"Attack that target",
		"Regroup at my position",
		"Defensive positions"
	]
	
	Logger.info("TestSetup", "Simulating voice commands as text...")
	
	for command in voice_commands:
		Logger.info("TestSetup", "Voice Command: '%s'" % command)
		EventBus.ui_command_entered.emit(command)
		await get_tree().create_timer(3.0).timeout
	
	Logger.info("TestSetup", "Voice command testing complete!")

func _test_ai_context_system() -> void:
	Logger.info("TestSetup", "Testing AI context system...")
	
	if not game_controller or not game_controller.ai_command_processor:
		Logger.error("TestSetup", "AI command processor not found")
		return
	
	# Test context building
	var selected_units = []
	var all_units = get_tree().get_nodes_in_group("units")
	
	if all_units.size() > 0:
		# Select first few units for testing
		selected_units = all_units.slice(0, min(3, all_units.size()))
		
		# Test context with selected units
		var test_command = "Move these units to a safe position"
		Logger.info("TestSetup", "Testing context with %d selected units" % selected_units.size())
		
		# Get game state
		var game_state = game_controller._get_current_game_state()
		Logger.info("TestSetup", "Game state: %s" % game_state)
		
		# Process command with context
		game_controller.ai_command_processor.process_command(test_command, selected_units, game_state)
	
	Logger.info("TestSetup", "AI context system testing complete!") 