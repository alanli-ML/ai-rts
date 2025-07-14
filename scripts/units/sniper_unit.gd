# SniperUnit.gd
class_name SniperUnit
extends Unit

# Sniper-specific properties
var is_scoped: bool = false
var scope_zoom_factor: float = 2.0
var scope_energy_cost: float = 1.0
var charge_time: float = 2.0
var is_charging_shot: bool = false
var charge_timer: float = 0.0
var last_shot_time: float = 0.0
var shot_cooldown: float = 3.0
var headshot_multiplier: float = 2.0

func _ready() -> void:
	archetype = "sniper"
	system_prompt = "You are a precision sniper unit. Your role is to eliminate high-priority targets from long range. You are vulnerable at close range but deadly at distance. Use positioning and patience to maximum effect."
	
	# Call parent _ready
	super._ready()
	
	# Sniper-specific setup
	_setup_sniper_abilities()

func _setup_sniper_abilities() -> void:
	# Snipers have long range but narrow vision
	vision_range = 50.0
	vision_angle = 60.0  # Narrow focus
	
	# Medium movement speed
	speed = 8.0
	move_speed = 8.0
	
	# Medium health
	max_health = 80.0
	current_health = max_health
	
	# Long attack range with high damage
	attack_range = 40.0
	attack_damage = 60.0
	
	# Update visual for sniper
	_update_sniper_visual()

func _update_sniper_visual() -> void:
	if unit_model:
		# Make sniper taller and thinner
		unit_model.scale = Vector3(0.9, 1.1, 0.9)
		
		# Different color scheme
		var material = unit_model.material_override as StandardMaterial3D
		if material:
			if team_id == 1:
				material.albedo_color = Color.GREEN  # Green for team 1 (camouflage)
			else:
				material.albedo_color = Color.BROWN  # Brown for team 2
			
			# Make material less shiny (more camouflaged)
			material.metallic = 0.1
			material.roughness = 0.8

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	# Handle scoped mode
	if is_scoped:
		_handle_scoped_mode(delta)
	
	# Handle charging shot
	if is_charging_shot:
		_handle_charging_shot(delta)
	
	# Update shot cooldown
	if last_shot_time > 0:
		last_shot_time -= delta

func _handle_scoped_mode(delta: float) -> void:
	# Drain energy while scoped
	energy -= scope_energy_cost * delta
	
	# Reduced movement while scoped
	move_speed = speed * 0.3
	
	if energy <= 0:
		toggle_scope()

func _handle_charging_shot(delta: float) -> void:
	charge_timer += delta
	
	if charge_timer >= charge_time:
		# Shot is fully charged
		is_charging_shot = false
		charge_timer = 0.0
		
		# Visual feedback for charged shot
		modulate = Color(1.2, 1.2, 1.0, 1.0)  # Slight yellow tint
		
		# Restore after visual feedback
		await get_tree().create_timer(0.5).timeout
		modulate = Color.WHITE

func toggle_scope() -> void:
	if is_scoped:
		# Exit scope
		is_scoped = false
		vision_range = 50.0
		vision_angle = 60.0
		move_speed = speed
		modulate = Color.WHITE
		Logger.debug("SniperUnit", "Sniper %s exited scope mode" % unit_id)
	else:
		# Enter scope (requires energy)
		if energy >= 10.0:
			is_scoped = true
			vision_range *= scope_zoom_factor
			vision_angle *= 0.5  # Even narrower vision
			modulate = Color(1.0, 1.0, 1.2, 1.0)  # Slight blue tint
			Logger.debug("SniperUnit", "Sniper %s entered scope mode" % unit_id)

func can_take_shot() -> bool:
	return last_shot_time <= 0.0 and not is_charging_shot

func charge_shot() -> void:
	if not can_take_shot():
		Logger.debug("SniperUnit", "Sniper %s cannot charge shot (on cooldown)" % unit_id)
		return
	
	is_charging_shot = true
	charge_timer = 0.0
	
	# Stop movement while charging
	velocity = Vector3.ZERO
	
	Logger.info("SniperUnit", "Sniper %s charging shot" % unit_id)

func fire_shot(target: Unit) -> bool:
	if not target or target.is_dead:
		return false
	
	if not can_take_shot():
		Logger.debug("SniperUnit", "Sniper %s cannot fire (on cooldown)" % unit_id)
		return false
	
	var distance = global_position.distance_to(target.global_position)
	if distance > attack_range:
		Logger.debug("SniperUnit", "Sniper %s target out of range" % unit_id)
		return false
	
	# Calculate damage
	var damage = attack_damage
	
	# Bonus damage if shot was charged
	if charge_timer >= charge_time:
		damage *= 1.5
		Logger.debug("SniperUnit", "Sniper %s fired charged shot" % unit_id)
	
	# Check for headshot (random chance or based on target state)
	if randf() < 0.2:  # 20% chance for headshot
		damage *= headshot_multiplier
		Logger.info("SniperUnit", "Sniper %s scored a headshot!" % unit_id)
	
	# Apply damage
	target.take_damage(damage)
	
	# Reset states
	is_charging_shot = false
	charge_timer = 0.0
	last_shot_time = shot_cooldown
	
	# Visual feedback
	_show_muzzle_flash()
	
	Logger.info("SniperUnit", "Sniper %s fired at %s for %s damage" % [unit_id, target.unit_id, damage])
	return true

