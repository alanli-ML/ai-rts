# AnimatedUnitTest.gd - Test script for animated units with weapons
extends Node3D

# References
var animated_unit_scene = preload("res://scenes/units/AnimatedUnit.tscn")
var spawned_units: Array[Node] = []
var spawn_counter: int = 0

# Spawn positions
var spawn_positions: Array[Vector3] = [
	Vector3(0, 0, 0),
	Vector3(5, 0, 0),
	Vector3(-5, 0, 0),
	Vector3(0, 0, 5),
	Vector3(0, 0, -5),
	Vector3(5, 0, 5),
	Vector3(-5, 0, 5),
	Vector3(5, 0, -5),
	Vector3(-5, 0, -5)
]

func _ready() -> void:
	# Connect buttons
	var spawn_scout = $UI/VBoxContainer/SpawnScout
	var spawn_soldier = $UI/VBoxContainer/SpawnSoldier
	var spawn_tank = $UI/VBoxContainer/SpawnTank
	var spawn_sniper = $UI/VBoxContainer/SpawnSniper
	var spawn_medic = $UI/VBoxContainer/SpawnMedic
	var spawn_engineer = $UI/VBoxContainer/SpawnEngineer
	var clear_units = $UI/VBoxContainer/ClearUnits
	var test_weapons = $UI/VBoxContainer/TestWeapons
	
	spawn_scout.pressed.connect(_on_spawn_scout_pressed)
	spawn_soldier.pressed.connect(_on_spawn_soldier_pressed)
	spawn_tank.pressed.connect(_on_spawn_tank_pressed)
	spawn_sniper.pressed.connect(_on_spawn_sniper_pressed)
	spawn_medic.pressed.connect(_on_spawn_medic_pressed)
	spawn_engineer.pressed.connect(_on_spawn_engineer_pressed)
	clear_units.pressed.connect(_on_clear_units_pressed)
	test_weapons.pressed.connect(_on_test_weapons_pressed)
	
	print("Animated Unit Test Scene loaded")
	print("Use buttons to spawn different unit archetypes")
	print("Watch for character models, animations, and weapons")
	print("Press X to test texture system specifically")
	print("Press A to test AnimationController system")
	print("Press T for combat simulation with animations")
	print("Press W for enhanced weapon testing with animations")

func _spawn_unit(archetype: String, team_id: int = 1) -> void:
	var unit = animated_unit_scene.instantiate()
	
	if unit:
		unit.archetype = archetype
		unit.team_id = team_id
		unit.name = "TestUnit_%s_%d" % [archetype, spawn_counter]
		
		# Get spawn position
		var spawn_pos = spawn_positions[spawn_counter % spawn_positions.size()]
		unit.position = spawn_pos
		
		# Add to scene
		add_child(unit)
		spawned_units.append(unit)
		spawn_counter += 1
		
		print("Spawned %s unit at %s" % [archetype, spawn_pos])
		
		# Connect to unit signals for debugging
		if unit.has_signal("character_loaded"):
			unit.character_loaded.connect(_on_unit_character_loaded)
		if unit.has_signal("animation_finished"):
			unit.animation_finished.connect(_on_unit_animation_finished)
		if unit.has_signal("team_color_applied"):
			unit.team_color_applied.connect(_on_unit_team_color_applied)
		if unit.has_signal("weapon_equipped"):
			unit.weapon_equipped.connect(_on_unit_weapon_equipped)
		if unit.has_signal("weapon_fired"):
			unit.weapon_fired.connect(_on_unit_weapon_fired)
		
		# Test animation after a delay
		await get_tree().create_timer(3.0).timeout
		_test_unit_features(unit)

func _test_unit_features(unit: Node) -> void:
	"""Test different unit features including weapons"""
	if unit.has_method("play_animation"):
		print("Testing animations and weapon features for unit %s" % unit.name)
		
		# Test animation sequence
		var test_animations = ["walk", "attack", "reload", "idle"]
		for animation in test_animations:
			unit.play_animation(animation)
			await get_tree().create_timer(2.0).timeout
		
		# Test weapon stats
		if unit.has_method("get_weapon_stats"):
			var weapon_stats = unit.get_weapon_stats()
			print("Weapon stats for %s: %s" % [unit.name, weapon_stats])
		
		# Test weapon firing (if unit has weapon)
		if unit.has_method("get_weapon_muzzle_position"):
			var muzzle_pos = unit.get_weapon_muzzle_position()
			print("Muzzle position for %s: %s" % [unit.name, muzzle_pos])
		
		# Test movement to trigger context animation
		if unit.has_method("move_to"):
			var target_pos = unit.position + Vector3(3, 0, 0)
			unit.move_to(target_pos)
			print("Unit %s moving to %s" % [unit.name, target_pos])

