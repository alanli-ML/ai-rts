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

# Peek and fire ability
var peek_positions: Array[Vector3] = []
var current_peek_position: Vector3 = Vector3.ZERO
var peek_cooldown: float = 5.0
var peek_cooldown_timer: float = 0.0
var peek_duration: float = 3.0
var peek_timer: float = 0.0
var is_peeking: bool = false
var original_position: Vector3 = Vector3.ZERO

# Overwatch ability
var overwatch_active: bool = false
var overwatch_duration: float = 20.0
var overwatch_timer: float = 0.0
var overwatch_cooldown: float = 25.0
var overwatch_cooldown_timer: float = 0.0
var overwatch_range: float = 45.0
var overwatch_targets: Array[Unit] = []

# Enhanced targeting
var target_priority_system: bool = true
var priority_targets: Array[String] = ["sniper", "medic", "engineer"]  # High priority archetypes
var marked_targets: Array[Unit] = []

# Visual indicators
var scope_indicator: Node3D
var overwatch_indicator: Node3D
var peek_trail: Node3D

# Signals
signal peek_and_fire_executed(target: Unit, success: bool)
signal overwatch_activated(duration: float)
signal overwatch_deactivated()
signal target_eliminated(target: Unit, was_headshot: bool)
signal precision_shot_charged(charge_level: float)

func _ready() -> void:
	archetype = "sniper"
	system_prompt = "You are a precision sniper unit. Your role is to eliminate high-priority targets from long range. You are vulnerable at close range but deadly at distance. Use positioning, patience, and tactical abilities like peek-and-fire and overwatch to maximum effect."
	
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
	movement_speed = 8.0
	
	# Medium health
	max_health = 80.0
	current_health = max_health
	
	# Long attack range with high damage
	attack_range = 40.0
	attack_damage = 60.0
	
	# Create visual indicators
	_create_visual_indicators()
	
	# Update visual for sniper
	_update_sniper_visual()

func _create_visual_indicators() -> void:
	"""Create visual indicators for sniper abilities"""
	# Scope indicator
	scope_indicator = MeshInstance3D.new()
	scope_indicator.name = "ScopeIndicator"
	scope_indicator.mesh = CylinderMesh.new()
	scope_indicator.mesh.height = 0.1
	scope_indicator.mesh.top_radius = 0.5
	scope_indicator.mesh.bottom_radius = 0.5
	scope_indicator.position = Vector3(0, 0.1, 0)
	scope_indicator.visible = false
	
	var scope_material = StandardMaterial3D.new()
	scope_material.albedo_color = Color.RED
	scope_material.flags_transparent = true
	scope_material.albedo_color.a = 0.3
	scope_indicator.material_override = scope_material
	
	add_child(scope_indicator)
	
	# Overwatch indicator
	overwatch_indicator = MeshInstance3D.new()
	overwatch_indicator.name = "OverwatchIndicator"
	overwatch_indicator.mesh = SphereMesh.new()
	overwatch_indicator.mesh.radius = 1.0
	overwatch_indicator.position = Vector3(0, 3, 0)
	overwatch_indicator.visible = false
	
	var overwatch_material = StandardMaterial3D.new()
	overwatch_material.albedo_color = Color.YELLOW
	overwatch_material.emission_enabled = true
	overwatch_material.emission = Color.YELLOW * 0.5
	overwatch_indicator.material_override = overwatch_material
	
	add_child(overwatch_indicator)

func _update_sniper_visual() -> void:
	# Find mesh instance for visual updates
	var mesh_instance = find_child("UnitMesh") as MeshInstance3D
	if mesh_instance:
		# Make sniper taller and thinner
		mesh_instance.scale = Vector3(0.9, 1.1, 0.9)
		
		# Different color scheme
		var material = mesh_instance.material_override as StandardMaterial3D
		if material:
			if team_id == 1:
				material.albedo_color = Color.DARK_RED  # Dark red for team 1
			else:
				material.albedo_color = Color.PURPLE  # Purple for team 2

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	# Update ability timers
	_update_ability_timers(delta)
	
	# Handle charging shot
	if is_charging_shot:
		_handle_charging_shot(delta)
	
	# Handle peek and fire
	if is_peeking:
		_handle_peek_and_fire(delta)
	
	# Handle overwatch
	if overwatch_active:
		_handle_overwatch(delta)

