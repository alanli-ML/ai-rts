# ScoutUnit.gd
class_name ScoutUnit
extends Unit

# Scout-specific properties
var stealth_mode: bool = false
var stealth_energy_cost: float = 2.0
var stealth_detection_range: float = 5.0

func _ready() -> void:
	archetype = "scout"
	system_prompt = "You are a fast, agile scout. Your role is to explore, gather intelligence, and report enemy positions. You are fragile but quick, so use hit-and-run tactics and avoid direct confrontation."
	
	# Call parent _ready
	super._ready()
	
	# Scout-specific setup
	_setup_scout_abilities()

func _setup_scout_abilities() -> void:
	# Scouts have enhanced vision
	vision_range = 40.0
	vision_angle = 120.0
	
	# Fast movement
	speed = 15.0
	move_speed = 15.0
	
	# Lower health but higher mobility
	max_health = 60.0
	current_health = max_health
	
	# Update visual for scout
	_update_scout_visual()

func _update_scout_visual() -> void:
	if unit_model:
		# Make scout smaller and more agile-looking
		unit_model.scale = Vector3(0.8, 0.8, 0.8)
		
		# Different color scheme
		var material = unit_model.material_override as StandardMaterial3D
		if material:
			if team_id == 1:
				material.albedo_color = Color.CYAN  # Light blue for team 1
			else:
				material.albedo_color = Color.ORANGE  # Orange for team 2

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	# Handle stealth mode
	if stealth_mode:
		_handle_stealth_mode(delta)

func _handle_stealth_mode(delta: float) -> void:
	# Drain energy while in stealth
	energy -= stealth_energy_cost * delta
	
	if energy <= 0:
		toggle_stealth_mode()

func toggle_stealth_mode() -> void:
	if stealth_mode:
		# Exit stealth
		stealth_mode = false
		modulate = Color.WHITE
		Logger.debug("ScoutUnit", "Scout %s exited stealth mode" % unit_id)
	else:
		# Enter stealth (requires energy)
		if energy >= 20.0:
			stealth_mode = true
			modulate = Color(1, 1, 1, 0.5)  # Semi-transparent
			Logger.debug("ScoutUnit", "Scout %s entered stealth mode" % unit_id)

func can_be_detected_by(other_unit: Unit) -> bool:
	if not stealth_mode:
		return true
	
	# Can be detected if enemy is very close
	var distance = global_position.distance_to(other_unit.global_position)
	return distance <= stealth_detection_range

func get_movement_speed_multiplier() -> float:
	# Scouts move faster when not in combat
	if visible_enemies.is_empty():
		return 1.5
	return 1.0

func scout_area(target_position: Vector3) -> Dictionary:
	# Return scouting information about an area
	var scout_info = {
		"position": target_position,
		"enemies_spotted": [],
		"terrain_type": "open",
		"safe_path": true
	}
	
	# Check for enemies in the area
	var nearby_enemies = get_tree().get_nodes_in_group("units")
	for node in nearby_enemies:
		if node is Unit:
			var unit = node as Unit
			if unit.is_enemy_of(self):
				var distance = target_position.distance_to(unit.global_position)
				if distance <= vision_range:
					scout_info.enemies_spotted.append({
						"unit_id": unit.unit_id,
						"archetype": unit.archetype,
						"position": unit.global_position,
						"health": unit.get_health_percentage()
					})
	
	return scout_info

func perform_recon(duration: float = 3.0) -> void:
	# Perform a reconnaissance sweep
	Logger.info("ScoutUnit", "Scout %s performing recon for %s seconds" % [unit_id, duration])
	
	# Temporarily increase vision range
	var original_range = vision_range
	vision_range *= 1.5
	
	# Restore vision range after duration
	await get_tree().create_timer(duration).timeout
	vision_range = original_range
	
	Logger.debug("ScoutUnit", "Scout %s completed recon" % unit_id)

func quick_escape() -> void:
	# Scout ability to quickly escape danger
	if visible_enemies.size() > 0:
		# Find escape direction (away from closest enemy)
		var closest_enemy = visible_enemies[0]
		var escape_direction = (global_position - closest_enemy.global_position).normalized()
		var escape_position = global_position + escape_direction * 20.0
		
		# Temporary speed boost
		var original_speed = move_speed
		move_speed *= 2.0
		
		move_to(escape_position)
		
		# Restore original speed after escape
		await get_tree().create_timer(2.0).timeout
		move_speed = original_speed
		
		Logger.debug("ScoutUnit", "Scout %s performed quick escape" % unit_id)

func _on_vision_body_entered(body: Node3D) -> void:
	super._on_vision_body_entered(body)
	
	# Scout-specific: Report enemy sightings
	if body is Unit:
		var unit = body as Unit
		if unit.is_enemy_of(self):
			_report_enemy_sighting(unit)

func _report_enemy_sighting(enemy: Unit) -> void:
	# Report enemy to team
	var sighting_report = {
		"reporter": unit_id,
		"enemy_id": enemy.unit_id,
		"enemy_archetype": enemy.archetype,
		"position": enemy.global_position,
		"timestamp": Time.get_ticks_msec()
	}
	
	EventBus.enemy_sighted.emit(sighting_report)
	Logger.debug("ScoutUnit", "Scout %s reported enemy %s at %s" % [unit_id, enemy.unit_id, enemy.global_position])

func _update_vision() -> void:
	super._update_vision()
	
	# Scout-specific vision updates
	if stealth_mode:
		# Enhanced vision while in stealth
		_enhance_stealth_vision()

func _enhance_stealth_vision() -> void:
	# While in stealth, scouts can see through some obstacles
	# This would be implemented with additional raycasting
	pass 