func _on_spawn_scout_pressed() -> void:
	_spawn_unit("scout", 1)

func _on_spawn_soldier_pressed() -> void:
	_spawn_unit("soldier", 1)

func _on_spawn_tank_pressed() -> void:
	_spawn_unit("tank", 2)

func _on_spawn_sniper_pressed() -> void:
	_spawn_unit("sniper", 2)

func _on_spawn_medic_pressed() -> void:
	_spawn_unit("medic", 1)

func _on_spawn_engineer_pressed() -> void:
	_spawn_unit("engineer", 2)

func _on_clear_units_pressed() -> void:
	print("Clearing all units")
	for unit in spawned_units:
		if unit and is_instance_valid(unit):
			unit.queue_free()
	spawned_units.clear()
	spawn_counter = 0

func _on_test_weapons_pressed() -> void:
	"""Test weapon functionality on all spawned units"""
	print("=== Testing Weapon Functionality ===")
	
	for unit in spawned_units:
		if unit and is_instance_valid(unit):
			print("Testing weapons for unit %s (%s)" % [unit.name, unit.archetype])
			
			# Test weapon stats
			if unit.has_method("get_weapon_stats"):
				var weapon_stats = unit.get_weapon_stats()
				print("  Weapon: %s" % weapon_stats.get("weapon_type", "none"))
				print("  Damage: %s" % weapon_stats.get("damage", 0))
				print("  Range: %s" % weapon_stats.get("range", 0))
				print("  Ammo: %s/%s" % [weapon_stats.get("current_ammo", 0), weapon_stats.get("max_ammo", 0)])
			
			# Test animation controller integration with weapons
			var animation_controller = unit.find_child("AnimationController")
			if animation_controller:
				print("  Testing weapon-animation integration...")
				
				# Test attack animation
				animation_controller.start_attack()
				await get_tree().create_timer(1.0).timeout
				print("    Attack animation state: %s" % animation_controller.get_current_state_name())
				
				# Test reload animation
				animation_controller.start_reload()
				await get_tree().create_timer(1.5).timeout
				print("    Reload animation state: %s" % animation_controller.get_current_state_name())
				
				animation_controller.finish_reload()
				await get_tree().create_timer(0.5).timeout
				print("    Post-reload state: %s" % animation_controller.get_current_state_name())
			
			# Test weapon attachment debug info
			if unit.has_method("debug_character_info"):
				var debug_info = unit.debug_character_info()
				var weapon_info = debug_info.get("weapon_info", {})
				print("  Weapon equipped: %s" % weapon_info.get("is_equipped", false))
				print("  Attachments: %s" % weapon_info.get("attachments", 0))
				
				# New: AnimationController debug info
				var anim_controller_info = debug_info.get("animation_controller", {})
				if anim_controller_info.get("status") != "not_available":
					print("  Animation state: %s" % anim_controller_info.get("current_state", "unknown"))
					print("  Animation speed: %s" % anim_controller_info.get("current_speed", 0))
			
			# Test texture debugging
			_debug_unit_textures(unit)
	
	print("=== Weapon Testing Complete ===")