func _update_ability_timers(delta: float) -> void:
	"""Update cooldown timers for abilities"""
	if peek_cooldown_timer > 0:
		peek_cooldown_timer -= delta
	
	if overwatch_cooldown_timer > 0:
		overwatch_cooldown_timer -= delta
	
	if peek_timer > 0:
		peek_timer -= delta
		if peek_timer <= 0:
			_finish_peek()
	
	if overwatch_timer > 0:
		overwatch_timer -= delta
		if overwatch_timer <= 0:
			deactivate_overwatch()

func _handle_charging_shot(delta: float) -> void:
	"""Handle shot charging mechanics"""
	if charge_timer < charge_time:
		charge_timer += delta
		var charge_level = charge_timer / charge_time
		precision_shot_charged.emit(charge_level)
		
		# Visual feedback during charging
		if scope_indicator:
			scope_indicator.visible = true
			scope_indicator.scale = Vector3(charge_level, 1.0, charge_level)
	else:
		# Shot is fully charged
		_fire_charged_shot()

func _handle_peek_and_fire(delta: float) -> void:
	"""Handle peek and fire mechanics"""
	# This is handled by the timer system
	pass

func _handle_overwatch(delta: float) -> void:
	"""Handle overwatch mechanics"""
	if not overwatch_active:
		return
	
	# Scan for targets in overwatch range
	_scan_for_overwatch_targets()
	
	# Auto-engage targets that enter range
	for target in overwatch_targets:
		if target and not target.is_dead:
			var distance = global_position.distance_to(target.global_position)
			if distance <= overwatch_range:
				_auto_engage_target(target)

# Enhanced Sniper Abilities
func peek_and_fire(target: Unit) -> bool:
	"""Peek from cover and fire at target"""
	if not target or peek_cooldown_timer > 0 or is_peeking:
		print("Sniper %s: Peek and fire on cooldown or already peeking" % unit_id)
		return false
	
	if energy < 30.0:
		print("Sniper %s: Not enough energy for peek and fire" % unit_id)
		return false
	
	# Find cover position
	var cover_position = _find_cover_position(target)
	if cover_position == Vector3.ZERO:
		print("Sniper %s: No suitable cover position found" % unit_id)
		return false
	
	# Store original position
	original_position = global_position
	
	# Move to cover position
	is_peeking = true
	peek_timer = peek_duration
	current_peek_position = cover_position
	
	# Move to peek position
	move_to(cover_position)
	
	# Wait for positioning, then fire
	await get_tree().create_timer(1.0).timeout
	
	if is_peeking and target and not target.is_dead:
		var shot_success = _fire_precision_shot(target)
		peek_and_fire_executed.emit(target, shot_success)
		
		# Set cooldown
		peek_cooldown_timer = peek_cooldown
		
		print("Sniper %s: Peek and fire executed at %s (success: %s)" % [unit_id, target.unit_id, shot_success])
		return shot_success
	
	return false

func activate_overwatch(duration: float = 0.0) -> bool:
	"""Activate overwatch mode"""
	if overwatch_active or overwatch_cooldown_timer > 0:
		print("Sniper %s: Overwatch on cooldown or already active" % unit_id)
		return false
	
	if energy < 40.0:
		print("Sniper %s: Not enough energy for overwatch" % unit_id)
		return false
	
	overwatch_active = true
	overwatch_timer = duration if duration > 0 else overwatch_duration
	overwatch_cooldown_timer = overwatch_cooldown
	
	# Visual feedback
	if overwatch_indicator:
		overwatch_indicator.visible = true
		var tween = create_tween()
		tween.set_loops()
		tween.tween_property(overwatch_indicator, "scale", Vector3(1.2, 1.2, 1.2), 0.5)
		tween.tween_property(overwatch_indicator, "scale", Vector3(1.0, 1.0, 1.0), 0.5)
	
	# Reduce movement speed while in overwatch
	movement_speed *= 0.3
	
	print("Sniper %s: Overwatch activated for %.1f seconds" % [unit_id, overwatch_timer])
	overwatch_activated.emit(overwatch_timer)
	
	return true

func deactivate_overwatch() -> void:
	"""Deactivate overwatch mode"""
	if not overwatch_active:
		return
	
	overwatch_active = false
	overwatch_timer = 0.0
	overwatch_targets.clear()
	
	# Restore movement speed
	movement_speed = speed
	
	# Hide visual indicator
	if overwatch_indicator:
		overwatch_indicator.visible = false
	
	print("Sniper %s: Overwatch deactivated" % unit_id)
	overwatch_deactivated.emit()

