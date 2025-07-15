# ScoutUnit.gd
class_name ScoutUnit
extends Unit

# Scout-specific properties
var stealth_mode: bool = false
var stealth_energy_cost: float = 2.0
var stealth_detection_range: float = 5.0
var stealth_duration: float = 10.0
var stealth_cooldown: float = 15.0
var stealth_timer: float = 0.0
var stealth_cooldown_timer: float = 0.0

# Target marking
var marked_targets: Array[Unit] = []
var mark_duration: float = 30.0
var mark_cooldown: float = 5.0
var mark_cooldown_timer: float = 0.0

# Area scanning
var scan_range: float = 20.0
var scan_cooldown: float = 8.0
var scan_cooldown_timer: float = 0.0
var scanned_areas: Array[Vector3] = []

# Visual effects
var stealth_material: StandardMaterial3D
var mark_indicators: Dictionary = {}  # target_id -> indicator_node

# Signals
signal target_marked(target: Unit, scout_id: String)
signal area_scanned(position: Vector3, entities_found: Array, scout_id: String)
signal stealth_activated(scout_id: String, duration: float)
signal stealth_deactivated(scout_id: String)

func _ready() -> void:
	archetype = "scout"
	system_prompt = "You are a fast, agile scout. Your role is to explore, gather intelligence, and report enemy positions. You are fragile but quick, so use hit-and-run tactics and avoid direct confrontation. Use stealth to avoid detection and mark targets for your team."
	
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
	movement_speed = 15.0
	
	# Lower health but higher mobility
	max_health = 60.0
	current_health = max_health
	
	# Create stealth material
	stealth_material = StandardMaterial3D.new()
	stealth_material.flags_transparent = true
	stealth_material.albedo_color = Color(0.5, 0.5, 1.0, 0.3)  # Semi-transparent blue
	
	# Update visual for scout
	_update_scout_visual()

func _update_scout_visual() -> void:
	# Find mesh instance for visual updates
	var mesh_instance = find_child("UnitMesh") as MeshInstance3D
	if mesh_instance:
		# Make scout smaller and more agile-looking
		mesh_instance.scale = Vector3(0.8, 0.8, 0.8)
		
		# Different color scheme
		var material = mesh_instance.material_override as StandardMaterial3D
		if material:
			if team_id == 1:
				material.albedo_color = Color.CYAN  # Light blue for team 1
			else:
				material.albedo_color = Color.ORANGE  # Orange for team 2

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	# Update ability timers
	_update_ability_timers(delta)
	
	# Handle stealth mode
	if stealth_mode:
		_handle_stealth_mode(delta)
	
	# Update marked targets
	_update_marked_targets(delta)

func _update_ability_timers(delta: float) -> void:
	"""Update cooldown timers for abilities"""
	if stealth_cooldown_timer > 0:
		stealth_cooldown_timer -= delta
	
	if mark_cooldown_timer > 0:
		mark_cooldown_timer -= delta
	
	if scan_cooldown_timer > 0:
		scan_cooldown_timer -= delta
	
	if stealth_timer > 0:
		stealth_timer -= delta
		if stealth_timer <= 0:
			deactivate_stealth()

func _handle_stealth_mode(delta: float) -> void:
	"""Handle stealth mode behavior"""
	# Consume energy while in stealth
	if energy > 0:
		energy -= stealth_energy_cost * delta
	else:
		# Run out of energy, deactivate stealth
		deactivate_stealth()

func _update_marked_targets(delta: float) -> void:
	"""Update marked targets and remove expired ones"""
	var expired_targets = []
	
	for target in marked_targets:
		if target.has_meta("mark_time"):
			var mark_time = target.get_meta("mark_time")
			if Time.get_ticks_msec() / 1000.0 - mark_time > mark_duration:
				expired_targets.append(target)
	
	# Remove expired marks
	for target in expired_targets:
		_remove_target_mark(target)

# Enhanced Scout Abilities
func activate_stealth(duration: float = 0.0) -> bool:
	"""Activate stealth mode for the scout"""
	if stealth_mode or stealth_cooldown_timer > 0:
		print("Scout %s: Stealth on cooldown or already active" % unit_id)
		return false
	
	if energy < 20.0:  # Minimum energy required
		print("Scout %s: Not enough energy for stealth" % unit_id)
		return false
	
	stealth_mode = true
	stealth_timer = duration if duration > 0 else stealth_duration
	stealth_cooldown_timer = stealth_cooldown
	
	# Apply stealth visual effect
	_apply_stealth_visual()
	
	# Reduce visibility to enemies
	_reduce_visibility()
	
	print("Scout %s: Stealth activated for %.1f seconds" % [unit_id, stealth_timer])
	stealth_activated.emit(unit_id, stealth_timer)
	
	return true