func _show_muzzle_flash() -> void:
	# Visual effect for shooting
	modulate = Color(1.5, 1.5, 1.5, 1.0)  # Bright flash
	
	# Restore after brief flash
	await get_tree().create_timer(0.1).timeout
	modulate = Color.WHITE

func find_overwatch_position(area_center: Vector3, area_radius: float) -> Vector3:
	# Find a good position to watch over an area
	var best_position = global_position
	var best_score = 0.0
	
	# Check several positions around the area
	for i in range(8):
		var angle = (i / 8.0) * 2 * PI
		var distance = area_radius * 1.5  # Position outside the area
		var test_position = area_center + Vector3(
			cos(angle) * distance,
			0,
			sin(angle) * distance
		)
		
		var score = _evaluate_overwatch_position(test_position, area_center)
		if score > best_score:
			best_score = score
			best_position = test_position
	
	return best_position

func _evaluate_overwatch_position(position: Vector3, target_area: Vector3) -> float:
	var score = 0.0
	
	# Distance to target area (prefer medium range)
	var distance = position.distance_to(target_area)
	if distance > attack_range * 0.5 and distance < attack_range * 0.9:
		score += 50.0
	
	# Elevation bonus (if we had terrain height)
	# score += get_elevation_at(position) * 10.0
	
	# Safety (distance from enemies)
	var nearby_enemies = get_tree().get_nodes_in_group("units")
	var min_enemy_distance = INF
	for node in nearby_enemies:
		if node is Unit:
			var unit = node as Unit
			if unit.is_enemy_of(self):
				var enemy_distance = position.distance_to(unit.global_position)
				min_enemy_distance = min(min_enemy_distance, enemy_distance)
	
	if min_enemy_distance > 20.0:
		score += 30.0
	
	return score

func take_overwatch_position(position: Vector3) -> void:
	# Move to overwatch position and prepare for long-range support
	move_to(position)
	
	# Wait until we reach the position
	await get_tree().create_timer(2.0).timeout
	
	# Enter overwatch mode
	toggle_scope()
	
	Logger.info("SniperUnit", "Sniper %s taking overwatch position at %s" % [unit_id, position])

func quick_shot(target: Unit) -> bool:
	# Faster shot without charging, but less damage
	if not target or target.is_dead:
		return false
	
	if last_shot_time > 0:
		return false
	
	var distance = global_position.distance_to(target.global_position)
	if distance > attack_range:
		return false
	
	# Quick shot does reduced damage
	var damage = attack_damage * 0.7
	target.take_damage(damage)
	
	# Shorter cooldown
	last_shot_time = shot_cooldown * 0.5
	
	_show_muzzle_flash()
	
	Logger.info("SniperUnit", "Sniper %s quick shot at %s for %s damage" % [unit_id, target.unit_id, damage])
	return true

func relocate_after_shot() -> void:
	# Move to a new position after shooting to avoid counter-attack
	if visible_enemies.size() > 0:
		var escape_direction = Vector3.ZERO
		
		# Calculate direction away from all visible enemies
		for enemy in visible_enemies:
			var direction = (global_position - enemy.global_position).normalized()
			escape_direction += direction
		
		escape_direction = escape_direction.normalized()
		var new_position = global_position + escape_direction * 15.0
		
		move_to(new_position)
		Logger.debug("SniperUnit", "Sniper %s relocating after shot" % unit_id)

func suppress_area(center: Vector3, radius: float, duration: float = 5.0) -> void:
	# Provide suppressing fire over an area
	Logger.info("SniperUnit", "Sniper %s suppressing area at %s" % [unit_id, center])
	
	var end_time = Time.get_ticks_msec() + duration * 1000
	
	while Time.get_ticks_msec() < end_time:
		# Look for targets in the suppression area
		var targets_in_area = get_tree().get_nodes_in_group("units")
		for node in targets_in_area:
			if node is Unit:
				var unit = node as Unit
				if unit.is_enemy_of(self):
					var distance = center.distance_to(unit.global_position)
					if distance <= radius:
						if can_take_shot():
							quick_shot(unit)
							break
		
		await get_tree().create_timer(0.5).timeout
	
	Logger.debug("SniperUnit", "Sniper %s finished suppressing area" % unit_id)

func _on_vision_body_entered(body: Node3D) -> void:
	super._on_vision_body_entered(body)
	
	# Sniper-specific: Prioritize high-value targets
	if body is Unit:
		var unit = body as Unit
		if unit.is_enemy_of(self):
			_assess_target_priority(unit)

func _assess_target_priority(target: Unit) -> void:
	var priority = 0
	
	# Prioritize based on archetype
	match target.archetype:
		"medic":
			priority = 3  # High priority
		"sniper":
			priority = 3  # Counter-sniper
		"engineer":
			priority = 2  # Medium priority
		"scout":
			priority = 1  # Low priority (hard to hit)
		"tank":
			priority = 1  # Low priority (hard to kill)
	
	# Prioritize low-health targets
	if target.get_health_percentage() < 0.3:
		priority += 1
	
	Logger.debug("SniperUnit", "Sniper %s assessed %s as priority %d" % [unit_id, target.unit_id, priority])

func get_optimal_range() -> float:
	# Snipers are most effective at 75% of their maximum range
	return attack_range * 0.75 