func charge_precision_shot(target: Unit) -> bool:
	"""Charge a precision shot for maximum damage"""
	if not target or is_charging_shot:
		return false
	
	if energy < 25.0:
		print("Sniper %s: Not enough energy for precision shot" % unit_id)
		return false
	
	is_charging_shot = true
	charge_timer = 0.0
	
	print("Sniper %s: Charging precision shot at %s" % [unit_id, target.unit_id])
	return true

func _fire_charged_shot() -> void:
	"""Fire the charged shot"""
	if not is_charging_shot:
		return
	
	is_charging_shot = false
	charge_timer = 0.0
	
	# Hide scope indicator
	if scope_indicator:
		scope_indicator.visible = false
	
	# Find target and fire
	var target = _get_current_target()
	if target:
		_fire_precision_shot(target, true)

func _fire_precision_shot(target: Unit, is_charged: bool = false) -> bool:
	"""Fire a precision shot at target"""
	if not target or target.is_dead:
		return false
	
	var distance = global_position.distance_to(target.global_position)
	if distance > attack_range:
		print("Sniper %s: Target out of range" % unit_id)
		return false
	
	# Calculate damage
	var damage = attack_damage
	if is_charged:
		damage *= 1.5  # Charged shots do more damage
	
	# Check for headshot (random chance based on charge)
	var headshot_chance = 0.1  # 10% base chance
	if is_charged:
		headshot_chance = 0.3  # 30% chance for charged shots
	
	var is_headshot = randf() < headshot_chance
	if is_headshot:
		damage *= headshot_multiplier
	
	# Apply damage
	target.take_damage(damage)
	
	# Create shot effect
	_create_shot_effect(target.global_position)
	
	# Check if target was eliminated
	if target.is_dead:
		target_eliminated.emit(target, is_headshot)
		print("Sniper %s: Target %s eliminated (headshot: %s)" % [unit_id, target.unit_id, is_headshot])
	
	# Energy cost
	energy -= 15.0 if is_charged else 10.0
	
	# Set shot cooldown
	last_shot_time = Time.get_ticks_msec() / 1000.0
	
	return true

func _scan_for_overwatch_targets() -> void:
	"""Scan for targets in overwatch range"""
	if not overwatch_active:
		return
	
	overwatch_targets.clear()
	
	var all_units = get_tree().get_nodes_in_group("units")
	for unit in all_units:
		if unit == self or unit.team_id == team_id:
			continue
		
		var distance = global_position.distance_to(unit.global_position)
		if distance <= overwatch_range and not unit.is_dead:
			overwatch_targets.append(unit)

func _auto_engage_target(target: Unit) -> void:
	"""Auto-engage target in overwatch"""
	if not overwatch_active or not target:
		return
	
	# Check if we can fire (cooldown)
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_shot_time < shot_cooldown:
		return
	
	# Fire at target
	_fire_precision_shot(target)
	
	print("Sniper %s: Overwatch auto-engaged %s" % [unit_id, target.unit_id])

func _find_cover_position(target: Unit) -> Vector3:
	"""Find cover position for peek and fire"""
	if not target:
		return Vector3.ZERO
	
	# Find position perpendicular to target with some cover
	var direction = (target.global_position - global_position).normalized()
	var perpendicular = Vector3(-direction.z, 0, direction.x)
	
	# Try different positions
	var test_positions = [
		global_position + perpendicular * 5.0,
		global_position - perpendicular * 5.0,
		global_position + direction * -3.0 + perpendicular * 3.0,
		global_position + direction * -3.0 - perpendicular * 3.0
	]
	
	# Return first valid position
	for pos in test_positions:
		if _is_valid_cover_position(pos, target):
			return pos
	
	return Vector3.ZERO

func _is_valid_cover_position(position: Vector3, target: Unit) -> bool:
	"""Check if position provides good cover"""
	var distance_to_target = position.distance_to(target.global_position)
	return distance_to_target <= attack_range and distance_to_target >= 15.0

func _finish_peek() -> void:
	"""Finish peek and fire maneuver"""
	if not is_peeking:
		return
	
	is_peeking = false
	
	# Return to original position
	if original_position != Vector3.ZERO:
		move_to(original_position)
	
	print("Sniper %s: Peek maneuver completed" % unit_id)

