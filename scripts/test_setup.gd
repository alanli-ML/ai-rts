# test_setup.gd
extends Node3D

const GameController = preload("res://scripts/core/game_controller.gd")
const UnitSpawner = preload("res://scripts/units/unit_spawner.gd")

var map_scene: PackedScene
var game_controller: GameController
var unit_spawner: Node3D

func _ready() -> void:
	Logger.info("TestSetup", "Starting test setup...")
	
	# Verify all singletons are loaded
	_verify_singletons()
	
	# Create game controller
	game_controller = GameController.new()
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