func _debug_unit_textures(unit: Node) -> void:
	"""Debug texture information for a unit"""
	if not unit.has_method("debug_character_info"):
		return
	
	print("  === Texture Debug Info ===")
	
	# Check if unit has texture manager
	var texture_manager = unit.find_child("TextureManager")
	if texture_manager:
		print("  TextureManager: Found")
		
		# Debug character texture info
		if unit.character_model and texture_manager.has_method("debug_texture_info"):
			var char_texture_info = texture_manager.debug_texture_info(unit.character_model, unit.current_character_variant)
			print("  Character textures:")
			print("    Model: %s" % char_texture_info.get("model_name", "unknown"))
			print("    Mesh instances: %s" % char_texture_info.get("mesh_instance_count", 0))
			
			var materials = char_texture_info.get("materials", [])
			for i in range(min(materials.size(), 3)):  # Show first 3 materials
				var material_info = materials[i]
				print("    Material %s: has_texture=%s, color=%s" % [
					i, 
					material_info.get("has_albedo_texture", false),
					material_info.get("albedo_color", Color.WHITE)
				])
		
		# Debug weapon texture info
		if unit.weapon_attachment and unit.weapon_attachment.weapon_model:
			var weapon_texture_info = texture_manager.debug_texture_info(unit.weapon_attachment.weapon_model, unit.current_weapon_type)
			print("  Weapon textures:")
			print("    Model: %s" % weapon_texture_info.get("model_name", "unknown"))
			print("    Mesh instances: %s" % weapon_texture_info.get("mesh_instance_count", 0))
			
			var materials = weapon_texture_info.get("materials", [])
			for i in range(min(materials.size(), 2)):  # Show first 2 materials
				var material_info = materials[i]
				print("    Material %s: has_texture=%s, color=%s" % [
					i,
					material_info.get("has_albedo_texture", false), 
					material_info.get("albedo_color", Color.WHITE)
				])
	else:
		print("  TextureManager: Not found")
	
	# Add AnimationController debug info
	var animation_controller = unit.find_child("AnimationController")
	if animation_controller:
		print("  AnimationController: Found")
		print("    Current state: %s" % animation_controller.get_current_state_name())
		
		var debug_info = animation_controller.debug_info()
		print("    Speed: %s" % debug_info.get("current_speed", 0))
		print("    Moving: %s" % debug_info.get("is_moving", false))
		print("    Combat: %s" % debug_info.get("is_in_combat", false))
	else:
		print("  AnimationController: Not found")
	
	print("  === End Texture Debug ===")

# Signal handlers for debugging
func _on_unit_character_loaded(character_variant: String) -> void:
	print("Unit character loaded: %s" % character_variant)

func _on_unit_animation_finished(animation_name: String) -> void:
	print("Animation finished: %s" % animation_name)

func _on_unit_team_color_applied(team_id: int, color: Color) -> void:
	print("Team color applied: Team %d = %s" % [team_id, color])

func _on_unit_weapon_equipped(weapon_type: String) -> void:
	print("Weapon equipped: %s" % weapon_type)

func _on_unit_weapon_fired(weapon_type: String, damage: float) -> void:
	print("Weapon fired: %s (damage: %s)" % [weapon_type, damage])

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				_spawn_unit("scout", 1)
			KEY_2:
				_spawn_unit("soldier", 1)
			KEY_3:
				_spawn_unit("tank", 2)
			KEY_4:
				_spawn_unit("sniper", 2)
			KEY_5:
				_spawn_unit("medic", 1)
			KEY_6:
				_spawn_unit("engineer", 2)
			KEY_C:
				_on_clear_units_pressed()
			KEY_D:
				_debug_units()
			KEY_W:
				_on_test_weapons_pressed()
			KEY_T:
				_test_combat_simulation()
			KEY_X:
				_test_texture_system()
			KEY_A:
				_test_animation_controller()

func _test_texture_system() -> void:
	"""Test the texture system specifically"""
	print("=== Texture System Test ===")
	
	if spawned_units.is_empty():
		print("No units spawned. Spawning test units...")
		_spawn_unit("soldier", 1)
		await get_tree().create_timer(2.0).timeout
	
	for unit in spawned_units:
		if unit and is_instance_valid(unit):
			print("Testing textures for unit: %s" % unit.name)
			_debug_unit_textures(unit)
			
			# Test texture manager methods if available
			var texture_manager = unit.find_child("TextureManager")
			if texture_manager:
				if texture_manager.has_method("get_available_character_variants"):
					var variants = texture_manager.get_available_character_variants()
					print("  Available character variants: %d" % variants.size())
				
				if texture_manager.has_method("preload_weapon_texture"):
					var weapon_texture = texture_manager.preload_weapon_texture()
					print("  Weapon texture preload: %s" % ("success" if weapon_texture else "failed"))
	
	print("=== Texture System Test Complete ===")

func _debug_units() -> void:
	"""Debug information about spawned units"""
	print("=== Unit Debug Info ===")
	for unit in spawned_units:
		if unit and is_instance_valid(unit) and unit.has_method("debug_character_info"):
			var debug_info = unit.debug_character_info()
			print("Unit %s: %s" % [unit.name, debug_info])
	print("=== End Debug Info ===")