func deactivate_stealth() -> void:
	"""Deactivate stealth mode"""
	if not stealth_mode:
		return
	
	stealth_mode = false
	stealth_timer = 0.0
	
	# Remove stealth visual effect
	_remove_stealth_visual()
	
	# Restore normal visibility
	_restore_visibility()
	
	print("Scout %s: Stealth deactivated" % unit_id)
	stealth_deactivated.emit(unit_id)

func mark_target(target: Unit) -> bool:
	"""Mark an enemy unit for the team"""
	if not target or mark_cooldown_timer > 0:
		print("Scout %s: Mark target on cooldown or invalid target" % unit_id)
		return false
	
	if target.team_id == team_id:
		print("Scout %s: Cannot mark allied unit" % unit_id)
		return false
	
	# Check if target is in vision range
	var distance = global_position.distance_to(target.global_position)
	if distance > vision_range:
		print("Scout %s: Target too far to mark" % unit_id)
		return false
	
	# Add target to marked list
	if target not in marked_targets:
		marked_targets.append(target)
	
	# Set mark metadata
	target.set_meta("mark_time", Time.get_ticks_msec() / 1000.0)
	target.set_meta("marked_by", unit_id)
	
	# Create visual indicator
	_create_mark_indicator(target)
	
	# Set cooldown
	mark_cooldown_timer = mark_cooldown
	
	print("Scout %s: Marked target %s" % [unit_id, target.unit_id])
	target_marked.emit(target, unit_id)
	
	return true

func scan_area(range: float = 0.0) -> bool:
	"""Scan area around the scout for enemies"""
	if scan_cooldown_timer > 0:
		print("Scout %s: Area scan on cooldown" % unit_id)
		return false
	
	var scan_radius = range if range > 0 else scan_range
	var entities_found = []
	
	# Find all units in scan range
	var all_units = get_tree().get_nodes_in_group("units")
	for unit in all_units:
		if unit == self:
			continue
		
		var distance = global_position.distance_to(unit.global_position)
		if distance <= scan_radius:
			entities_found.append({
				"unit_id": unit.unit_id if unit.has_method("get") else unit.name,
				"archetype": unit.archetype if unit.has_method("get") else "unknown",
				"position": unit.global_position,
				"team_id": unit.team_id if unit.has_method("get") else 0,
				"health": unit.current_health if unit.has_method("get") else 100,
				"distance": distance
			})
	
	# Find all buildings in scan range
	var all_buildings = get_tree().get_nodes_in_group("buildings")
	for building in all_buildings:
		var distance = global_position.distance_to(building.global_position)
		if distance <= scan_radius:
			entities_found.append({
				"building_id": building.building_id if building.has_method("get") else building.name,
				"building_type": building.building_type if building.has_method("get") else "unknown",
				"position": building.global_position,
				"team_id": building.team_id if building.has_method("get") else 0,
				"distance": distance
			})
	
	# Add scanned position to history
	scanned_areas.append(global_position)
	if scanned_areas.size() > 10:  # Keep last 10 scanned areas
		scanned_areas.pop_front()
	
	# Create visual scan effect
	_create_scan_effect(scan_radius)
	
	# Set cooldown
	scan_cooldown_timer = scan_cooldown
	
	print("Scout %s: Scanned area (%.1fm) - found %d entities" % [unit_id, scan_radius, entities_found.size()])
	area_scanned.emit(global_position, entities_found, unit_id)
	
	return true

# Helper methods
func _apply_stealth_visual() -> void:
	"""Apply stealth visual effect"""
	var mesh_instance = find_child("UnitMesh") as MeshInstance3D
	if mesh_instance and stealth_material:
		mesh_instance.material_override = stealth_material

func _remove_stealth_visual() -> void:
	"""Remove stealth visual effect"""
	var mesh_instance = find_child("UnitMesh") as MeshInstance3D
	if mesh_instance:
		# Restore original material
		var material = StandardMaterial3D.new()
		if team_id == 1:
			material.albedo_color = Color.CYAN
		else:
			material.albedo_color = Color.ORANGE
		mesh_instance.material_override = material

func _reduce_visibility() -> void:
	"""Reduce visibility to enemies while stealthed"""
	# This would integrate with the vision system
	# For now, we'll just modify the collision detection
	if collision_shape:
		collision_shape.disabled = true

func _restore_visibility() -> void:
	"""Restore normal visibility"""
	if collision_shape:
		collision_shape.disabled = false