func _create_shot_effect(target_position: Vector3) -> void:
	"""Create visual effect for shot"""
	# Create muzzle flash
	var muzzle_flash = MeshInstance3D.new()
	muzzle_flash.name = "MuzzleFlash"
	muzzle_flash.mesh = SphereMesh.new()
	muzzle_flash.mesh.radius = 0.3
	muzzle_flash.position = Vector3(0, 1, 1)  # At weapon position
	
	var flash_material = StandardMaterial3D.new()
	flash_material.albedo_color = Color.YELLOW
	flash_material.emission_enabled = true
	flash_material.emission = Color.YELLOW * 2.0
	muzzle_flash.material_override = flash_material
	
	add_child(muzzle_flash)
	
	# Animate muzzle flash
	var tween = create_tween()
	tween.tween_property(muzzle_flash, "scale", Vector3(2.0, 2.0, 2.0), 0.1)
	tween.tween_property(muzzle_flash, "scale", Vector3(0.1, 0.1, 0.1), 0.1)
	tween.tween_callback(func(): muzzle_flash.queue_free())

func _get_current_target() -> Unit:
	"""Get current target for shooting"""
	if not visible_enemies.is_empty():
		return visible_enemies[0]
	return null

func _get_priority_target() -> Unit:
	"""Get highest priority target"""
	var priority_target = null
	var highest_priority = -1
	
	for enemy in visible_enemies:
		var priority = _get_target_priority(enemy)
		if priority > highest_priority:
			highest_priority = priority
			priority_target = enemy
	
	return priority_target

func _get_target_priority(target: Unit) -> int:
	"""Get priority score for target"""
	if not target:
		return 0
	
	var priority = 1  # Base priority
	
	# Higher priority for specific archetypes
	if target.archetype in priority_targets:
		priority += 5
	
	# Higher priority for low health targets
	if target.get_health_percentage() < 0.3:
		priority += 3
	
	# Higher priority for closer targets
	var distance = global_position.distance_to(target.global_position)
	if distance < 20.0:
		priority += 2
	
	return priority

# Enhanced targeting system
func acquire_target(preferred_archetype: String = "") -> Unit:
	"""Acquire best target based on priority system"""
	if visible_enemies.is_empty():
		return null
	
	var best_target = null
	var highest_score = -1
	
	for enemy in visible_enemies:
		var score = _calculate_target_score(enemy, preferred_archetype)
		if score > highest_score:
			highest_score = score
			best_target = enemy
	
	return best_target

func _calculate_target_score(target: Unit, preferred_archetype: String) -> int:
	"""Calculate targeting score for unit"""
	if not target or target.is_dead:
		return 0
	
	var score = 10  # Base score
	
	# Archetype preferences
	if preferred_archetype != "" and target.archetype == preferred_archetype:
		score += 20
	
	# Priority target bonus
	if target.archetype in priority_targets:
		score += 15
	
	# Health-based scoring
	var health_pct = target.get_health_percentage()
	if health_pct < 0.3:
		score += 10  # Finish off weak targets
	
	# Distance penalty
	var distance = global_position.distance_to(target.global_position)
	if distance > attack_range * 0.8:
		score -= 5
	
	return score

# Public ability interface for plan executor
func get_available_abilities() -> Array[String]:
	"""Get list of available abilities"""
	var abilities = []
	
	if peek_cooldown_timer <= 0:
		abilities.append("peek_and_fire")
	
	if overwatch_cooldown_timer <= 0:
		abilities.append("overwatch")
	
	abilities.append("charge_precision_shot")
	abilities.append("acquire_target")
	
	return abilities

func get_ability_cooldown(ability: String) -> float:
	"""Get cooldown time for specific ability"""
	match ability:
		"peek_and_fire":
			return peek_cooldown_timer
		"overwatch":
			return overwatch_cooldown_timer
		"charge_precision_shot":
			return max(0.0, shot_cooldown - (Time.get_ticks_msec() / 1000.0 - last_shot_time))
		_:
			return 0.0

func is_ability_available(ability: String) -> bool:
	"""Check if ability is available"""
	return get_ability_cooldown(ability) <= 0.0

func get_overwatch_status() -> Dictionary:
	"""Get current overwatch status"""
	return {
		"active": overwatch_active,
		"time_remaining": overwatch_timer,
		"targets_in_range": overwatch_targets.size()
	}

func get_peek_status() -> Dictionary:
	"""Get current peek status"""
	return {
		"active": is_peeking,
		"time_remaining": peek_timer,
		"cover_position": current_peek_position
	} 