func _test_combat_simulation() -> void:
	"""Test combat scenarios with animation integration"""
	print("=== Combat Simulation Test ===")
	
	if spawned_units.size() < 2:
		print("Need at least 2 units for combat simulation. Spawning...")
		_spawn_unit("soldier", 1)
		_spawn_unit("tank", 2)
		await get_tree().create_timer(2.0).timeout
	
	var unit1 = spawned_units[0]
	var unit2 = spawned_units[1] if spawned_units.size() > 1 else null
	
	if unit1 and unit2:
		print("Simulating combat between %s and %s" % [unit1.name, unit2.name])
		
		# Test combat animations
		var anim_controller1 = unit1.find_child("AnimationController")
		var anim_controller2 = unit2.find_child("AnimationController")
		
		if anim_controller1 and anim_controller2:
			print("  Testing combat animation sequence...")
			
			# Unit 1 attacks
			anim_controller1.start_attack()
			await get_tree().create_timer(1.0).timeout
			print("    Unit1 state: %s" % anim_controller1.get_current_state_name())
			
			# Unit 2 takes damage (simulate)
			anim_controller2.take_damage(25.0, 75.0, 100.0)
			await get_tree().create_timer(0.5).timeout
			print("    Unit2 after damage: %s" % anim_controller2.get_current_state_name())
			
			# Unit 2 counter-attacks
			anim_controller2.start_attack()
			await get_tree().create_timer(1.0).timeout
			print("    Unit2 counter-attack: %s" % anim_controller2.get_current_state_name())
			
			# Both units reload
			anim_controller1.start_reload()
			anim_controller2.start_reload()
			await get_tree().create_timer(2.0).timeout
			print("    Both units reloading...")
			
			anim_controller1.finish_reload()
			anim_controller2.finish_reload()
			await get_tree().create_timer(0.5).timeout
			print("    Combat simulation complete")
		else:
			print("  ❌ AnimationControllers not found for combat simulation")
	
	print("=== Combat Simulation Complete ===")

func _test_animation_controller() -> void:
	"""Test the AnimationController system specifically"""
	print("=== Animation Controller Test ===")
	
	if spawned_units.is_empty():
		print("No units spawned. Spawning test units...")
		_spawn_unit("soldier", 1)
		_spawn_unit("scout", 2)
		await get_tree().create_timer(2.0).timeout
	
	for unit in spawned_units:
		if unit and is_instance_valid(unit):
			print("Testing AnimationController for unit: %s (%s)" % [unit.name, unit.archetype])
			await _test_unit_animation_controller(unit)
	
	print("=== Animation Controller Test Complete ===")

func _test_unit_animation_controller(unit: Node) -> void:
	"""Test animation controller functionality for a specific unit"""
	var animation_controller = unit.find_child("AnimationController")
	
	if not animation_controller:
		print("  ❌ AnimationController not found for unit %s" % unit.name)
		return
	
	print("  ✅ AnimationController found")
	
	# Test 1: Basic state information
	print("  Current state: %s" % animation_controller.get_current_state_name())
	
	# Test 2: Movement animations
	print("  Testing movement animations...")
	animation_controller.start_moving(1.0)  # Walk speed
	await get_tree().create_timer(2.0).timeout
	print("    Walk state: %s" % animation_controller.get_current_state_name())
	
	animation_controller.update_speed(4.0)  # Run speed
	await get_tree().create_timer(2.0).timeout
	print("    Run state: %s" % animation_controller.get_current_state_name())
	
	animation_controller.stop_moving()
	await get_tree().create_timer(1.0).timeout
	print("    Stop state: %s" % animation_controller.get_current_state_name())
	
	# Test 3: Combat animations
	print("  Testing combat animations...")
	animation_controller.start_attack()
	await get_tree().create_timer(1.5).timeout
	print("    Attack state: %s" % animation_controller.get_current_state_name())
	
	animation_controller.start_reload()
	await get_tree().create_timer(2.0).timeout
	print("    Reload state: %s" % animation_controller.get_current_state_name())
	
	animation_controller.finish_reload()
	await get_tree().create_timer(1.0).timeout
	print("    Post-reload state: %s" % animation_controller.get_current_state_name())
	
	# Test 4: Debug information
	var debug_info = animation_controller.debug_info()
	print("  Debug info:")
	print("    Speed: %s" % debug_info.get("current_speed", 0))
	print("    Moving: %s" % debug_info.get("is_moving", false))
	print("    Attacking: %s" % debug_info.get("is_attacking", false))
	print("    Health: %s%%" % (debug_info.get("health_percentage", 1.0) * 100))
	print("    Available animations: %s" % debug_info.get("available_animations", []))

func _on_tree_exiting() -> void:
	# Clean up units when scene exits
	_on_clear_units_pressed() 