func _create_mark_indicator(target: Unit) -> void:
	"""Create visual indicator for marked target"""
	var indicator = MeshInstance3D.new()
	indicator.name = "MarkIndicator"
	indicator.mesh = SphereMesh.new()
	indicator.mesh.radius = 0.3
	indicator.mesh.height = 0.1
	indicator.position = Vector3(0, 3, 0)  # Above the target
	
	# Create bright material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.YELLOW
	material.emission_enabled = true
	material.emission = Color.YELLOW * 0.5
	material.flags_unshaded = true
	indicator.material_override = material
	
	target.add_child(indicator)
	mark_indicators[target.unit_id] = indicator

func _remove_target_mark(target: Unit) -> void:
	"""Remove mark from target"""
	if target in marked_targets:
		marked_targets.erase(target)
	
	if target.has_meta("mark_time"):
		target.remove_meta("mark_time")
	
	if target.has_meta("marked_by"):
		target.remove_meta("marked_by")
	
	# Remove visual indicator
	if target.unit_id in mark_indicators:
		var indicator = mark_indicators[target.unit_id]
		if indicator:
			indicator.queue_free()
		mark_indicators.erase(target.unit_id)

func _create_scan_effect(radius: float) -> void:
	"""Create visual scan effect"""
	# Create expanding circle effect
	var scan_effect = MeshInstance3D.new()
	scan_effect.name = "ScanEffect"
	scan_effect.mesh = SphereMesh.new()
	scan_effect.mesh.radius = radius
	scan_effect.mesh.height = 0.1
	scan_effect.position = Vector3(0, 0.1, 0)
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.GREEN
	material.flags_transparent = true
	material.albedo_color.a = 0.3
	material.emission_enabled = true
	material.emission = Color.GREEN * 0.2
	scan_effect.material_override = material
	
	add_child(scan_effect)
	
	# Animate the effect
	var tween = create_tween()
	tween.tween_property(scan_effect, "scale", Vector3(1.2, 1.2, 1.2), 0.5)
	tween.parallel().tween_property(scan_effect, "material_override:albedo_color:a", 0.0, 0.5)
	tween.tween_callback(func(): scan_effect.queue_free())

# Enhanced visibility and detection
func can_be_detected_by(other_unit: Unit) -> bool:
	"""Check if this scout can be detected by another unit"""
	if not stealth_mode:
		return true
	
	# Can be detected if enemy is very close
	var distance = global_position.distance_to(other_unit.global_position)
	return distance <= stealth_detection_range

func get_movement_speed_multiplier() -> float:
	"""Get movement speed multiplier for scout"""
	# Scouts move faster when not in combat
	if visible_enemies.is_empty():
		return 1.5
	return 1.0

func scout_area(target_position: Vector3) -> Dictionary:
	"""Return scouting information about an area"""
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
			if unit.team_id != team_id and not unit.is_dead:
				var distance = target_position.distance_to(unit.global_position)
				if distance <= vision_range:
					scout_info.enemies_spotted.append({
						"unit_id": unit.unit_id,
						"archetype": unit.archetype,
						"position": unit.global_position,
						"health": unit.get_health_percentage() if unit.has_method("get_health_percentage") else 1.0
					})
	
	return scout_info

func perform_recon(duration: float = 3.0) -> void:
	"""Perform a reconnaissance sweep"""
	print("Scout %s: Performing recon for %.1f seconds" % [unit_id, duration])
	
	# Temporarily increase vision range
	var original_range = vision_range
	vision_range *= 1.5
	
	# Automatically scan area
	scan_area(vision_range)
	
	# Restore vision range after duration
	await get_tree().create_timer(duration).timeout
	vision_range = original_range
	
	print("Scout %s: Recon completed" % unit_id)

# Public ability interface for plan executor
func get_available_abilities() -> Array[String]:
	"""Get list of available abilities"""
	var abilities = []
	
	if stealth_cooldown_timer <= 0:
		abilities.append("stealth")
	
	if mark_cooldown_timer <= 0:
		abilities.append("mark_target")
	
	if scan_cooldown_timer <= 0:
		abilities.append("scan_area")
	
	abilities.append("perform_recon")
	
	return abilities

func get_ability_cooldown(ability: String) -> float:
	"""Get cooldown time for specific ability"""
	match ability:
		"stealth":
			return stealth_cooldown_timer
		"mark_target":
			return mark_cooldown_timer
		"scan_area":
			return scan_cooldown_timer
		_:
			return 0.0

func is_ability_available(ability: String) -> bool:
	"""Check if ability is available"""
	return get_ability_cooldown(ability) <= 0.0 